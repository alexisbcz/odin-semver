package semver_tests

import semver ".."
import "core:mem"
import "core:testing"

// expect_desugar checks that `text` parses and desugars to `want`.
expect_desugar :: proc(t: ^testing.T, text, want: string, include_prerelease := false, loc := #caller_location) {
	r, err := semver.parse_range(text, include_prerelease)
	defer semver.range_destroy(&r)
	testing.expectf(t, err == nil, "parse_range(%q) failed: %v", text, err, loc = loc)
	got, ferr := semver.range_to_string(r)
	defer delete(got)
	testing.expect_value(t, ferr, nil, loc = loc)
	testing.expectf(t, got == want, "parse_range(%q): got %q, want %q", text, got, want, loc = loc)
}

// expect_range_error checks that parsing `text` fails with exactly `want`.
expect_range_error :: proc(t: ^testing.T, text: string, want: semver.Error, loc := #caller_location) {
	r, err := semver.parse_range(text)
	defer semver.range_destroy(&r)
	testing.expectf(t, err == want, "parse_range(%q): got %v, want %v", text, err, want, loc = loc)
}

// expect_match checks satisfies for one version against one range.
expect_match :: proc(t: ^testing.T, version, text: string, want: bool, include_prerelease := false, loc := #caller_location) {
	v, verr := semver.parse(version)
	defer semver.version_destroy(v)
	r, rerr := semver.parse_range(text, include_prerelease)
	defer semver.range_destroy(&r)
	testing.expect_value(t, verr, nil, loc = loc)
	testing.expect_value(t, rerr, nil, loc = loc)
	testing.expectf(t, semver.satisfies(v, r) == want, "satisfies(%s, %q) should be %v", version, text, want, loc = loc)
}

@(test)
test_range_exact_version :: proc(t: ^testing.T) {
	expect_desugar(t, "1.2.3", "1.2.3")
	expect_desugar(t, "=1.2.3", "1.2.3")
	expect_desugar(t, "v1.2.3", "1.2.3")
	expect_match(t, "1.2.3", "1.2.3", true)
	expect_match(t, "1.2.4", "=1.2.3", false)
}

@(test)
test_range_primitive_operators :: proc(t: ^testing.T) {
	expect_desugar(t, ">1.2.3", ">1.2.3")
	expect_desugar(t, ">=1.2.3", ">=1.2.3")
	expect_desugar(t, "<1.2.3", "<1.2.3")
	expect_desugar(t, "<=1.2.3", "<=1.2.3")
	expect_match(t, "1.2.3", ">=1.2.3", true)
	expect_match(t, "1.2.3", ">1.2.3", false)
	expect_match(t, "1.2.2", "<1.2.3", true)
	expect_match(t, "1.2.3", "<=1.2.3", true)
}

@(test)
test_range_operator_followed_by_space :: proc(t: ^testing.T) {
	expect_desugar(t, ">= 1.2.3 < 2", ">=1.2.3 <2.0.0-0")
	expect_desugar(t, "^ 1.2", ">=1.2.0 <2.0.0-0")
}

@(test)
test_range_commas_separate_comparators :: proc(t: ^testing.T) {
	expect_desugar(t, ">=1.2.0, <1.5.0", ">=1.2.0 <1.5.0")
	expect_desugar(t, ">=1.2.0,<1.5.0", ">=1.2.0 <1.5.0")
	expect_match(t, "1.4.9", ">=1.2.0, <1.5.0", true)
	expect_match(t, "1.5.0", ">=1.2.0, <1.5.0", false)
}

@(test)
test_range_caret :: proc(t: ^testing.T) {
	expect_desugar(t, "^1.2.3", ">=1.2.3 <2.0.0-0")
	expect_desugar(t, "^0.2.3", ">=0.2.3 <0.3.0-0")
	expect_desugar(t, "^0.0.3", ">=0.0.3 <0.0.4-0")
	expect_desugar(t, "^1.2.3-beta.2", ">=1.2.3-beta.2 <2.0.0-0")
	expect_desugar(t, "^0.0.0", ">=0.0.0 <0.0.1-0")
}

@(test)
test_range_caret_partial :: proc(t: ^testing.T) {
	expect_desugar(t, "^1.2.x", ">=1.2.0 <2.0.0-0")
	expect_desugar(t, "^1.x", ">=1.0.0 <2.0.0-0")
	expect_desugar(t, "^0.0.x", ">=0.0.0 <0.1.0-0")
	expect_desugar(t, "^0.0", ">=0.0.0 <0.1.0-0")
	expect_desugar(t, "^0.x", ">=0.0.0 <1.0.0-0")
	expect_desugar(t, "^*", ">=0.0.0")
}

@(test)
test_range_caret_matching :: proc(t: ^testing.T) {
	expect_match(t, "1.9.9", "^1.2.3", true)
	expect_match(t, "2.0.0", "^1.2.3", false)
	expect_match(t, "1.2.2", "^1.2.3", false)
	expect_match(t, "0.2.9", "^0.2.3", true)
	expect_match(t, "0.3.0", "^0.2.3", false)
	expect_match(t, "0.0.4", "^0.0.3", false)
}

@(test)
test_range_tilde :: proc(t: ^testing.T) {
	expect_desugar(t, "~1.2.3", ">=1.2.3 <1.3.0-0")
	expect_desugar(t, "~1.2", ">=1.2.0 <1.3.0-0")
	expect_desugar(t, "~1", ">=1.0.0 <2.0.0-0")
	expect_desugar(t, "~0.2.3", ">=0.2.3 <0.3.0-0")
	expect_desugar(t, "~1.2.3-beta.2", ">=1.2.3-beta.2 <1.3.0-0")
	expect_desugar(t, "~>1.2.3", ">=1.2.3 <1.3.0-0")
	expect_desugar(t, "~*", ">=0.0.0")
	expect_match(t, "1.2.9", "~1.2.3", true)
	expect_match(t, "1.3.0", "~1.2.3", false)
}

@(test)
test_range_x_ranges :: proc(t: ^testing.T) {
	expect_desugar(t, "*", ">=0.0.0")
	expect_desugar(t, "x", ">=0.0.0")
	expect_desugar(t, "X", ">=0.0.0")
	expect_desugar(t, "", ">=0.0.0")
	expect_desugar(t, "1.x", ">=1.0.0 <2.0.0-0")
	expect_desugar(t, "1.X.*", ">=1.0.0 <2.0.0-0")
	expect_desugar(t, "1", ">=1.0.0 <2.0.0-0")
	expect_desugar(t, "1.2.x", ">=1.2.0 <1.3.0-0")
	expect_desugar(t, "1.2", ">=1.2.0 <1.3.0-0")
	expect_desugar(t, "=1.2", ">=1.2.0 <1.3.0-0")
}

@(test)
test_range_x_ranges_with_operators :: proc(t: ^testing.T) {
	expect_desugar(t, ">1", ">=2.0.0")
	expect_desugar(t, ">1.2", ">=1.3.0")
	expect_desugar(t, ">=1.2", ">=1.2.0")
	expect_desugar(t, "<1.2", "<1.2.0-0")
	expect_desugar(t, "<=1.2", "<1.3.0-0")
	expect_desugar(t, "<=1", "<2.0.0-0")
	expect_desugar(t, ">=*", ">=0.0.0")
	expect_desugar(t, "<=*", ">=0.0.0")
}

@(test)
test_range_impossible_wildcards_match_nothing :: proc(t: ^testing.T) {
	expect_desugar(t, "<*", "<0.0.0-0")
	expect_desugar(t, ">x", "<0.0.0-0")
	expect_match(t, "0.0.0", "<*", false)
	expect_match(t, "99.0.0", ">*", false)
}

@(test)
test_range_hyphen :: proc(t: ^testing.T) {
	expect_desugar(t, "1.2.3 - 2.3.4", ">=1.2.3 <=2.3.4")
	expect_desugar(t, "1.2 - 2.3.4", ">=1.2.0 <=2.3.4")
	expect_desugar(t, "1.2.3 - 2.3", ">=1.2.3 <2.4.0-0")
	expect_desugar(t, "1.2.3 - 2", ">=1.2.3 <3.0.0-0")
	expect_desugar(t, "* - 2.0.0", "<=2.0.0")
	expect_desugar(t, "1.0.0 - *", ">=1.0.0")
	expect_desugar(t, "* - *", ">=0.0.0")
	expect_match(t, "2.3.4", "1.2.3 - 2.3.4", true)
	expect_match(t, "2.3.5", "1.2.3 - 2.3.4", false)
	expect_match(t, "2.3.9", "1.2.3 - 2.3", true)
}

@(test)
test_range_hyphen_inside_version_is_prerelease :: proc(t: ^testing.T) {
	expect_desugar(t, "1.2.3-2.0.0", "1.2.3-2.0.0")
}

@(test)
test_range_unions :: proc(t: ^testing.T) {
	expect_desugar(t, "^1.2 || ~2.0.1 || 3.x", ">=1.2.0 <2.0.0-0 || >=2.0.1 <2.1.0-0 || >=3.0.0 <4.0.0-0")
	expect_desugar(t, "1.2.3||2.0.0", "1.2.3 || 2.0.0")
	expect_match(t, "2.0.5", "^1.2 || ~2.0.1", true)
	expect_match(t, "2.1.0", "^1.2 || ~2.0.1", false)
	expect_match(t, "3.4.0", "<1 || >=3", true)
}

@(test)
test_range_empty_union_member_matches_anything :: proc(t: ^testing.T) {
	expect_desugar(t, "1.2.3 ||", "1.2.3 || >=0.0.0")
	expect_match(t, "9.9.9", "1.2.3 || ", true)
}

@(test)
test_range_build_metadata_is_ignored :: proc(t: ^testing.T) {
	expect_match(t, "1.2.3+build.9", "1.2.3", true)
	expect_match(t, "1.2.3", "=1.2.3+other", true)
}

@(test)
test_range_to_string_drops_build_metadata :: proc(t: ^testing.T) {
	// node-semver prints comparators without build metadata.
	expect_desugar(t, "^1.2.3+build", ">=1.2.3 <2.0.0-0")
	expect_desugar(t, "=1.2.3+other", "1.2.3")
	expect_desugar(t, "1.2.3-pre+asdf - 2.4.3-pre+asdf", ">=1.2.3-pre <=2.4.3-pre")
	expect_desugar(t, ">1.2.3+b <2.0.0+c.d || ~1.0.0-rc.1+e", ">1.2.3 <2.0.0 || >=1.0.0-rc.1 <1.1.0-0")
}

@(test)
test_range_prerelease_needs_same_tuple :: proc(t: ^testing.T) {
	expect_match(t, "1.2.3-alpha.7", ">1.2.3-alpha.3", true)
	expect_match(t, "1.2.3-alpha.2", ">1.2.3-alpha.3", false)
	expect_match(t, "3.4.5-alpha.9", ">1.2.3-alpha.3", false)
	expect_match(t, "1.3.0-beta", "^1.2.0", false)
	expect_match(t, "1.3.0-beta", ">=1.3.0-alpha <2", true)
	expect_match(t, "2.0.0-rc.1", "^1.2.0", false)
}

@(test)
test_range_include_prerelease :: proc(t: ^testing.T) {
	expect_match(t, "1.3.0-beta", "^1.2.0", true, include_prerelease = true)
	expect_match(t, "2.0.0-rc.1", "^1.2.0", false, include_prerelease = true)
	expect_match(t, "1.0.0-beta", "1.x", true, include_prerelease = true)
	expect_match(t, "1.0.0-beta", "1.x", false)
	expect_desugar(t, "*", ">=0.0.0-0", include_prerelease = true)
	expect_desugar(t, "1.x", ">=1.0.0-0 <2.0.0-0", include_prerelease = true)
	expect_desugar(t, ">1.2", ">=1.3.0-0", include_prerelease = true)
}

@(test)
test_range_rejects_bad_operators :: proc(t: ^testing.T) {
	expect_range_error(t, "=>1.2.3", .Invalid_Operator)
	expect_range_error(t, ">>1", .Invalid_Operator)
	expect_range_error(t, "^~1.2", .Invalid_Operator)
	expect_range_error(t, ">= <1", .Invalid_Operator)
}

@(test)
test_range_rejects_missing_version :: proc(t: ^testing.T) {
	expect_range_error(t, ">=", .Missing_Version)
	expect_range_error(t, "1.2.3 <", .Missing_Version)
	expect_range_error(t, "^v", .Missing_Version)
}

@(test)
test_range_rejects_bad_hyphen_ranges :: proc(t: ^testing.T) {
	expect_range_error(t, "1.2.3 -", .Invalid_Hyphen_Range)
	expect_range_error(t, "- 1.2.3", .Invalid_Hyphen_Range)
	expect_range_error(t, "1 - 2 - 3", .Invalid_Hyphen_Range)
	expect_range_error(t, ">1 - 2", .Invalid_Hyphen_Range)
	expect_range_error(t, "1 - ^2", .Invalid_Hyphen_Range)
}

@(test)
test_range_rejects_number_after_wildcard :: proc(t: ^testing.T) {
	expect_range_error(t, "1.x.3", .Invalid_Wildcard)
	expect_range_error(t, "*.2", .Invalid_Wildcard)
}

@(test)
test_range_rejects_qualifier_on_partial :: proc(t: ^testing.T) {
	expect_range_error(t, "1.2-beta", .Unexpected_Qualifier)
	expect_range_error(t, "^1+build", .Unexpected_Qualifier)
	expect_range_error(t, "1.x-rc.1", .Unexpected_Qualifier)
}

@(test)
test_range_reports_version_errors :: proc(t: ^testing.T) {
	expect_range_error(t, "01.2.3", .Leading_Zero)
	expect_range_error(t, "1.2.3.4", .Extra_Component)
	expect_range_error(t, "1..3", .Empty_Component)
	expect_range_error(t, "abc", .Invalid_Number)
	expect_range_error(t, "1.2.3-beta_1", .Invalid_Identifier)
	expect_range_error(t, "1.2.3-", .Empty_Identifier)
}

@(test)
test_range_reports_bound_overflow :: proc(t: ^testing.T) {
	expect_range_error(t, "^18446744073709551615.0.0", .Number_Overflow)
	expect_range_error(t, "~1.18446744073709551615", .Number_Overflow)
	expect_desugar(t, ">=18446744073709551615.0.0", ">=18446744073709551615.0.0")
}

@(test)
test_range_owns_its_source :: proc(t: ^testing.T) {
	text := make([]byte, 6)
	copy(text, "^1.2.3")
	r, err := semver.parse_range(string(text))
	defer semver.range_destroy(&r)
	testing.expect_value(t, err, nil)
	delete(text)
	expect_match(t, "1.5.0", "^1.2.3", true)
	testing.expect(t, semver.satisfies({major = 1, minor = 5}, r))
}

@(test)
test_range_destroy_zeroes_value :: proc(t: ^testing.T) {
	r, _ := semver.parse_range("1.x")
	semver.range_destroy(&r)
	testing.expect_value(t, len(r.sets), 0)
	testing.expect(t, !semver.satisfies({major = 1}, r))
}

@(test)
test_range_parse_does_not_leak :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	alloc := mem.tracking_allocator(&track)

	inputs := []string{"^1.2.3 || ~2 || 3.x - 4", "", "1 2 3 4 5 6 7 8 9 10 11 12 >=13", "* || * || * || * || * || *"}
	for input in inputs {
		r, err := semver.parse_range(input, false, alloc)
		testing.expectf(t, err == nil, "parse_range(%q) failed: %v", input, err)
		s, _ := semver.range_to_string(r, alloc)
		delete(s, alloc)
		semver.range_destroy(&r)
	}
	expect_no_leaks(t, &track)
}

@(test)
test_range_parse_errors_do_not_leak :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	alloc := mem.tracking_allocator(&track)

	inputs := []string{"^1.2.3 || 1.x.3", "1 2 3 4 5 6 7 8 9 =>10", ">=", "1 - 2 - 3"}
	for input in inputs {
		r, err := semver.parse_range(input, false, alloc)
		testing.expectf(t, err != nil, "parse_range(%q) should fail", input)
		testing.expect_value(t, len(r.sets), 0)
	}
	expect_no_leaks(t, &track)
}

@(test)
test_range_parse_survives_every_allocation_failure :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	text := "^1.2.3 || ~2.0 || 1 2 3 4 5 6 7 8 9 10 || >=4"
	succeeded := false
	for budget in 0 ..< 64 {
		limited := Limited_Allocator{backing = mem.tracking_allocator(&track), remaining = budget}
		r, err := semver.parse_range(text, false, limited_allocator(&limited))
		if err == nil {
			testing.expect(t, semver.satisfies({major = 1, minor = 9}, r))
			semver.range_destroy(&r)
			succeeded = true
			break
		}
		testing.expect_value(t, err, semver.Error(mem.Allocator_Error.Out_Of_Memory))
	}
	testing.expect(t, succeeded)
	expect_no_leaks(t, &track)
}

@(test)
test_comparator_matches :: proc(t: ^testing.T) {
	v := semver.Version{major = 1, minor = 2, patch = 3}
	bound := semver.Version{major = 1, minor = 2, patch = 3, build = "x"}
	testing.expect(t, semver.comparator_matches({.Equal, bound}, v))
	testing.expect(t, semver.comparator_matches({.Less_Equal, bound}, v))
	testing.expect(t, semver.comparator_matches({.Greater_Equal, bound}, v))
	testing.expect(t, !semver.comparator_matches({.Less, bound}, v))
	testing.expect(t, !semver.comparator_matches({.Greater, bound}, v))
}

@(test)
test_max_and_min_satisfying :: proc(t: ^testing.T) {
	versions := []semver.Version{
		{major = 1, minor = 2, patch = 0},
		{major = 1, minor = 4, patch = 1},
		{major = 1, minor = 5, prerelease = "beta"},
		{major = 2},
		{major = 1, minor = 3, patch = 7},
	}
	r, err := semver.parse_range("^1.2")
	defer semver.range_destroy(&r)
	testing.expect_value(t, err, nil)

	hi, hi_ok := semver.max_satisfying(versions, r)
	testing.expect(t, hi_ok)
	testing.expect_value(t, hi, 1)
	lo, lo_ok := semver.min_satisfying(versions, r)
	testing.expect(t, lo_ok)
	testing.expect_value(t, lo, 0)
}

@(test)
test_max_satisfying_none :: proc(t: ^testing.T) {
	versions := []semver.Version{{major = 1}, {major = 2}}
	r, _ := semver.parse_range(">=3")
	defer semver.range_destroy(&r)
	index, ok := semver.max_satisfying(versions, r)
	testing.expect(t, !ok)
	testing.expect_value(t, index, -1)
	index, ok = semver.min_satisfying(nil, r)
	testing.expect(t, !ok)
	testing.expect_value(t, index, -1)
}

@(test)
test_max_satisfying_first_wins_on_ties :: proc(t: ^testing.T) {
	versions := []semver.Version{{major = 1, build = "a"}, {major = 1, build = "b"}}
	r, _ := semver.parse_range("1")
	defer semver.range_destroy(&r)
	index, ok := semver.max_satisfying(versions, r)
	testing.expect(t, ok)
	testing.expect_value(t, index, 0)
}

@(test)
test_max_satisfying_string_skips_invalid_entries :: proc(t: ^testing.T) {
	listing := []string{"1.2.0", "not-a-version", "v1.4.1", "1.4.0", "2.0.0", "1.9.0-rc.1", "01.9.0"}
	index, err := semver.max_satisfying_string(listing, "~1.4 || 1.2.x")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, index, 2)

	index, err = semver.max_satisfying_string(listing, ">=3")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, index, -1)
}

@(test)
test_max_satisfying_string_reports_range_errors :: proc(t: ^testing.T) {
	index, err := semver.max_satisfying_string({"1.0.0"}, "1.x.2")
	testing.expect_value(t, err, semver.Error(semver.Range_Error.Invalid_Wildcard))
	testing.expect_value(t, index, -1)
}

@(test)
test_satisfies_string :: proc(t: ^testing.T) {
	ok, err := semver.satisfies_string("v1.4.2", "^1.2")
	testing.expect_value(t, err, nil)
	testing.expect(t, ok)

	ok, err = semver.satisfies_string("1.4", "^1.2")
	testing.expect_value(t, err, semver.Error(semver.Parse_Error.Missing_Component))
	testing.expect(t, !ok)

	ok, err = semver.satisfies_string("1.4.0", "^1.x.2")
	testing.expect_value(t, err, semver.Error(semver.Range_Error.Invalid_Wildcard))
}
