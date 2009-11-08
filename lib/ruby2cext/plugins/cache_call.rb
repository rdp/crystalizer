# this one does something like... 
# @ location X
# there is a call of method y on z
# if z has the same class as last time
# then do something of a pseudo-ruby-call into that method, since
# we have a pointer saved to it from the previous time.
# the pseudo-ruby call being necessary so that we can pass in arguments in ruby like fashion
# to the C method, etc.
# what are the limitations?
#
# this one also conflicts with builtin_extensions
# which...might be faster?
# TODOR make the order matter
# TODOR various

module Ruby2CExtension::Plugins

class CacheCall < Ruby2CExtension::Plugin

    include Util

    def initialize(compiler, need_frame=false)
        super(compiler)
        @need_frame = need_frame || nil
        @cache_index = Hash.new { |h,k| h[k] = h.size }
        @argcs = {}
        compiler.add_preprocessor(:call, &method(:handle_call))
        compiler.add_preprocessor(:vcall, &method(:handle_call))
        compiler.add_preprocessor(:fcall, &method(:handle_call))
        compiler.add_preprocessor(:attrasgn, &method(:handle_call))
    end

    def handle_call(cfun, node)
        ntype = node.first
        hash = node.last
        mid = hash[:mid]
        args = hash[:args] || [:array, []]
        argc = if args.first == :array
            args = args.last
            args.size
        else
            -1
        end
        @argcs[argc] = true
        recv = hash[:recv]
        allow_private = case ntype
        when :fcall, :vcall
            1
        else
            recv.equal?(0) ? 1 : 0
        end
        recv = nil if recv.equal?(0)
        recv ||= [:self, {}]
        key = [mid, argc, allow_private]
        if type=deduce_type(recv)
            key << type
        else
            key << cfun.__id__ << recv.inspect
        end
        index = @cache_index[key]
        entry = "method_cache[#{index}]"
        assign = node.first.equal?(:attrasgn)
        if argc >= 0
            last = assign && args.pop
            values(cfun, 1, last, recv, *args) { |last, recv, *args|
                args << last if assign
                args = args.inject("") { |s, arg| s.concat(", #{arg}") }
                # cache_call1 means "one argument"
                # delta == 0 means "they accept exactly as many args as I want to pass them"
                # delta == 1 means "it accepts -1"
                # it appears to 
                call = "cache_call#{argc}(#{allow_private}, &#{entry}, #{recv}, #{cfun.sym(mid)}#{args})"
                if assign
                    cfun.l("#{call};")
                    last
                else
                    call
                end
            }
        else
            recv = cfun.comp(recv)
            cfun.c_scope_res {
                cfun.l "VALUE recv = #{recv};"
                cfun.build_args(args)
                call = "cache_call(#{allow_private}, &#{entry}, recv, #{cfun.sym(mid)}, argc, argv)"
                if assign
                    cfun.l("#{call};")
                    "argv[argc-1]"
                else
                    call
                end
            }
        end
    end

    def global_c_code
        begin
            #TODO: try handling NOEX_PROTECTED
            code = %{
                typedef struct {
                    VALUE klass;
                    VALUE (*func)(ANYARGS);
                    #{@need_frame && 'VALUE origin;'}
                    #{@need_frame && 'ID mid0;'}
                } method_cache_entry;
                static method_cache_entry method_cache[#{@cache_index.size}];
                static void init_method_cache() {
                    method_cache_entry* entry;
                    for (entry = method_cache + #{@cache_index.size-1}; entry >= method_cache; --entry) {
                        entry->klass = 0;
                        entry->func = 0;
                    }
                }
                static VALUE recache(
                    int allow_private, method_cache_entry *entry,
                    VALUE recv, ID mid, int argc
                ) {
                    VALUE klass = CLASS_OF(recv);
                    entry->klass = klass;
                    NODE* body;
                    while (!st_lookup(RCLASS(klass)->m_tbl, mid,
                                      (st_data_t *)&body))
                    {
                        klass = RCLASS(klass)->super;
                        if (!klass) {
                            entry->klass += 2;
                            return;
                        }
                    }
                    if (!allow_private &&
                        (body->nd_noex & (NOEX_PRIVATE|NOEX_PROTECTED)))
                    {
                        entry->klass += 2;
                        return;
                    }
                    body = body->nd_body;
                    if (nd_type(body) == NODE_FBODY) {
                        #{@need_frame && 'entry->origin = body->nd_orig;'}
                        #{@need_frame && 'entry->mid0 = body->nd_mid;'}
                        body = body->nd_head;
                    } else {
                        #{@need_frame && 'entry->origin = klass;'}
                        #{@need_frame && 'entry->mid0 = mid;'}
                    }
                    if (nd_type(body) == NODE_CFUNC) {
                        entry->func = body->nd_cfnc;
                        if (body->nd_argc == -1) {
                            entry->klass += 1;
                            return;
                        } else if (body->nd_argc == argc) {
                            return;
                        }
                    }
                    entry->klass += 2;
                    return;
                }
            }
        end
        @argcs.keys.sort.each { |argc|
            args = (0...argc).inject("") { |s, i|
                s.concat(", arg#{i}")
            }
            args_declare = (0...argc).inject("") { |s, i|
                s.concat(", VALUE arg#{i}")
            }
            argv_init = (0...argc).inject("") { |s, i|
                s.concat("argv[#{i}]=arg#{i}; ")
            }
            argv = case argc
            when 0
                "0"
            when 1
                "&arg0"
            else
                "argv"
            end
            if @need_frame
                # NOTE: uniq=(long)&_frame should be frame_unique++
                pre_call = %({
                    VALUE res;
                    struct FRAME _frame = {
                        .self = recv,
                        .argc = #{(argc < 0) ? 'argc' : argc},
                        .last_func = mid,
                        .orig_func = entry->mid0,
                        .last_class = entry->origin,
                        .prev = ruby_frame,
                        .tmp = 0,
                        .node = ruby_current_node,
                        .iter = 0,
                        .flags = 0,
                        .uniq = (long)&_frame
                    };
                    ruby_frame = &_frame;
                    res = )
                post_call = %(
                    ruby_frame = _frame.prev;
                    return res;
                })
            else
                pre_call = "return "
                post_call = ""
            end
            code.concat((argc < 0) ? %{
                static inline VALUE cache_call(
                    int allow_private, method_cache_entry *entry,
                    VALUE recv, ID mid, int argc, VALUE *argv
                ) {
                    while (1) {
                        VALUE klass = CLASS_OF(recv);
                        switch (entry->klass - klass) {
                        case 1:
                            #{pre_call}
                            (*entry->func)(argc, argv, recv);
                            #{post_call}
                        case 0:
                        case 2:
                            return (*(allow_private ? rb_funcall2 : rb_funcall3))(
                                recv, mid, argc, argv
                            );
                        default:
                            recache(allow_private, entry, recv, mid, argc);
                        }
                    }
                }
            } : (argc<=1) ? %{
                static inline VALUE cache_call#{argc}(
                    int allow_private, method_cache_entry *entry,
                    VALUE recv, ID mid#{args_declare}
                ) {
                    while (1) {
                        VALUE klass = CLASS_OF(recv);
                        VALUE delta = entry->klass - klass;
                        // here1
                        switch (delta) {
                        case 0:
                        case 1:
                            #{pre_call}
                            delta ? (*entry->func)(#{argc}, #{argv}, recv) :
                                    (*entry->func)(recv#{args});
                            #{post_call}
                        case 2:
                            return (*(allow_private ? rb_funcall2 : rb_funcall3))(
                                recv, mid, #{argc}, #{argv}
                            );
                        default:
                            recache(allow_private, entry, recv, mid, #{argc});
                        }
                    }
                }
            } : %{
                static inline VALUE cache_call#{argc}(
                    int allow_private, method_cache_entry *entry,
                    VALUE recv, ID mid#{args_declare}
                ) {
                    while (1) {
                        VALUE klass = CLASS_OF(recv);
                        VALUE delta = entry->klass - klass;
                        if (delta==0) {
                            #{pre_call}
                            (*entry->func)(recv#{args});
                            #{post_call}
                        } else {
                            VALUE argv[#{argc}];
                            #{argv_init}
                            if (delta == 1) {
                                #{pre_call}
                                (*entry->func)(#{argc}, #{argv}, recv);
                                #{post_call}
                            } else if (delta == 2) {
                                return (*(allow_private ? rb_funcall2 : rb_funcall3))(
                                    recv, mid, #{argc}, #{argv}
                                );
                            } else {
                                recache(allow_private, entry, recv, mid, #{argc});
                            }
                        }
                    }
                }
            })
        }
        code
    end

    def init_c_code
        %{
            init_method_cache();
        }
    end

end

end
