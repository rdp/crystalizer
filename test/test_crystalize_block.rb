require 'frubygems'
require 'sane'
require_rel 'bootstrap'
require 'fileutils'

include Ruby2CExtension

# test cache
times = []
2.times { |n|

 # ltodo test that between runs it caches and stores
 # reset AA's method
  class AA
    def go
      33
    end
  end
  assert AA.instance_method(:go).arity == 0
  
  start = Time.now

  if n == 0
    $old = Concretize.good_codes.dup
    Concretize.good_codes.clear # allow it to do something with the re-concretize
    Concretize.c_ify! AA, :go, true
    assert Concretize.cache_hits == 0
    assert AA.instance_method(:go).arity == -1
  else
    Concretize.c_ify! AA, :go, true
    assert Concretize.cache_hits > 0
    assert AA.instance_method(:go).arity == 0 # it doesn't run it just returns us the cached value
    Concretize.good_codes.merge $old # keep it around
  end
  
  times << Time.now - start
}
puts times


# now test crystalize

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
# LTODO should [?] not crystalize internal classes?
Ruby2CExtension::Concretize.crystalize_after_first_time_through {
  A.new.go
}
assert A.instance_method(:go).arity == -1
assert B.instance_method(:go).arity == 0 # b should still be 0

class C
  def go
  end
end

#Ruby2CExtension::Concretize.crystalize_after
#1000000.times { B.new.go }
#assert B.instance_method(:go).arity == -1 # should now be -1
#assert C.instance_method(:go).arity == 0 # should not have been crystalized

# TODO should ignore it after first time through...
