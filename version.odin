package semver

import "core:slice"
import "core:strings"

/*
parse reads a strict Semantic Versioning 2.0.0 version such as `1.2.3-rc.1+build.5`.

It accepts no leading `v`, no surrounding whitespace and no partial versions;
use parse_loose for user-typed input.

Inputs:
- s: the version text.
- allocator: allocates the copies of the prerelease and build strings.

Returns:
- v: the version; free it with `version_destroy(v, allocator)`.
- err: a Parse_Error describing the first problem found, or an allocator error.

Example:
	v, err := semver.parse("1.0.0-alpha.1")
	if err != nil {
		return
	}
	defer semver.version_destroy(v)
*/
parse :: proc(s: string, allocator := context.allocator) -> (v: Version, err: Error) {
	view, perr := parse_view(s)
	if perr != .None {
		return {}, perr
	}
	return version_clone(view, allocator)
}

/*
parse_loose reads a version the way people tend to write it: it trims
surrounding whitespace and accepts one leading `=`, `v` or `V`, as in
`v1.2.3` or ` =1.2.3 `. Everything after the prefix must be a strict
Semantic Versioning 2.0.0 version.

Returns:
- v: the version; free it with `version_destroy(v, allocator)`.
- err: a Parse_Error or an allocator error.
*/
parse_loose :: proc(s: string, allocator := context.allocator) -> (v: Version, err: Error) {
	return parse(trim_loose(s), allocator)
}

/*
is_valid reports whether `s` is a strict Semantic Versioning 2.0.0 version.
It never allocates.
*/
is_valid :: proc(s: string) -> bool {
	_, err := parse_view(s)
	return err == .None
}

/*
version_clone returns a deep copy of `v` whose prerelease and build strings
are allocated with `allocator`.

Returns:
- clone: the copy; free it with `version_destroy(clone, allocator)`.
- err: an allocator error. On failure nothing stays allocated.
*/
version_clone :: proc(v: Version, allocator := context.allocator) -> (clone: Version, err: Error) {
	clone = v
	clone.prerelease = ""
	clone.build = ""
	if v.prerelease != "" {
		pre, alloc_err := strings.clone(v.prerelease, allocator)
		if alloc_err != nil {
			return {}, alloc_err
		}
		clone.prerelease = pre
	}
	if v.build != "" {
		build, alloc_err := strings.clone(v.build, allocator)
		if alloc_err != nil {
			delete(clone.prerelease, allocator)
			return {}, alloc_err
		}
		clone.build = build
	}
	return clone, nil
}

/*
version_destroy frees the prerelease and build strings of a Version returned
by parse, parse_loose or version_clone. Pass the same allocator that created
it. Calling it on a Version that owns nothing is safe.
*/
version_destroy :: proc(v: Version, allocator := context.allocator) {
	delete(v.prerelease, allocator)
	delete(v.build, allocator)
}

/*
write_version appends the canonical text of `v`, such as `1.2.3-rc.1+b5`, to `b`.
*/
write_version :: proc(b: ^strings.Builder, v: Version) {
	strings.write_u64(b, v.major)
	strings.write_byte(b, '.')
	strings.write_u64(b, v.minor)
	strings.write_byte(b, '.')
	strings.write_u64(b, v.patch)
	if v.prerelease != "" {
		strings.write_byte(b, '-')
		strings.write_string(b, v.prerelease)
	}
	if v.build != "" {
		strings.write_byte(b, '+')
		strings.write_string(b, v.build)
	}
}

/*
to_string formats `v` in canonical form, so `to_string(parse(s))` returns `s`
for every valid `s`.

Returns:
- s: a new string owned by the caller; free it with `delete(s, allocator)`.
- err: an allocator error.
*/
to_string :: proc(v: Version, allocator := context.allocator) -> (s: string, err: Error) {
	b := strings.builder_make(allocator) or_return
	write_version(&b, v)
	return strings.to_string(b), nil
}

/*
compare returns -1, 0 or 1 when `a` has lower, equal or higher precedence
than `b`, following section 11 of Semantic Versioning 2.0.0.

A version without a prerelease ranks above the same version with one, so
`1.0.0-rc.1 < 1.0.0`. Build metadata is ignored, so `1.0.0+a` and `1.0.0+b`
compare equal; use compare_with_build when you need a total order.
*/
compare :: proc(a, b: Version) -> int {
	if c := cmp_u64(a.major, b.major); c != 0 {
		return c
	}
	if c := cmp_u64(a.minor, b.minor); c != 0 {
		return c
	}
	if c := cmp_u64(a.patch, b.patch); c != 0 {
		return c
	}
	switch {
	case a.prerelease == "" && b.prerelease == "":
		return 0
	case a.prerelease == "":
		return 1
	case b.prerelease == "":
		return -1
	}
	return compare_identifiers(a.prerelease, b.prerelease)
}

/*
compare_with_build orders versions like compare, then breaks ties on build
metadata: no build ranks first, then identifiers compare the same way
prerelease identifiers do, and builds that still tie, such as `01` and `1`,
fall back to byte order. Only identical versions compare equal. The Semantic Versioning specification gives build
metadata no precedence, so use this only for stable sorting and deduplication.
*/
compare_with_build :: proc(a, b: Version) -> int {
	if c := compare(a, b); c != 0 {
		return c
	}
	switch {
	case a.build == b.build:
		return 0
	case a.build == "":
		return -1
	case b.build == "":
		return 1
	}
	if c := compare_identifiers(a.build, b.build); c != 0 {
		return c
	}
	// Numeric identifiers such as `01` and `1` have equal value but are
	// different metadata; fall back to the raw text to keep the order total.
	return strings.compare(a.build, b.build)
}

// less reports whether `a` has lower precedence than `b`.
less :: proc(a, b: Version) -> bool {
	return compare(a, b) < 0
}

// equal reports whether `a` and `b` have the same precedence, ignoring build metadata.
equal :: proc(a, b: Version) -> bool {
	return compare(a, b) == 0
}

/*
sort orders `versions` in place from lowest to highest precedence. Versions
of equal precedence are ordered by build metadata with compare_with_build, so
the result is deterministic.
*/
sort :: proc(versions: []Version) {
	slice.sort_by_cmp(versions, proc(a, b: Version) -> slice.Ordering {
		return slice.Ordering(compare_with_build(a, b))
	})
}

/*
next_major returns the next major release after `v`, following npm: a
prerelease of a major release, such as `2.0.0-rc.1`, becomes `2.0.0`, and
anything else becomes `major+1.0.0`. The result owns no memory.

Returns:
- next: the new version, without prerelease or build.
- err: `.Number_Overflow` when the major component is already the u64 maximum.
*/
next_major :: proc(v: Version) -> (next: Version, err: Error) {
	if v.minor == 0 && v.patch == 0 && v.prerelease != "" {
		return {major = v.major}, nil
	}
	if v.major == max(u64) {
		return {}, .Number_Overflow
	}
	return {major = v.major + 1}, nil
}

/*
next_minor returns the next minor release after `v`, following npm: a
prerelease of a minor release, such as `1.3.0-rc.1`, becomes `1.3.0`, and
anything else becomes `major.minor+1.0`. The result owns no memory.

Returns:
- next: the new version, without prerelease or build.
- err: `.Number_Overflow` when the minor component is already the u64 maximum.
*/
next_minor :: proc(v: Version) -> (next: Version, err: Error) {
	if v.patch == 0 && v.prerelease != "" {
		return {major = v.major, minor = v.minor}, nil
	}
	if v.minor == max(u64) {
		return {}, .Number_Overflow
	}
	return {major = v.major, minor = v.minor + 1}, nil
}

/*
next_patch returns the next patch release after `v`, following npm: a
prerelease such as `1.2.3-rc.1` becomes `1.2.3`, and a release becomes
`major.minor.patch+1`. The result owns no memory.

Returns:
- next: the new version, without prerelease or build.
- err: `.Number_Overflow` when the patch component is already the u64 maximum.
*/
next_patch :: proc(v: Version) -> (next: Version, err: Error) {
	if v.prerelease != "" {
		return {major = v.major, minor = v.minor, patch = v.patch}, nil
	}
	if v.patch == max(u64) {
		return {}, .Number_Overflow
	}
	return {major = v.major, minor = v.minor, patch = v.patch + 1}, nil
}

// parse_view parses `s` without allocating; the result borrows from `s`.
@(private)
parse_view :: proc(s: string) -> (v: Version, err: Parse_Error) {
	if len(strings.trim_space(s)) == 0 {
		return {}, .Empty_Input
	}
	rest := s
	if i := strings.index_byte(rest, '+'); i >= 0 {
		v.build = rest[i + 1:]
		rest = rest[:i]
		validate_identifiers(v.build, false) or_return
	}
	if i := strings.index_byte(rest, '-'); i >= 0 {
		v.prerelease = rest[i + 1:]
		rest = rest[:i]
		validate_identifiers(v.prerelease, true) or_return
	}

	parts: [3]u64
	count := 0
	for {
		part := rest
		next := strings.index_byte(rest, '.')
		if next >= 0 {
			part = rest[:next]
		}
		if count == 3 {
			return {}, .Extra_Component
		}
		parts[count] = parse_number(part) or_return
		count += 1
		if next < 0 {
			break
		}
		rest = rest[next + 1:]
	}
	if count < 3 {
		return {}, .Missing_Component
	}
	v.major, v.minor, v.patch = parts[0], parts[1], parts[2]
	return v, .None
}

// parse_number reads one numeric component: ASCII digits, no leading zero, fits in u64.
@(private)
parse_number :: proc(s: string) -> (n: u64, err: Parse_Error) {
	if len(s) == 0 {
		return 0, .Empty_Component
	}
	for c in transmute([]byte)s {
		if c < '0' || c > '9' {
			return 0, .Invalid_Number
		}
	}
	if len(s) > 1 && s[0] == '0' {
		return 0, .Leading_Zero
	}
	for c in transmute([]byte)s {
		d := u64(c - '0')
		if n > (max(u64) - d) / 10 {
			return 0, .Number_Overflow
		}
		n = n * 10 + d
	}
	return n, .None
}

// validate_identifiers checks a dot-separated prerelease or build identifier list.
@(private)
validate_identifiers :: proc(s: string, is_prerelease: bool) -> Parse_Error {
	rest := s
	for {
		ident := rest
		next := strings.index_byte(rest, '.')
		if next >= 0 {
			ident = rest[:next]
		}
		if len(ident) == 0 {
			return .Empty_Identifier
		}
		for c in transmute([]byte)ident {
			if !is_identifier_byte(c) {
				return .Invalid_Identifier
			}
		}
		if is_prerelease && len(ident) > 1 && ident[0] == '0' && is_numeric(ident) {
			return .Leading_Zero
		}
		if next < 0 {
			return .None
		}
		rest = rest[next + 1:]
	}
}

@(private)
is_identifier_byte :: proc(c: byte) -> bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '-'
}

@(private)
is_numeric :: proc(s: string) -> bool {
	if len(s) == 0 {
		return false
	}
	for c in transmute([]byte)s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

@(private)
cmp_u64 :: proc(a, b: u64) -> int {
	if a < b {
		return -1
	}
	if a > b {
		return 1
	}
	return 0
}

/*
compare_identifiers compares two dot-separated identifier lists following
section 11.4: numeric identifiers compare numerically and rank below
alphanumeric ones, alphanumeric ones compare in ASCII order, and a shorter
list ranks below a longer one that it prefixes. Numbers compare as digit
strings, so arbitrarily long numeric identifiers never overflow.
*/
@(private)
compare_identifiers :: proc(a, b: string) -> int {
	ra, rb := a, b
	for {
		ia, more_a := strings.split_iterator(&ra, ".")
		ib, more_b := strings.split_iterator(&rb, ".")
		switch {
		case !more_a && !more_b:
			return 0
		case !more_a:
			return -1
		case !more_b:
			return 1
		}
		if c := compare_identifier(ia, ib); c != 0 {
			return c
		}
	}
}

@(private)
compare_identifier :: proc(a, b: string) -> int {
	na, nb := is_numeric(a), is_numeric(b)
	switch {
	case na && nb:
		// Build identifiers may carry leading zeros; they do not change the value.
		da := strings.trim_left(a, "0")
		db := strings.trim_left(b, "0")
		if len(da) != len(db) {
			return len(da) < len(db) ? -1 : 1
		}
		return strings.compare(da, db)
	case na:
		return -1
	case nb:
		return 1
	}
	return strings.compare(a, b)
}
