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