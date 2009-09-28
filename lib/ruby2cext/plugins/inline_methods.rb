# this one inlines [trivial] ruby methods, like #nil?
require "ruby2cext/plugin"

module Ruby2CExtension::Plugins

	class InlineMethods < Ruby2CExtension::Plugin

		METHODS = {
			[:nil?, 0] => proc { |cfun, recv, args|
				"(Qnil == (#{recv}) ? Qtrue : Qfalse)"
			},
			[:equal?, 1] => proc { |cfun, recv, args|
				cfun.instance_eval {
					c_scope_res {
						l "VALUE recv = #{recv};"
						"(recv == (#{comp(args[0])}) ? Qtrue : Qfalse)"
					}
				}
			},
			:__send__ => proc { |cfun, recv, args|
				unless args
					raise Ruby2CExtension::Ruby2CExtError, "inlining #__send__ without arguments is not allowed"
				end
				cfun.instance_eval {
					add_helper <<-EOC
						static void inline_method_send_no_method_name() {
							rb_raise(rb_eArgError, "no method name given");
						}
					EOC
					c_scope_res {
						l "VALUE recv = #{recv};"
						build_args(args)
						l "if (argc == 0) inline_method_send_no_method_name();"
						"rb_funcall2(recv, rb_to_id(argv[0]), argc - 1, (&(argv[0])) + 1)"
					}
				}
			},
		}

		def initialize(compiler)
			super
			self_node = [:self, {}]
			compiler.add_preprocessor(:vcall) { |cfun, node|
				handle(cfun, node.last[:mid], self_node, false) || node
			}
			compiler.add_preprocessor(:fcall) { |cfun, node|
				handle(cfun, node.last[:mid], self_node, node.last[:args]) || node
			}
			compiler.add_preprocessor(:call) { |cfun, node|
				handle(cfun, node.last[:mid], node.last[:recv], node.last[:args]) || node
			}
		end

		def handle(cfun, method, recv, args)
			if (pr = METHODS[method])
				pr.call(cfun, cfun.comp(recv), args)
			else
				args ||= [:array, []]
				if args.first == :array && (pr = METHODS[[method, args.last.size]])
					pr.call(cfun, cfun.comp(recv), args.last)
				else
					nil
				end
			end
		end

	end

end
