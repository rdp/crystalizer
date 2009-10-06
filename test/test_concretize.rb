require File.dirname(__FILE__) + '/test_bootstrap'
require 'assert2'

class F
  def go; end
end
F.concretize! # make sure we can
assert F.instance_method(:go).arity == -1

include Ruby2CExtension
# TODO retain visibility right
at_exit {
  if $!
    puts "==== "
    puts $!.backtrace.join("\n")
    puts "===="
  end
}

Dir['temp*'].each{|f| File.delete f} rescue nil # LTODO these don't all delete right at the end...can I avoid that tho?



class A
  def go a
    23
  end
end

# make sure it gets the guts of a method
raise unless  A.instance_method(:go).arity == 1
rb = Concretize.c_ify! A, :go, true
raise "bad rb" unless rb.include? "23"
raise "bad rb" unless rb.include? "class"


rb = Concretize.c_ify! A, :go
raise "should have concretized" unless A.instance_method(:go).arity == -1

# test: class with one ruby, one C should translate the ruby to C

class B
  def go a
    32
  end
end

assert B.instance_method(:go).arity == 1

assert Concretize.c_ify_class! B
assert !Concretize.c_ify_class!(B) # should be all done

assert B.instance_method(:go).arity == -1


assert B.public_instance_methods.grep(/go/).length == 1# it should be public...I think

class C
  def go a
    33
  end
end


class DD
  def go a, b
    34
  end
end
assert DD.instance_method(:go).arity == 2
DD.concretize!
assert DD.instance_method(:go).arity == -1

DD.new.go 3, 4 # shouldn't blow! LTODO what was that old way...

assert C.instance_method(:go).arity == 1
assert String.instance_method(:to_c_strlit).arity == 0
puts 'cified these', Concretize.concretize_all!.inspect
assert C.instance_method(:go).arity == -1
assert String.instance_method(:to_c_strlit).arity == -1


# test some ancestry shtuff

class Parent
  def go_parent
  end
end

class Child < Parent
  def go
  end
end

assert Child.ancestors[0..1] == [Child, Parent]

# TODO test: if two descend from real_c_klass normal c_klass they both get all of normal's methods

ruby = Concretize.c_ify! Child, :go, true
assert ruby.include?('Child')
assert ruby.include?('Parent')
assert Child.new.respond_to?( :go_parent )
assert Child.new.respond_to?( :go )

Child.concretize!
assert Child.ancestors[0..1] == [Child, Parent]

module M; def go_m a; end; end

class IM; include M;
end;

IM.new.go_m 2
assert IM.instance_method(:go_m).arity == 1
IM.concretize!
assert IM.instance_method(:go_m).arity == -1

optimized_time = Benchmark.realtime { 1000000.times { a.go 3 }}

puts 'started as', start_time, 'optimized as', optimized_time

puts 'overall concretize success'
