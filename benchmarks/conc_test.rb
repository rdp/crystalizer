require 'rubygems'
require 'benchmark'
require '../lib/concretizer'


at_exit {
  if false #$!
    puts "==== "
    puts $!.backtrace.join("\n")
    puts "===="
  end
}


class A
 def go
 end
 def go2
  go
 end
end

a = A.new
puts Benchmark.realtime { 4000000.times { a.go }}
puts Benchmark.realtime { Ruby2CExtension::Concretize.concretize_all! }
puts Benchmark.realtime { 4000000.times { a.go }}
