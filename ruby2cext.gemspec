spec = Gem::Specification.new do |s|
	s.name = "ruby2cext"
	s.version = "0.2.0.1"
	s.author = "Dominik Bathon"
	s.email = "dbatml@gmx.de"
	s.homepage = "http://ruby2cext.rubyforge.org/"
	s.platform = Gem::Platform::RUBY
	s.summary = "Ruby2CExtension is a Ruby to C extension translator/compiler."
	s.files =
		Dir.glob("{bin,lib,testfiles}/**/*").delete_if { |item| item.include?(".svn") } +
		Dir.glob("doc/*.{html,css}").delete_if { |item| item.include?(".svn") } +
		%w[README Changelog]
	s.executables << "rb2cx"
	s.add_dependency("rubynode", ">= 0.1.1")
	s.required_ruby_version = '~> 1.8.4'
end
