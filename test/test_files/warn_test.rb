eval("1")
method(:eval).arity
class A
	define_method(:evxx, method(:eval))
	attr :a1
	attr_reader :a2, :a3
	attr_writer :a4, :a5
	attr_accessor :a7
end
def foo
	local_variables +
		[binding]
end

class A
	p=proc{}
	instance_eval(&p)
	module_eval(&p)
	class_eval(&p)
	define_method(:xx, &p)
	instance_eval("1")
	module_eval("1")
	class_eval("1")
	define_method(:yy) {}
end

callcc(&proc{})
callcc { |cc| cc }

# no warnings below
class A
	instance_eval { 1 }
	module_eval { 1 }
	class_eval { 1 }
end
