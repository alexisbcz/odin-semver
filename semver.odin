/*
Package semver parses, formats and compares Semantic Versioning 2.0.0
versions, and matches them against npm and Cargo style range constraints.

Versions follow https://semver.org/spec/v2.0.0.html exactly: `parse` rejects
leading zeros, empty identifiers and missing components. Precedence follows
section 11 of the specification, so build metadata never affects `compare`.

Ranges follow the node-semver grammar: primitive comparators (`<`, `<=`, `>`,
`>=`, `=`), caret (`^`), tilde (`~` and `~>`), X-ranges (`1.x`, `1.2.*`, `*`),
hyphen ranges (`1.2 - 2.3.4`) and `||` unions. Comparators inside one set may
be separated by spaces or commas.

Example:
	import "shared:semver"

	main :: proc() {
		r, err := semver.parse_range("^1.2.0 || ~2.0.1")
		if err != nil {
			return
		}
		defer semver.range_destroy(&r)

		v, _ := semver.parse("1.9.3")
		defer semver.version_destroy(v)
		assert(semver.satisfies(v, r))
	}

Every value in this package is safe to use from one thread at a time. Values
that are only read, such as a parsed Range passed to satisfies, may be shared
between threads.
*/
package semver

import "base:runtime"

/*
Version is one Semantic Versioning 2.0.0 version.

`prerelease` and `build` hold the dot-separated identifiers without the
leading `-` or `+`, and are empty when absent. A Version returned by parse
owns those strings; free them with version_destroy. A Version built as a
literal, or returned by next_major, next_minor or next_patch, owns nothing
unless you assign allocated strings to it.
*/
Version :: struct {
	major:      u64,
	minor:      u64,
	patch:      u64,
	prerelease: string,
	build:      string,
}

// Parse_Error lists the ways a version string can violate Semantic Versioning 2.0.0.
Parse_Error :: enum {
	None,
	// The input was empty or only whitespace.
	Empty_Input,
	// Fewer than three numeric components, for example `1.2`.
	Missing_Component,
	// More than three numeric components, for example `1.2.3.4`.
	Extra_Component,
	// A numeric component was empty, for example `1..3`.
	Empty_Component,
	// A numeric component contained something other than ASCII digits.
	Invalid_Number,
	// A numeric component or numeric prerelease identifier had a leading zero.
	Leading_Zero,
	// A numeric component did not fit in a u64.
	Number_Overflow,
	// A prerelease or build identifier was empty, for example `1.2.3-a..b` or `1.2.3+`.
	Empty_Identifier,
	// An identifier contained a character outside `[0-9A-Za-z-]`.
	Invalid_Identifier,
}

// Range_Error lists the ways a range string can be malformed beyond its versions.
Range_Error :: enum {
	None,
	// An operator was unknown or doubled, for example `=>1.2.3` or `>>1`.
	Invalid_Operator,
	// A hyphen range lacked a bound or carried an operator, for example `1.2.3 -` or `>1 - 2`.
	Invalid_Hyphen_Range,
	// A concrete number followed a wildcard, for example `1.x.3`.
	Invalid_Wildcard,
	// A prerelease or build suffix appeared on a partial version, for example `1.2-beta`.
	Unexpected_Qualifier,
	// An operator had no version after it, for example `>=` on its own.
	Missing_Version,
}

/*
Error is the compound error type returned by every fallible procedure in this
package. `nil` means success. Compare it against a specific variant, such as
`semver.Error(semver.Parse_Error.Leading_Zero)`, or use a type switch.
*/
Error :: union #shared_nil {
	Parse_Error,
	Range_Error,
	runtime.Allocator_Error,
}
