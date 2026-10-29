# semver

[![CI](https://github.com/alexisbcz/odin-semver/actions/workflows/ci.yml/badge.svg)](https://github.com/alexisbcz/odin-semver/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Odin](https://img.shields.io/badge/Odin-dev--2026--09-1e5a99.svg)](https://odin-lang.org)

Parse, compare and match [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) versions in Odin, with npm and Cargo style range constraints and the same results as node-semver.

## Install

The repository root is the package, so you can vendor it in two ways.

As a Git submodule inside your project:

```sh
git submodule add https://github.com/alexisbcz/odin-semver libs/semver
```

```odin
import "libs/semver"
```

As a copy in a shared collection that all your projects use:

```sh
git clone https://github.com/alexisbcz/odin-semver ~/odin-shared/semver
odin build . -collection:shared=$HOME/odin-shared
```

```odin
import "shared:semver"
```

## Quick start

```odin
package main

import "core:fmt"
import "shared:semver"

main :: proc() {
	r, err := semver.parse_range("^1.2 || ~2.0.1")
	if err != nil {
		fmt.eprintln("range failed:", err)
		return
	}
	defer semver.range_destroy(&r)

	published := []semver.Version{
		{major = 1, minor = 9, patch = 4},
		{major = 2, minor = 0, patch = 3},
		{major = 2, minor = 1, patch = 0},
	}
	if i, ok := semver.max_satisfying(published, r); ok {
		fmt.printfln("best match: %d.%d.%d", published[i].major, published[i].minor, published[i].patch)
	}

	v, perr := semver.parse("1.0.0-rc.1+build.5")
	if perr != nil {
		fmt.eprintln("parse failed:", perr)
		return
	}
	defer semver.version_destroy(v)
	fmt.println("rc.1 ranks below the release:", semver.less(v, semver.Version{major = 1}))
}
```

This prints `best match: 2.0.3` and `rc.1 ranks below the release: true`.

## Range syntax

`parse_range` follows the node-semver grammar. Each form desugars to primitive comparators, and `range_to_string` prints the result:

| Range | Means |
| --- | --- |
| `1.2.3`, `=1.2.3`, `v1.2.3` | `1.2.3` |
| `>1.2.3`, `>=1.2.3`, `<1.2.3`, `<=1.2.3` | Itself |
| `^1.2.3` | `>=1.2.3 <2.0.0-0` |
| `^0.2.3` | `>=0.2.3 <0.3.0-0` |
| `^0.0.3` | `>=0.0.3 <0.0.4-0` |
| `~1.2.3`, `~>1.2.3` | `>=1.2.3 <1.3.0-0` |
| `~1` | `>=1.0.0 <2.0.0-0` |
| `1.x`, `1.*`, `1` | `>=1.0.0 <2.0.0-0` |
| `*`, `x`, empty | `>=0.0.0` |
| `>1.2` | `>=1.3.0` |
| `<=1.2` | `<1.3.0-0` |
| `1.2 - 2.3.4` | `>=1.2.0 <=2.3.4` |
| `1.2.3 - 2.3` | `>=1.2.3 <2.4.0-0` |
| `>=1.2.0, <1.5.0` | `>=1.2.0 <1.5.0` |
| `^1 \|\| ^3` | `>=1.0.0 <2.0.0-0 \|\| >=3.0.0 <4.0.0-0` |

You may separate the comparators in one set with spaces or commas, which covers Cargo's `>=1.2, <1.5` form. A bare version means an exact match, as in npm. Cargo treats a bare version as a caret range, so write `^1.2.3` when you mean that.

A prerelease such as `1.3.0-beta` only satisfies a set that also names a prerelease of `1.3.0`. So `^1.2.0` rejects it while `>=1.3.0-alpha <2` accepts it. Pass `include_prerelease = true` to `parse_range` to let prereleases match every set.

## API overview

| Declaration | Purpose | Allocates | Free with |
| --- | --- | --- | --- |
| `Version` | Major, minor, patch, prerelease and build | Not by itself | `version_destroy` |
| `parse(s, allocator)` | Strict Semantic Versioning 2.0.0 parse | Prerelease and build copies | `version_destroy` |
| `parse_loose(s, allocator)` | Parse after trimming spaces and a leading `v` or `=` | Prerelease and build copies | `version_destroy` |
| `is_valid(s)` | Check a version string | No | Not needed |
| `version_clone(v, allocator)` | Deep copy | Yes | `version_destroy` |
| `to_string(v, allocator)`, `write_version(b, v)` | Canonical text | Yes, or into a builder | `delete` |
| `compare(a, b)`, `less`, `equal` | Precedence, ignoring build metadata | No | Not needed |
| `compare_with_build(a, b)`, `sort(versions)` | Total order that breaks ties on build metadata | No | Not needed |
| `next_major`, `next_minor`, `next_patch` | The next release, npm style | No | Not needed |
| `Range`, `parse_range(s, include_prerelease, allocator)` | Parse a constraint | Yes | `range_destroy` |
| `satisfies(v, r)`, `comparator_matches(c, v)` | Test a version | No | Not needed |
| `max_satisfying`, `min_satisfying` | Index of the best match in a slice | No | Not needed |
| `max_satisfying_string(versions, range, allocator)` | Best match in a string listing, skipping invalid entries | Scratch only | Not needed |
| `satisfies_string(version, range, allocator)` | One-shot check from text | Scratch only | Not needed |
| `range_to_string(r, allocator)`, `write_range(b, r)` | Desugared text | Yes, or into a builder | `delete` |
| `Error` | Union of `Parse_Error`, `Range_Error` and `runtime.Allocator_Error` | No | Not needed |

Errors are enum values that print as their names, for example `parse("1.02.3")` returns `Parse_Error.Leading_Zero`.

## Examples

Each directory under `examples/` is a runnable program:

```sh
odin run examples/basic
```

## Design notes

- Every allocating procedure takes `allocator := context.allocator` and says who owns the result.
- A `Version` is a plain value. It owns its prerelease and build strings only when `parse`, `parse_loose` or `version_clone` created it, and `version_destroy` takes the same allocator back. A version without a prerelease or build allocates nothing.
- A `Range` copies its source text once. Every comparator borrows from that copy, so `range_destroy` frees three allocations and nothing else.
- Numeric prerelease identifiers compare as digit strings, so `1.0.0-99999999999999999999999` still sorts correctly. Major, minor and patch are `u64` and overflow is an error.
- Fallible procedures return `(T, Error)`. The library never panics on bad input.
- The package keeps no global mutable state. A parsed `Range` is read-only, so several threads may match against one value.

## Testing

```sh
odin check . -vet -strict-style -disallow-do -no-entry-point
odin test tests -vet -strict-style -disallow-do -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true
vale sync && vale *.md
```

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Commits follow Conventional Commits, and every change that users can see gets a line in [CHANGELOG.md](CHANGELOG.md).

## License

MIT. See [LICENSE](LICENSE).
