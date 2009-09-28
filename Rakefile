begin
  require 'jeweler'
  Jeweler::Tasks.new do |s|
	s.name = "ruby2cext"
	s.version = "0.2.0.2"
        # 0.2.0.
        #       2 actually works with concretize now
	s.author = "Dominik Bathon, rogerdpack"
	s.email = "dbatml@gmx.de"
	s.homepage = "http://ruby2cext.rubyforge.org/"
	s.summary = "Ruby2CExtension is a Ruby to C extension translator/compiler."
	s.files =
		Dir.glob("{bin,lib,testfiles}/**/*").delete_if { |item| item.include?(".svn") } +
		Dir.glob("doc/*.{html,css}").delete_if { |item| item.include?(".svn") } +
		%w[README Changelog]
	s.add_dependency("rubynode", ">= 0.1.1")
	s.add_dependency("rogerdpack-sane")

  end
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end