module Ruby2CExtension

	module Tools
		# keeps track of used symbols and provides global variables that hold the corresponding ID
		class SymbolManager
			def initialize
				@syms = {}
			end

			# returns the var name for sym
			def get(sym)
				idx = (@syms[sym] ||= @syms.size)
				"sym[#{idx}] /* #{sym.to_s.gsub(/[^\w<=>+\-*\/!?@$|&~.]/, "_").gsub("*/", "__")} */"
			end

			def to_c_code(init_fun_name = "init_syms")
				res = []
				res << "static ID sym[#{@syms.size}];" unless @syms.empty?
				res << "static void #{init_fun_name}() {"
				@syms.sort_by { |sym, idx| idx }.each { |sym, idx|
					res << "sym[#{idx}] = rb_intern(#{sym.to_s.to_c_strlit});"
				}
				res << "}"
				res.join("\n")
			end
		end

		class GlobalManager
			def initialize
				@cnt = 0
				@src = []
				@reusable = {}
			end

			# returns the var name for sym
			def get(str, allow_reuse, register_gc)
				if allow_reuse && (name = @reusable[str])
					return name
				end
				name = "global[#{@cnt}]"
				@cnt += 1
				@src << "#{name} = #{str};"
				@src << "rb_global_variable(&(#{name}));" if register_gc
				if allow_reuse
					@reusable[str] = name
				end
				name
			end

			def to_c_code(init_fun_name = "init_globals")
				res = []
				res << "static VALUE global[#{@cnt}];" if @cnt > 0
				res << "static void #{init_fun_name}() {"
				res.concat(@src)
				res << "}"
				res.join("\n")
			end
		end

		class UniqueNames
			def initialize
				@prefix_cnt = Hash.new(0)
			end
			def get(prefix)
				"#{prefix}_#{@prefix_cnt[prefix]+=1}"
			end
		end

		module EnsureNodeTypeMixin
			def ensure_node_type(node, expected_types)
				expected_types = [expected_types] unless Array === expected_types
				unless node && expected_types.index(node.first)
					raise Ruby2CExtError, "unexpected node type: expected #{expected_types.join(" or ")}, found #{node.inspect}"
				end
			end
		end

	end

end