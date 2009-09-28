# this one inlines things like [].empty? -- no ruby calls it's all in C
# builtin_methods does some more...
require "ruby2cext/error"
require "ruby2cext/plugin"
require "ruby2cext/plugins/util"

module Ruby2CExtension::Plugins

class InlineBuiltin < Ruby2CExtension::Plugin

    include Util
    extend Util

    def initialize(compiler)
        super(compiler)
        compiler.add_preprocessor(:call, &method(:call))
        compiler.add_preprocessor(:vcall, &method(:call))
        compiler.add_preprocessor(:fcall, &method(:call))
        compiler.add_preprocessor(:inline_pass, &method(:inline_pass))
    end

    def call(cfun, node)
        hash = node.last
        recv = hash[:recv] || [:self, {}]
        klass = deduce_type(recv)
        inline = INLINE[klass]
        inline0 = klass ? INLINE[nil] : {}
        mid = hash[:mid]
        args = hash[:args] || [:array, []]
        if :array==args.first and arity = args.last.size and
                m = (inline[[mid, arity]] || inline0[[mid, arity]])
            args = args.last
        elsif m = (inline[mid] || inline0[mid])
            return m[cfun, node, recv, args]
        else
            return node
        end
        if arity==0
            return values(cfun, (m.arity<0) ? 1 : 0, recv, &m)
        end
        args = args.clone
        first = args.shift
        if klass = deduce_type(first)
            if f = m[klass]
                return values(cfun, (f.arity<0) ? (arity+1) : 0, recv, first, *args, &f)
            else
                return node
            end
        end
        reuse = false
        m.each_value { |f| reuse = false if f.arity<0 }
        default = m[nil]
        size = m.size - (default ? 1 : 0)
        default ||= lambda { |cfun, recv, *args|
            cfun.comp([:inline_pass, :call, {
                :recv => recv,
                :mid => mid,
                :args => [:array, args]
            }])
        }
        values(cfun, reuse ? (arity+1) : 1, first, recv, *args) { |first, recv, *args|
            if size==0
                default[cfun, recv, first, *args]
            elsif size==1
                m.each { |klass, f|
                    match = Class2Match[klass] or next
                    cfun.c_if(match[first]) {
                        cfun.assign_res(f[cfun, recv, first, *args])
                    }
                }
                cfun.c_else {
                    cfun.assign_res(default[cfun, recv, first, *args])
                }
                "res"
            else
                cfun.l("switch (TYPE(#{first})) {")
                m.each { |klass, f|
                    type = Class2Type[klass] or next
                    cfun.l("case #{type}:")
                    cfun.assign_res(f[cfun, recv, first, *args])
                    cfun.l("break;")
                }
                cfun.l("default:")
                    cfun.assign_res(default[cfun, recv, first, *args])
                cfun.l("}")
                "res"
            end
        }
    end

    def inline_pass(cfun, node)
        node.shift
        node
    end

    Class2Type = {
        NilClass => "T_NIL",
        FalseClass => "T_FALSE",
        TrueClass => "T_TRUE",
        Fixnum => "T_FIXNUM",
        Symbol => "T_SYMBOL",
        Float => "T_FLOAT",
        Bignum => "T_BIGNUM",
        Regexp => "T_REGEXP",
        String => "T_STRING",
        Array => "T_ARRAY",
        Hash => "T_HASH",
    }

    Class2Match = {
        NilClass => lambda { |obj|
            %{(#{obj} == Qnil)}
        },
        FalseClass => lambda { |obj|
            %{(#{obj} == Qfalse)}
        },
        TrueClass => lambda { |obj|
            %{(#{obj} == Qtrue)}
        },
        Fixnum => lambda { |obj|
            %{FIXNUM_P(#{obj})}
        },
        Symbol => lambda { |obj|
            %{SYMBOL_P(#{obj})}
        },
        Float => lambda { |obj|
            %{(!SPECIAL_CONST_P(#{obj}) && (RBASIC(#{obj})->klass == rb_cFloat))}
        },
        Bignum => lambda { |obj|
            %{(!SPECIAL_CONST_P(#{obj}) && (RBASIC(#{obj})->klass == rb_cBignum))}
        },
        Regexp => lambda { |obj|
            %{(!SPECIAL_CONST_P(#{obj}) && (RBASIC(#{obj})->klass == rb_cRegexp))}
        },
        String => lambda { |obj|
            %{(!SPECIAL_CONST_P(#{obj}) && (RBASIC(#{obj})->klass == rb_cString))}
        },
        Array => lambda { |obj|
            %{(!SPECIAL_CONST_P(#{obj}) && (RBASIC(#{obj})->klass == rb_cArray))}
        },
        Hash => lambda { |obj|
            %{(!SPECIAL_CONST_P(#{obj}) && (RBASIC(#{obj})->klass == rb_cHash))}
        },
    }

    COMMON = {
        [:equal?,1] => {nil => lambda { |cfun, this, that|
            %{(#{this} == (#{that}) ? Qtrue : Qfalse)}
        }},
        [:'eql?',1] => {nil => lambda { |cfun, this, that|
            %{(#{this} == (#{that}) ? Qtrue : Qfalse)}
        }},
        [:'==',1] => {nil => lambda { |cfun, this, that|
            %{(#{this} == (#{that}) ? Qtrue : Qfalse)}
        }},
        [:'===',1] => {nil => lambda { |cfun, this, that|
            %{(#{this} == (#{that}) ? Qtrue : Qfalse)}
        }},
        [:'=~',1] => {nil => lambda { |cfun, this, that|
            %{Qfalse}
        }},
        [:'nil?',0] => lambda { |cfun, this|
            %{Qfalse}
        },
        [:'class',0] => lambda { |cfun, this|
            %{rb_obj_class(#{this})}
        },
    }

    INLINE = {}

    INLINE[nil] = {
        [:__id__,0] => lambda { |cfun, this|
            %{rb_obj_id(#{this})}
        },
        :__send__ => lambda { |cfun, node, this, args|
            args = split_args(-2, args)
            if args
                method = args.shift
                this = cfun.comp(this);
                cfun.c_scope_res {
                    cfun.l "VALUE recv = #{this};"
                    cfun.build_args(args)
                    %{rb_funcall2(#{this}, rb_to_id(#{cfun.comp(method)}), argc, argv)}
                }
            else
                node
            end
        }
    }

    INLINE[NilClass] = COMMON.merge({
        [:'&',1] => {nil => lambda { |cfun, this, that|
            %{Qfalse}
        }},
        [:'|',1] => {nil => lambda { |cfun, this, that|
            %{(RTEST(#{that}) ? Qtrue : Qfalse)}
        }},
        [:'^',1] => {nil => lambda { |cfun, this, that|
            %{(RTEST(#{that}) ? Qtrue : Qfalse)}
        }},
        [:'to_i',0] => lambda { |cfun, this|
            %{INT2FIX(0)}
        },
        [:'to_f',0] => lambda { |cfun, this|
            %{rb_float_new(0.0)}
        },
        [:'to_s',0] => lambda { |cfun, this|
            %{rb_str_new2("")}
        },
        [:'to_a',0] => lambda { |cfun, this|
            %{rb_ary_new2(0)}
        },
        [:'inspect',0] => lambda { |cfun, this|
            %{rb_str_new2("nil")}
        },
        [:'nil?',0] => lambda { |cfun, this|
            %{Qtrue}
        },
    })

    INLINE[FalseClass] = COMMON.merge({
        [:'&',1] => {nil => lambda { |cfun, this, that|
            %{Qfalse}
        }},
        [:'|',1] => {nil => lambda { |cfun, this, that|
            %{(RTEST(#{that}) ? Qtrue : Qfalse)}
        }},
        [:'^',1] => {nil => lambda { |cfun, this, that|
            %{(RTEST(#{that}) ? Qtrue : Qfalse)}
        }},
        [:'to_s',0] => lambda { |cfun, this|
            %{rb_str_new2("false")}
        },
    })

    INLINE[TrueClass] = COMMON.merge({
        [:'&',1] => {nil => lambda { |cfun, this, that|
            %{(RTEST(#{that}) ? Qtrue : Qfalse)}
        }},
        [:'|',1] => {nil => lambda { |cfun, this, that|
            %{Qtrue}
        }},
        [:'^',1] => {nil => lambda { |cfun, this, that|
            %{(RTEST(#{that}) ? Qfalse : Qtrue)}
        }},
        [:'to_s',0] => lambda { |cfun, this|
            %{rb_str_new2("true")}
        },
    })

    INLINE[Symbol] = COMMON.merge({
        [:'to_i',0] => lambda { |cfun, this|
            %{LONG2FIX(SYM2ID(#{this}))}
        },
        [:'to_s',0] => lambda { |cfun, this|
            %{rb_str_new2(rb_id2name(SYM2ID(#{this})))}
        },
        [:'to_sym',0] => lambda { |cfun, this|
            this
        },
        [:'id2name',0] => lambda { |cfun, this|
            %{rb_str_new2(rb_id2name(SYM2ID(#{this})))}
        },
    })

    def self.fixnum_binary(reuse=false) # :yield: cfun, op, this, that
        fix2long = lambda { |val|
            val.clone.gsub!(/\ALONG2FIX\((\d+)\)\Z/, '\1') or
            %{FIX2LONG(#{val})}
        }
        {
            Fixnum => lambda { |cfun, this, that|
                this = fix2long[this]
                that = fix2long[that]
                if reuse
                    c_scope_res {
                        cfun.l("long a = #{this};")
                        cfun.l("long b = #{that};")
                        yield(cfun, "a", "b")
                    }
                else
                    yield(cfun, this, that)
                end
            }
        }
    end

    INLINE[Fixnum] = COMMON.merge({
        [:'===',1] => {Fixnum => lambda { |cfun, this, that|
            %{((#{this} == #{that}) ? Qtrue : Qfalse)}
        }},
        [:'==',1] => {Fixnum => lambda { |cfun, this, that|
            %{((#{this} == #{that}) ? Qtrue : Qfalse)}
        }},
        [:'>',1] => fixnum_binary { |cfun, this, that|
            %{((#{this} > #{that}) ? Qtrue : Qfalse)}
        },
        [:'>=',1] => fixnum_binary { |cfun, this, that|
            %{((#{this} >= #{that}) ? Qtrue : Qfalse)}
        },
        [:'<',1] => fixnum_binary { |cfun, this, that|
            %{((#{this} < #{that}) ? Qtrue : Qfalse)}
        },
        [:'<=',1] => fixnum_binary { |cfun, this, that|
            %{((#{this} <= #{that}) ? Qtrue : Qfalse)}
        },
        [:'<=>',1] => fixnum_binary(true) { |cfun, this, that|
            %{INT2FIX((#{this} > #{that}) - (#{this} < #{that}))}
        },
        [:'+',1] => fixnum_binary { |cfun, this, that|
            %{LONG2NUM(#{this} + #{that})}
        },
        [:'-',1] => fixnum_binary { |cfun, this, that|
            %{LONG2NUM(#{this} - #{that})}
        },
        [:'&',1] => fixnum_binary { |cfun, this, that|
            %{LONG2NUM(#{this} & #{that})}
        },
        [:'|',1] => fixnum_binary { |cfun, this, that|
            %{LONG2NUM(#{this} | #{that})}
        },
        [:'^',1] => fixnum_binary { |cfun, this, that|
            %{LONG2NUM(#{this} ^ #{that})}
        },
        [:'-@',0] => lambda { |cfun, this|
            %{LONG2NUM(-FIX2LONG(#{this}))}
        },
        [:'to_f',0] => lambda { |cfun, this|
            %{rb_float_new((double)FIX2LONG(#{this}))}
        },
        [:'size',0] => lambda { |cfun, this|
            %{INT2FIX(sizeof(long))}
        },
        [:'zero?',0] => lambda { |cfun, this|
            %{(FIX2LONG(#{this}) ? Qfalse : Qtrue)}
        },
        [:'abs',0] => lambda { |cfun, this, *|
            cfun.l("long i = FIX2LONG(#{this});")
            %{LONG2NUM((i < 0) ? -i : i)}
        },
        [:'to_s',0] => lambda { |cfun, this|
            %{rb_fix2str(#{this}, 10)}
        },
        [:'to_int',0] => lambda { |cfun, this|
            this
        },
        [:'to_i',0] => lambda { |cfun, this|
            this
        },
        [:'floor',0] => lambda { |cfun, this|
            this
        },
        [:'ceil',0] => lambda { |cfun, this|
            this
        },
        [:'round',0] => lambda { |cfun, this|
            this
        },
        [:'truncate',0] => lambda { |cfun, this|
            this
        },
        [:'succ',0] => lambda { |cfun, this|
            %{LONG2NUM(FIX2LONG(#{this}) + 1)}
        },
        [:'next',0] => lambda { |cfun, this|
            %{LONG2NUM(FIX2LONG(#{this}) + 1)}
        },
        [:'integer?',0] => lambda { |cfun, this|
            %{Qtrue}
        },
    })

    def self.float_binary(reuse=false) # :yield: cfun, op, this, that
        handle = lambda { |cfun, this, that|
            this = %{RFLOAT(#{this})->value}
            if reuse
                c_scope_res {
                    cfun.l("double a = #{this};")
                    cfun.l("double b = #{that};")
                    yield(cfun, "a", "b")
                }
            else
                yield(cfun, this, that)
            end
        }
        {
            Fixnum => lambda { |cfun, this, that|
                handle[cfun, this, %{((double)FIX2LONG(#{that}))}]
            },
            Float => lambda { |cfun, this, that|
                handle[cfun, this, %{RFLOAT(#{that})->value}]
            },
            Bignum => lambda { |cfun, this, that|
                handle[cfun, this, %{rb_big2dbl(#{that})}]
            },
        }
    end

    INLINE[Float] = COMMON.merge({
        [:eql?,1] => {nil => lambda { |cfun, this, that|
            %{((#{Class2Match[Float][this]} &&
                !isnan(#{this}) && !isnan(#{that}) &&
                (#{this} == #{that})
               ) ? Qtrue : Qfalse)}
        }},
        [:'===',1] => float_binary(true) {
            %{((!isnan(#{this}) && !isnan(#{that}) && (#{this} == #{that})) ? Qtrue : Qfalse)}
        },
        [:'==',1] => float_binary(true) { |cfun, this, that|
            %{((!isnan(#{this}) && !isnan(#{that}) &&
                (#{this} == #{that})) ? Qtrue : Qfalse)}
        },
        [:'<=>',1] => float_binary(true) { |cfun, this, that|
            %{((isnan(#{this}) || isnan(#{that})) ? Qnil :
              INT2FIX((#{this} > #{that}) - (#{this} < #{that})))}
        },
        [:'>',1] => float_binary(true) { |cfun, this, that|
            %{((!isnan(#{this}) && !isnan(#{that}) &&
                (#{this} > #{that})) ? Qtrue : Qfalse)}
        },
        [:'>=',1] => float_binary(true) { |cfun, this, that|
            %{((!isnan(#{this}) && !isnan(#{that}) &&
                (#{this} >= #{that})) ? Qtrue : Qfalse)}
        },
        [:'<',1] => float_binary(true) { |cfun, this, that|
            %{((!isnan(#{this}) && !isnan(#{that}) &&
                (#{this} < #{that})) ? Qtrue : Qfalse)}
        },
        [:'<=',1] => float_binary(true) { |cfun, this, that|
            %{((!isnan(#{this}) && !isnan(#{that}) &&
                (#{this} <= #{that})) ? Qtrue : Qfalse)}
        },
        [:'+',1] => float_binary { |cfun, this, that|
            %{rb_float_new(#{this} + #{that})}
        },
        [:'-',1] => float_binary { |cfun, this, that|
            %{rb_float_new(#{this} - #{that})}
        },
        [:'*',1] => float_binary { |cfun, this, that|
            %{rb_float_new(#{this} * #{that})}
        },
        [:'/',1] => float_binary { |cfun, this, that|
            %{rb_float_new(#{this} / #{that})}
        },
        [:'**',1] => float_binary { |cfun, this, that|
            %{rb_float_new(pow(#{this}, #{that}))}
        },
        [:'-@',0] => lambda { |cfun, this|
            %{rb_float_new(-RFLOAT(#{this})->value)}
        },
        [:'to_f',0] => lambda { |cfun, this|
            this
        },
        [:'abs',0] => lambda { |cfun, this|
            %{rb_float_new(fabs(RFLOAT(#{this})->value))}
        },
        [:'zero?',0] => lambda { |cfun, this|
            %{((RFLOAT(#{this})->value == 0.0) ? Qtrue : Qfalse)}
        },
        [:'to_i',0] => lambda { |cfun, this|
            cfun.c_scope_res {
                cfun.l("double f = RFLOAT(#{this})->value;")
                cfun.l("f = (f >= 0.0) ? floor(f) : ceil(f);")
                %{(FIXABLE(f) ? LONG2FIX((long)f) : rb_dbl2big(f))}
            }
        },
        [:'to_int',0] => lambda { |cfun, this|
            cfun.c_scope_res {
                cfun.l("double f = RFLOAT(#{this})->value;")
                cfun.l("f = (f >= 0.0) ? floor(f) : ceil(f);")
                %{(FIXABLE(f) ? LONG2FIX((long)f) : rb_dbl2big(f))}
            }
        },
        [:'truncate',0] => lambda { |cfun, this|
            cfun.c_scope_res {
                cfun.l("double f = RFLOAT(#{this})->value;")
                cfun.l("f = (f >= 0.0) ? floor(f) : ceil(f);")
                %{(FIXABLE(f) ? LONG2FIX((long)f) : rb_dbl2big(f))}
            }
        },
        [:'floor',0] => lambda { |cfun, this|
            cfun.c_scope_res {
                cfun.l("double f = floor(RFLOAT(#{this})->value);")
                %{(FIXABLE(f) ? LONG2FIX((long)f) : rb_dbl2big(f))}
            }
        },
        [:'ceil',0] => lambda { |cfun, this|
            cfun.c_scope_res {
                cfun.l("double f = ceil(RFLOAT(#{this})->value);")
                %{(FIXABLE(f) ? LONG2FIX((long)f) : rb_dbl2big(f))}
            }
        },
        [:'round',0] => lambda { |cfun, this|
            cfun.c_scope_res {
                cfun.l("double f = RFLOAT(#{this})->value;")
                cfun.l("f = (f >= 0.0) ? floor(f + 0.5) : ceil(f - 0.5);")
                %{(FIXABLE(f) ? LONG2FIX((long)f) : rb_dbl2big(f))}
            }
        },
        [:'nan?',0] => lambda { |cfun, this|
            %{(isnan(RFLOAT(#{this})->value) ? Qtrue : Qfalse)}
        },
        [:'infinite?',0] => lambda { |cfun, this, *|
            %{(isinf(RFLOAT(#{this})->value) ?
                INT2FIX((RFLOAT(#{this})->value < 0) ? -1 : 1) :
                Qnil)}
        },
        [:'finite?',0] => lambda { |cfun, this|
            %{((isinf(RFLOAT(#{this})->value) || isnan(RFLOAT(#{this})->value)) ? Qfalse : Qtrue)}
        },
        [:'integer?',0] => lambda { |cfun, this|
            %{Qfalse}
        },
        [:'nonzero?',0] => lambda { |cfun, this|
            %{((RFLOAT(#{this})->value == 0.0) ? Qfalse : Qtrue)}
        },
    })

    INLINE[String] = COMMON.merge({
        [:'eql?',1] => {nil => lambda { |cfun, this, that|
            %{(((TYPE(#{that}) == T_STRING) &&
                (RSTRING(#{this})->len == RSTRING(#{that})->len) &&
                !memcmp(#{this}, #{that}, RSTRING(#{this})->len)
               ) ? Qtrue : Qfalse)}
        }},
        [:'==',1]   => {String => lambda { |cfun, this, that|
            %{(((RSTRING(#{this})->len == RSTRING(#{that})->len) &&
                !rb_memcmp(#{this}, #{that}, RSTRING(#{this})->len)
               ) ? Qtrue : Qfalse)}
        }},
        [:'===',1]   => {String => lambda { |cfun, this, that|
            %{(((RSTRING(#{this})->len == RSTRING(#{that})->len) &&
                !rb_memcmp(#{this}, #{that}, RSTRING(#{this})->len)
               ) ? Qtrue : Qfalse)}
        }},
        [:'=~',1]  => {Regexp => lambda { |cfun, this, that|
            %{rb_reg_match(#{that}, #{this})}
        }},
        [:'<=>',1]  => {String => lambda { |cfun, this, that|
            %{rb_str_cmp(#{this}, #{that})}
        }},
        [:'[]',1]   => {nil => lambda { |cfun, this, that|
            %{rb_str_aref(#{this}, #{that})}
        }},
        [:'[]',2]  => {Fixnum => lambda { |cfun, this, index, len|
            %{rb_str_substr(#{this}, FIX2LONG(#{index}), NUM2LONG(#{len}))}
        }},
        [:'[]=',2]  => {nil => lambda { |cfun, this, that, other|
            %{rb_str_aset(#{this}, #{that}, #{other})}
        }},
        [:'<<',1]   => {nil => lambda { |cfun, this, that|
            %{rb_str_concat(#{this}, #{that})}
        }},
        [:'empty?',0] => lambda { |cfun, this|
            %{(RSTRING(#{this})->len ? Qfalse : Qtrue)}
        },
        [:'length',0] => lambda { |cfun, this|
            %{LONG2NUM(RSTRING(#{this})->len)}
        },
        [:'size',0]   => lambda { |cfun, this|
            %{LONG2NUM(RSTRING(#{this})->len)}
        },
        [:'slice',1]  => {nil => lambda { |cfun, this, that|
            %{rb_str_aref(#{this}, #{that})}
        }},
        [:'slice',2]  => {Fixnum => lambda { |cfun, this, index, len|
            %{rb_str_substr(#{this}, FIX2LONG(#{index}), NUM2LONG(#{len}))}
        }},
        [:'concat',1] => {nil => lambda { |cfun, this, that|
            %{rb_str_concat(#{this}, #{that})}
        }},
        [:'to_sym',0] => lambda { |cfun, this|
            %{rb_str_intern(#{this})}
        },
        [:'intern',0] => lambda { |cfun, this|
            %{rb_str_intern(#{this})}
        },
        [:'inspect',0] => lambda { |cfun, this|
            %{rb_str_inspect(#{this})}
        },
        [:'dump',0] => lambda { |cfun, this|
            %{rb_str_dump(#{this})}
        },
        [:'to_s',0] => lambda { |cfun, this|
            this
        },
        [:'to_str',0] => lambda { |cfun, this|
            this
        },
        [:'to_i',0] => lambda { |cfun, this|
            %{rb_str_to_inum(#{this}, 10, Qfalse)}
        },
        [:'hex',0] => lambda { |cfun, this|
            %{rb_str_to_inum(#{this}, 16, Qfalse)}
        },
        [:'oct',0] => lambda { |cfun, this|
            %{rb_str_to_inum(#{this}, -8, Qfalse)}
        },
    })

    INLINE[Array] = COMMON.merge({
        [:'eql?',1] => {
        },
        [:'==',1] => {
        },
        [:'===',1] => {
        },
        [:'to_s',0] => lambda { |cfun, this|
            %{rb_ary_to_s(#{this})}
        },
        [:'to_a',0] => lambda { |cfun, this|
            this
        },
        [:'to_ary',0] => lambda { |cfun, this|
            this
        },
        [:'slice',1] => {
            Fixnum => lambda { |cfun, this, index|
            },
            nil => lambda { |cfun, this, index|
                %{rb_ary_aref(1, &#{index}, #{this})}
            }
        },
        [:'slice',2] => {
            nil => lambda { |cfun, this, beg, len, *|
                cfun.c_scope_res {
                    cfun.l("long beg = NUM2LONG(#{beg});")
                    cfun.l("if (beg<0) beg += RARRAY(#{this})->len;")
                    %{rb_ary_subseq(#{this}, beg, #{len})}
                }
            }
        },
        [:'[]',1] => {
            Fixnum => lambda { |cfun, this, index|
            },
            nil => lambda { |cfun, this, index|
                %{rb_ary_aref(1, &#{index}, #{this})}
            }
        },
        [:'[]',2] => {
            nil => lambda { |cfun, this, beg, len, *|
                cfun.c_scope_res {
                    cfun.l("long beg = NUM2LONG(#{beg});")
                    cfun.l("if (beg<0) beg += RARRAY(#{this})->len;")
                    %{rb_ary_subseq(#{this}, beg, #{len})}
                }
            }
        },
        [:'[]=',2] => {Fixnum => lambda { |cfun, this, index, val|
            cfun.l("rb_ary_store(#{this}, FIX2LONG(index), val);")
            val
        }},
        [:'at',1] => {nil => lambda { |cfun, this, that|
            %{rb_ary_entry(#{this}, NUM2LONG(#{that}))}
        }},
        [:'first',0] => lambda { |cfun, this|
            %{((RARRAY(#{this})->len == 0) ? Qnil : RARRAY(#{this})->ptr[0])}
        },
        [:'last',0] => lambda { |cfun, this|
            %{((RARRAY(#{this})->len == 0) ? Qnil : RARRAY(#{this})->ptr[RARRAY(#{this})->len-1])}
        },
        [:'concat',1] => {nil => lambda { |cfun, this, that|
            %{rb_ary_concat(#{this}, #{that})}
        }},
        [:'<<',1] => {nil => lambda { |cfun, this, that|
            %{rb_ary_push(#{this}, #{that})}
        }},
        [:'push',1] => {nil => lambda { |cfun, this, that|
            %{rb_ary_push(#{this}, #{that})}
        }},
        [:'pop',0] => lambda { |cfun, this|
            %{rb_ary_pop(#{this})}
        },
        [:'shift',0] => lambda { |cfun, this|
            %{rb_ary_shift(#{this})}
        },
        [:'unshift',1] => {nil => lambda { |cfun, this, that|
            %{rb_ary_unshift(#{this}, #{that})}
        }},
        [:'length',0] => lambda { |cfun, this|
            %{LONG2NUM(RARRAY(#{this})->len)}
        },
        [:'size',0] => lambda { |cfun, this|
            %{LONG2NUM(RARRAY(#{this})->len)}
        },
        [:'empty?',0] => lambda { |cfun, this|
            %{(RARRAY(#{this})->len ? Qfalse : Qtrue)}
        },
        [:'reverse!',0] => lambda { |cfun, this|
            %{rb_ary_reverse(#{this})}
        },
        [:'delete_at',1] => {nil => lambda { |cfun, this, that|
            %{rb_ary_delete_at(#{this}, NUM2LONG(#{that}))}
        }},
        [:'clear',0] => lambda { |cfun, this|
            %{rb_ary_clear(#{this})}
        },
        [:'include?',1] => {nil => lambda { |cfun, this, that|
            %{rb_ary_includes(#{this}, #{that})}
        }},
        [:'<=>',1] => {nil => lambda { |cfun, this, that|
            %{rb_ary_cmp(#{this}, #{that})}
        }},
        [:'+',1] => {nil => lambda { |cfun, this, that|
            %{rb_ary_plus(#{this}, #{that})}
        }},
        [:'join',1] => {nil => lambda { |cfun, this, that|
            %{rb_ary_join(#{this}, #{that})}
        }},
    })

    INLINE[Hash] = COMMON.merge({
        [:'eql?',1] => {
        },
        [:'==',1] => {
        },
        [:'===',1] => {
        },
        [:'to_hash',0] => lambda { |cfun, this|
            this
        },
        [:'[]',1] => {nil => lambda { |cfun, this, that|
            %{rb_hash_aref(#{this}, #{that})}
        }},
        [:'[]=',2] => {nil => lambda { |cfun, this, that, other|
            %{rb_hash_aset(#{this}, #{that}, #{other})}
        }},
        [:'store',2] => {nil => lambda { |cfun, this, that, other|
            %{rb_hash_aset(#{this}, #{that}, #{other})}
        }},
        [:'length',0] => lambda { |cfun, this|
            %{INT2FIX(RHASH(#{this})->tbl->num_entries)}
        },
        [:'size',0] => lambda { |cfun, this|
            %{INT2FIX(RHASH(#{this})->tbl->num_entries)}
        },
        [:'empty?',0] => lambda { |cfun, this|
            %{(RHASH(#{this})->tbl->num_entries ? Qfalse : Qtrue)}
        },
        [:'delete',1] => {nil => lambda { |cfun, this, that|
            %{rb_hash_delete(#{this}, #{that})}
        }},
    })

    INLINE[Range] = COMMON.merge({
        [:'eql?',1] => {nil => lambda { |cfun, this, that|
            %{((rb_obj_is_instance_of(#{that}, rb_obj_class(#{this})) &&
                (rb_eql(rb_ivar_get(#{this}, #{cfun.sym(:begin)}), rb_ivar_get(#{that}, #{cfun.sym(:begin)}))) &&
                (rb_eql(rb_ivar_get(#{this}, #{cfun.sym(:end)}), rb_ivar_get(#{that}, #{cfun.sym(:end)}))) &&
                (rb_eql(rb_ivar_get(#{this}, #{cfun.sym(:excl)}), rb_ivar_get(#{that}, #{cfun.sym(:excl)})))
              ) ? Qtrue : Qfalse)}
        }},
        [:'==',1] => {nil => lambda { |cfun, this, that|
            %{((rb_obj_is_instance_of(#{that}, rb_obj_class(#{this})) &&
                (rb_equal(rb_ivar_get(#{this}, #{cfun.sym(:begin)}), rb_ivar_get(#{that}, #{cfun.sym(:begin)}))) &&
                (rb_equal(rb_ivar_get(#{this}, #{cfun.sym(:end)}), rb_ivar_get(#{that}, #{cfun.sym(:end)}))) &&
                (rb_equal(rb_ivar_get(#{this}, #{cfun.sym(:excl)}), rb_ivar_get(#{that}, #{cfun.sym(:excl)})))
              ) ? Qtrue : Qfalse)}
        }},
        [:'===',1] => {
        },
        [:'first',0] => lambda { |cfun, this|
            %{rb_ivar_get(#{this}, #{cfun.sym(:begin)})}
        },
        [:'begin',0] => lambda { |cfun, this|
            %{rb_ivar_get(#{this}, #{cfun.sym(:begin)})}
        },
        [:'last',0] => lambda { |cfun, this|
            %{rb_ivar_get(#{this}, #{cfun.sym(:end)})}
        },
        [:'end',0] => lambda { |cfun, this|
            %{rb_ivar_get(#{this}, #{cfun.sym(:end)})}
        },
        [:'exclude_end?',0] => lambda { |cfun, this|
            %{rb_ivar_get(#{this}, #{cfun.sym(:excl)})}
        },
    })

    INLINE[Regexp] = COMMON.merge({
        [:'eql?',1] => {
        },
        [:'==',1] => {
        },
        [:'===',1] => {String => lambda { |cfun, this, that|
            cfun.l("StringValue(#{that});")
            %{((rb_reg_search(#{this}, #{that}) < 0) ? Qfalse : Qtrue)}
        }},
        [:'=~',1] => {nil => lambda { |cfun, this, that|
            %{rb_reg_match(#{this}, #{that})}
        }},
        [:'~',0] => lambda { |cfun, this|
            %{rb_reg_match2(#{this})}
        },
    })

end

end

