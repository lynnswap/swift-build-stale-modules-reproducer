# Reproducing stale Swift modules in Swift Build

This Swift package reproduces a Swift Build bug where a dependency change leaves an old `.swiftmodule` behind. The compiler loads that module and cannot see a newly added library method. The issue also reproduces with Xcode 27.1's bundled build service and compilation caching disabled.

After adding `FooValue.newMethod()` to the source and rebuilding, compilation fails with:

```text
error: value of type 'FooValue' has no member 'newMethod'
```

See [issue #58](https://github.com/lynnswap/swift-build/issues/58) for the investigation and [PR #59](https://github.com/lynnswap/swift-build/pull/59) for the fix.

## Reproduction scenario

First, build `Consumer` with only `Foo` as a dependency. Then add `A` and `B`, two dynamic libraries that both depend on `Foo`, to `Consumer`'s dependencies.

```text
First build              Second build
Consumer → Foo           Consumer → Foo
                                  → A → Foo
                                  → B → Foo
```

For the second build, also add `FooValue.newMethod()` to `Foo` and call it from `Consumer`. Rebuild using the same DerivedData directory, which holds the build outputs. The build fails because the new method cannot be found. Both builds should succeed.

## Run the reproducer

Requires an arm64 Mac, Xcode 27.1 at `/Applications/Xcode_27.1.app`, `zsh`, and `python3`. The packages require Swift tools 6.3 and macOS 26.0 or later.

Run from the repository root. The `apple` argument selects Apple's bundled build service; `NO` disables compilation caching.

```sh
./reproduce.zsh apple NO
```

The script creates a working copy in `.artifacts/<run>/work` and performs both builds. When the bug reproduces, the output includes:

```text
phase=1 exit=0 log=.../logs/phase1.log
phase=2 exit=65 log=.../logs/phase2.log
```

The script also exits with code `65`. Check the reported `phase2.log` for the error shown above. The same output directory's `logs/` folder also contains the commands, source snapshots from each build, and hashes of the build outputs.

The repository's root `Package.swift` and sources contain the second build's configuration. `Fixtures/phase1` contains the files for the first build, and the script switches between the two states. You can open the root package in Xcode to inspect its structure; reproducing the bug requires the consecutive builds.

## Why the old module is loaded

The library declaration in `Foo`'s `Package.swift` stays `.library(name: "Foo", targets: ["Foo"])` for both builds, with no explicit linkage type. Adding `A` and `B` causes Swift Build to build `Foo` as a dynamic library automatically and changes where its module is generated.

| Build | Location of `Foo`'s module within DerivedData |
| --- | --- |
| First | `Build/Products/Debug/Foo.swiftmodule` |
| Second | `Build/Products/Debug/PackageFrameworks/Foo.framework/Modules/Foo.swiftmodule` |

The affected build service leaves the first build's old module in place. The compiler loads it before the new module inside the framework, so it cannot see the added method.

## Compare with the fix

Run the same reproduction with a fixed build service. Set `CUSTOM_BUILD_SERVICE_PATH` to the `SWBBuildService` executable.

```sh
CUSTOM_BUILD_SERVICE_PATH=/absolute/path/to/SWBBuildService \
  ./reproduce.zsh custom NO
```

The fixed service removes the old module, allowing the second build to succeed. Each script invocation uses a separate output directory, with its two builds sharing the same DerivedData directory.

Verified with Xcode 27.1 (27A9275) and compilation caching disabled:

| Environment | Build service | First build | Second build |
| --- | --- | --- | --- |
| macOS 26.6.2 (25G83) | Apple's bundled service | Succeeds | Fails: missing `newMethod` |
| M1 Pro / macOS 27.2 | Apple's bundled service | Succeeds | Fails: missing `newMethod` |
| M1 Pro / macOS 27.2 | Fixed service ([`18a31d57`](https://github.com/lynnswap/swift-build/commit/18a31d578bbe4eb650cd2f22c441a77d4f647cc5)) | Succeeds | Succeeds |

To enable compilation caching, set the second argument to `YES`. Apple's bundled service with `YES` has not been tested with this repository's script.
