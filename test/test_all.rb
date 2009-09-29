require File.dirname(__FILE__) + '/test_bootstrap'
include Ruby2CExtension


dir = File.dirname(__FILE__)
Dir.glob(dir + '/test_files/*.{c,so,o}').each{|f| File.delete f} # cleanup

logger = Logger.new STDOUT

for file_name in Dir[dir + '/test_files/*.rb']
  # TODO grab the normal ruby output, then grab the ruby2c output :)
  logger = Logger.new STDOUT
  out = Compiler.compile_file(file_name, plugins = {}, 
        include_paths = [], only_c = true, logger)
  raise unless out
end

Compiler.compile_file('test_files/test.rb', plugins = {}, 
        include_paths = [], only_c = false, logger)
require 'test_files/test.so'
raise "non worky" unless defined?(AliasTest) # should have loaded it in

require dir + '/test_concretize' # run this test, too

puts 'success'
