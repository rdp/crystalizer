# some benchmarks

require "benchmark"

def fib(n)
    if n < 2
        n
    else
        fib(n - 1) + fib(n - 2)
    end
end

def mkmatrix(rows, cols)
    count = 1
    mx = Array.new(rows)
    (0 .. (rows - 1)).each do |bi|
        row = Array.new(cols, 0)
        (0 .. (cols - 1)).each do |j|
            row[j] = count
            count += 1
        end
        mx[bi] = row
    end
    mx
end

def mmult(rows, cols, m1, m2)
    m3 = Array.new(rows)
    (0 .. (rows - 1)).each do |bi|
        row = Array.new(cols, 0)
        (0 .. (cols - 1)).each do |j|
            val = 0
            (0 .. (cols - 1)).each do |k|
                val += m1.at(bi).at(k) * m2.at(k).at(j)
            end
            row[j] = val
        end
        m3[bi] = row
    end
    m3
end

def sqrt(x)
    x = x.to_f
    average = lambda { |a, b| (a+b)/2 }
    impr    = lambda { |g| average[g, x/g] }
    good_en = lambda { |g| (g*g - x).abs < 0.001 }
    try     = lambda { |g| good_en[g] ? g : try[impr[g]] }
    try[1.0]
end


Benchmark.bm(12) { |bmx|
    bmx.report("times") { 3000000.times{|e| e + e } }
    bmx.report("times") { 3000000.times{|e| e + e } }
    bmx.report("fib") { fib 30 }
    bmx.report("array") {
        n = 2000
        x = Array.new(n)
        y = Array.new(n, 0)
        n.times{|bi| x[bi] = bi + 1 }
        (0 .. 999).each do |e|
            (n-1).step(0,-1) do |bi|
                y[bi] += x.at(bi)
            end
        end
    }
    bmx.report("matrix") {
        n = 40
        size = 30
        m1 = mkmatrix(size, size)
        m2 = mkmatrix(size, size)
        mm = Array.new
        n.times do
            mm = mmult(size, size, m1, m2)
        end
    }
    bmx.report("while") {
        i = 3000000
        while i > 0
            break if i == 5
            i -= 1
            next if i % 100 == 0
            redo if (i-=1) % 100 == 1
        end
    }
    bmx.report("sqrt") {
        i = 40000
        while (i-=1) > 0
            sqrt 2
        end
    }
    bmx.report("3 [] alloc") {
        i = 1000000
        while (i-=1) > 0
            [[], []]
        end
    }
    bmx.report("const cache") {
        1000000.times {
            a = Array
            a = Object::Array
            a = ::Array
        }
    }
    bmx.report("method calls") {
        max = 2000
        z = x = 0
        while (x+=1) <= max
            y = 0
            while (y+=1) <= max
                z = (x+y-z) % 32000
            end
        end
    }
    bmx.report("ivar") {
        Class.new {
            def run
                @i = 4000000
                while 0 < (@i = -1 + @i)
                    a = @i
                    b = @i
                end
            end
        }.new.run
    }
}


