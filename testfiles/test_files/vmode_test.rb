def a; end
public
def b; end
private
def c; end
protected rescue puts("failed OK")
def d; end
module_function rescue puts("failed OK")
def e; end

module A
	def a; end
	public
	def b; end
	private
	def c; end
	protected
	def d; end
	module_function
	def e; end
end

class B
	def a; end
	public
	def b; end
	private
	def c; end
	protected
	def d; end
	module_function rescue puts("failed OK")
	def e; end
end

class << "xxx"
	def a; end
	public
	def b; end
	private
	def c; end
	protected
	def d; end
	module_function rescue puts("failed OK")
	def e; end
end

class C
	def foo
		def a; end
		public rescue puts("failed OK")
		def b; end
		private rescue puts("failed OK")
		def c; end
		protected rescue puts("failed OK")
		def d; end
		module_function rescue puts("failed OK")
		def e; end
	end
end

C.new.foo

Module.new.class_eval {
	def a; end
	public
	def b; end
	private
	def c; end
	protected
	def d; end
	module_function
	def e; end
}
