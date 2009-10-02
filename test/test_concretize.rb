require File.dirname(__FILE__) + '/test_bootstrap'
include Ruby2CExtension

class A
  def go a
    23
  end
end


at_exit {
  if $!
    puts "==== "
    puts $!.backtrace.join("\n")
    puts "===="
  end
}

Dir['temp*'].each{|f| File.delete f} rescue nil # LTODO these don't all delete right at the end...can I avoid that tho?

begin
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
  assert B.instance_method(:go).arity == -1

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


module M; def go_m a; end; end
class IM; include M; end;
  IM.new.go_m 2
  assert IM.instance_method(:go_m).arity == 1
  IM.concretize!
  assert IM.instance_method(:go_m).arity == -1
  

  assert C.instance_method(:go).arity == 1
  puts Concretize.concretize_all!
  assert C.instance_method(:go).arity == -1
ensure
  #Dir['temp*'].each{|f| File.delete f} rescue nil # LTODO these don't all delete right...
end
puts 'overall concretize success'
