# Doore implementation handoff

The next task is to build and run the app on a Mac with Xcode 16 or later. Start from `codex/initialize-universal-app`. Commit `a5c0052` contains the implementation for iOS 17, iPadOS 17 and macOS 14. The shared scheme is `Doore`.

## Where the previous session stopped

| Area | Status at the implementation commit |
|---|---|
| Protocol and connection | WooshKit includes 25 restored schemas and their generated Swift bindings, the public WebSocket client, ordered initial sync, notification handling, reconnect and a fake robot. SwiftPM resolves SwiftProtobuf 1.29.0. |
| Operation and setup | The app displays reported state, maps and stations. It supports teleoperation, position initialization, task control, selected settings and WiFi operations, map management and ordinary station registration. Task submission can reuse action-group numbers referenced by presets in the same active scene. |
| Design | Local scene and task-set editing, undo/redo, save, backup and paged task history are implemented. iPhone Monitor and Deploy use view-only layouts. |
| Verification | On Linux, all 51 WooshKit tests and 12 portable app-logic tests passed. The latter ran in a temporary harness. Swift sources also passed syntax parsing for the Apple targets. The native builds, hosted Xcode tests and physical robot checks are still open. |

The [implementation status](../README.md#implementation-status) summarizes feature coverage. Use [AGENTS.md](../AGENTS.md) for repository conventions, the [specification](plans/00-initialize-app.spec.md) for behavior, [DESIGN.md](DESIGN.md) for the UI and [ARCHITECTURE.md](ARCHITECTURE.md) for code boundaries.

## First task on the Mac

From the repository root, check the active toolchain and run these commands. SwiftPM may need network access for its first dependency fetch.

```sh
xcodebuild -version
swift test --package-path Packages/WooshKit
xcodebuild -project Doore.xcodeproj -scheme Doore -destination 'platform=macOS' build
xcodebuild -project Doore.xcodeproj -scheme Doore -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Doore.xcodeproj -scheme Doore -destination 'platform=macOS' test
```

Then run the hosted tests once on an iPhone simulator and once on an iPad simulator. Use `xcrun simctl list devices available` to find the installed device IDs. Substitute each ID for `<UDID>` below.

```sh
xcodebuild -project Doore.xcodeproj -scheme Doore -destination 'platform=iOS Simulator,id=<UDID>' test
```

Fix reproducible compiler, resource-bundling or test failures and rerun the affected commands. The Apple-only [screen rendering tests](../DooreTests/ScreenRenderingTests.swift) exercise offline and fake-connected views at four sizes. The [presentation tests](../DooreTests/WorkspacePresentationTests.swift) exercise shortcuts, dialog motion gating and the bundled languages. Also launch the app to inspect iPhone rotation and large text, iPad Split View, and Mac window resizing and keyboard focus. A rendered image alone cannot establish that the controls fit or accept input.

The first task is complete when both native builds pass and the Mac, iPhone simulator and iPad simulator test results are recorded, with the Xcode version and destinations used. Record any remaining failures with their command and diagnostic. These checks can proceed with the fake transport and simulators.

## Evidence needed for the remaining features

| Open item | Evidence or decision needed |
|---|---|
| Robot acceptance and motion | For the target firmware, confirm port 5480, authentication, supported requests and topics. With a site operator, verify teleop release, app backgrounding, controller removal and link loss. The fake tests check commands sent by the client. |
| Charge, park, skip and device-specific actions | Capture the original app's request names, fields and mode restrictions for each shortcut on the relevant robot. Use those findings to enable the matching control. |
| Mapping and task authoring | Obtain a live map-building frame with known dimensions and encoding, a precise-deployment trace and a scene with a representative action-group JSON document. The current client shows frame metadata and uses the scene's known preset references. Empty-scene creation also needs a confirmed request. |
| Design and dispatch | Obtain an example download/edit/upload round trip, dispatch connection and navigation traces, and the time unit used for history filtering. Local edits and backups can already be exercised offline. |
| Localization and release | The catalog has 412 keys. Fifteen fall back to Korean in at least one language. Resolve those from original wording. The bundle ID is temporarily `org.example.Doore`; the owner still needs to choose a production ID, signing team and distribution route, and confirm rights to the vendor status-code table. |

Track real-robot acceptance against [specification §§ 11–13](plans/00-initialize-app.spec.md#11-verification). The earlier analysis report and reference screenshots were supplied as `woosh-analysis.md` and `woosh-analysis.zip`. A fresh clone already contains the schemas, generated bindings and app string catalog needed to build. Refer back to the original attachments for source wording or screenshot comparisons.
