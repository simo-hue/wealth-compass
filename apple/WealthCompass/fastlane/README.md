fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload App Store text metadata only (no binary, no submit)

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload an iOS build to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Build and upload iOS binary + metadata to App Store Connect (no auto-submit)

----


## Mac

### mac beta

```sh
[bundle exec] fastlane mac beta
```

Build and upload a macOS build to TestFlight

### mac release

```sh
[bundle exec] fastlane mac release
```

Build and upload macOS binary + metadata to App Store Connect (no auto-submit)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
