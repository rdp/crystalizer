public
def tak(x, y, z)
  unless (y < x)
    z
  else
    tak(tak(x-1, y, z),
         tak(y-1, z, x),
         tak(z-1, x, y))
  end
end

require 'benchmark'

[7, 8, 9].each do |n|
  print n, " took ", Benchmark.realtime {   tak(18, n, 0) }, "\n"
end
