# Swift Build stale module reproducer

An automatic Swift package library becomes dynamically linked when its consumer adds two dynamic libraries that both depend on it. An old `.swiftmodule` remains in the products directory and hides the new module inside the framework, so the consumer cannot see a newly added method.

This repository is a standalone Swift package. Its root `Package.swift` builds `Consumer` using the local `FooPackage`; no remote dependencies, app project, signing, or UI are needed.

```text
Phase 1                  Phase 2
Consumer → Foo           Consumer → Foo
                                  → A → Foo
                                  → B → Foo
```

Open this repository directory or its root `Package.swift` in Xcode to inspect the phase-2 package graph. Run the script below to exercise the graph transition with Xcode builds.

## Reproduce

Requires arm64 macOS, Xcode 27.1 at `/Applications/Xcode_27.1.app`, `zsh`, and `python3`.

```sh
./reproduce.zsh apple NO
```

The runner copies the package into `.artifacts/<unique>/work`. It overlays the three phase-1 files, builds, then restores the root phase-2 versions and rebuilds using the **same DerivedData and SourcePackages**. It retains commands, logs, module hashes, source snapshots, and build databases under that run's `.artifacts` directory.

Phase 2 adds `FooValue.newMethod()`, imports A/B, and adds their dynamic products to Consumer's dependencies. The automatic Foo product declaration never changes. The root package contains the phase-2 sources; `Fixtures/phase1` contains only the three earlier files.

Expected: both builds succeed and the consumer can use `newMethod()`.

Observed on the affected build services: phase 1 exits 0; phase 2 exits 65 with:

```text
error: value of type 'FooValue' has no member 'newMethod'
```

The old root module remains unchanged, while a new module exists in `PackageFrameworks/Foo.framework`. Import probes recorded by the runner fail with root `-I` plus framework `-F`, but succeed with framework `-F` alone. Compilation caching is disabled by `NO`; caching is not required for the failure.

## Compare build services

```sh
# Apple's bundled service, caching enabled.
./reproduce.zsh apple YES

# An installed baseline or fixed custom service.
CUSTOM_BUILD_SERVICE_PATH=/absolute/path/to/SWBBuildServiceBundle \
  ./reproduce.zsh custom NO
```

Each invocation uses a fresh artifact directory. Before each build the runner clears `XCBBUILDSERVICE_PATH`, `SWBBUILDSERVICE_PATH`, `SWBBUILDSERVICE_BUNDLE_PATH`, and `XCBBUILDSERVICE_BUNDLE_PATH`, then selects the exact service executable. Apple runs select Xcode's `SwiftBuild.framework/.../SWBBuildService` executable. No global settings or shared caches are removed.

Both builds use Debug, native arm64 macOS, `SWIFT_INSTALL_MODULE_FOR_DEPLOYMENT=YES`, common Swift/Clang prefix mappings, and the same shared CAS path. The caching argument sets `COMPILATION_CACHE_ENABLE_CACHING`. The runner returns phase 2's build status; import-probe results are separate.

## Environment and verification

The repository-root runner reproduced the Apple/no-CAS failure on macOS 26.6.2 (25G83), Xcode 27.1 (27A9275), Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), and the macOS 27.0 SDK: phase 1 exited 0, phase 2 exited 65 with the missing-method diagnostic, and import probes exited 1/0. The stale root module remained byte-identical across phases. The manifests require Swift tools 6.3 and macOS 26.0.

Apple-with-CAS and custom invocations of this runner have not been executed. No fixed-service result is claimed here.

Related: [issue #58](https://github.com/lynnswap/swift-build/issues/58) and [fix PR #59](https://github.com/lynnswap/swift-build/pull/59).
