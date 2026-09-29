# Contributing

Open an issue before starting a substantial change. Keep pull requests focused
and include tests for behavior changes.

For Flutter UI, theme, and animation changes, follow the
[application design system](docs/design-system.md), including its shared
tokens, component boundaries, accessibility rules, and validation scope.

Before a pull request can be accepted, its author must read [CLA.md](CLA.md)
and check the CLA confirmation in the pull request template. Contributions
and official client binaries remain available under `AGPL-3.0-only`.

Run root `make check` for architecture boundaries, Flutter analysis and unit tests.
Direct Flutter commands run from `apps/flutter`. Keep dependencies directed as
described in the [repository architecture](docs/architecture/repository.md).

Local macOS staging targets (`macos-debug-staging`, `macos-profile-staging`,
and `macos-release-staging`) opt into the in-process test StoreKit catalog,
matching staging TestFlight. Purchases in this mode are simulated and do not
validate Apple networking, real payments, or server entitlement verification.
Pro is not automatically unlocked. To intentionally query the staging app's
App Store catalog, pass `MACOS_STAGING_STOREKIT_DEFINES=` to Make. Production
continues to use the remote App Store catalog. Build configuration changes
require rebuilding the app; pushing source does not update an existing binary.
