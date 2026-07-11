# Changelog

## 0.4.0 - 2026-07-11

### Added

- Parametric `Int16`, `Int32`, and `Int64` counters across ordinary, atomic,
  concurrent, and synchronized histograms.
- Java-compatible copy, corrected-copy, subtraction, range-query,
  inverse-percentile, non-zero-minimum, equality, and hashing operations.
- Idiomatic `push!`, `append!`, `copy`, and `copyto!` interfaces.
- Allocation-free iterator values, direct query kernels, reusable encoding
  workspaces, and benchmark coverage for the new operations.
- Aqua package-quality checks and Codecov uploads authenticated with GitHub
  OpenID Connect.

### Changed

- Raised the minimum supported Julia version from 1.9 to 1.10.
- Switched atomic storage to Julia's supported atomic-memory API on Julia 1.12
  and newer, while retaining Atomix compatibility on Julia 1.10 and 1.11.
- Improved auto-resizing concurrent recording and recorder hot paths.
- Preserved immutable histogram layout configuration when constructing copies.

### Fixed

- Corrected narrow-counter construction, overflow handling, and recorder
  compatibility.
- Added bounds validation for count access and malformed encoded histograms.
- Avoided synchronized-histogram lock-order deadlocks.
- Made Java interoperability tests reproducible and portable across CI
  platforms.
