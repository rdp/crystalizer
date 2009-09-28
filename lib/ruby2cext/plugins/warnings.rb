
module Ruby2CExtension::Plugins

	# TODO: Module.nesting, Module.constants, Kernel#autoload and Kernel#autoload?

	class Warnings < Ruby2CExtension::Plugin

		CALL_TYPES = [:vcall, :fcall, :call]

		exp = "might not behave as expected"
		exp2 = "will not behave as expected"
		vis_exp = "visibility of the defined %s might not be as expected"

		VCALL_WARNINGS = {
			:binding => exp2,
			:local_variables => exp2,
			:callcc => exp,
		}

		FCALL_WARNINGS = {
			:set_trace_func => exp,
			:eval => exp,
			:define_method => vis_exp % "method",
			:attr => vis_exp % "attribute",
			:attr_reader => vis_exp % "attribute(s)",
			:attr_writer => vis_exp % "attribute(s)",
			:attr_accessor => vis_exp % "attribute(s)",
			:instance_eval => exp,
			:module_eval => exp,
			:class_eval => exp,
		}

		CALL_WARNINGS = {
			:arity => "will return -1 for all methods defined in compiled Ruby code",
			:instance_eval => exp,
			:module_eval => exp,
			:class_eval => exp,
		}

		BLOCK_PASS_WARNINGS = {
			:define_method => true,
			:instance_eval => true,
			:module_eval => true,
			:class_eval => true,
		}

		NO_WARNING_WITH_ITER = {
			:instance_eval => true,
			:module_eval => true,
			:class_eval => true,
		}

		def initialize(compiler)
			super
			CALL_TYPES.each { |ct|
				ct_sym = "check_#{ct}".to_sym
				compiler.add_preprocessor(ct) { |cfun, node|
					send(ct_sym, node.last)
					node
				}
			}
			[:iter, :block_pass].each { |it|
				it_sym = "check_#{it}".to_sym
				compiler.add_preprocessor(it) { |cfun, node|
					if node.last[:iter] && CALL_TYPES.include?(node.last[:iter].first)
						send(it_sym, node.last[:iter])
					end
					node
				}
			}
		end

		def warn(str, node_hash = {})
			lstr = ""
			if (n = node_hash[:node])
				lstr << "#{n.file}:#{n.line}: "
			end
			lstr << "warning: " << str
			compiler.log(lstr, true)
		end

		def check_vcall(hash)
			if (m = VCALL_WARNINGS[hash[:mid]])
				warn("#{hash[:mid]}: #{m}", hash)
			end
		end

		def check_fcall(hash)
			if (m = FCALL_WARNINGS[hash[:mid]])
				warn("#{hash[:mid]}: #{m}", hash)
			else
				unless hash[:args]
					check_vcall(hash)
				end
			end
		end

		def check_call(hash)
			if (m = CALL_WARNINGS[hash[:mid]])
				warn("#{hash[:mid]}: #{m}", hash)
			end
		end

		def check_iter(iter_node)
			mid = iter_node.last[:mid]
			unless NO_WARNING_WITH_ITER[mid]
				send("check_#{iter_node.first}", iter_node.last)
			end
		end

		def check_block_pass(iter_node)
			mid = iter_node.last[:mid]
			if BLOCK_PASS_WARNINGS[mid]
				warn("#{mid} with block_pass: might not behave as expected", iter_node.last)
			else
				send("check_#{iter_node.first}", iter_node.last)
			end
		end
	end

end
