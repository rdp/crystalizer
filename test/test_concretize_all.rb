require File.dirname(__FILE__) + '/bootstrap'

at_exit {
  if $!
    puts "==== "
    puts $!.backtrace.join("\n")
    puts "===="
  end
}

class C
  def go a
    33
  end
end

include Ruby2CExtension

assert C.instance_method(:go).arity == 1
assert String.instance_method(:to_c_strlit).arity == 0
puts 'cified these', Concretize.concretize_all!.inspect
assert C.instance_method(:go).arity == -1
assert String.instance_method(:to_c_strlit).arity == -1 # this one should have been concretized, too
