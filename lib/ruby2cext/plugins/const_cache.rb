
module Ruby2CExtension::Plugins

	class ConstCache < Ruby2CExtension::Plugin
		def initialize(compiler)
			super
			compiler.add_preprocessor(:const) { |cfun, node|
				cfun.instance_eval {
					c_static_once {
						comp_const(node.last)
					}
				}
			}
			compiler.add_preprocessor(:colon2) { |cfun, node|
				mid = node.last[:mid]
				if mid.to_s[0,1].downcase != mid.to_s[0,1] # then it is a constant
					cfun.instance_eval {
						c_static_once {
							comp_colon2(node.last)
						}
					}
				else
					node
				end
			}
			compiler.add_preprocessor(:colon3) { |cfun, node|
				cfun.instance_eval {
					c_static_once {
						comp_colon3(node.last)
					}
				}
			}
		end
	end

end
