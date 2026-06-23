package tests

import "core:strings"
import "core:testing"

import test "src:testing"

// Methodin/odinfmt: when the user puts the closing `)` / `}` on its own line,
// the call or composite literal must stay broken across lines even when it would
// fit within the character width — instead of being collapsed onto one line.
// Goes through the real server formatting path (the editor's).

@(test)
format_keeps_multiline_call :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

f :: proc() {
	r := compute(
		alpha,
		beta,
		gamma,
	)
}
`,
		packages = {},
	}
	out := test.format_document_for_test(&source)
	testing.expect(t, strings.count(out, "\n") >= 6, "multi-line call was collapsed")
	testing.expect(t, strings.contains(out, "compute(\n"), "call did not stay broken")
}

@(test)
format_keeps_multiline_comp_lit :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

f :: proc() {
	v := Vec3{
		x,
		y,
		z,
	}
}
`,
		packages = {},
	}
	out := test.format_document_for_test(&source)
	testing.expect(t, strings.contains(out, "Vec3{\n") || strings.contains(out, "Vec3 {\n"), "comp lit was collapsed")
}

// When an `if` condition is a parenthesized expression the user laid out with
// its closing `)` on its own line, the `if` must not align (hang) the broken
// paren to the opening `(`. Instead the condition body indents one level past
// `if` and the `)` lines up with the `if`.
@(test)
format_if_paren_cond_aligns_to_if :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

f :: proc() {
	if (
		alpha && beta && gamma
	) {
		g()
	}
}
`,
		packages = {},
	}
	out := test.format_document_for_test(&source)
	// Body of the condition is one indent past the `if` (two tabs), not aligned
	// to the opening paren (which would be a tab followed by spaces).
	testing.expect(t, strings.contains(out, "\n\t\talpha &&\n"), "condition body not nested one level")
	// Closing paren sits at the `if` indentation (one tab), then ` {`.
	testing.expect(t, strings.contains(out, "\n\t) {\n"), "closing paren not aligned with if")
}

@(test)
format_collapses_single_line :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package main

f :: proc() {
	a := compute(alpha, beta, gamma)
	b := Vec3{x, y, z}
}
`,
		packages = {},
	}
	out := test.format_document_for_test(&source)
	testing.expect(t, strings.contains(out, "compute(alpha, beta, gamma)"), "single-line call should stay collapsed")
	testing.expect(t, strings.contains(out, "Vec3{x, y, z}"), "single-line comp lit should stay collapsed")
}
