package semver

import "base:runtime"
import "core:strings"

// Operator is the relation a Comparator checks between a candidate version and its bound.
Operator :: enum u8 {
	// The candidate has the same precedence as the bound.
	Equal,
	// The candidate ranks below the bound.
	Less,
	// The candidate ranks below or equal to the bound.
	Less_Equal,
	// The candidate ranks above the bound.
	Greater,
	// The candidate ranks above or equal to the bound.
	Greater_Equal,
}

/*
Comparator is one primitive constraint such as `>=1.2.0` or `<2.0.0-0`.

Caret, tilde, X-range and hyphen syntax all desugar into comparators, so a
Range only ever holds these. The version inside a Comparator that belongs to
a Range borrows its strings from that Range; don't pass it to version_destroy.
*/
Comparator :: struct {
	op:      Operator,
	version: Version,
}

/*
Range is a parsed range constraint: a union of comparator sets. A version
satisfies the range when it satisfies every comparator in at least one set.

Create one with parse_range and release it with range_destroy. A Range keeps
its own copy of the source text, so the string passed to parse_range may be
freed right after the call. A Range is never modified after parsing, so one
value may be shared between threads for reading.
*/
Range :: struct {
	// One entry per `||` member, each a slice into `comparators`.
	sets:               [][]Comparator,
	// Backing storage for every set, in source order.
	comparators:        []Comparator,
	// When true, prerelease versions may match any comparator set, not only
	// sets that name a prerelease of the same major.minor.patch.
	include_prerelease: bool,
	// The owned copy of the range text that comparator versions borrow from.
	source:             string,
	allocator:          runtime.Allocator,
}

/*
parse_range parses an npm or Cargo style range constraint.

Supported syntax, with what each form desugars to:
- `1.2.3`, `=1.2.3`: exactly that version.
- `>1.2.3`, `>=1.2.3`, `<1.2.3`, `<=1.2.3`: primitive comparators.
- `1.x`, `1.2.*`, `1`, `*`, `x`, empty: X-ranges, for example `1.x` is `>=1.0.0 <2.0.0-0`.
- `~1.2.3`, `~>1.2.3`: patch updates only, `>=1.2.3 <1.3.0-0`.
- `^1.2.3`: changes that keep the left-most nonzero component, `>=1.2.3 <2.0.0-0`;
  `^0.2.3` is `>=0.2.3 <0.3.0-0` and `^0.0.3` is `>=0.0.3 <0.0.4-0`.
- `1.2 - 2.3.4`: inclusive hyphen range, `>=1.2.0 <=2.3.4`.
- `A || B`: either set matches.

Comparators in one set are separated by spaces or commas, an operator may be
followed by spaces, and versions may start with `v`. Without
`include_prerelease`, a prerelease such as `1.3.0-beta` only matches a set that
also names a prerelease of `1.3.0`, as in npm.

Inputs:
- s: the range text.
- include_prerelease: let prerelease versions match every set, as npm's `includePrerelease` does.
- allocator: allocates the Range and its copy of `s`.

Returns:
- r: the range; free it with `range_destroy(&r)`.
- err: a Parse_Error or Range_Error for the first malformed part, or an
  allocator error. On failure nothing stays allocated.

Example:
	r, err := semver.parse_range(">=1.2.0, <1.5.0 || ^2")
	if err != nil {
		return
	}
	defer semver.range_destroy(&r)
*/
parse_range :: proc(s: string, include_prerelease := false, allocator := context.allocator) -> (r: Range, err: Error) {
	r.allocator = allocator
	r.include_prerelease = include_prerelease
	if err = build_range(&r, s); err != nil {
		range_destroy(&r)
		return {}, err
	}
	return r, nil
}

// range_destroy frees everything a Range owns. The range is zeroed.
range_destroy :: proc(r: ^Range) {
	delete(r.sets, r.allocator)
	delete(r.comparators, r.allocator)
	delete(r.source, r.allocator)
	r^ = {}
}

// comparator_matches reports whether `v` satisfies the single comparator `c`.
comparator_matches :: proc(c: Comparator, v: Version) -> bool {
	d := compare(v, c.version)
	switch c.op {
	case .Equal:
		return d == 0
	case .Less:
		return d < 0
	case .Less_Equal:
		return d <= 0
	case .Greater:
		return d > 0
	case .Greater_Equal:
		return d >= 0
	}
	return false
}

/*
satisfies reports whether `v` satisfies `r`: every comparator of at least one
set must match. Unless the range was parsed with `include_prerelease`, a
prerelease version only matches a set in which some comparator names a
prerelease with the same major, minor and patch numbers, so `^1.2.0` rejects
`1.3.0-beta` while `>=1.3.0-alpha <2` accepts it.
*/
satisfies :: proc(v: Version, r: Range) -> bool {
	for set in r.sets {
		if set_matches(set, v, r.include_prerelease) {
			return true
		}
	}
	return false
}

/*
satisfies_string parses `version` with parse_loose rules and `range_text`
with parse_range, then reports whether the version satisfies the range.

Inputs:
- version: the version text, for example `v1.4.2`.
- range_text: the range text, for example `^1.2`.
- allocator: used for scratch memory, all of which is freed before returning.

Returns:
- ok: whether the version satisfies the range.
- err: the first parse error in either input, or an allocator error.
*/
satisfies_string :: proc(version, range_text: string, allocator := context.allocator) -> (ok: bool, err: Error) {
	v, perr := parse_view(trim_loose(version))
	if perr != .None {
		return false, perr
	}
	r := parse_range(range_text, false, allocator) or_return
	defer range_destroy(&r)
	return satisfies(v, r), nil
}

/*
max_satisfying returns the index of the highest version in `versions` that
satisfies `r`. When several versions share that precedence, the first one wins.

Returns:
- index: the position in `versions`, or -1 when none matches.
- ok: false when no version matches.
*/
max_satisfying :: proc(versions: []Version, r: Range) -> (index: int, ok: bool) {
	index = -1
	for v, i in versions {
		if !satisfies(v, r) {
			continue
		}
		if index < 0 || compare(v, versions[index]) > 0 {
			index = i
		}
	}
	return index, index >= 0
}

/*
min_satisfying returns the index of the lowest version in `versions` that
satisfies `r`. When several versions share that precedence, the first one wins.

Returns:
- index: the position in `versions`, or -1 when none matches.
- ok: false when no version matches.
*/
min_satisfying :: proc(versions: []Version, r: Range) -> (index: int, ok: bool) {
	index = -1
	for v, i in versions {
		if !satisfies(v, r) {
			continue
		}
		if index < 0 || compare(v, versions[index]) < 0 {
			index = i
		}
	}
	return index, index >= 0
}

/*
max_satisfying_string picks the highest version string that satisfies
`range_text`, the way a package manager picks a release from a registry
listing. Entries that aren't valid versions, even under parse_loose rules,
are skipped rather than reported.

Inputs:
- versions: candidate version strings, for example `{"1.2.0", "v1.4.1", "2.0.0"}`.
- range_text: the range text.
- allocator: used for scratch memory, all of which is freed before returning.

Returns:
- index: the position of the best match in `versions`, or -1 when none matches.
- err: a parse error in `range_text`, or an allocator error.
*/
max_satisfying_string :: proc(versions: []string, range_text: string, allocator := context.allocator) -> (index: int, err: Error) {
	index = -1
	r := parse_range(range_text, false, allocator) or_return
	defer range_destroy(&r)
	best: Version
	for text, i in versions {
		v, perr := parse_view(trim_loose(text))
		if perr != .None || !satisfies(v, r) {
			continue
		}
		if index < 0 || compare(v, best) > 0 {
			index, best = i, v
		}
	}
	return index, nil
}

/*
write_range appends the desugared form of `r` to `b`, for example
`>=1.2.3 <2.0.0-0 || >=3.0.0`. An Equal comparator prints as the bare version.
Build metadata is left out because it never affects matching, so the output
matches node-semver.
*/
write_range :: proc(b: ^strings.Builder, r: Range) {
	for set, i in r.sets {
		if i > 0 {
			strings.write_string(b, " || ")
		}
		for c, j in set {
			if j > 0 {
				strings.write_byte(b, ' ')
			}
			write_comparator(b, c)
		}
	}
}

// write_comparator appends `c` to `b` without build metadata, for example `>=1.2.3`.
write_comparator :: proc(b: ^strings.Builder, c: Comparator) {
	switch c.op {
	case .Equal:
	case .Less:
		strings.write_byte(b, '<')
	case .Less_Equal:
		strings.write_string(b, "<=")
	case .Greater:
		strings.write_byte(b, '>')
	case .Greater_Equal:
		strings.write_string(b, ">=")
	}
	// Build metadata never affects matching, so print the bound without it,
	// as node-semver does.
	bound := c.version
	bound.build = ""
	write_version(b, bound)
}

/*
range_to_string formats the desugared form of `r`, which is handy for showing
users what a constraint means.

Returns:
- s: a new string owned by the caller; free it with `delete(s, allocator)`.
- err: an allocator error.
*/
range_to_string :: proc(r: Range, allocator := context.allocator) -> (s: string, err: Error) {
	b := strings.builder_make(allocator) or_return
	write_range(&b, r)
	return strings.to_string(b), nil
}

// The smallest prerelease identifier; `X-0` is the lowest version on the X tuple.
@(private)
LOWEST_PRERELEASE :: "0"

// build_range fills `r` from `s`. On failure `r` may hold partial allocations.
@(private)
build_range :: proc(r: ^Range, s: string) -> Error {
	allocator := r.allocator
	r.source = strings.clone(s, allocator) or_return

	p: Range_Parser
	p.include_prerelease = r.include_prerelease
	p.comparators = make([dynamic]Comparator, 0, 8, allocator) or_return
	defer delete(p.comparators)
	p.words = make([dynamic]string, 0, 8, allocator) or_return
	defer delete(p.words)
	ends := make([dynamic]int, 0, 4, allocator) or_return
	defer delete(ends)

	rest := r.source
	for {
		member := rest
		next := strings.index(rest, "||")
		if next >= 0 {
			member = rest[:next]
		}
		parse_set(&p, member) or_return
		_ = append(&ends, len(p.comparators)) or_return
		if next < 0 {
			break
		}
		rest = rest[next + 2:]
	}

	r.comparators = make([]Comparator, len(p.comparators), allocator) or_return
	copy(r.comparators, p.comparators[:])
	r.sets = make([][]Comparator, len(ends), allocator) or_return
	start := 0
	for end, i in ends {
		r.sets[i] = r.comparators[start:end]
		start = end
	}
	return nil
}

@(private)
Range_Parser :: struct {
	comparators:        [dynamic]Comparator,
	words:              [dynamic]string,
	include_prerelease: bool,
}

@(private)
Range_Op :: enum u8 {
	None,
	Equal,
	Less,
	Less_Equal,
	Greater,
	Greater_Equal,
	Tilde,
	Caret,
}

// Partial is a version that may stop early or use wildcards, such as `1.2` or `1.x`.
@(private)
Partial :: struct {
	parts:      [3]u64,
	// How many leading components are concrete numbers: 0 for `*`, 2 for `1.2.x`.
	count:      int,
	prerelease: string,
	build:      string,
}

@(private)
set_matches :: proc(set: []Comparator, v: Version, include_prerelease: bool) -> bool {
	for c in set {
		if !comparator_matches(c, v) {
			return false
		}
	}
	if v.prerelease == "" || include_prerelease {
		return true
	}
	for c in set {
		cv := c.version
		if cv.prerelease != "" && cv.major == v.major && cv.minor == v.minor && cv.patch == v.patch {
			return true
		}
	}
	return false
}

@(private)
trim_loose :: proc(s: string) -> string {
	text := strings.trim_space(s)
	text = strings.trim_prefix(text, "=")
	if len(text) > 0 && (text[0] == 'v' || text[0] == 'V') {
		text = text[1:]
	}
	return text
}

@(private)
is_separator :: proc(c: byte) -> bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == ','
}

@(private)
is_operator_byte :: proc(c: byte) -> bool {
	return c == '<' || c == '>' || c == '=' || c == '~' || c == '^'
}

// parse_set parses one `||` member and appends its desugared comparators.
@(private)
parse_set :: proc(p: ^Range_Parser, text: string) -> Error {
	clear(&p.words)
	i := 0
	for i < len(text) {
		for i < len(text) && is_separator(text[i]) {
			i += 1
		}
		start := i
		for i < len(text) && !is_separator(text[i]) {
			i += 1
		}
		if start < i {
			_ = append(&p.words, text[start:i]) or_return
		}
	}
	words := p.words[:]
	if len(words) == 0 {
		return emit(p, any_comparator(p))
	}

	for w, j in words {
		if w == "-" && (j != 1 || len(words) != 3) {
			return .Invalid_Hyphen_Range
		}
	}
	if len(words) == 3 && words[1] == "-" {
		if is_operator_byte(words[0][0]) || is_operator_byte(words[2][0]) {
			return .Invalid_Hyphen_Range
		}
		lo := parse_partial(words[0]) or_return
		hi := parse_partial(words[2]) or_return
		return desugar_hyphen(p, lo, hi)
	}

	j := 0
	for j < len(words) {
		op, rest := split_operator(words[j]) or_return
		j += 1
		if rest == "" {
			if j >= len(words) {
				return .Missing_Version
			}
			rest = words[j]
			j += 1
		}
		if is_operator_byte(rest[0]) {
			return .Invalid_Operator
		}
		partial := parse_partial(rest) or_return
		desugar(p, op, partial) or_return
	}
	return nil
}

// split_operator separates a leading operator from the rest of a word.
@(private)
split_operator :: proc(w: string) -> (op: Range_Op, rest: string, err: Error) {
	switch {
	case strings.has_prefix(w, ">="):
		op, rest = .Greater_Equal, w[2:]
	case strings.has_prefix(w, "<="):
		op, rest = .Less_Equal, w[2:]
	case strings.has_prefix(w, "~>"):
		op, rest = .Tilde, w[2:]
	case strings.has_prefix(w, ">"):
		op, rest = .Greater, w[1:]
	case strings.has_prefix(w, "<"):
		op, rest = .Less, w[1:]
	case strings.has_prefix(w, "="):
		op, rest = .Equal, w[1:]
	case strings.has_prefix(w, "~"):
		op, rest = .Tilde, w[1:]
	case strings.has_prefix(w, "^"):
		op, rest = .Caret, w[1:]
	case:
		op, rest = .None, w
	}
	if len(rest) > 0 && is_operator_byte(rest[0]) {
		return .None, "", .Invalid_Operator
	}
	return op, rest, nil
}

// parse_partial reads `1`, `1.2`, `1.2.3-pre+build`, `1.x`, `*` and friends.
@(private)
parse_partial :: proc(w: string) -> (p: Partial, err: Error) {
	s := w
	if len(s) > 0 && (s[0] == 'v' || s[0] == 'V') {
		s = s[1:]
	}
	if s == "" {
		return {}, .Missing_Version
	}
	if i := strings.index_byte(s, '+'); i >= 0 {
		p.build = s[i + 1:]
		s = s[:i]
		if e := validate_identifiers(p.build, false); e != .None {
			return {}, e
		}
	}
	if i := strings.index_byte(s, '-'); i >= 0 {
		p.prerelease = s[i + 1:]
		s = s[:i]
		if e := validate_identifiers(p.prerelease, true); e != .None {
			return {}, e
		}
	}

	wildcard := false
	k := 0
	for {
		part := s
		next := strings.index_byte(s, '.')
		if next >= 0 {
			part = s[:next]
		}
		if k == 3 {
			return {}, .Extra_Component
		}
		if part == "x" || part == "X" || part == "*" {
			wildcard = true
		} else {
			if wildcard {
				return {}, .Invalid_Wildcard
			}
			n, e := parse_number(part)
			if e != .None {
				return {}, e
			}
			p.parts[k] = n
			p.count = k + 1
		}
		k += 1
		if next < 0 {
			break
		}
		s = s[next + 1:]
	}
	if p.count < 3 && (p.prerelease != "" || p.build != "") {
		return {}, .Unexpected_Qualifier
	}
	return p, nil
}

@(private)
emit :: proc(p: ^Range_Parser, c: Comparator) -> Error {
	_ = append(&p.comparators, c) or_return
	return nil
}

// any_comparator matches every release, and every prerelease when include_prerelease is set.
@(private)
any_comparator :: proc(p: ^Range_Parser) -> Comparator {
	return {.Greater_Equal, floor_version(p, {})}
}

// none_comparator matches nothing: no version ranks below 0.0.0-0.
@(private)
none_comparator :: proc() -> Comparator {
	return {.Less, {prerelease = LOWEST_PRERELEASE}}
}

@(private)
exact_version :: proc(partial: Partial) -> Version {
	return {partial.parts[0], partial.parts[1], partial.parts[2], partial.prerelease, partial.build}
}

// floor_version is the lowest version a wildcard partial covers.
@(private)
floor_version :: proc(p: ^Range_Parser, partial: Partial) -> Version {
	v := Version{major = partial.parts[0], minor = partial.parts[1], patch = partial.parts[2]}
	if p.include_prerelease {
		v.prerelease = LOWEST_PRERELEASE
	}
	return v
}

// bump_at returns `<parts up to index+1>.0-0`, the first version past component `index`.
@(private)
bump_at :: proc(partial: Partial, index: int) -> (v: Version, err: Error) {
	parts := partial.parts
	if parts[index] == max(u64) {
		return {}, Parse_Error.Number_Overflow
	}
	parts[index] += 1
	for k in index + 1 ..< 3 {
		parts[k] = 0
	}
	return {parts[0], parts[1], parts[2], LOWEST_PRERELEASE, ""}, nil
}

// desugar turns one operator and partial into primitive comparators.
@(private)
desugar :: proc(p: ^Range_Parser, op: Range_Op, partial: Partial) -> Error {
	c := partial.count
	switch op {
	case .None, .Equal:
		if c == 3 {
			return emit(p, {.Equal, exact_version(partial)})
		}
		return desugar_wildcard(p, partial)

	case .Greater:
		switch c {
		case 3:
			return emit(p, {.Greater, exact_version(partial)})
		case 0:
			return emit(p, none_comparator())
		}
		upper := bump_at(partial, c - 1) or_return
		upper.prerelease = p.include_prerelease ? LOWEST_PRERELEASE : ""
		return emit(p, {.Greater_Equal, upper})

	case .Greater_Equal:
		switch c {
		case 3:
			return emit(p, {.Greater_Equal, exact_version(partial)})
		case 0:
			return emit(p, any_comparator(p))
		}
		return emit(p, {.Greater_Equal, floor_version(p, partial)})

	case .Less:
		switch c {
		case 3:
			return emit(p, {.Less, exact_version(partial)})
		case 0:
			return emit(p, none_comparator())
		}
		bound := floor_version(p, partial)
		bound.prerelease = LOWEST_PRERELEASE
		return emit(p, {.Less, bound})

	case .Less_Equal:
		switch c {
		case 3:
			return emit(p, {.Less_Equal, exact_version(partial)})
		case 0:
			return emit(p, any_comparator(p))
		}
		upper := bump_at(partial, c - 1) or_return
		return emit(p, {.Less, upper})

	case .Tilde:
		if c == 0 {
			return emit(p, any_comparator(p))
		}
		lower := c == 3 ? exact_version(partial) : floor_version(p, partial)
		upper := bump_at(partial, c == 1 ? 0 : 1) or_return
		emit(p, {.Greater_Equal, lower}) or_return
		return emit(p, {.Less, upper})

	case .Caret:
		if c == 0 {
			return emit(p, any_comparator(p))
		}
		lower := c == 3 ? exact_version(partial) : floor_version(p, partial)
		// Bump the left-most nonzero component, or the last concrete one.
		index := 0
		for index < c - 1 && partial.parts[index] == 0 {
			index += 1
		}
		upper := bump_at(partial, index) or_return
		emit(p, {.Greater_Equal, lower}) or_return
		return emit(p, {.Less, upper})
	}
	return nil
}

// desugar_wildcard handles a bare or `=` partial with fewer than three numbers.
@(private)
desugar_wildcard :: proc(p: ^Range_Parser, partial: Partial) -> Error {
	if partial.count == 0 {
		return emit(p, any_comparator(p))
	}
	upper := bump_at(partial, partial.count - 1) or_return
	emit(p, {.Greater_Equal, floor_version(p, partial)}) or_return
	return emit(p, {.Less, upper})
}

// desugar_hyphen handles `lo - hi`, inclusive at both ends.
@(private)
desugar_hyphen :: proc(p: ^Range_Parser, lo, hi: Partial) -> Error {
	before := len(p.comparators)
	switch lo.count {
	case 0:
	case 3:
		emit(p, {.Greater_Equal, exact_version(lo)}) or_return
	case:
		emit(p, {.Greater_Equal, floor_version(p, lo)}) or_return
	}
	switch hi.count {
	case 0:
	case 3:
		emit(p, {.Less_Equal, exact_version(hi)}) or_return
	case:
		upper := bump_at(hi, hi.count - 1) or_return
		emit(p, {.Less, upper}) or_return
	}
	if len(p.comparators) == before {
		return emit(p, any_comparator(p))
	}
	return nil
}
