begin
  require 'jeweler'
  Jeweler::Tasks.new do |s|
    s.name = "crystalizer"
    # 0.2.0.
    #       2 actually works with concretize now
    s.author = "Dominik Bathon, rogerdpack"
    s.email = "dbatml@gmx.de"
#    s.homepage = "http://ruby2cext.rubyforge.org/"
    s.summary = "Ruby2CExtension is a Ruby to C extension translator/compiler/concretizer."
    s.add_dependency("rubynode", ">= 0.1.1")
    s.add_dependency("sane")
    s.add_dependency("event_hook")
    s.files.exclude '**/temp*'
    s.add_dependency("backports")
    s.add_dependency("ruby2ruby")
    s.add_dependency("ParseTree")
    s.add_development_dependency("assert2")
    s.add_development_dependency("backtracer")
  end

rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end
