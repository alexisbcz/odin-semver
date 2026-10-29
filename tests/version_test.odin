// Package semver_tests holds the unit tests for semver. Run them with `odin test tests`.
package semver_tests

import semver ".."
import "core:mem"
import "core:testing"

// expect_no_leaks fails the test when the tracking allocator still holds allocations.
expect_no_leaks :: proc(t: ^testing.T, track: ^mem.Tracking_Allocator, loc := #caller_location) {
	testing.expectf(t, len(track.allocation_map) == 0, "leaked %d allocation(s)", len(track.allocation_map), loc = loc)
	testing.expectf(t, len(track.bad_free_array) == 0, "%d bad free(s)", len(track.bad_free_array), loc = loc)
}

// Limited_Allocator serves `remaining` allocations from `backing`, then fails every later one.
Limited_Allocator :: struct {
	backing:   mem.Allocator,
	remaining: int,
}

limited_allocator_proc :: proc(
	data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	l := (^Limited_Allocator)(data)
	switch mode {
	case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
		if l.remaining <= 0 {
			return nil, .Out_Of_Memory
		}
		l.remaining -= 1
	case .Free, .Free_All, .Query_Features, .Query_Info:
	}
	return l.backing.procedure(l.backing.data, mode, size, alignment, old_memory, old_size, loc)
}

// limited_allocator wraps `l` as an Allocator.
limited_allocator :: proc(l: ^Limited_Allocator) -> mem.Allocator {
	return {procedure = limited_allocator_proc, data = l}
}

// failing_allocator fails every allocation without a backing allocator.
failing_allocator :: proc() -> mem.Allocator {
	fail :: proc(
		data: rawptr,
		mode: mem.Allocator_Mode,
		size, alignment: int,
		old_memory: rawptr,
		old_size: int,
		loc := #caller_location,
	) -> (
		[]byte,
		mem.Allocator_Error,
	) {
		#partial switch mode {
		case .Free, .Free_All:
			return nil, nil
		}
		return nil, .Out_Of_Memory
	}
	return {procedure = fail}
}

// expect_parse_error checks that parsing `s` fails with exactly `want`.
expect_parse_error :: proc(t: ^testing.T, s: string, want: semver.Parse_Error, loc := #caller_location) {
	v, err := semver.parse(s)
	defer semver.version_destroy(v)
	testing.expectf(t, err == semver.Error(want), "parse(%q): got %v, want %v", s, err, want, loc = loc)
	testing.expectf(t, !semver.is_valid(s), "is_valid(%q) should be false", s, loc = loc)
}

// expect_order checks that `a` ranks strictly below `b`, both ways round.
expect_order :: proc(t: ^testing.T, a, b: string, loc := #caller_location) {
	va, ea := semver.parse(a)
	defer semver.version_destroy(va)
	vb, eb := semver.parse(b)
	defer semver.version_destroy(vb)
	testing.expect_value(t, ea, nil, loc = loc)
	testing.expect_value(t, eb, nil, loc = loc)
	testing.expectf(t, semver.compare(va, vb) == -1, "%s should rank below %s", a, b, loc = loc)
	testing.expectf(t, semver.compare(vb, va) == 1, "%s should rank above %s", b, a, loc = loc)
}

@(test)
test_parse_core_version :: proc(t: ^testing.T) {
	v, err := semver.parse("1.2.3")
	defer semver.version_destroy(v)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, v, semver.Version{major = 1, minor = 2, patch = 3})
}

@(test)
test_parse_zero_version :: proc(t: ^testing.T) {
	v, err := semver.parse("0.0.0")
	defer semver.version_destroy(v)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, v, semver.Version{})
}

@(test)
test_parse_prerelease_and_build :: proc(t: ^testing.T) {
	v, err := semver.parse("1.0.0-alpha.1+exp.sha.5114f85")
	defer semver.version_destroy(v)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, v.major, 1)
	testing.expect_value(t, v.prerelease, "alpha.1")
	testing.expect_value(t, v.build, "exp.sha.5114f85")
}

@(test)
test_parse_build_without_prerelease :: proc(t: ^testing.T) {
	v, err := semver.parse("1.0.0+20130313144700")
	defer semver.version_destroy(v)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, v.prerelease, "")
	testing.expect_value(t, v.build, "20130313144700")
}

@(test)
test_parse_hyphens_inside_identifiers :: proc(t: ^testing.T) {
	v, err := semver.parse("1.0.0-x-y-z.--+b-1")
	defer semver.version_destroy(v)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, v.prerelease, "x-y-z.--")
	testing.expect_value(t, v.build, "b-1")
}

@(test)
test_parse_build_allows_leading_zeros :: proc(t: ^testing.T) {
	v, err := semver.parse("1.0.0+001.0002")
	defer semver.version_destroy(v)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, v.build, "001.0002")
}

@(test)
test_parse_max_u64_components :: proc(t: ^testing.T) {
	v, err := semver.parse("18446744073709551615.0.18446744073709551615")
	defer semver.version_destroy(v)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, v.major, max(u64))
	testing.expect_value(t, v.patch, max(u64))
}

@(test)
test_parse_rejects_overflow :: proc(t: ^testing.T) {
	expect_parse_error(t, "18446744073709551616.0.0", .Number_Overflow)
	expect_parse_error(t, "1.99999999999999999999.0", .Number_Overflow)
}

@(test)
test_parse_rejects_empty_input :: proc(t: ^testing.T) {
	expect_parse_error(t, "", .Empty_Input)
	expect_parse_error(t, "   ", .Empty_Input)
}

@(test)
test_parse_rejects_missing_components :: proc(t: ^testing.T) {
	expect_parse_error(t, "1", .Missing_Component)
	expect_parse_error(t, "1.2", .Missing_Component)
	expect_parse_error(t, "1.2-beta", .Missing_Component)
}

@(test)
test_parse_rejects_extra_components :: proc(t: ^testing.T) {
	expect_parse_error(t, "1.2.3.4", .Extra_Component)
}

@(test)
test_parse_rejects_empty_components :: proc(t: ^testing.T) {
	expect_parse_error(t, "1..3", .Empty_Component)
	expect_parse_error(t, "1.2.", .Empty_Component)
	expect_parse_error(t, ".1.2", .Empty_Component)
}

@(test)
test_parse_rejects_non_digits :: proc(t: ^testing.T) {
	expect_parse_error(t, "v1.2.3", .Invalid_Number)
	expect_parse_error(t, "1.2.x", .Invalid_Number)
	expect_parse_error(t, " 1.2.3", .Invalid_Number)
	expect_parse_error(t, "1.a.3", .Invalid_Number)
}

@(test)
test_parse_rejects_leading_zeros :: proc(t: ^testing.T) {
	expect_parse_error(t, "01.2.3", .Leading_Zero)
	expect_parse_error(t, "1.02.3", .Leading_Zero)
	expect_parse_error(t, "1.2.03", .Leading_Zero)
	expect_parse_error(t, "1.2.3-01", .Leading_Zero)
}

@(test)
test_parse_accepts_zero_prefixed_alphanumeric_prerelease :: proc(t: ^testing.T) {
	v, err := semver.parse("1.2.3-0a.00b.0")
	defer semver.version_destroy(v)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, v.prerelease, "0a.00b.0")
}

@(test)
test_parse_rejects_empty_identifiers :: proc(t: ^testing.T) {
	expect_parse_error(t, "1.2.3-", .Empty_Identifier)
	expect_parse_error(t, "1.2.3+", .Empty_Identifier)
	expect_parse_error(t, "1.2.3-a..b", .Empty_Identifier)
	expect_parse_error(t, "1.2.3-a.", .Empty_Identifier)
	expect_parse_error(t, "1.2.3+a..b", .Empty_Identifier)
}

@(test)
test_parse_rejects_invalid_identifier_characters :: proc(t: ^testing.T) {
	expect_parse_error(t, "1.2.3-beta_1", .Invalid_Identifier)
	expect_parse_error(t, "1.2.3+build+2", .Invalid_Identifier)
	expect_parse_error(t, "1.2.3-é", .Invalid_Identifier)
	expect_parse_error(t, "1.2.3 ", .Invalid_Number)
}

@(test)
test_parse_loose_accepts_prefixes_and_whitespace :: proc(t: ^testing.T) {
	inputs := []string{"v1.2.3", "V1.2.3", "=1.2.3", "=v1.2.3", "  1.2.3\n"}
	for input in inputs {
		v, err := semver.parse_loose(input)
		defer semver.version_destroy(v)
		testing.expectf(t, err == nil, "parse_loose(%q) failed: %v", input, err)
		testing.expect_value(t, v, semver.Version{major = 1, minor = 2, patch = 3})
	}
}

@(test)
test_parse_loose_stays_strict_after_prefix :: proc(t: ^testing.T) {
	v, err := semver.parse_loose("v1.2")
	defer semver.version_destroy(v)
	testing.expect_value(t, err, semver.Error(semver.Parse_Error.Missing_Component))
}

@(test)
test_is_valid :: proc(t: ^testing.T) {
	testing.expect(t, semver.is_valid("1.0.0-rc.1+build.1"))
	testing.expect(t, semver.is_valid("0.0.4"))
	testing.expect(t, !semver.is_valid("1.0"))
	testing.expect(t, !semver.is_valid("1.0.0-"))
}

@(test)
test_to_string_round_trips :: proc(t: ^testing.T) {
	inputs := []string{"0.0.0", "1.2.3", "10.20.30-rc.1", "1.0.0+build", "1.0.0-alpha.beta+exp.sha.1"}
	for input in inputs {
		v, err := semver.parse(input)
		defer semver.version_destroy(v)
		testing.expect_value(t, err, nil)
		s, serr := semver.to_string(v)
		defer delete(s)
		testing.expect_value(t, serr, nil)
		testing.expect_value(t, s, input)
	}
}

@(test)
test_parse_result_owns_its_strings :: proc(t: ^testing.T) {
	text := make([]byte, 16)
	copy(text, "1.2.3-beta+meta")
	v, err := semver.parse(string(text[:15]))
	defer semver.version_destroy(v)
	testing.expect_value(t, err, nil)
	for &c in text {
		c = 'X'
	}
	delete(text)
	testing.expect_value(t, v.prerelease, "beta")
	testing.expect_value(t, v.build, "meta")
}

@(test)
test_version_clone_and_destroy_do_not_leak :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	alloc := mem.tracking_allocator(&track)

	v, err := semver.parse("1.2.3-rc.1+b.7", alloc)
	testing.expect_value(t, err, nil)
	c, cerr := semver.version_clone(v, alloc)
	testing.expect_value(t, cerr, nil)
	testing.expect(t, raw_data(c.prerelease) != raw_data(v.prerelease))
	testing.expect_value(t, semver.compare_with_build(v, c), 0)
	semver.version_destroy(v, alloc)
	semver.version_destroy(c, alloc)

	_, perr := semver.parse("1.2.3-01", alloc)
	testing.expect_value(t, perr, semver.Error(semver.Parse_Error.Leading_Zero))
	expect_no_leaks(t, &track)
}

@(test)
test_parse_without_qualifiers_allocates_nothing :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	v, err := semver.parse("4.5.6", mem.tracking_allocator(&track))
	testing.expect_value(t, err, nil)
	testing.expect_value(t, v.major, 4)
	testing.expect_value(t, track.total_allocation_count, 0)
}

@(test)
test_parse_reports_allocator_errors :: proc(t: ^testing.T) {
	v, err := semver.parse("1.2.3-beta", failing_allocator())
	testing.expect_value(t, err, semver.Error(mem.Allocator_Error.Out_Of_Memory))
	testing.expect_value(t, v, semver.Version{})
}

@(test)
test_version_clone_frees_prerelease_when_build_fails :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	// The prerelease copy succeeds, the build copy fails.
	limited := Limited_Allocator{backing = mem.tracking_allocator(&track), remaining = 1}

	src := semver.Version{major = 1, prerelease = "rc", build = "0123456789abcdef"}
	c, err := semver.version_clone(src, limited_allocator(&limited))
	testing.expect_value(t, err, semver.Error(mem.Allocator_Error.Out_Of_Memory))
	testing.expect_value(t, c, semver.Version{})
	expect_no_leaks(t, &track)
}

@(test)
test_spec_precedence_chain :: proc(t: ^testing.T) {
	// The example chain from section 11.4 of Semantic Versioning 2.0.0.
	chain := []string{
		"1.0.0-alpha",
		"1.0.0-alpha.1",
		"1.0.0-alpha.beta",
		"1.0.0-beta",
		"1.0.0-beta.2",
		"1.0.0-beta.11",
		"1.0.0-rc.1",
		"1.0.0",
		"2.0.0",
		"2.1.0",
		"2.1.1",
	}
	for i in 0 ..< len(chain) - 1 {
		expect_order(t, chain[i], chain[i + 1])
	}
}

@(test)
test_compare_numeric_components :: proc(t: ^testing.T) {
	expect_order(t, "1.9.0", "1.10.0")
	expect_order(t, "1.0.9", "1.0.10")
	expect_order(t, "9.99.99", "10.0.0")
}

@(test)
test_compare_numeric_prerelease_ranks_below_alphanumeric :: proc(t: ^testing.T) {
	expect_order(t, "1.0.0-999", "1.0.0-a")
	expect_order(t, "1.0.0-2", "1.0.0-10")
	expect_order(t, "1.0.0-Z", "1.0.0-a")
	expect_order(t, "1.0.0-99999999999999999999998", "1.0.0-99999999999999999999999")
}

@(test)
test_compare_ignores_build_metadata :: proc(t: ^testing.T) {
	a, _ := semver.parse("1.0.0+a")
	defer semver.version_destroy(a)
	b, _ := semver.parse("1.0.0+b")
	defer semver.version_destroy(b)
	testing.expect_value(t, semver.compare(a, b), 0)
	testing.expect(t, semver.equal(a, b))
	testing.expect(t, !semver.less(a, b))
}

@(test)
test_compare_with_build_breaks_ties :: proc(t: ^testing.T) {
	plain := semver.Version{major = 1}
	b2 := semver.Version{major = 1, build = "2"}
	b10 := semver.Version{major = 1, build = "010"}
	ba := semver.Version{major = 1, build = "a"}
	testing.expect_value(t, semver.compare_with_build(plain, b2), -1)
	testing.expect_value(t, semver.compare_with_build(b2, b10), -1)
	testing.expect_value(t, semver.compare_with_build(b10, ba), -1)
	testing.expect_value(t, semver.compare_with_build(ba, ba), 0)
	testing.expect_value(t, semver.compare_with_build(ba, plain), 1)
}

@(test)
test_sort_orders_by_precedence_then_build :: proc(t: ^testing.T) {
	versions := []semver.Version{
		{major = 2},
		{major = 1, build = "z"},
		{major = 1, prerelease = "rc.1"},
		{major = 0, minor = 9},
		{major = 1},
		{major = 1, prerelease = "beta"},
	}
	semver.sort(versions)
	want := []semver.Version{
		{major = 0, minor = 9},
		{major = 1, prerelease = "beta"},
		{major = 1, prerelease = "rc.1"},
		{major = 1},
		{major = 1, build = "z"},
		{major = 2},
	}
	for v, i in versions {
		testing.expectf(t, v == want[i], "index %d: got %v, want %v", i, v, want[i])
	}
}

@(test)
test_next_patch :: proc(t: ^testing.T) {
	next, err := semver.next_patch({major = 1, minor = 2, patch = 3, build = "b"})
	testing.expect_value(t, err, nil)
	testing.expect_value(t, next, semver.Version{major = 1, minor = 2, patch = 4})

	next, err = semver.next_patch({major = 1, minor = 2, patch = 3, prerelease = "rc.1"})
	testing.expect_value(t, err, nil)
	testing.expect_value(t, next, semver.Version{major = 1, minor = 2, patch = 3})
}

@(test)
test_next_minor :: proc(t: ^testing.T) {
	next, err := semver.next_minor({major = 1, minor = 2, patch = 3})
	testing.expect_value(t, err, nil)
	testing.expect_value(t, next, semver.Version{major = 1, minor = 3})

	next, err = semver.next_minor({major = 1, minor = 3, prerelease = "beta"})
	testing.expect_value(t, next, semver.Version{major = 1, minor = 3})

	next, err = semver.next_minor({major = 1, minor = 3, patch = 1, prerelease = "beta"})
	testing.expect_value(t, next, semver.Version{major = 1, minor = 4})
}

@(test)
test_next_major :: proc(t: ^testing.T) {
	next, err := semver.next_major({major = 1, minor = 2, patch = 3, prerelease = "x"})
	testing.expect_value(t, err, nil)
	testing.expect_value(t, next, semver.Version{major = 2})

	next, err = semver.next_major({major = 2, prerelease = "rc.1"})
	testing.expect_value(t, next, semver.Version{major = 2})
}

@(test)
test_next_reports_overflow :: proc(t: ^testing.T) {
	_, err := semver.next_major({major = max(u64)})
	testing.expect_value(t, err, semver.Error(semver.Parse_Error.Number_Overflow))
	_, err = semver.next_minor({minor = max(u64)})
	testing.expect_value(t, err, semver.Error(semver.Parse_Error.Number_Overflow))
	_, err = semver.next_patch({patch = max(u64)})
	testing.expect_value(t, err, semver.Error(semver.Parse_Error.Number_Overflow))
}
