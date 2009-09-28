require 'benchmark'
require 'frubygems'

require 'concretizer'

class A
 def go
 end
 def go2
  go
 end
end

a = A.new
puts Benchmark.realtime { 1000000.times { a.go }}
puts Benchmark.realtime { Ruby2CExtension::Concretize.concretize_all! }
puts Benchmark.realtime { 1000000.times { a.go }}
