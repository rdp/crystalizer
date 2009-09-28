
module Ruby2CExtension::Plugins

	class BuiltinMethods < Ruby2CExtension::Plugin
		# for public methods of builtin types with a fixed arity, which don't do anything with blocks

		SUPPORTED_BUILTINS = [:Array, :Bignum, :FalseClass, :Fixnum, :Float, :Hash, :NilClass, :Regexp, :String, :Symbol, :TrueClass]

		NO_CLASS_CHECK_BUILTINS = [:FalseClass, :Fixnum, :NilClass, :Symbol, :TrueClass]

		COMMON_METHODS = [ # all supported builtins use these methods from Kernel
			 [:__id__, 0, :Kernel],
			 [:class, 0, :Kernel],
			 [:clone, 0, :Kernel],
			 [:dup, 0, :Kernel],
			 [:freeze, 0, :Kernel],
			 [:instance_variables, 0, :Kernel],
			 [:object_id, 0, :Kernel],
			 [:taint, 0, :Kernel],
			 [:tainted?, 0, :Kernel],
			 [:untaint, 0, :Kernel],
			 [:equal?, 1, :Kernel],
			 [:instance_of?, 1, :Kernel],
			 [:instance_variable_get, 1, :Kernel],
			 [:is_a?, 1, :Kernel],
			 [:kind_of?, 1, :Kernel],
			 [:method, 1, :Kernel],
			 [:instance_variable_set, 2, :Kernel],
		]

		METHODS = {
			:Array => [
				[:[], 1, nil, nil, -1],
				[:[], 2, nil, nil, -1],
				[:first, 0, nil, nil, -1],
				[:first, 1, nil, nil, -1],
				[:insert, 2, nil, nil, -1],
				[:insert, 3, nil, nil, -1],
				[:join, 0, nil, nil, -1],
				[:join, 1, nil, nil, -1],
				[:last, 0, nil, nil, -1],
				[:last, 1, nil, nil, -1],
				[:push, 1, nil, nil, -1],
				[:slice, 1, nil, nil, -1],
				[:slice, 2, nil, nil, -1],
				[:slice!, 1, nil, nil, -1],
				[:slice!, 2, nil, nil, -1],
				[:unshift, 1, nil, nil, -1],
				[:values_at, 1, nil, nil, -1],
				[:values_at, 2, nil, nil, -1],
				[:values_at, 3, nil, nil, -1],
				[:values_at, 4, nil, nil, -1],
				[:clear, 0],
				[:compact, 0],
				[:compact!, 0],
				[:empty?, 0],
				[:flatten, 0],
				[:flatten!, 0],
				[:frozen?, 0],
				[:hash, 0],
				[:inspect, 0],
				[:length, 0],
				[:nitems, 0],
				[:pop, 0],
				[:reverse, 0],
				[:reverse!, 0],
				[:shift, 0],
				[:size, 0],
				[:to_a, 0],
				[:to_ary, 0],
				[:to_s, 0],
				[:transpose, 0],
				[:uniq, 0],
				[:uniq!, 0],
				[:&, 1],
				[:|, 1],
				[:*, 1],
				[:+, 1],
				[:-, 1],
				[:<<, 1],
				[:<=>, 1],
				[:==, 1],
				[:assoc, 1],
				[:at, 1],
				[:concat, 1],
				[:delete_at, 1],
				[:eql?, 1],
				[:include?, 1],
				[:index, 1],
				[:rassoc, 1],
				[:replace, 1],
				[:rindex, 1],
				[:entries, 0, :Enumerable],
				[:member?, 1, :Enumerable],
				[:nil?, 0, :Kernel],
				[:===, 1, :Kernel],
				[:=~, 1, :Kernel],
			],
			:Bignum => [
				[:to_s, 0, nil, nil, -1],
				[:to_s, 1, nil, nil, -1],
				[:-@, 0],
				[:abs, 0],
				[:hash, 0],
				[:size, 0],
				[:to_f, 0],
				[:~, 0],
				[:%, 1, nil, [:Fixnum, :Bignum]],
				[:&, 1],
				[:*, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:**, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:+, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:-, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:/, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:<<, 1],
				[:<=>, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:==, 1],
				[:>>, 1],
				[:[], 1],
				[:^, 1],
				[:coerce, 1],
				[:div, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:divmod, 1, nil, [:Fixnum, :Bignum]],
				[:eql?, 1],
				[:modulo, 1, nil, [:Fixnum, :Bignum]],
				[:quo, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:remainder, 1, nil, [:Fixnum, :Bignum]],
				[:|, 1],
				[:<, 1, :Comparable],
				[:<=, 1, :Comparable],
				[:>, 1, :Comparable],
				[:>=, 1, :Comparable],
				[:between?, 2, :Comparable],
				[:ceil, 0, :Integer],
				[:chr, 0, :Integer],
				[:floor, 0, :Integer],
				[:integer?, 0, :Integer],
				[:next, 0, :Integer],
				[:round, 0, :Integer],
				[:succ, 0, :Integer],
				[:to_i, 0, :Integer],
				[:to_int, 0, :Integer],
				[:truncate, 0, :Integer],
				[:+@, 0, :Numeric],
				[:nonzero?, 0, :Numeric],
				[:zero?, 0, :Numeric],
				[:frozen?, 0, :Kernel],
				[:inspect, 0, :Kernel],
				[:nil?, 0, :Kernel],
				[:to_a, 0, :Kernel],
				[:===, 1, :Kernel],
				[:=~, 1, :Kernel],
			],
			:FalseClass => [
				[:to_s, 0],
				[:&, 1],
				[:^, 1],
				[:|, 1],
				[:frozen?, 0, :Kernel],
				[:hash, 0, :Kernel],
				[:inspect, 0, :Kernel],
				[:nil?, 0, :Kernel],
				[:to_a, 0, :Kernel],
				[:==, 1, :Kernel],
				[:===, 1, :Kernel],
				[:=~, 1, :Kernel],
				[:eql?, 1, :Kernel],
			],
			:Fixnum => [
				[:to_s, 0, nil, nil, -1],
				[:to_s, 1, nil, nil, -1],
				[:-@, 0],
				[:abs, 0],
				[:id2name, 0],
				[:size, 0],
				[:to_sym, 0],
				[:to_f, 0],
				[:zero?, 0],
				[:~, 0],
				[:+, 1, nil, [:Fixnum, :Float]],
				[:-, 1, nil, [:Fixnum, :Float]],
				[:*, 1, nil, [:Fixnum, :Float]],
				[:**, 1, nil, [:Fixnum, :Float]],
				[:/, 1, nil, [:Fixnum]],
				[:div, 1, nil, [:Fixnum]],
				[:%, 1, nil, [:Fixnum]],
				[:modulo, 1, nil, [:Fixnum]],
				[:divmod, 1, nil, [:Fixnum]],
				[:quo, 1, nil, [:Fixnum]],
				[:<=>, 1, nil, [:Fixnum]],
				[:>, 1, nil, [:Fixnum]],
				[:>=, 1, nil, [:Fixnum]],
				[:<, 1, nil, [:Fixnum]],
				[:<=, 1, nil, [:Fixnum]],
				[:==, 1],
				[:&, 1],
				[:|, 1],
				[:^, 1],
				[:[], 1],
				[:<<, 1],
				[:>>, 1],
				[:between?, 2, :Comparable],
				[:+@, 0, :Numeric],
				[:nonzero?, 0, :Numeric],
				[:coerce, 1, :Numeric],
				[:eql?, 1, :Numeric],
				[:remainder, 1, :Numeric],
				[:ceil, 0, :Integer],
				[:chr, 0, :Integer],
				[:floor, 0, :Integer],
				[:integer?, 0, :Integer],
				[:next, 0, :Integer],
				[:round, 0, :Integer],
				[:succ, 0, :Integer],
				[:to_i, 0, :Integer],
				[:to_int, 0, :Integer],
				[:truncate, 0, :Integer],
				[:frozen?, 0, :Kernel],
				[:hash, 0, :Kernel],
				[:inspect, 0, :Kernel],
				[:nil?, 0, :Kernel],
				[:to_a, 0, :Kernel],
				[:===, 1, :Kernel],
				[:=~, 1, :Kernel],
			],
			:Float => [
				[:-@, 0],
				[:to_s, 0],
				[:hash, 0],
				[:to_f, 0],
				[:abs, 0],
				[:zero?, 0],
				[:to_i, 0],
				[:to_int, 0],
				[:floor, 0],
				[:ceil, 0],
				[:round, 0],
				[:truncate, 0],
				[:nan?, 0],
				[:infinite?, 0],
				[:finite?, 0],
				[:coerce, 1],
				[:eql?, 1],
				[:==, 1],
				[:+, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:-, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:*, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:/, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:%, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:modulo, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:divmod, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:**, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:<=>, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:>, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:>=, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:<, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:<=, 1, nil, [:Fixnum, :Bignum, :Float]],
				[:between?, 2, :Comparable],
				[:+@, 0, :Numeric],
				[:integer?, 0, :Numeric],
				[:nonzero?, 0, :Numeric],
				[:div, 1, :Numeric],
				[:quo, 1, :Numeric],
				[:remainder, 1, :Numeric],
				[:frozen?, 0, :Kernel],
				[:inspect, 0, :Kernel],
				[:nil?, 0, :Kernel],
				[:to_a, 0, :Kernel],
				[:===, 1, :Kernel],
				[:=~, 1, :Kernel],
			],
			:Hash => [
				[:default, 0, nil, nil, -1],
				[:default, 1, nil, nil, -1],
				[:values_at, 1, nil, nil, -1],
				[:values_at, 2, nil, nil, -1],
				[:values_at, 3, nil, nil, -1],
				[:values_at, 4, nil, nil, -1],
				[:clear, 0],
				[:default_proc, 0],
				[:empty?, 0],
				[:inspect, 0],
				[:invert, 0],
				[:keys, 0],
				[:length, 0],
				[:rehash, 0],
				[:shift, 0],
				[:size, 0],
				[:to_a, 0],
				[:to_hash, 0],
				[:to_s, 0],
				[:values, 0],
				[:==, 1],
				[:[], 1],
				[:default=, 1],
				[:delete, 1],
				[:has_key?, 1],
				[:has_value?, 1],
				[:include?, 1],
				[:index, 1],
				[:key?, 1],
				[:member?, 1],
				[:replace, 1],
				[:value?, 1],
				[:store, 2],
				[:entries, 0, :Enumerable],
				[:frozen?, 0, :Kernel],
				[:hash, 0, :Kernel],
				[:nil?, 0, :Kernel],
				[:===, 1, :Kernel],
				[:=~, 1, :Kernel],
				[:eql?, 1, :Kernel],
			],
			:NilClass => [
				[:inspect, 0],
				[:nil?, 0],
				[:to_a, 0],
				[:to_f, 0],
				[:to_i, 0],
				[:to_s, 0],
				[:&, 1],
				[:^, 1],
				[:|, 1],
				[:frozen?, 0, :Kernel],
				[:hash, 0, :Kernel],
				[:==, 1, :Kernel],
				[:===, 1, :Kernel],
				[:=~, 1, :Kernel],
				[:eql?, 1, :Kernel],
			],
			:Regexp => [
				[:casefold?, 0],
				[:hash, 0],
				[:inspect, 0],
				[:kcode, 0],
				[:options, 0],
				[:source, 0],
				[:to_s, 0],
				[:~, 0],
				[:==, 1],
				[:===, 1],
				[:=~, 1],
				[:eql?, 1],
				[:match, 1],
				[:frozen?, 0, :Kernel],
				[:nil?, 0, :Kernel],
				[:to_a, 0, :Kernel],
			],
			:String => [
				[:[], 1, nil, nil, -1],
				[:[], 2, nil, nil, -1],
				[:center, 1, nil, nil, -1],
				[:center, 2, nil, nil, -1],
				[:chomp, 1, nil, nil, -1],
				[:chomp, 2, nil, nil, -1],
				[:chomp!, 1, nil, nil, -1],
				[:chomp!, 2, nil, nil, -1],
				[:count, 1, nil, nil, -1],
				[:count, 2, nil, nil, -1],
				[:count, 3, nil, nil, -1],
				[:delete, 1, nil, nil, -1],
				[:delete, 2, nil, nil, -1],
				[:delete, 3, nil, nil, -1],
				[:delete!, 1, nil, nil, -1],
				[:delete!, 2, nil, nil, -1],
				[:delete!, 3, nil, nil, -1],
				[:index, 1, nil, nil, -1],
				[:index, 2, nil, nil, -1],
				[:ljust, 1, nil, nil, -1],
				[:ljust, 2, nil, nil, -1],
				[:rindex, 1, nil, nil, -1],
				[:rindex, 2, nil, nil, -1],
				[:rjust, 1, nil, nil, -1],
				[:rjust, 2, nil, nil, -1],
				[:slice, 1, nil, nil, -1],
				[:slice, 2, nil, nil, -1],
				[:slice!, 1, nil, nil, -1],
				[:slice!, 2, nil, nil, -1],
				[:split, 0, nil, nil, -1],
				[:split, 1, nil, nil, -1],
				[:split, 2, nil, nil, -1],
				[:squeeze, 1, nil, nil, -1],
				[:squeeze, 2, nil, nil, -1],
				[:squeeze, 3, nil, nil, -1],
				[:squeeze!, 1, nil, nil, -1],
				[:squeeze!, 2, nil, nil, -1],
				[:squeeze!, 3, nil, nil, -1],
				[:to_i, 0, nil, nil, -1],
				[:to_i, 1, nil, nil, -1],
				[:capitalize, 0],
				[:capitalize!, 0],
				[:chop, 0],
				[:chop!, 0],
				[:downcase, 0],
				[:downcase!, 0],
				[:dump, 0],
				[:empty?, 0],
				[:hash, 0],
				[:hex, 0],
				[:inspect, 0],
				[:intern, 0],
				[:length, 0],
				[:lstrip, 0],
				[:lstrip!, 0],
				[:next, 0],
				[:next!, 0],
				[:oct, 0],
				[:reverse, 0],
				[:reverse!, 0],
				[:rstrip, 0],
				[:rstrip!, 0],
				[:size, 0],
				[:strip, 0],
				[:strip!, 0],
				[:succ, 0],
				[:succ!, 0],
				[:swapcase, 0],
				[:swapcase!, 0],
				[:to_f, 0],
				[:to_s, 0],
				[:to_str, 0],
				[:to_sym, 0],
				[:upcase, 0],
				[:upcase!, 0],
				[:%, 1],
				[:*, 1],
				[:+, 1],
				[:<<, 1],
				[:<=>, 1],
				[:==, 1],
				[:=~, 1],
				[:casecmp, 1],
				[:concat, 1],
				[:crypt, 1],
				[:eql?, 1],
				[:include?, 1],
				[:match, 1],
				[:replace, 1],
				[:insert, 2],
				[:tr, 2],
				[:tr!, 2],
				[:tr_s, 2],
				[:tr_s!, 2],
				[:<, 1, :Comparable],
				[:<=, 1, :Comparable],
				[:>, 1, :Comparable],
				[:>=, 1, :Comparable],
				[:between?, 2, :Comparable],
				[:entries, 0, :Enumerable],
				[:to_a, 0, :Enumerable],
				[:member?, 1, :Enumerable],
				[:frozen?, 0, :Kernel],
				[:nil?, 0, :Kernel],
				[:===, 1, :Kernel],
			],
			:Symbol => [
				[:id2name, 0],
				[:inspect, 0],
				[:to_i, 0],
				[:to_int, 0],
				[:to_s, 0],
				[:to_sym, 0],
				[:===, 1],
				[:frozen?, 0, :Kernel],
				[:hash, 0, :Kernel],
				[:nil?, 0, :Kernel],
				[:to_a, 0, :Kernel],
				[:==, 1, :Kernel],
				[:=~, 1, :Kernel],
				[:eql?, 1, :Kernel],
			],
			:TrueClass => [
				[:to_s, 0],
				[:&, 1],
				[:^, 1],
				[:|, 1],
				[:frozen?, 0, :Kernel],
				[:hash, 0, :Kernel],
				[:inspect, 0, :Kernel],
				[:nil?, 0, :Kernel],
				[:to_a, 0, :Kernel],
				[:==, 1, :Kernel],
				[:===, 1, :Kernel],
				[:=~, 1, :Kernel],
				[:eql?, 1, :Kernel],
			],
		}

		METHOD_NAME_MAPPINGS = Hash.new { |h, k|
			case k.to_s
			when /\A\w+\z/
				h[k] = "builtinoptmeth_#{k}"
			when /\A\w+\?\z/
				h[k] = "builtinoptmeth_#{k.to_s[0..-2]}__pred"
			when /\A\w+!\z/
				h[k] = "builtinoptmeth_#{k.to_s[0..-2]}__bang"
			when /\A\w+=\z/
				h[k] = "builtinoptmeth_#{k.to_s[0..-2]}__assign"
			else
				raise Ruby2CExtension::Ruby2CExtError::Bug, "unexpected method name: #{k.inspect}"
			end
		}
		METHOD_NAME_MAPPINGS.merge!({
			:+@  => "builtinoptop_uplus",
			:-@  => "builtinoptop_uminus",
			:+   => "builtinoptop_plus",
			:-   => "builtinoptop_minus",
			:*   => "builtinoptop_mul",
			:/   => "builtinoptop_div",
			:**  => "builtinoptop_pow",
			:%   => "builtinoptop_mod",
			:~   => "builtinoptop_rev",
			:==  => "builtinoptop_equal",
			:=== => "builtinoptop_eqq",
			:=~  => "builtinoptop_match",
			:<=> => "builtinoptop_cmp",
			:>   => "builtinoptop_gt",
			:>=  => "builtinoptop_ge",
			:<   => "builtinoptop_lt",
			:<=  => "builtinoptop_le",
			:&   => "builtinoptop_and",
			:|   => "builtinoptop_or",
			:^   => "builtinoptop_xor",
			:[]  => "builtinoptop_aref",
			:<<  => "builtinoptop_lshift",
			:>>  => "builtinoptop_rshift",
		})

		BUILTIN_TYPE_MAP = Hash.new { |h, k|
			h[k] = "T_#{k}".upcase
		}
		BUILTIN_TYPE_MAP.merge!({
			:NilClass => "T_NIL",
			:TrueClass => "T_TRUE",
			:FalseClass => "T_FALSE",
		})

		BUILTIN_C_VAR_MAP = Hash.new { |h, k|
			h[k] = "rb_#{Module.const_get(k).instance_of?(Module) ? "m" : "c"}#{k}"
		}

		attr_reader :methods

		def initialize(compiler, builtins)
			super(compiler)
			builtins = SUPPORTED_BUILTINS & builtins # "sort" and unique
			@methods = {} # [meth_sym, arity] => # [[type, impl. class/mod, types of first arg or nil, real arity], ...]
			@function_names = {} # [meth_sym, arity] => name # initialized on first use
			@typed_function_infos = {} # [meth_sym, arity, recv_type] => [fun_ptr, real_arity, first_arg_types] # initialized on first use
			@fallback_functions = {} # [meth_sym, real_arity] => name
			@functions_code = [] # source code of the replacement functions
			@fallback_functions_code = [] # source code of the fallback functions
			@method_tbl_size = 0
			@init_code = []
			builtins.each { |builtin|
				(METHODS[builtin] + COMMON_METHODS).each { |arr|
					(@methods[arr[0, 2]] ||= []) << [builtin, arr[2] || builtin, arr[3], arr[4] || arr[1]]
				}
			}
			compiler.add_preprocessor(:call) { |cfun, node|
				handle_call(cfun, node.last, node)
			}
		end

		def deduce_type(node)
			if Array === node
				case node.first
				when :lit
					node.last[:lit].class.name.to_sym
				when :nil
					:NilClass
				when :false
					:FalseClass
				when :true
					:TrueClass
				when :str, :dstr
					:String
				when :dsym
					:Symbol
				when :array, :zarray
					:Array
				when :hash
					:Hash
				when :dregx, :dregx_once
					:Regexp
				else
					nil
				end
			else
				nil
			end
		end

		def do_init_lookup(method, method_info, fallback_fun = nil)
			tbl_idx = @method_tbl_size
			@method_tbl_size += 1
			var = "builtinopt_method_tbl[#{tbl_idx}]"
			lookup_args = [BUILTIN_C_VAR_MAP[method_info[0]], BUILTIN_C_VAR_MAP[method_info[1]], compiler.sym(method), method_info[3]]
			@init_code << "#{var} = builtinopt_method_lookup(#{lookup_args.join(", ")});"
			if fallback_fun
				@init_code << "if (!(#{var})) #{var} = #{fallback_fun};"
			end
			var
		end

		def get_function(method, arity)
			ma = [method, arity]
			if (name = @function_names[ma])
				name
			elsif (meth_list = methods[ma])
				name = @function_names[ma] = "#{METHOD_NAME_MAPPINGS[method]}__#{arity}"
				code = []
				code << "static VALUE #{name}(VALUE recv#{arity > 0 ? ", VALUE *argv" : ""}) {"
				code << "switch(TYPE(recv)) {"
				meth_list.each { |m|
					fun_ptr = do_init_lookup(method, m)
					code << "case #{BUILTIN_TYPE_MAP[m[0]]}:"
					check = fun_ptr.dup
					unless NO_CLASS_CHECK_BUILTINS.include?(m[0])
						check << " && RBASIC(recv)->klass == #{BUILTIN_C_VAR_MAP[m[0]]}"
					end
					call =
						if m[3] == -1
							"(*(#{fun_ptr}))(#{arity}, #{arity > 0 ? "argv" : "NULL"}, recv)"
						else
							args = (0...arity).map { |j| "argv[#{j}]" }.join(", ")
							args = ", " + args unless args.empty?
							"(*(#{fun_ptr}))(recv#{args})"
						end
					if (first_arg_types = m[2])
						if arity != 1
							raise Ruby2CExtension::Ruby2CExtError::Bug, "arity must be 1 for arg type check"
						end
						code << "switch(TYPE(argv[0])) {"
						first_arg_types.each { |o| code << "case #{BUILTIN_TYPE_MAP[o]}:" }
						code << "if (#{check}) return #{call};"
						code << "}"
					else
						code << "if (#{check}) return #{call};"
					end
					code << "break;"
				}
				code << "}"
				code << "return rb_funcall3(recv, #{compiler.sym(method)}, #{arity}, #{arity > 0 ? "argv" : "NULL"});"
				code << "}"
				@functions_code << code.join("\n")
				name
			else
				nil
			end
		end

		def generate_fallback_function(method, real_arity)
			ma = [method, real_arity]
			if (name = @fallback_functions[ma])
				name
			else
				name = @fallback_functions[ma] = "#{METHOD_NAME_MAPPINGS[method]}__#{real_arity >= 0 ? real_arity : "V"}__fallback"
				code = []
				if real_arity == -1
					code << "static VALUE #{name}(int argc, VALUE *argv, VALUE recv) {"
					code << "return rb_funcall3(recv, #{compiler.sym(method)}, argc, argv);"
					code << "}"
				else
					args = (["VALUE recv"] + (0...real_arity).map { |j| "VALUE arg_#{j}" }).join(", ")
					code << "static VALUE #{name}(#{args}) {"
					if real_arity > 1
						code << "VALUE argv[#{real_arity}];"
						(0...real_arity).each { |j|
							code << "argv[#{j}] = arg_#{j};"
						}
					end
					argv =
						case real_arity
						when 0: "NULL"
						when 1: "&arg_0"
						else "argv"
						end
					code << "return rb_funcall3(recv, #{compiler.sym(method)}, #{real_arity}, #{argv});"
					code << "}"
				end
				@fallback_functions_code << code.join("\n")
				name
			end
		end

		def get_typed_function_info(method, arity, recv_type)
			mat = [method, arity, recv_type]
			if (infos = @typed_function_infos[mat])
				infos
			elsif (meth_list = methods[[method, arity]])
				if (m = meth_list.find { |arr| arr.first == recv_type })
					@typed_function_infos[mat] = [
						do_init_lookup(method, m, generate_fallback_function(method, m[3])),
						m[3], m[2]
					]
				else
					nil # this call is not optimizable
				end
			else
				nil
			end
		end

		def handle_call(cfun, hash, node)
			args = []
			if hash[:args]
				if hash[:args].first == :array
					args = hash[:args].last
				else
					return node
				end
			end
			if (recv_type = deduce_type(hash[:recv]))
				fun_ptr, real_arity, first_arg_types = *get_typed_function_info(hash[:mid], args.size, recv_type)
				if fun_ptr
					cfun.instance_eval {
						recv = comp(hash[:recv])
						if args.empty?
							"(*(#{fun_ptr}))(#{real_arity == -1 ? "0, NULL, " : ""}#{recv})"
						else
							arity = args.size
							c_scope_res {
								l "VALUE recv = #{recv};"
								build_c_arr(args, "argv")
								call_args =
									if real_arity == -1
										"#{arity}, #{arity > 0 ? "argv" : "NULL"}, recv"
									else
										"recv, " + (0...arity).map { |j| "argv[#{j}]" }.join(", ")
									end
								if first_arg_types
									l "switch(TYPE(argv[0])) {"
									first_arg_types.each { |o|
										l "case #{BUILTIN_TYPE_MAP[o]}:"
									}
									assign_res("(*(#{fun_ptr}))(#{call_args})")
									l "break;"
									l "default:"
									assign_res("rb_funcall3(recv, #{compiler.sym(hash[:mid])}, 1, argv)")
									l "}"
									"res"
								else
									"(*(#{fun_ptr}))(#{call_args})"
								end
							}
						end
					}
				else
					node
				end
			elsif (fun = get_function(hash[:mid], args.size))
				cfun.instance_eval {
					recv = comp(hash[:recv])
					if args.empty?
						"#{fun}(#{recv})"
					else
						c_scope_res {
							l "VALUE recv = #{recv};"
							build_c_arr(args, "argv")
							"#{fun}(recv, argv)"
						}
					end
				}
			else
				node
			end
		end

		METHOD_LOOKUP_CODE = %{
			static BUILTINOPT_FP builtinopt_method_lookup(VALUE klass, VALUE origin, ID mid, long arity) {
				NODE *body;
				while (klass != origin) {
					if (TYPE(klass) == T_ICLASS && RBASIC(klass)->klass == origin) break;
					if (st_lookup(RCLASS(klass)->m_tbl, mid, (st_data_t *)&body)) return NULL;
					klass = RCLASS(klass)->super;
					if (!klass) return NULL;
				}
				if (st_lookup(RCLASS(klass)->m_tbl, mid, (st_data_t *)&body)) {
					body = body->nd_body;
					if (nd_type(body) == NODE_FBODY) body = body->nd_head;
					if (nd_type(body) == NODE_CFUNC && body->nd_argc == arity) {
						return body->nd_cfnc;
					}
				}
				return NULL;
			}
		}

		def global_c_code
			unless @init_code.empty?
				res = []
				res << "typedef VALUE (*BUILTINOPT_FP)(ANYARGS);"
				res << "static BUILTINOPT_FP builtinopt_method_tbl[#{@method_tbl_size}];"
				res << METHOD_LOOKUP_CODE

				res.concat(@fallback_functions_code)

				res << "static void init_builtinopt() {"
				res.concat(@init_code)
				res << "}"

				res.concat(@functions_code)

				res.join("\n")
			end
		end

		def init_c_code
			unless @init_code.empty?
				"init_builtinopt();"
			end
		end

	end

end
