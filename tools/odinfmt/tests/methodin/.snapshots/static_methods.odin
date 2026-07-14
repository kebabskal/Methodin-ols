package test

Foo :: struct {
	x: int,
	y: int,

	pair :: static proc(n: int) -> Foo {
		return Foo{n, n}
	},

	sum :: proc() -> int {
		return x + y
	},
}

impl Foo {
	Zero :: Foo{0, 0}

	from :: static proc(x: int) -> Foo {
		return Foo{x = x, y = x * 2}
	}
}
