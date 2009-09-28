
module Ruby2CExtension::Plugins

	class CaseOptimize < Ruby2CExtension::Plugin

		include Ruby2CExtension::Tools::EnsureNodeTypeMixin

		def initialize(compiler)
			super
			compiler.add_preprocessor(:case) { |cfun, node|
				handle_case(cfun, node.last) || node
			}
		end

		def fixnum?(node)
			Array === node && node.first == :lit && Fixnum === node.last[:lit]
		end

		def fixed_immediate?(node)
			# checks if the node is optimizable and if yes returns the equivalent C value
			if fixnum?(node)
				"LONG2FIX(#{node.last[:lit].inspect})"
			elsif Array === node
				case node.first
				when :nil
					"Qnil"
				when :true
					"Qtrue"
				when :false
					"Qfalse"
				else
					false
				end
			else
				false
			end
		end

		def handle_case(cfun, hash)
			cur_when = hash[:body]
			fallback_whens = []
			opt_cases = []
			while cur_when.first == :when
				ensure_node_type(head = cur_when.last[:head], :array)
				cases = head.last.map { |wn| fixed_immediate?(wn) }
				break unless cases.all?
				case_c_code = cases.map { |c| "case #{c}:" }.join("\n")
				fixnum_whens = head.last.select { |wn| fixnum?(wn) }
				unless fixnum_whens.empty?
					goto_label = compiler.un("case_opt_label")
					case_c_code << "\n#{goto_label}:"
					fallback_whens << [:when, {
						:body => "Qnil;\ngoto #{goto_label}", # TODO: evil, depends on impl. details of comp_case/handle_when
						:head => [:array, fixnum_whens]
					}]
				end
				opt_cases << [case_c_code, cur_when.last[:body]]
				cur_when = cur_when.last[:next] || [:nil, {}]
			end
			return nil if opt_cases.empty? # nothing to optimize
			rest = cur_when
			if rest.first == :when # some whens are left construct a complete new case node
				rest = [:case, {:head => "case_opt_val", :body => rest}]
			end
			cfun.instance_eval {
				c_scope_res {
					l "VALUE case_opt_val;"
					l "case_opt_val = #{comp(hash[:head])};"
					l "switch (case_opt_val) {"
					opt_cases.each { |(case_code, body_node)|
						l case_code
						assign_res(comp(body_node))
						l "break;"
					}
					l "default:"
					if fallback_whens.empty?
						assign_res(comp(rest))
					else
						# link the fallback_whens
						fallback_whens.each_with_index { |wn, i|
							fallback_whens[i - 1].last[:next] = wn if i > 0
						}
						fallback_whens.last.last[:next] = "Qundef"
						c_if("!FIXNUM_P(case_opt_val)") {
							assign_res(comp_case({:head => "case_opt_val", :body => fallback_whens.first}))
						}
						c_else {
							assign_res("Qundef")
						}
						c_if("res == Qundef") {
							assign_res(comp(rest))
						}
					end
					l "}"
					"res"
				}
			}
		end

	end

end
