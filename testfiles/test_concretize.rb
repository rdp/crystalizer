require File.dirname(__FILE__) + '/test_bootstrap'
include Ruby2CExtension

class A
 def go a
   23
 end
end

Dir['temp*'].each{|f| File.delete f}

raise unless  A.instance_method(:go).arity == 1
rb = Concretize.c_ify! A, :go, true
raise "bad rb" unless rb.include? "23"
raise "bad rb" unless rb.include? "class"

c = Concretize.c_ify! A, :go, false, true
raise "bad c" unless c.include? "23"
raise "bad c" unless c.include? "VALUE"

c = Concretize.c_ify! A, :go

raise "should have concretized" unless A.instance_method(:go).arity == -1

# test: class with one ruby, one C should translate the ruby to C

class B
 def go a
  32
 end
end

assert B.instance_method(:go).arity == 1
Concretize.c_ify_class! B
assert B.instance_method(:go).arity == 1


class C
 def go a
   33
 end
end

assert C.instance_method(:go).arity == 1
Concretize.concretize!
assert C.instance_method(:go).arity == 1

puts 'success'