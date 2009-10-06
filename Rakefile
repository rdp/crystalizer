begin
  require 'jeweler'
  Jeweler::Tasks.new do |s|
    s.name = "ruby2cext"
    # 0.2.0.
    #       2 actually works with concretize now
    s.author = "Dominik Bathon, rogerdpack"
    s.email = "dbatml@gmx.de"
    s.homepage = "http://ruby2cext.rubyforge.org/"
    s.summary = "Ruby2CExtension is a Ruby to C extension translator/compiler."
    s.add_dependency("rubynode", ">= 0.1.1")
    s.add_dependency("rogerdpack-sane")
    s.files.exclude '**/temp*'
	s.add_dependency("backports")
  end
  Jeweler::Tasks.new(spec)

rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end
