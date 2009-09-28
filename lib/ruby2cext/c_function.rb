
module Ruby2CExtension

	module CFunction
		# contains all different Types of C functions that are compiled from ruby nodes

		class Base
			include CommonNodeComp
			extend Tools::EnsureNodeTypeMixin
			attr_reader :scope, :compiler, :closure_tbl
			attr_accessor :need_res, :need_self, :need_cref, :need_class, :need_wrap
			def initialize(compiler, scope)
				@compiler = compiler
				@scope = scope
				@closure_tbl = []
				@scope.closure_tbl = @closure_tbl
				@lines = []
				@while_stack = []
			end

			# some redirects to compiler
			def un(str); compiler.un(str); end
			def sym(sym); compiler.sym(sym); end
			def global_const(str, register_gc = true)
				compiler.global_const(str, register_gc)
			end
			def global_var(str)
				compiler.global_var(str)
			end
			def add_helper(str); compiler.add_helper(str); end

			def get_lines
                                puts @lines
                                puts @lines.class
				@lines.join("\n")
			end
			def l(line) # add_line
				# ignore lines with only whitespace or only alnum chars (variable name)
				unless line =~ /\A\s*\z/ || (line =~ /\A(\w*);?\z/ && !(%w[break continue].include? $1))
					@lines << line
				end
			end

			def push_while(redo_lbl, next_lbl, break_lbl)
				@while_stack << [redo_lbl, next_lbl, break_lbl]
			end
			def pop_while
				raise Ruby2CExtError::Bug, "popped from empty while stack" if @while_stack.empty?
				@while_stack.pop
			end
			def in_while?(lbl_type = nil)
				return false if @while_stack.empty?
				case lbl_type
				when nil
					true
				when :redo
					@while_stack.last[0]
				when :next
					@while_stack.last[1]
				when :break
					@while_stack.last[2]
				else
					false
				end
			end

			def break_allowed?(with_value)
				in_while?(:break)
			end
			def comp_break(hash)
				if (lbl = in_while?(:break))
					l "while_res = #{comp(hash[:stts])};"
					l "goto #{lbl};"
					"Qnil"
				else
					raise Ruby2CExtError::NotSupported, "break is not supported here"
				end
			end

			def next_allowed?
				in_while?(:next)
			end
			def comp_next(hash)
				if (lbl = in_while?(:next))
					# hash[:stts] is silently ignored (as ruby does)
					l "goto #{lbl};"
					"Qnil"
				else
					raise Ruby2CExtError::NotSupported, "next is not supported here"
				end
			end

			def redo_allowed?
				in_while?(:redo)
			end
			def comp_redo(hash)
				if (lbl = in_while?(:redo))
					l "goto #{lbl};"
					"Qnil"
				else
					raise Ruby2CExtError::NotSupported, "redo is not supported here"
				end
			end

			def return_allowed?
				false
			end
			def comp_return(hash)
				raise Ruby2CExtError::NotSupported, "return is not supported here"
			end

			def comp_retry(hash)
				l "rb_jump_tag(0x4 /* TAG_RETRY */);"
				"Qnil"
			end

			def need_closure_ptr
				false # only needed in Block
			end

			def assign_res(str)
				self.need_res = true
				unless str.strip == "res"
					l "res = #{str};"
				end
			end
			def get_self
				self.need_self = true
				"self"
			end
			def get_cref
				self.need_cref = true
				get_cref_impl # subclass
			end
			def get_class
				self.need_class = true
				"s_class"
			end
			def get_cbase
				"(#{get_cref}->nd_clss)"
			end
			def get_cvar_cbase
				# there is always at least one real class in the cref chain
				add_helper <<-EOC
					static VALUE cvar_cbase(NODE *cref) {
						while (FL_TEST(cref->nd_clss, FL_SINGLETON)) { cref = cref->nd_next; }
						return cref->nd_clss;
					}
				EOC
				"cvar_cbase(#{get_cref})"
			end

			def get_closure_ary_var
				"my_closure_ary"
			end

			def get_wrap_ptr
				"(&the_wrap)"
			end

			def add_closure_need(sym)
				closure_tbl << sym unless closure_tbl.include? sym
			end

			def closure_buid_c_code
				if closure_tbl.empty?
					nil
				else
					res = ["#{get_closure_ary_var} = rb_ary_new2(#{closure_tbl.size});"]
					closure_tbl.each_with_index { |entry, idx|
						case entry
						when Integer
							res << "RARRAY(#{get_closure_ary_var})->ptr[#{idx}] = #{scope.get_dvar_ary(entry)};"
						when :lvar
							res << "RARRAY(#{get_closure_ary_var})->ptr[#{idx}] = #{scope.get_lvar_ary};"
						when :self
							res << "RARRAY(#{get_closure_ary_var})->ptr[#{idx}] = #{get_self};"
						when :class
							res << "RARRAY(#{get_closure_ary_var})->ptr[#{idx}] = #{get_class};"
						when :cref
							add_helper <<-EOC
								static void cref_data_mark(NODE *n) {
									rb_gc_mark((VALUE)n);
								}
							EOC
							res << "RARRAY(#{get_closure_ary_var})->ptr[#{idx}] = " +
								"Data_Wrap_Struct(rb_cObject, cref_data_mark, 0, #{get_cref});"
						else
							raise Ruby2CExtError::Bug, "unexpected closure_tbl entry: #{entry.inspect}"
						end
					}
					res << "RARRAY(#{get_closure_ary_var})->len = #{closure_tbl.size};"
					res.join("\n")
				end
			end

			def wrap_buid_c_code
				add_helper <<-EOC
					struct wrap {
						VALUE self;
						VALUE s_class;
						NODE *cref;
						VALUE my_closure_ary;
						VALUE *closure;
						VALUE *var;
						long state;
					};
				EOC
				res = []
				res << "the_wrap.self = #{get_self};" if need_self
				res << "the_wrap.s_class = #{get_class};" if need_class
				res << "the_wrap.cref = #{get_cref};" if need_cref
				res << "the_wrap.my_closure_ary = #{get_closure_ary_var};" unless closure_tbl.empty?
				res << "the_wrap.closure = closure;" if need_closure_ptr
				res << "the_wrap.var = #{scope.var_ptr_for_wrap};" if scope.var_ptr_for_wrap
				res.compact.join("\n")
			end

			def init_c_code
				cb_c_code = closure_buid_c_code # must be called before the rest because it might change self or scope
				res = []
				res << "VALUE res;" if need_res
				res << "VALUE s_class = (#{get_cref})->nd_clss;" if need_class
				res << "VALUE #{get_closure_ary_var};" if cb_c_code
				res << "struct wrap the_wrap;" if need_wrap
				res << scope.init_c_code
				res << cb_c_code if cb_c_code
				res << wrap_buid_c_code if need_wrap
				res.compact.join("\n")
			end
		end

		class ClassModuleScope < Base
			def self.compile(outer, scope_node, class_mod_var, is_class)
				ensure_node_type(scope_node, :scope)
				vmode_methods = Scopes::Scope::VMODES.dup
				vmode_methods.delete :module_function if is_class
				cf = self.new(outer.compiler, Scopes::Scope.new(scope_node.last[:tbl], vmode_methods))
				cf.instance_eval {
					block = make_block(scope_node.last[:next])
					l "return #{comp(block)};"
				}
				body = "#{cf.init_c_code}\n#{cf.get_lines}"
				args = []
				args << "VALUE self" if cf.need_self
				args << "NODE *cref" if cf.need_cref
				sig = "static VALUE FUNNAME(#{args.join(", ")}) {"
				fname = cf.compiler.add_fun("#{sig}\n#{body}\n}", "class_module_scope")
				outer.instance_eval {
					args = []
					args << class_mod_var if cf.need_self
					args << "NEW_NODE(NODE_CREF, #{class_mod_var}, 0, #{get_cref})" if cf.need_cref
					assign_res("#{fname}(#{args.join(", ")})")
				}
				"res"
			end

			def get_cref_impl
				"cref"
			end

		end

		class ToplevelScope < ClassModuleScope
			def self.compile(compiler, scope_node, private_vmode = true)
				ensure_node_type(scope_node, :scope)
				cf = self.new(compiler, Scopes::Scope.new(scope_node.last[:tbl], [:public, :private], private_vmode))
				cf.instance_eval {
					block = make_block(scope_node.last[:next])
					l "#{comp(block)};"
				}
				body = "#{cf.init_c_code}\n#{cf.get_lines}"
				sig = "static void FUNNAME(VALUE self, NODE *cref) {"
				cf.compiler.add_fun("#{sig}\n#{body}\n}", "toplevel_scope") # and return the function name
			end
		end

		class Method < Base
			def self.compile(outer, scope_node, def_fun, class_var, mid)
				ensure_node_type(scope_node, :scope)
				cf = self.new(outer.compiler, Scopes::Scope.new(scope_node.last[:tbl], []))
				cf.instance_eval {
					block_array = make_block(scope_node.last[:next]).last.dup # dup the block_array to allow modification
					arg = block_array.shift
					ba = nil
					unless block_array.empty? || block_array.first.first != :block_arg
						ba = block_array.shift
					end
					handle_method_args(arg, ba)
					l "return #{comp([:block, block_array])};"
				}
				begin
				  body = "#{cf.init_c_code}\n#{cf.get_lines}"
				  rescue Exception => e
				     3
				     require '_dbg'
				     3
				     raise e
				  
				  end
				sig = "static VALUE FUNNAME(int meth_argc, VALUE *meth_argv, VALUE self) {"
				fname = cf.compiler.add_fun("#{sig}\n#{body}\n}", "method")
				if cf.need_cref
					outer.instance_eval {
						add_helper <<-EOC
							static void def_only_once(ID mid) {
								rb_raise(rb_eTypeError, "def for \\"%s\\" can only be used once", rb_id2name(mid));
							}
						EOC
						l "if (#{cf.cref_global_var}) def_only_once(#{sym(mid)});"
						l "#{cf.cref_global_var} = (VALUE)(#{get_cref});"
					}
				end
				outer.l "#{def_fun}(#{class_var}, #{mid.to_s.to_c_strlit}, #{fname}, -1);"
				"Qnil"
			end

			def return_allowed?
				true
			end
			def comp_return(hash)
				l "return #{comp(hash[:stts])};"
				"Qnil"
			end

			def get_cref_impl
				@cref_global_var ||= global_var("Qfalse")
				"(RNODE(#{@cref_global_var}))"
			end
			attr_reader :cref_global_var
		end

		class Block < Base
			def self.compile(outer, block_node, var_node)
				ensure_node_type(block_node, :block)
				cf = self.new(outer.compiler, outer.scope.new_dyna_scope)
				cf.instance_eval {
					if Array === var_node
						if var_node.first == :masgn
							dup_hash = var_node.last.dup
							c_if("ruby_current_node->nd_state != 1") { # 1 is YIELD_FUNC_AVALUE
								# do "svalue_to_mrhs"
								c_if("bl_val == Qundef") {
									l "bl_val = rb_ary_new2(0);"
								}
								c_else {
									#if dup_hash[:head] # TODO
										l "VALUE tmp = rb_check_array_type(bl_val);"
										l "bl_val = (NIL_P(tmp) ? rb_ary_new3(1, bl_val) : tmp);"
									#else
									#	l "bl_val = rb_ary_new3(1, bl_val);"
									#end
								}
							}
							dup_hash[:value] = "bl_val"
							comp_masgn(dup_hash)
						else
							c_if("ruby_current_node->nd_state == 1") { # 1 is YIELD_FUNC_AVALUE
								# do "avalue_to_svalue"
								l "if (RARRAY(bl_val)->len == 0) bl_val = Qnil;"
								l "else if (RARRAY(bl_val)->len == 1) bl_val = RARRAY(bl_val)->ptr[0];"
							}
							handle_assign(var_node, "bl_val")
						end
					end
					l "block_redo:"
					l "return #{comp_block(block_node.last)};"
				}
				body = "#{cf.init_c_code(outer)}\n#{cf.get_lines}"
				sig = "static VALUE FUNNAME(VALUE bl_val, VALUE closure_ary, VALUE bl_self) {"
				fname = cf.compiler.add_fun("#{sig}\n#{body}\n}", "block")
				[fname, cf.need_closure_ptr]
			end

			def init_c_code(outer)
				cb_c_code = closure_buid_c_code # must be called before the rest because it might change self or scope
				outer.add_closure_need(:self) if need_self
				outer.add_closure_need(:class) if need_class
				outer.add_closure_need(:cref) if need_cref
				res = []
				res << "VALUE res;" if need_res
				if need_closure_ptr
					res << "VALUE *closure = RARRAY(closure_ary)->ptr;"
				end
				res << "VALUE self = (bl_self == Qundef ? closure[#{outer.closure_tbl.index(:self)}] : bl_self);" if need_self
				res << "VALUE s_class = (bl_self == Qundef ? closure[#{outer.closure_tbl.index(:class)}] : ruby_class);" if need_class
				if need_cref
					# see #define Data_Get_Struct
					res << "NODE *cref = (Check_Type(closure[#{outer.closure_tbl.index(:cref)}]," +
						" T_DATA), (NODE*)DATA_PTR(closure[#{outer.closure_tbl.index(:cref)}]));"
				end
				res << "VALUE #{get_closure_ary_var};" if cb_c_code
				res << "struct wrap the_wrap;" if need_wrap
				res << scope.init_c_code
				res << cb_c_code if cb_c_code
				res << wrap_buid_c_code if need_wrap
				res.compact.join("\n")
			end

			def break_allowed?(with_value)
				super || !with_value
			end
			def comp_break(hash)
				if in_while?(:break)
					super
				else
					raise Ruby2CExtError::NotSupported, "break with a value is not supported in a block" if hash[:stts]
					l "rb_iter_break();"
					"Qnil"
				end
			end

			def next_allowed?
				true
			end
			def comp_next(hash)
				if in_while?(:next)
					super
				else
					l "return #{comp(hash[:stts])};"
					"Qnil"
				end
			end

			def redo_allowed?
				true
			end
			def comp_redo(hash)
				if in_while?(:redo)
					super
				else
					l "goto block_redo;"
					"Qnil"
				end
			end

			def need_closure_ptr
				scope.need_closure || need_self || need_class || need_cref
			end

			def get_cref_impl
				"cref"
			end
		end

		class Wrap < Base

			def self.compile(outer, base_name, cflow_hash = nil)
				cf = self.new(outer, cflow_hash)
				cf.instance_eval {
					if cf.cflow_hash
						l "#{get_wrap_ptr}->state &= (1<<20)-1;" # set bits 20+ to 0
					end
					l "return #{yield cf};"
				}
				body = "#{cf.init_c_code}\n#{cf.get_lines}"
				sig = "static VALUE FUNNAME(struct wrap *wrap_ptr) {"
				outer.need_wrap = true
				cf.compiler.add_fun("#{sig}\n#{body}\n}", base_name) # and return the function name
			end

			attr_reader :base_cfun, :outer_cfun, :cflow_hash

			# the following attr_accessors from Base are redefined, to redirect to base_cfun
			[:need_self, :need_cref, :need_class, :need_wrap].each { |a|
				define_method(a) { base_cfun.send(a) }
				asgn_sym = :"#{a}="
				define_method(asgn_sym) { |arg| base_cfun.send(asgn_sym, arg) }
			}

			# cflow_hash can either be nil or a hash, if it is nil then break,
			# next, redo and return are not possible from the wrap to
			# outer_cfun.
			#
			# If cflow_hash is a hash then those are possible if outer_cfun
			# allows them. For this to work only the bits 0-19 of
			# wrap_ptr->state may be modified by code inside this wrap and
			# after the call the code generated by Wrap.handle_wrap_cflow has
			# to be inserted.
			def initialize(outer_cfun, cflow_hash = nil)
				@outer_cfun = outer_cfun
				if Wrap === outer_cfun
					@base_cfun = outer_cfun.base_cfun
				else
					@base_cfun = outer_cfun
				end
				@cflow_hash = cflow_hash
				@compiler = base_cfun.compiler
				@scope = Scopes::WrappedScope.new(base_cfun.scope)
				@closure_tbl = base_cfun.closure_tbl
				@lines = []
				@while_stack = []
			end

			BREAK_FLAG  = 1 << 20
			NEXT_FLAG   = 1 << 21
			REDO_FLAG   = 1 << 22
			RETURN_FLAG = 1 << 23

			def break_allowed?(with_value)
				super || (cflow_hash && outer_cfun.break_allowed?(with_value))
			end
			def comp_break(hash)
				if in_while?(:break)
					super
				elsif break_allowed?(hash[:stts])
					@cflow_hash[:break] ||= hash[:stts]
					l "#{get_wrap_ptr}->state |= #{BREAK_FLAG};"
					l "return #{comp(hash[:stts])};"
					"Qnil"
				else
					raise Ruby2CExtError::NotSupported, "break #{hash[:stts] ? "with a value " : ""}is not supported here"
				end
			end

			def next_allowed?
				super || (cflow_hash && outer_cfun.next_allowed?)
			end
			def comp_next(hash)
				if in_while?(:next)
					super
				elsif next_allowed?
					@cflow_hash[:next] = true
					l "#{get_wrap_ptr}->state |= #{NEXT_FLAG};"
					# hash[:stts] might be evaluated unnecessarily (because it
					# is ignored in while loops), but oh well ...
					l "return #{comp(hash[:stts])};"
					"Qnil"
				else
					raise Ruby2CExtError::NotSupported, "next is not supported here"
				end
			end

			def redo_allowed?
				super || (cflow_hash && outer_cfun.redo_allowed?)
			end
			def comp_redo(hash)
				if in_while?(:redo)
					super
				elsif redo_allowed?
					@cflow_hash[:redo] = true
					l "#{get_wrap_ptr}->state |= #{REDO_FLAG};"
					l "return Qnil;"
					"Qnil"
				else
					raise Ruby2CExtError::NotSupported, "redo is not supported here"
				end
			end

			def return_allowed?
				cflow_hash && outer_cfun.return_allowed?
			end
			def comp_return(hash)
				if return_allowed?
					@cflow_hash[:return] = true
					l "#{get_wrap_ptr}->state |= #{RETURN_FLAG};"
					l "return #{comp(hash[:stts])};"
					"Qnil"
				else
					raise Ruby2CExtError::NotSupported, "return is not supported here"
				end
			end

			# the result of the call to the wrap cfun is expected in "res"
			def self.handle_wrap_cflow(cfun, cflow_hash)
				cfun.instance_eval {
					if cflow_hash.has_key?(:break)
						c_if("#{get_wrap_ptr}->state & #{BREAK_FLAG}") {
							l comp_break(:stts => (cflow_hash[:break] ? "res" : false))
						}
					end
					if cflow_hash.has_key?(:next)
						c_if("#{get_wrap_ptr}->state & #{NEXT_FLAG}") {
							l comp_next(:stts => "res")
						}
					end
					if cflow_hash.has_key?(:redo)
						c_if("#{get_wrap_ptr}->state & #{REDO_FLAG}") {
							l comp_redo({})
						}
					end
					if cflow_hash.has_key?(:return)
						c_if("#{get_wrap_ptr}->state & #{RETURN_FLAG}") {
							l comp_return(:stts => "res")
						}
					end
				}
			end

			def get_self
				self.need_self = true
				"(wrap_ptr->self)"
			end
			def get_cref_impl
				"(wrap_ptr->cref)"
			end
			def get_class
				self.need_class = true
				"(wrap_ptr->s_class)"
			end

			def get_closure_ary_var
				"(wrap_ptr->my_closure_ary)"
			end

			def get_wrap_ptr
				"wrap_ptr"
			end

			[:closure_buid_c_code, :wrap_buid_c_code, :need_closure_ptr].each { |m|
				define_method(m) {
					raise Ruby2CExtError::Bug, "the method #{m} may not be called for an instance of Wrap"
				}
			}

			def init_c_code
				res = []
				res << "VALUE res;" if need_res
				res.compact.join("\n")
			end
		end

	end

end