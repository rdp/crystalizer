
module Ruby2CExtension::Plugins

	class RequireInclude < Ruby2CExtension::Plugin

		attr_reader :include_paths

		def initialize(compiler, include_paths, ignore_files = nil)
			super(compiler)
			@include_paths = include_paths
			done = {}
			if ignore_files
				ignore_files.each { |file|
					done[File.expand_path(file)] = true
				}
			end
			compiler.add_preprocessor(:fcall) { |cfun, node|
				hash = node.last
				if hash[:mid] == :require &&
						(args = hash[:args]) &&
						args.first == :array &&
						(args = args.last).size == 1 &&
						Array === args[0] &&
						args[0].first == :str &&
						(file = search_file(args[0].last[:lit]))
					unless done[File.expand_path(file)]
						done[File.expand_path(file)] = true
						cfun.compiler.log "including require'd file: #{file}"
						cfun.instance_eval {
							add_helper <<-EOC
								static NODE * find_top_cref(NODE *cref) {
									while (cref && cref->nd_next) cref = cref->nd_next;
									return cref;
								}
							EOC
							c_scope {
								l "NODE *top_cref = find_top_cref(#{get_cref});"
								l "static int done = 0;"
								c_if("!done") {
									l "done = 1;"
									compiler.rb_file_to_toplevel_functions(IO.read(file), file).each { |tlfn|
										l "#{tlfn}(org_ruby_top_self, top_cref);"
									}
								}
							}
						}
					end
					"Qtrue"
				else
					node
				end
			}
		end

		def search_file(req_str)
			req_str = req_str.dup
			unless req_str =~ /\.rb\z/
				req_str << ".rb"
			end
			res = false
			include_paths.map { |path|
				File.join(path, req_str)
			}.find { |file|
				File.exists? file
			}
		end
	end

end
