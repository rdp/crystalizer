require 'frubygems'
require 'sane'
require_rel 'bootstrap'

class A
 def go
   33
 end
end


class B
  def go
  end
end

assert A.instance_method(:go).arity == 0
assert B.instance_method(:go).arity == 0
Ruby2CExtension::Concretize.crystalize_after_first_time_through {
  A.new.go
}
assert A.instance_method(:go).arity == -1
assert B.instance_method(:go).arity == 0 # b should still be 0

class C
  def go
  end
end

Ruby2CExtension::Concretize.crystalize_after
1000000.times { B.new.go }
assert B.instance_method(:go).arity == -1 # should now be -1
assert C.instance_method(:go).arity == 0 # should not have been crystalized


# TODO should ignore it after first time through...