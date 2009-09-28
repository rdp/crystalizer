
require "rubynode"
require "digest/sha1"

module Ruby2CExtension

	class Eval2C

		attr_reader :path, :prefix, :plugins, :logger, :force_recompile

		DEFAULT_PATH = File.join(File.expand_path(ENV["HOME"] || ENV["USERPROFILE"] || ENV["HOMEPATH"] || "."), ".ruby2cext")

		def initialize(options = {})
			unless (@path = options[:path])
				@path = DEFAULT_PATH
				Dir.mkdir(@path, 0700) unless File.exists?(@path)
			end
			@path = File.expand_path(@path)
			unless File.directory?(@path)
				raise Ruby2CExtError, "#{@path} is no directory"
			end
			unless File.stat(@path).mode & 022 == 0 # no writing for group and others
				warn "Ruby2CExtension::Eval2C warning: #{@path} is insecure"
			end
			@prefix = options[:prefix] || "eval2c"
			@plugins = options[:plugins] || {:optimizations => :all}
			@logger = options[:logger]
			@force_recompile = options[:force_recompile]
			@done = {}
			@digest_extra = Ruby2CExtension::FULL_VERSION_STRING + @plugins.inspect.split(//).sort.join("")
		end

		private

		def compile_helper(digest_str)
			name = "#{prefix}_#{Digest::SHA1.hexdigest(digest_str + @digest_extra)}"
			gvar_name = "$__#{name}__"
			dl_filename = File.join(path, "#{name}.#{Compiler::DLEXT}")
			if !File.exists?(dl_filename) || (force_recompile && !@done[name])
				c = Compiler.new(name, logger)
				c.add_plugins(plugins)
				yield c, name, gvar_name
				c_filename = File.join(path, "#{name}.c")
				File.open(c_filename, "w") { |f| f.puts(c.to_c_code) }
				unless Compiler.compile_c_file_to_dllib(c_filename, logger) == dl_filename
					raise Ruby2CExtError::Bug, "unexpected return value from compile_c_file_to_dllib"
				end
				@done[name] = true
			end
			require dl_filename
			eval(gvar_name) # return the proc
		end

		public

		def compile_to_proc(code_str)
			compile_helper(code_str) { |compiler, name, gvar_name|
				compiler.add_rb_file("#{gvar_name} = proc { #{code_str} }", name)
			}
		end

		def module_eval(mod, code_str)
			mod.module_eval(&compile_to_proc(code_str))
		end
		alias :class_eval :module_eval

		def instance_eval(object, code_str)
			object.instance_eval(&compile_to_proc(code_str))
		end

		def toplevel_eval(code_str)
			compile_to_proc(code_str).call
		end

		def compile_methods(mod, *methods)
			methods = methods.map { |m| m.to_sym }.uniq
			defs = methods.map { |m|
				bnode = mod.instance_method(m).body_node
				unless bnode.type == :scope
					raise Ruby2CExtError, "the method #{m} cannot be compiled, only methods defined using def can be compiled"
				end
				[:defn, {:mid => m, :defn => bnode.transform(Compiler::NODE_TRANSFORM_OPTIONS)}]
			}
			node_tree = [:scope, {:next => [:gasgn, {:vid => :$test, :value =>
				[:iter, {
					:var => false,
					:iter => [:fcall, {:args => false, :mid => :proc}],
					:body => [:block, defs]
				}]
			}]}]
			# save current visibility of the methods
			publ_methods = mod.public_instance_methods.map { |m| m.to_sym } & methods
			prot_methods = mod.protected_instance_methods.map { |m| m.to_sym } & methods
			priv_methods = mod.private_instance_methods.map { |m| m.to_sym } & methods
			# compile to test if the methods don't need a cref and to get a string for the hash
			c = Compiler.new("test")
			c.add_toplevel(c.compile_toplevel_function(node_tree))
			test_code = c.to_c_code(nil) # no time_stamp
			# don't allow methods that need a cref, because the compiled version would get a different cref
			if test_code =~ /^static void def_only_once/ # a bit hackish ...
				raise Ruby2CExtError, "the method(s) cannot be compiled, because at least one needs a cref"
			end
			# compile the proc
			def_proc = compile_helper(test_code) { |compiler, name, gvar_name|
				node_tree.last[:next].last[:vid] = gvar_name.to_sym
				compiler.add_toplevel(compiler.compile_toplevel_function(node_tree))
			}
			# try to remove all the methods
			mod.module_eval {
				methods.each { |m|
					remove_method(m) rescue nil
				}
			}
			# add the compiled methods
			mod.module_eval &def_proc
			# restore original visibility
			mod.module_eval {
				public *publ_methods unless publ_methods.empty?
				protected *prot_methods unless prot_methods.empty?
				private *priv_methods unless priv_methods.empty?
			}
		end

	end

end
