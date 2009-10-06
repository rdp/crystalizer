
module Ruby2CExtension

	module CommonNodeComp

		# the comp methods need lots of methods from CFunction::Base or subclasses to work, e.g.:
		# l, assign_res, get_self, get_class, get_cbase, get_cvar_cbase,
		# scope (with get_lvar, get_lvar_idx, get_dvar, get_dvar_curr, vmode_method?, vmode_def_fun, ...)
		# un, sym, global, add_helper
		# ...

		is_ruby_185 = (RUBY_VERSION >= "1.8.5") # see below

		include Tools::EnsureNodeTypeMixin

		def c_scope
			l "{"
			yield
			l "}"
		end
		def c_scope_res
			l "{"
			assign_res(yield)
			l "}"
			"res"
		end

		def c_if(cond)
			l "if (#{cond}) {"
			yield
			l "}"
		end
		def c_else
			l "else {"
			yield
			l "}"
		end
		def c_for(exprs)
			l "for (#{exprs}) {"
			yield
			l "}"
		end

		def c_static_once
			c_scope_res {
				l "static VALUE static_once_value = Qundef;"
				c_if("static_once_value == Qundef") {
					assign_res(yield)
					# other thread might have been faster
					c_if("static_once_value == Qundef") {
						l "static_once_value = res;"
						l "rb_global_variable(&static_once_value);"
					}
				}
				"static_once_value"
			}
		end

		def get_global_entry(vid)
			g_entry = "(VALUE)rb_global_entry(#{sym(vid)})"
			"(struct global_entry*)(#{global_const(g_entry, false)})"
		end

		def make_block(block)
			if block
				block.first == :block ? block : [:block, [block]]
			else
				[:block, []]
			end
		end

		def handle_method_args(arg, block_arg)
			ensure_node_type(arg, :args)
			# handle arg
			arg = arg.last
			cnt = arg[:cnt]
			opt = make_block(arg[:opt]).last
			rest = arg[:rest] || -1
			if Array === rest # 1.8.5 change
				ensure_node_type(rest, :lasgn)
				if rest.last[:vid] == 0 # e.g. def foo(*); end
					rest = -2
				else
					rest = rest.last[:cnt]
				end
			end
			rest = rest - 2
			need_wrong_arg_num_helper = false
			if opt.empty? && rest == -3 # then it was rest == -1, which means no rest_arg
				l "if (meth_argc != #{cnt}) wrong_arg_num(meth_argc, #{cnt});"
				need_wrong_arg_num_helper = true
			else
				if cnt > 0
					l "if (meth_argc < #{cnt}) wrong_arg_num(meth_argc, #{cnt});"
					need_wrong_arg_num_helper = true
				end
				if rest == -3 # then it was rest == -1, which means no rest_arg
					l "if (meth_argc > #{cnt + opt.size}) wrong_arg_num(meth_argc, #{cnt + opt.size});"
					need_wrong_arg_num_helper = true
				end
			end
			if need_wrong_arg_num_helper
				add_helper <<-EOC
					static void wrong_arg_num(int argc, int exp) {
						rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)", argc, exp);
					}
				EOC
			end
			(0...cnt).each { |i|
				l "#{scope.get_lvar_idx(i)} = meth_argv[#{i}];"
			}
			opt.each_with_index { |asgn, i|
				c_if("meth_argc > #{cnt + i}") {
					l "#{scope.get_lvar_idx(cnt + i)} = meth_argv[#{cnt + i}];"
				}
				c_else {
					l "#{comp(asgn)};"
				}
			}
			if rest >= 0
				sum = cnt + opt.size
				c_if("meth_argc > #{sum}") {
					l "#{scope.get_lvar_idx(rest)} = rb_ary_new4(meth_argc-#{sum}, meth_argv+#{sum});"
				}
				c_else {
					l "#{scope.get_lvar_idx(rest)} = rb_ary_new2(0);"
				}
			end

			# handle block arg if available
			if block_arg
				ensure_node_type(block_arg, :block_arg)
				c_if("rb_block_given_p()") {
					l "#{scope.get_lvar(block_arg.last[:vid])} = rb_block_proc();"
				}
				# no else, lvars are initialized to nil
			end
		end

		def comp(node)
			case node
			when false
				"Qnil"
			when String
				node
			else
				while (ntype = node.first) == :newline
					node = node.last[:next]
				end
				orig_node = node
				l "/* #{ntype} */"
				begin
					if (pps = compiler.preprocessors_for(ntype))
						# apply each preprocessor until one returns a string or
						# a different node type
						pps.each { |pp_proc|
							node = pp_proc[self, node]
							break unless Array === node && node.first == ntype
						}
					end
					if Array === node && node.first == ntype
						__send__("comp_#{ntype}", node.last)
					else
						# retry with the result of preprocessing
						comp(node)
					end
				rescue Ruby2CExtError => e
					if Hash === orig_node.last && (n = orig_node.last[:node])
						# add file and line to message
						raise "#{n.file}:#{n.line}: #{e}"
					else
						raise # reraise
					end
				end
			end
		end

		def comp_block(exprs)
			return "Qnil" if exprs.empty?
			last = exprs.last
			exprs[0..-2].each { |ex|
				l "#{comp(ex)};"
			}
			comp(last)
		end

		def comp_vcall(hash)
			if scope.vmode_method?(hash[:mid])
				"Qnil"
			else
				"rb_funcall2(#{get_self}, #{sym(hash[:mid])}, 0, 0)"
			end
		end

		def build_c_arr(arr, var_name, extra = 0)
			l "VALUE #{var_name}[#{arr.size + extra}];"
			arr.each_with_index { |n, i|
				l "#{var_name}[#{i}] = #{comp(n)};"
			}
		end
		def build_args(args, one_extra = false)
			if args.first == :array
				l "const int argc = #{args.last.size};"
				build_c_arr(args.last, "argv", one_extra ? 1 : 0)
			else
				l "int argc; VALUE *argv;"
				l "volatile VALUE argv_ary;" if in_while?
				assign_res(comp(args))
				l "if (TYPE(res) != T_ARRAY) res = rb_ary_to_ary(res);"
				l "argc = RARRAY(res)->len;"
				if in_while?
					# don't use ALLOCA_N in a while loop to avoid a stack overflow
					l "argv_ary = rb_ary_dup(res);"
					l "rb_ary_push(argv_ary, Qnil);" if one_extra
					l "argv = RARRAY(argv_ary)->ptr;"
				else
					l "argv = ALLOCA_N(VALUE, argc#{one_extra ? " + 1" : ""});"
					l "MEMCPY(argv, RARRAY(res)->ptr, VALUE, argc);"
				end
			end
		end

		NON_ITER_PROC = proc { |str, args, arg_types| str % args }

		def do_funcall(recv, mid, args, allow_private, iter_proc)
			iter_proc ||= NON_ITER_PROC
			fun = "rb_funcall#{allow_private ? 2 : 3}"
			if args
				c_scope_res {
					l "VALUE recv = #{recv};"
					build_args(args)
					iter_proc["#{fun}(%s, #{sym(mid)}, %s, %s)", %w[recv argc argv], %w[VALUE int VALUE*]]
				}
			else
				if allow_private && iter_proc == NON_ITER_PROC
					if scope.vmode_method?(mid)
						return "Qnil"
					end
				end
				iter_proc["#{fun}(%s, #{sym(mid)}, 0, 0)", [recv], %w[VALUE]]
			end
		end

		def comp_fcall(hash, &iter_proc)
			do_funcall(get_self, hash[:mid], hash[:args], true, iter_proc)
		end

		def comp_call(hash, &iter_proc)
			do_funcall(comp(hash[:recv]), hash[:mid], hash[:args], false, iter_proc)
		end

		def comp_attrasgn(hash)
			fun = "rb_funcall#{hash[:recv] == 0 ? 2 : 3}"
			recv = (hash[:recv] == 0 ? get_self : comp(hash[:recv]))
			c_scope_res {
				l "VALUE recv = #{recv};"
				build_args(hash[:args])
				l "#{fun}(recv, #{sym(hash[:mid])}, argc, argv);"
				"argv[argc - 1]"
			}
		end

		def helper_super_allowed_check
			# last_func is set to 0 by rb_require_safe
			add_helper <<-EOC
				static void super_allowed_check() {
					if (!ruby_frame->last_func) {
						rb_raise(rb_eNoMethodError, "super called outside of method");
					}
				}
			EOC
		end

		if is_ruby_185
			def comp_zsuper(hash, &iter_proc)
				if CFunction::Method === self
					# super zsuper only in a method in 1.8.5
					iter_proc ||= NON_ITER_PROC
					helper_super_allowed_check
					l "super_allowed_check();"
					# this is not 100% equivalent to 1.8.5 behavior ...
					iter_proc["rb_call_super(%s, %s)", %w[meth_argc meth_argv], %w[int VALUE*]]
				else
					raise Ruby2CExtError::NotSupported, "super without explicit arguments is not supported here"
				end
			end
		else
			def comp_zsuper(hash, &iter_proc)
				iter_proc ||= NON_ITER_PROC
				helper_super_allowed_check
				l "super_allowed_check();"
				iter_proc["rb_call_super(ruby_frame->argc, ruby_frame->argv)", [], []]
			end
		end

		def comp_super(hash, &iter_proc)
			iter_proc ||= NON_ITER_PROC
			helper_super_allowed_check
			l "super_allowed_check();"
			args = hash[:args]
			if args
				c_scope_res {
					build_args(args)
					iter_proc["rb_call_super(%s, %s)", %w[argc argv], %w[int VALUE*]]
				}
			else
				iter_proc["rb_call_super(0, 0)", [], []]
			end
		end

		def comp_lit(hash)
			case (l = hash[:lit])
			when Fixnum
				"LONG2FIX(#{l.inspect})"
			when Symbol
				"ID2SYM(#{sym(l)})"
			when Bignum
				global_const("rb_cstr_to_inum(#{l.to_s.to_c_strlit}, 10, Qfalse)")
			when Float
				global_const("rb_float_new(%.40e)" % l)
			when Range
				global_const("rb_range_new(#{comp_lit(:lit=>l.first)}, #{comp_lit(:lit=>l.last)}, Q#{l.exclude_end?})")
			when Regexp
				s = l.source
				global_const("rb_reg_new(#{s.to_c_strlit}, #{s.size}, #{l.options})")
			else
				raise Ruby2CExtError::Bug, "unsupported literal type: #{l.inspect}"
			end
		end

		def comp_nil(hash); "Qnil"; end
		def comp_false(hash); "Qfalse"; end
		def comp_true(hash); "Qtrue"; end
		def comp_self(hash); get_self; end

		def comp_argscat(hash)
			c_scope_res {
				l "VALUE head, body;"
				l "head = #{comp(hash[:head])};"
				l "body = #{comp(hash[:body])};"
				l "body = (NIL_P(body) ? rb_ary_new3(1, Qnil) : rb_Array(body));"
				"rb_ary_concat(head, body)"
			}
		end
		def comp_argspush(hash)
			# argspush is used in a[2,*a]=4 for example
			c_scope_res {
				l "VALUE head;"
				l "head = rb_ary_dup(#{comp(hash[:head])});"
				"rb_ary_push(head, #{comp(hash[:body])})"
			}
		end

		def comp_begin(hash)
			comp(make_block(hash[:body]))
		end

		def comp_if(hash)
			cond = comp(hash[:cond])
			if !hash[:body] && !hash[:else]
				l cond + ";"
				"Qnil"
			else
				c_if("RTEST(#{cond})") {
					assign_res(comp(hash[:body]))
				}
				c_else {
					assign_res(comp(hash[:else]))
				}
				"res"
			end
		end

		def comp_postexe(hash, &iter_proc)
			raise Ruby2CExtError, "postexe only allowed with iter" unless iter_proc
			c_scope {
				l "static int done = 0;"
				c_if("!done") {
					l "done = 1;"
					# compile as at_exit (rb_f_END() is static)
					l do_funcall(get_self, :at_exit, false, true, iter_proc)
				}
			}
			"Qnil"
		end

		def comp_match(hash)
			"rb_reg_match2(#{comp_lit(hash)})"
		end
		def comp_match2(hash)
			c_scope_res {
				l "VALUE recv;"
				l "recv = #{comp(hash[:recv])};"
				"rb_reg_match(recv, #{comp(hash[:value])})"
			}
		end
		def comp_match3(hash)
			c_scope_res {
				l "VALUE recv, val;"
				l "recv = #{comp(hash[:recv])};"
				l "val = #{comp(hash[:value])};"
				"(TYPE(val) == T_STRING ? rb_reg_match(recv, val) : rb_funcall(val, #{sym(:=~)}, 1, recv))"
			}
		end

		def handle_when(hash, test_proc)
			ensure_node_type(head = hash[:head], :array)
			c_scope_res {
				l "int when_handle = 1;"
				head.last.each { |check|
					if check.first == :when
						l "VALUE arr; long i;"
						l "arr = #{comp(check.last[:head])};"
						l "if (TYPE(arr) != T_ARRAY) arr = rb_ary_to_ary(arr);"
						c_for("i = 0; i < RARRAY(arr)->len; ++i") {
							c_if("RTEST(#{test_proc["RARRAY(arr)->ptr[i]"]})") {
								l "arr = Qfalse;"
								l "break;"
							}
						}
						l "if (RTEST(arr)) {"
					else
						l "if (!RTEST(#{test_proc[check]})) {"
					end
				}
				l "when_handle = 0;" # here all checks failed
				head.last.size.times { l "}" }
				c_if("when_handle") {
					assign_res(comp(hash[:body]))
				}
				c_else {
					if Array === hash[:next] && hash[:next].first == :when
						assign_res(handle_when(hash[:next].last, test_proc))
					else
						assign_res(comp(hash[:next]))
					end
				}
				"res"
			}
		end
		def comp_when(hash)
			handle_when(hash, proc { |val| comp(val) })
		end
		def comp_case(hash)
			ensure_node_type(hash[:body], :when)
			c_scope_res {
				l "VALUE case_val;"
				l "case_val = #{comp(hash[:head])};"
				handle_when(hash[:body].last, proc { |val|
					# Ruby 1.8.4 actually uses rb_funcall2, but a :call node
					# (which uses rb_funcall3) is more correct
					comp([:call, {:mid => :===, :recv => val, :args => [:array, ["case_val"]]}])
				})
			}
		end

		def comp_while(hash, is_until = false)
			redo_lbl = un("while_redo")
			next_lbl = un("while_next")
			break_lbl = un("while_break")
			c_scope_res {
				l "VALUE while_res = Qnil;"
				c_for(";;") {
					l "if (#{is_until ? "" : "!"}RTEST(#{comp(hash[:cond])})) break;" if hash[:state] != 0
					l "#{redo_lbl}:"
					push_while(redo_lbl, next_lbl, break_lbl)
					l "#{comp(hash[:body])};"
					pop_while
					l "#{next_lbl}: ;"
					l "if (#{is_until ? "" : "!"}RTEST(#{comp(hash[:cond])})) break;" if hash[:state] == 0
				}
				l "#{break_lbl}:"
				"while_res"
			}
		end
		def comp_until(hash)
			comp_while(hash, true)
		end

		def handle_iter(iter, bl_fun, closure)
			ensure_node_type(iter, [:call, :fcall, :super, :zsuper, :postexe]) # attrasgn ???
			l "do {"
			block_calls = 0
			assign_res(__send__("comp_#{iter.first}", iter.last) { |str, args, arg_types|
				block_calls += 1
				c_scope_res {
					l "VALUE iter_data[#{args.size + 1}];"
					l "iter_data[0] = Qfalse;"
					args.each_with_index { |arg, i|
						l "iter_data[#{i + 1}] = (VALUE)(#{arg});"
					}
					iter_data_cast = []
					arg_types.each_with_index { |arg_type, i|
						iter_data_cast << "(#{arg_type})(iter_data[#{i + 1}])"
					}
					it_fun = compiler.add_fun(<<-EOC.chomp % iter_data_cast, "iterate")
						static VALUE FUNNAME(VALUE data) {
							VALUE *iter_data = (VALUE*)data;
							ruby_top_self = org_ruby_top_self;
							if (iter_data[0]) return Qundef;
							iter_data[0] = Qtrue;
							return #{str};
						}
					EOC
					# hack to make instance_eval etc. work (rb_iterate() uses ruby_top_self as block.self)
					# this _should_ be save, because rb_trap_immediate should always be 0 here ...
					l "ruby_top_self = Qundef;"
					"rb_iterate(#{it_fun}, (VALUE)iter_data, #{bl_fun}, #{closure})"
				}
			})
			raise Ruby2CExtError::Bug, "internal error while compiling iter" unless block_calls == 1
			l "}"
			l "while (res == Qundef);"
			"res"
		end

		def comp_block_pass(hash)
			# TODO: is just a workaround/hack, does not work with instance_eval etc.
			c_scope_res {
				l "VALUE proc;"
				l "proc = #{comp(hash[:body])};"
				iter = hash[:iter]
				c_if("NIL_P(proc)") {
					assign_res(__send__("comp_#{iter.first}", iter.last))
				}
				c_else {
					# rb_obj_is_proc is static in eval.c, so we just convert and hope the best...
					add_helper <<-EOC
						#define PROC_TSHIFT (FL_USHIFT+1)
						#define PROC_TMASK  (FL_USER1|FL_USER2|FL_USER3)
						static VALUE obj_to_proc(VALUE proc) {
							VALUE tmp;
							tmp = rb_check_convert_type(proc, T_DATA, "Proc", "to_proc");
							if (rb_class_real(CLASS_OF(tmp)) != rb_cProc)
								rb_raise(rb_eTypeError, "wrong argument type %s (expected Proc)", rb_obj_classname(proc));
							proc = tmp;
							if (ruby_safe_level >= 1 && OBJ_TAINTED(proc) &&
								ruby_safe_level > ((RBASIC(proc)->flags & PROC_TMASK) >> PROC_TSHIFT))
								rb_raise(rb_eSecurityError, "Insecure: tainted block value");
							return proc;
						}
					EOC
					l "proc = obj_to_proc(proc);"
					add_helper <<-EOC
						static VALUE block_pass_helper_block(VALUE bl_val, VALUE proc, VALUE self) {
							if (ruby_current_node->nd_state != 1) {
								if (bl_val == Qundef) bl_val = rb_ary_new2(0);
								else {
									VALUE tmp = rb_check_array_type(bl_val);
									bl_val = (NIL_P(tmp) ? rb_ary_new3(1, bl_val) : tmp);
								}
							}
							if (RARRAY(bl_val)->len == 0) return rb_funcall3(proc, #{sym(:call)}, 0, 0);
							else {
								int argc = RARRAY(bl_val)->len;
								VALUE *argv = ALLOCA_N(VALUE, argc);
								MEMCPY(argv, RARRAY(bl_val)->ptr, VALUE, argc);
								return rb_funcall3(proc, #{sym(:call)}, argc, argv);
							}
						}
						EOC
					assign_res(handle_iter(iter, "block_pass_helper_block", "proc"))
				}
				"res"
			}
		end

		def comp_for(hash)
			# transform to equivalent iter node
			hash = hash.dup
			hash[:iter] = [:call, {:args=>false, :mid=>:each, :recv=>hash[:iter]}]
			comp_iter(hash)
		end

		def comp_iter(hash)
			bl_fun, need_clos = CFunction::Block.compile(self, make_block(hash[:body]), hash[:var])
			handle_iter(hash[:iter], bl_fun, need_clos ? get_closure_ary_var : "Qnil")
		end

		def comp_break(hash)
			# must be implemented by the "user" of CommonNodeComp
			raise Ruby2CExtError::NotSupported, "break is not supported"
		end
		def comp_next(hash)
			# must be implemented by the "user" of CommonNodeComp
			raise Ruby2CExtError::NotSupported, "next is not supported"
		end
		def comp_redo(hash)
			# must be implemented by the "user" of CommonNodeComp
			raise Ruby2CExtError::NotSupported, "redo is not supported"
		end
		def comp_return(hash)
			# must be implemented by the "user" of CommonNodeComp
			raise Ruby2CExtError::NotSupported, "return is not supported"
		end
		def comp_retry(hash)
			# must be implemented by the "user" of CommonNodeComp
			raise Ruby2CExtError::NotSupported, "retry is not supported"
		end

		def comp_splat(hash)
			assign_res(comp(hash[:head]))
			"(NIL_P(res) ? rb_ary_new3(1, Qnil) : rb_Array(res))"
		end
		def comp_to_ary(hash)
			"rb_ary_to_ary(#{comp(hash[:head])})"
		end
		def comp_svalue(hash)
			assign_res(comp(hash[:head]))
			"(RARRAY(res)->len == 1 ? RARRAY(res)->ptr[0] : (RARRAY(res)->len == 0 ? Qnil : res))"
		end

		def comp_yield(hash)
			val = (hash[:head] ? comp(hash[:head]) : "Qundef")
			"rb_yield#{hash[:state] == 0 ? "" : "_splat"}(#{val})"
		end

		def comp_rescue(hash)
			ensure_node_type(resb = hash[:resq], :resbody)
			# compile the real body
			cflow_hash = {}
			body = CFunction::Wrap.compile(self, "rescue_body", cflow_hash) { |cf|
				cf.instance_eval {
					l "#{get_wrap_ptr}->state |= 1;"
					comp(hash[:head])
				}
			}
			# now all the resbodies in one c function
			res_bodies = CFunction::Wrap.compile(self, "rescue_resbodies", cflow_hash) { |cf|
				cf.instance_eval {
					cnt = 0
					while resb
						cnt += 1
						args = resb.last[:args]
						unless args
							l "if (rb_obj_is_kind_of(ruby_errinfo, rb_eStandardError)) {"
						else
							add_helper <<-EOC
								static void rescue_mod_check(VALUE mod) {
									if (!rb_obj_is_kind_of(mod, rb_cModule)) {
										rb_raise(rb_eTypeError, "class or module required for rescue clause");
									}
								}
							EOC
							if args.first == :array # TODO
								# ruby doesn't handle this case specially, but it might be faster this way
								# (on the other side: we might miss exceptions (for not evaluated entries of the array))
								args.last.each { |ex|
									assign_res(comp(ex))
									l "rescue_mod_check(res);"
									l "if (!RTEST(rb_funcall(res, #{sym(:===)}, 1, ruby_errinfo))) {"
								}
								# non did match
								assign_res("Qfalse")
								# close all ifs
								args.last.size.times { l "}" }
							else
								c_scope {
									l "int i = 0;"
									# TODO: ruby has BEGIN_CALLARGS protection here, is this really necessary???
									build_args(args)
									assign_res("Qfalse")
									c_for("; i < argc; ++i") {
										l "rescue_mod_check(argv[i]);"
										c_if("RTEST(rb_funcall(argv[i], #{sym(:===)}, 1, ruby_errinfo))") {
											assign_res("Qtrue");
											l "break;"
										}
									}
								}
							end
							l "if (res) {"
						end
						l "#{get_wrap_ptr}->state &= ~1;" # set first bit = 0
						assign_res(comp(resb.last[:body]))
						l "}"
						l "else {"
						resb = resb.last[:head]
					end
					# we are in the last else, if the exception wasn't handled, then reraise
					l "rb_jump_tag(0x6 /* TAG_RAISE */);"
					# close all elses
					cnt.times { l "}" }
				}
				"res"
			}
			# now call rb_rescue2 with the two bodies (and handle else if necessary)
			c_scope_res {
				else_node = hash[:else]
				l "long save_state = #{get_wrap_ptr}->state;"
				l "long do_else;" if else_node
				wp = "(VALUE)#{get_wrap_ptr}"
				assign_res("rb_rescue2(#{body}, #{wp}, #{res_bodies}, #{wp}, rb_eException, (VALUE)0)")
				l "do_else = #{get_wrap_ptr}->state & 1;" if else_node
				l "#{get_wrap_ptr}->state = (#{get_wrap_ptr}->state & ~1) | (save_state & 1);" # restore the 1st bit of save_state
				CFunction::Wrap::handle_wrap_cflow(self, cflow_hash)
				if else_node
					c_if("do_else") {
						assign_res(comp(else_node))
					}
				end
				"res"
			}
		end

		def comp_ensure(hash)
			cflow_hash = {}
			b = CFunction::Wrap.compile(self, "ensure_body", cflow_hash) { |cf| cf.comp(hash[:head]) }
			e = CFunction::Wrap.compile(self, "ensure_ensure") { |cf| cf.comp(hash[:ensr]) } # ensr without cflow
			ensr_code = "rb_ensure(#{b}, (VALUE)#{get_wrap_ptr}, #{e}, (VALUE)#{get_wrap_ptr})"
			if cflow_hash.empty?
				ensr_code
			else
				assign_res(ensr_code)
				CFunction::Wrap::handle_wrap_cflow(self, cflow_hash)
				"res"
			end
		end

		def comp_and(hash)
			assign_res(comp(hash[:first]))
			c_if("RTEST(res)") {
				assign_res(comp(hash[:second]))
			}
			"res"
		end
		def comp_or(hash)
			assign_res(comp(hash[:first]))
			c_if("!RTEST(res)") {
				assign_res(comp(hash[:second]))
			}
			"res"
		end
		def comp_not(hash)
			"(RTEST(#{comp(hash[:body])}) ? Qfalse : Qtrue)"
		end

		def handle_dot(hash, dot3)
			c_scope_res {
				l "VALUE beg;"
				l "beg = #{comp(hash[:beg])};"
				"rb_range_new(beg, #{comp(hash[:end])}, Q#{dot3})"
			}
		end
		def comp_dot2(hash)
			handle_dot(hash, false)
		end
		def comp_dot3(hash)
			handle_dot(hash, true)
		end

		def handle_flip(hash, flip3)
			flip_var = scope.get_lvar_idx(hash[:cnt] - 2)
			c_if("RTEST(#{flip_var})") {
				l "if (RTEST(#{comp(hash[:end])})) #{flip_var} = Qfalse;"
				assign_res("Qtrue")
			}
			c_else {
				if flip3
					assign_res("(RTEST(#{comp(hash[:beg])}) ? Qtrue : Qfalse)")
					l "#{flip_var} = res;"
				else
					assign_res(c_scope_res {
						l "VALUE beg_res;"
						l "beg_res = (RTEST(#{comp(hash[:beg])}) ? Qtrue : Qfalse);"
						c_if("beg_res") {
							l "#{flip_var} = (RTEST(#{comp(hash[:end])}) ? Qfalse : Qtrue);"
						}
						"beg_res"
					})
				end
			}
			"res"
		end
		def comp_flip2(hash)
			handle_flip(hash, false)
		end
		def comp_flip3(hash)
			handle_flip(hash, true)
		end

		if is_ruby_185
			# Ruby 1.8.5
			def comp_op_asgn1(hash)
				ensure_node_type(hash[:args], :argscat)
				c_scope_res {
					l "VALUE oa1_recv, oa1_val;"
					l "oa1_recv = #{comp(hash[:recv])};"
					c_scope_res {
						build_args(hash[:args].last[:body], true)
						l "oa1_val = rb_funcall3(oa1_recv, #{sym(:[])}, argc, argv);"
						mid = hash[:mid]
						rval = hash[:args].last[:head]
						if Symbol === mid
							call = [:call, {:recv=>"oa1_val", :mid=>mid, :args=>[:array, [rval]]}]
							l "oa1_val = #{comp(call)};"
							l "{"
						else
							# mid == 0 is OR, mid == 1 is AND
							l "if (#{mid == 0 ? "!" : ""}RTEST(oa1_val)) {"
							l "oa1_val = #{comp(rval)};"
						end
						l "argv[argc] = oa1_val;"
						l "rb_funcall2(oa1_recv, #{sym(:[]=)}, argc + 1, argv);"
						l "}"
						"oa1_val"
					}
				}
			end
			def comp_op_asgn2(hash)
				ensure_node_type(ids = hash[:next], :op_asgn2)
				ids = ids.last
				c_scope_res {
					l "VALUE oa2_recv, oa2_val;"
					l "oa2_recv = #{comp(hash[:recv])};"
					call = [:call, {:recv=>"oa2_recv", :mid=>ids[:vid], :args=>false}]
					l "oa2_val = #{comp(call)};"
					mid = ids[:mid]
					if Symbol === mid
						call = [:call, {:recv=>"oa2_val", :mid=>mid, :args=>[:array, [hash[:value]]]}]
						l "oa2_val = #{comp(call)};"
						l "{"
					else
						# mid == 0 is OR, mid == 1 is AND
						l "if (#{mid == 0 ? "!" : ""}RTEST(oa2_val)) {"
						l "oa2_val = #{comp(hash[:value])};"
					end
					l "rb_funcall2(oa2_recv, #{sym(ids[:aid])}, 1, &oa2_val);"
					l "}"
					"oa2_val"
				}
			end
		else
			# Ruby 1.8.4
			def comp_op_asgn1(hash)
				ensure_node_type(hash[:args], :array)
				c_scope_res {
					l "VALUE recv, val;"
					l "recv = #{comp(hash[:recv])};"
					c_scope_res {
						build_args([:array, hash[:args].last[1..-1]])
						l "val = rb_funcall2(recv, #{sym(:[])}, argc-1, argv);"
						mid = hash[:mid]
						if Symbol === mid
							l "val = rb_funcall(val, #{sym(mid)}, 1, #{comp(hash[:args].last.first)});"
							l "{"
						else
							# mid == 0 is OR, mid == 1 is AND
							l "if (#{mid == 0 ? "!" : ""}RTEST(val)) {"
							l "val = #{comp(hash[:args].last.first)};"
						end
						l "argv[argc-1] = val;"
						l "rb_funcall2(recv, #{sym(:[]=)}, argc, argv);"
						l "}"
						"val"
					}
				}
			end
			def comp_op_asgn2(hash)
				ensure_node_type(ids = hash[:next], :op_asgn2)
				ids = ids.last
				c_scope_res {
					l "VALUE recv, val;"
					l "recv = #{comp(hash[:recv])};"
					l "val = rb_funcall(recv, #{sym(ids[:vid])}, 0);"
					mid = ids[:mid]
					if Symbol === mid
						l "val = rb_funcall(val, #{sym(mid)}, 1, #{comp(hash[:value])});"
						l "{"
					else
						# mid == 0 is OR, mid == 1 is AND
						l "if (#{mid == 0 ? "!" : ""}RTEST(val)) {"
						l "val = #{comp(hash[:value])};"
					end
					l "rb_funcall2(recv, #{sym(ids[:aid])}, 1, &val);"
					l "}"
					"val"
				}
			end
		end

		def comp_op_asgn_and(hash)
			assign_res(comp(hash[:head]))
			c_if("RTEST(res)") {
				assign_res(comp(hash[:value]))
			}
			"res"
		end
		def comp_op_asgn_or(hash)
			if Symbol === (aid = hash[:aid])
				def_test =
					case aid.to_s
					when /\A@@/
						"rb_cvar_defined(#{get_cvar_cbase}, #{sym(aid)})"
					when /\A@/
						"rb_ivar_defined(#{get_self}, #{sym(aid)})"
					when /\A\$/
						"rb_gvar_defined(#{get_global_entry(aid)})"
					else
						raise Ruby2CExtError::Bug, "unexpected aid for op_asgn_or: #{aid.inspect}"
					end
				c_if(def_test) {
					assign_res(comp(hash[:head]))
				}
				c_else {
					assign_res("Qnil")
				}
			else
				assign_res(comp(hash[:head]))
			end
			c_if("!RTEST(res)") {
				assign_res(comp(hash[:value]))
			}
			"res"
		end

		def comp_masgn(hash)
			c_scope_res {
				l "VALUE ma_val;"
				l "long ma_len;"
				l "ma_val = #{comp(hash[:value])};"
				l "ma_len = RARRAY(ma_val)->len;"
				head_len = 0
				if (head = hash[:head])
					ensure_node_type(head, :array)
					head_len = head.last.size
					head.last.each_with_index { |asgn, i|
						handle_assign(asgn, "(#{i} < ma_len ? RARRAY(ma_val)->ptr[#{i}] : Qnil)", false)
					}
				end
				if ((args = hash[:args]) && (args != -1))
					handle_assign(args, "(#{head_len} < ma_len ? rb_ary_new4(ma_len-#{head_len}, " +
						"RARRAY(ma_val)->ptr+#{head_len}) : rb_ary_new2(0))", false)
				end
				"ma_val"
			}
		end

		def handle_assign(asgn_node, val, undef_check = true)
			c_scope {
				if undef_check
					l "VALUE as_val;"
					l "as_val = #{comp(val)};"
					l "if (as_val == Qundef) as_val = Qnil;"
					val = "as_val"
				end
				dup_node = [asgn_node.first, asgn_node.last.dup]
				case asgn_node.first
				when :lasgn, :dasgn, :dasgn_curr, :iasgn, :gasgn, :cdecl, :cvdecl, :cvasgn
					if dup_node.last[:value]
						raise Ruby2CExtError, "unexpected value in #{asgn_node.first} node in handle_assign"
					end
					dup_node.last[:value] = val
					l "#{comp(dup_node)};"
				when :masgn
					c_scope {
						l "VALUE as_ma_val;"
						l "VALUE tmp;" if (ma_head = asgn_node.last[:head])
						l "as_ma_val = #{comp(val)};"
						# adapted from svalue_to_mrhs()
						if ma_head
							l "tmp = rb_check_array_type(as_ma_val);"
							l "as_ma_val = (NIL_P(tmp) ? rb_ary_new3(1, as_ma_val) : tmp);"
						else
							l "as_ma_val = rb_ary_new3(1, as_ma_val);"
						end
						dup_node.last[:value] = "as_ma_val"
						l "#{comp(dup_node)};"
					}
				when :attrasgn # TODO: can :call also appear here ???
					c_scope {
						l "VALUE as_aa_val;"
						l "as_aa_val = #{comp(val)};"
						if asgn_node.last[:args]
							dup_node.last[:args] = [:argspush, {:body => "as_aa_val", :head => asgn_node.last[:args]}]
						else
							dup_node.last[:args] = [:array, ["as_aa_val"]]
						end
						l "#{comp(dup_node)};"
					}
				else
					raise Ruby2CExtError::Bug, "unexpected assign node type: #{asgn_node.first}"
				end
			}
		end

		def comp_lasgn(hash)
			"(#{scope.get_lvar(hash[:vid])} = #{comp(hash[:value])})"
		end
		def comp_dasgn(hash)
			"(#{scope.get_dvar(hash[:vid])} = #{comp(hash[:value])})"
		end
		def comp_dasgn_curr(hash)
			"(#{scope.get_dvar_curr(hash[:vid])} = #{comp(hash[:value])})"
		end
		def comp_gasgn(hash)
			assign_res(comp(hash[:value]))
			l "rb_gvar_set(#{get_global_entry(hash[:vid])}, res);"
			"res"
		end
		def comp_iasgn(hash)
			assign_res(comp(hash[:value]))
			l "rb_ivar_set(#{get_self}, #{sym(hash[:vid])}, res);"
			"res"
		end

		def helper_class_module_check
			add_helper <<-EOC
				static void class_module_check(VALUE klass) {
					switch (TYPE(klass)) {
						case T_CLASS:
						case T_MODULE:
							break;
						default:
							rb_raise(rb_eTypeError, "%s is not a class/module", RSTRING(rb_obj_as_string(klass))->ptr);
					}
				}
			EOC
		end

		def make_class_prefix(node)
			ensure_node_type(node, [:colon2, :colon3])
			if node.first == :colon2
				hash = node.last
				if hash[:head]
					assign_res(comp(hash[:head]))
					helper_class_module_check
					l "class_module_check(res);"
					"res"
				else
					get_cbase
				end
			else
				"rb_cObject"
			end
		end

		def comp_cdecl(hash)
			c_scope_res {
				l "VALUE val;"
				l "val = #{comp(hash[:value])};"
				if Symbol === hash[:vid]
					l "rb_const_set(#{get_cbase}, #{sym(hash[:vid])}, val);"
				else
				  out = make_class_prefix(hash[:else])
				  l "rb_const_set(#{out}, #{sym(hash[:else].last[:mid])}, val);"
				end
				"val"
			}
		end
		def comp_cvasgn(hash, decl = false)
			assign_res(comp(hash[:value]))
			l "rb_cvar_set(#{get_cvar_cbase}, #{sym(hash[:vid])}, res, Q#{decl});"
			"res"
		end
		def comp_cvdecl(hash)
			comp_cvasgn(hash, true)
		end

		def comp_lvar(hash)
			"#{scope.get_lvar(hash[:vid])}"
		end
		def comp_dvar(hash)
			scope.get_dvar(hash[:vid])
		end
		def comp_gvar(hash)
			"rb_gvar_get(#{get_global_entry(hash[:vid])})"
		end
		def comp_ivar(hash)
			"rb_ivar_get(#{get_self}, #{sym(hash[:vid])})"
		end
		def comp_const(hash)
			add_helper <<-EOC
				static VALUE const_get(ID id, NODE *cref) {
					NODE *cbase = cref;
					VALUE result;
					while (cbase && cbase->nd_next) {
						VALUE klass = cbase->nd_clss;
						while (RCLASS(klass)->iv_tbl && st_lookup(RCLASS(klass)->iv_tbl, id, &result)) {
							if (result == Qundef) {
								if (!RTEST(rb_autoload_load(klass, id))) break;
								continue;
							}
							return result;
						}
						cbase = cbase->nd_next;
					}
					return rb_const_get(cref->nd_clss, id);
				}
			EOC
			"const_get(#{sym(hash[:vid])}, #{get_cref})"
		end
		def comp_cvar(hash)
			"rb_cvar_get(#{get_cvar_cbase}, #{sym(hash[:vid])})"
		end
		def comp_colon2(hash)
			mid = hash[:mid]
			if mid.to_s[0,1].downcase != mid.to_s[0,1] # then it is a constant
				helper_class_module_check
				assign_res(comp(hash[:head]))
				l "class_module_check(res);"
				"rb_const_get_from(res, #{sym(mid)})"
			else
				"rb_funcall(#{comp(hash[:head])}, #{sym(mid)}, 0, 0)"
			end
		end
		def comp_colon3(hash)
			"rb_const_get_from(rb_cObject, #{sym(hash[:mid])})"
		end

		def comp_nth_ref(hash)
			"rb_reg_nth_match(#{hash[:nth]}, rb_backref_get())"
		end
		def comp_back_ref(hash)
			case hash[:nth]
			when ?&
				"rb_reg_last_match(rb_backref_get())"
			when ?`
				"rb_reg_match_pre(rb_backref_get())"
			when ?'
				"rb_reg_match_post(rb_backref_get())"
			when ?+
				"rb_reg_match_last(rb_backref_get())"
			else
				raise Ruby2CExtError, "unexpected back-ref type: '#{hash[:nth].chr}'"
			end
		end

		def comp_array(arr)
			c_scope_res {
				l "VALUE ary = rb_ary_new2(#{arr.size});"
				arr.each_with_index { |n, i|
					l "RARRAY(ary)->ptr[#{i}] = #{comp(n)};"
					l "RARRAY(ary)->len = #{i+1};"
				}
				"ary"
			}
		end
		def comp_zarray(hash)
			"rb_ary_new()"
		end

		def comp_hash(hash)
			if (arr = hash[:head])
				ensure_node_type(arr, :array)
				arr = arr.last
				raise Ruby2CExtError, "odd number list for hash" unless arr.size % 2 == 0
				c_scope_res {
					l "VALUE key, hash = rb_hash_new();"
					arr.each_with_index { |n, i|
						if i % 2 == 0
							l "key = #{comp(n)};"
						else
							l "rb_hash_aset(hash, key, #{comp(n)});"
						end
					}
					"hash"
				}
			else
				"rb_hash_new()"
			end
		end

		def comp_str(hash)
			lit = global_const("rb_str_new(#{hash[:lit].to_c_strlit}, #{hash[:lit].size})")
			"rb_str_new3(#{lit})"
		end
		def comp_evstr(hash)
			"rb_obj_as_string(#{comp(hash[:body])})"
		end
		def handle_dyn_str(hash)
			ensure_node_type(hash[:next], :array)
			c_scope_res {
				l "VALUE str, str2;"
				l "str = #{comp_str(hash)};"
				hash[:next].last.each { |node|
					l "str2 = #{comp(node)};"
					l "rb_str_append(str, str2);"
					l "OBJ_INFECT(str, str2);"
				}
				"str"
			}
		end
		def comp_dstr(hash)
			handle_dyn_str(hash)
		end
		def comp_dxstr(hash)
			handle_dyn_str(hash)
			"rb_funcall(#{get_self}, '`', 1, res)"
		end
		def comp_dsym(hash)
			handle_dyn_str(hash)
			"rb_str_intern(res)"
		end
		def comp_dregx(hash)
			handle_dyn_str(hash)
			"rb_reg_new(RSTRING(res)->ptr, RSTRING(res)->len, #{hash[:cflag]})"
		end
		def comp_dregx_once(hash)
			c_static_once {
				comp_dregx(hash)
			}
		end
		def comp_xstr(hash)
			"rb_funcall(#{get_self}, '`', 1, #{comp_str(hash)})"
		end

		def comp_defn(hash)
			add_helper <<-EOC
				static void class_nil_check(VALUE klass) {
				    if (NIL_P(klass)) rb_raise(rb_eTypeError, "no class/module to add method");
				}
			EOC
			l "class_nil_check(#{get_class});" # can happen in instance_eval for Fixnum/Symbol
			CFunction::Method.compile(self, hash[:defn], scope.vmode_def_fun, get_class, hash[:mid])
			"Qnil"
		end

		def comp_defs(hash)
			add_helper <<-EOC
				static void defs_allowed(VALUE recv, ID mid) {
					if (ruby_safe_level >= 4 && !OBJ_TAINTED(recv))
						rb_raise(rb_eSecurityError, "Insecure: can't define singleton method");
					if (OBJ_FROZEN(recv)) rb_error_frozen("object");
					if (ruby_safe_level >= 4) {
						NODE *body = 0;
						VALUE klass = rb_singleton_class(recv);
						if (st_lookup(RCLASS(klass)->m_tbl, mid, (st_data_t *)&body))
						rb_raise(rb_eSecurityError, "redefining method prohibited");
					}
				}
			EOC
			c_scope_res {
				l "VALUE recv;"
				l "recv = #{comp(hash[:recv])};"
				l "defs_allowed(recv, #{sym(hash[:mid])});"
				CFunction::Method.compile(self, hash[:defn], "rb_define_singleton_method", "recv", hash[:mid])
				"Qnil"
			}
		end

		def comp_undef(hash)
			if Array === (mid = hash[:mid]) # 1.8.5
				l "rb_undef(#{get_class}, rb_to_id(#{comp(mid)}));"
			else
				l "rb_undef(#{get_class}, #{sym(mid)});"
			end
			"Qnil"
		end

		def comp_alias(hash)
			if Array === hash[:new] # 1.8.5
				c_scope {
					l "ID new_id;"
					l "new_id = rb_to_id(#{comp(hash[:new])});"
					l "rb_alias(#{get_class}, new_id, rb_to_id(#{comp(hash[:old])}));"
				}
			else
				l "rb_alias(#{get_class}, #{sym(hash[:new])}, #{sym(hash[:old])});"
			end
			"Qnil"
		end
		def comp_valias(hash)
			l "rb_alias_variable(#{sym(hash[:new])}, #{sym(hash[:old])});"
			"Qnil"
		end

		def comp_class(hash)
			add_helper <<-EOC
				static VALUE class_prep(VALUE prefix, VALUE super, ID cname) {
					VALUE klass;
					if (rb_const_defined_at(prefix, cname)) {
						klass = rb_const_get_at(prefix, cname);
						if (TYPE(klass) != T_CLASS) rb_raise(rb_eTypeError, "%s is not a class", rb_id2name(cname));
						if (super) {
							VALUE tmp = rb_class_real(RCLASS(klass)->super);
							if (tmp != super) rb_raise(rb_eTypeError, "superclass mismatch for class %s", rb_id2name(cname));
						}
						if (ruby_safe_level >= 4) rb_raise(rb_eSecurityError, "extending class prohibited");
					}
					else {
						if (!super) super = rb_cObject;
						klass = rb_define_class_id(cname, super);
						rb_set_class_path(klass, prefix, rb_id2name(cname));
						rb_const_set(prefix, cname, klass);
						rb_class_inherited(super, klass);
					}
					return klass;
				}
			EOC
			sup = hash[:super]
			c_scope_res {
				l "VALUE prefix, tmp_class;"
				l "VALUE super;" if sup
				puts 
				out = make_class_prefix(hash[:cpath])
            if out.nil? or out == '' or out == '('
            puts 'bad', 'from', hash
				  raise hash
				end
				l "prefix = #{out};"
				l "super = #{comp(sup)};" if sup
				l "tmp_class = class_prep(prefix, #{sup ? "super" : "0"}, #{sym(hash[:cpath].last[:mid])});"
				CFunction::ClassModuleScope.compile(self, hash[:body], "tmp_class", true)
			}
		end

		def comp_module(hash)
			add_helper <<-EOC
				static VALUE module_prep(VALUE prefix, ID cname) {
					VALUE module;
					if (rb_const_defined_at(prefix, cname)) {
						module = rb_const_get_at(prefix, cname);
						if (TYPE(module) != T_MODULE) rb_raise(rb_eTypeError, "%s is not a module", rb_id2name(cname));
						if (ruby_safe_level >= 4) rb_raise(rb_eSecurityError, "extending module prohibited");
					}
					else {
						module = rb_define_module_id(cname);
						rb_set_class_path(module, prefix, rb_id2name(cname));
						rb_const_set(prefix, cname, module);
					}
					return module;
				}
			EOC
			c_scope_res {
				l "VALUE prefix, tmp_module;"
				out = make_class_prefix(hash[:cpath])
				l "prefix = #{out};"
				l "tmp_module = module_prep(prefix, #{sym(hash[:cpath].last[:mid])});"
				CFunction::ClassModuleScope.compile(self, hash[:body], "tmp_module", false)
			}
		end

		def comp_sclass(hash)
			add_helper <<-EOC
				static void sclass_check(VALUE obj) {
					if (FIXNUM_P(obj) || SYMBOL_P(obj)) rb_raise(rb_eTypeError, "no virtual class for %s", rb_obj_classname(obj));
					if (ruby_safe_level >= 4 && !OBJ_TAINTED(obj)) rb_raise(rb_eSecurityError, "Insecure: can't extend object");
				}
			EOC
			c_scope_res {
				l "VALUE tmp_sclass;"
				l "tmp_sclass = #{comp(hash[:recv])};"
				l "sclass_check(tmp_sclass);"
				l "tmp_sclass = rb_singleton_class(tmp_sclass);"
				CFunction::ClassModuleScope.compile(self, hash[:body], "tmp_sclass", true)
			}
		end

		def comp_defined(hash)
			head = hash[:head]
			hhash = head.last
			res =
			case head.first
			when :match2, :match3
				'"method"'
			when :yield
				'(rb_block_given_p() ? "yield" : 0)'
			when :self, :nil, :true, :false
				head.first.to_s.to_c_strlit
			when :op_asgn1, :op_asgn2, :masgn, :lasgn, :dasgn, :dasgn_curr,
				:gasgn, :iasgn, :cdecl, :cvdecl, :cvasgn  # :attrset can never be parsed
				'"assignment"'
			when :lvar
				'"local-variable"'
			when :dvar
				'"local-variable(in-block)"'
			when :gvar
				"(rb_gvar_defined(#{get_global_entry(hhash[:vid])}) ? \"global-variable\" : 0)"
			when :ivar
				"(rb_ivar_defined(#{get_self}, #{sym(hhash[:vid])}) ? \"instance-variable\" : 0)"
			when :const
				add_helper <<-EOC
					static VALUE const_defined(ID id, NODE *cref) {
						NODE *cbase = cref;
						VALUE result;
						while (cbase && cbase->nd_next) {
							VALUE klass = cbase->nd_clss;
							if (RCLASS(klass)->iv_tbl && st_lookup(RCLASS(klass)->iv_tbl, id, &result)) {
								if (result == Qundef && NIL_P(rb_autoload_p(klass, id))) return Qfalse;
								return Qtrue;
							}
							cbase = cbase->nd_next;
						}
						return rb_const_defined(cref->nd_clss, id);
					}
				EOC
				"(const_defined(#{sym(hhash[:vid])}, #{get_cref}) ? \"constant\" : 0)"
			when :cvar
				"(rb_cvar_defined(#{get_cvar_cbase}, #{sym(hhash[:vid])}) ? \"class variable\" : 0)"
			when :colon3
				"(rb_const_defined_from(rb_cObject, #{sym(hhash[:mid])}) ? \"constant\" : 0)"
			when :nth_ref
				"(RTEST(rb_reg_nth_defined(#{hhash[:nth]}, rb_backref_get())) ? \"$#{hhash[:nth]}\" : 0)"
			when :back_ref
				"(RTEST(rb_reg_nth_defined(0, rb_backref_get())) ? \"$#{hhash[:nth].chr}\" : 0)"
			else
				raise Ruby2CExtError::NotSupported, "defined? with node type #{head.first} is not supported"
			end
			if res[0,1] == '"' # just a string
				"rb_str_new2(#{res})"
			else
				c_scope_res {
					l "char * def_desc;"
					l "def_desc = #{res};"
					"(def_desc ? rb_str_new2(def_desc) : Qnil)"
				}
			end
		end
	end

end
