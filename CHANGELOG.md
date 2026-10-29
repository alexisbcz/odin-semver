# Changelog

This file records all notable changes to this project.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-29

### Added

- `parse`, `parse_loose` and `is_valid` for strict Semantic Versioning 2.0.0 versions, with a `Parse_Error` for each rule.
- `to_string`, `write_version` and `version_clone`, plus `version_destroy` to free parsed versions.
- `compare`, `less` and `equal` with specification precedence, and `compare_with_build` and `sort` for a total order.
- `next_major`, `next_minor` and `next_patch` with npm increment rules.
- `parse_range` for primitive, caret, tilde, X-range, hyphen and `||` constraints, with commas accepted between comparators.
- `satisfies`, `satisfies_string`, `comparator_matches`, `max_satisfying`, `min_satisfying` and `max_satisfying_string`.
- `range_to_string` and `write_range` to print the desugared comparators.
- The `include_prerelease` option of `parse_range`.

[Unreleased]: https://github.com/alexisbcz/odin-semver/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/alexisbcz/odin-semver/releases/tag/v0.1.0
