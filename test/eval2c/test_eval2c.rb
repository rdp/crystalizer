
require "ruby2cext/eval2c"

$e2c = Ruby2CExtension::Eval2C.new

$e2c.toplevel_eval("p __FILE__")

3.times { $e2c.toplevel_eval("p 'hello'") }

class A
	$e2c.module_eval(self, %{
		def initialize(x)
			@x = x
		end
		def foo(y)
			@x + y
		end
	})
end

p A.new(5).foo(6)

p $e2c.instance_eval("4321", "reverse")

p $e2c.compile_to_proc("|a,b| a+b").call(2, 3)

class B
	def m1; m2; end
	protected
	def m2; m3; end
	private
	def m3; :m3; end

	$e2c.compile_methods(self, :m1, :m2, :m3)
end

p B.new.m1
