require './tak_source.so'

require 'benchmark'

[7, 8, 9].each do |n|
  print n, " took ", Benchmark.realtime {   tak(18, n, 0) }, "\n"
end
