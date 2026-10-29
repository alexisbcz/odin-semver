// Example basic parses versions, sorts them and picks releases for ranges. Run it with `odin run examples/basic`.
package main

import semver "../.."
import "core:fmt"
import "core:os"

main :: proc() {
	// Parse and compare two versions. Build metadata never affects precedence.
	a, a_err := semver.parse("1.0.0-rc.1+build.5")
	if a_err != nil {
		fmt.eprintln("parse failed:", a_err)
		os.exit(1)
	}
	defer semver.version_destroy(a)
	b, _ := semver.parse("1.0.0")
	defer semver.version_destroy(b)
	fmt.println("1.0.0-rc.1 < 1.0.0:", semver.less(a, b))

	// Malformed input comes back as an error value, never a panic.
	_, bad := semver.parse("1.02.3")
	fmt.println("1.02.3:", bad)

	// Ranges desugar to primitive comparators.
	r, r_err := semver.parse_range("^1.2 || ~2.0.1")
	if r_err != nil {
		fmt.eprintln("range failed:", r_err)
		os.exit(1)
	}
	defer semver.range_destroy(&r)
	desugared, _ := semver.range_to_string(r)
	defer delete(desugared)
	fmt.println("^1.2 || ~2.0.1 means:", desugared)

	// Pick the newest release that satisfies the range.
	published := []semver.Version{
		{major = 1, minor = 2, patch = 0},
		{major = 1, minor = 9, patch = 4},
		{major = 2, minor = 0, patch = 3},
		{major = 2, minor = 1, patch = 0},
		{major = 3, minor = 0, patch = 0, prerelease = "beta.1"},
	}
	if i, ok := semver.max_satisfying(published, r); ok {
		fmt.printfln("best match: %d.%d.%d", published[i].major, published[i].minor, published[i].patch)
	}

	// Registry listings often arrive as strings; invalid entries are skipped.
	listing := []string{"0.9.0", "v1.4.1", "garbage", "1.5.0-rc.1", "1.4.7"}
	if i, err := semver.max_satisfying_string(listing, ">=1.4.0, <1.5.0"); err == nil && i >= 0 {
		fmt.println("from listing:", listing[i])
	}

	// Sorting uses precedence, then build metadata for a stable order.
	semver.sort(published)
	for v in published {
		s, _ := semver.to_string(v)
		defer delete(s)
		fmt.print(s, "")
	}
	fmt.println()
}
