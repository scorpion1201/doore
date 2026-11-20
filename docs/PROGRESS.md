# Woosh Mobile implementation progress

**2026-11-18** · Working tree on `codex/initialize-universal-app`, including uncommitted changes.

The Apple app and its windows use the name **Woosh Mobile** in Korean, English and Simplified Chinese. The Xcode project and scheme use the internal codename `Doore` (두레).

The macOS and iOS Simulator Debug builds pass. Basic operation, site setup and the Design workspace are partially implemented. Physical robot acceptance and release verification remain open. [Spec 00 completion criteria](plans/00-initialize-app.spec.md#12-milestones)

## Milestone status

| Milestone | Current implementation | Remaining work |
|---|---|---|
| M0 · Robot API verification | The client uses the public WebSocket API. | Verify port 5480 and authentication on target firmware. Record support for each required request and notification. |
| M1 · WooshKit | The package includes 25 restored schemas, generated Swift types, the WebSocket transport, initial sync, reconnect, the teleoperation command loop and a fake robot. Package tests pass. | Confirm connect, sync and reconnect on a physical robot. |
| M2 · Basic operation | Connection history, live status, Monitor, station tasks, pause/resume/cancel, wait release, charge and park, position initialization and longitudinal teleoperation are implemented. Task authoring uses action-group numbers referenced by presets in the active Scene. | Manual charging, lateral and omnidirectional driving, and full action-group selection remain open. Compare requests and displayed states with Woosh Mobile and verify stopping on hardware. |
| M3 · Site setup | Map building and saving requests, Scene and map management, ordinary Station registration, TaskSets, WiFi and selected device controls are implemented. The live mapping screen shows received frame dimensions and byte count. | Render live map pixels, create an empty Scene, implement precise Station deployment and complete model-specific device controls. Verify setup through task execution at a new site. |
| M4 · Design workspace | Monitor, Deploy and Statistics exist. Local Scene and TaskSet editing, undo/redo, save, backup and paged task history work. Action groups are displayed read-only. | Complete action-group editing, Scene upload, dispatch and multi-robot monitoring, and date-range filtering. Verify an edited Scene round trip with Woosh Design. |
| M5 · Release | Korean is the default. The main string catalog contains 416 entries, of which 15 lack an English or Simplified Chinese value. | Complete copy review and obtain supplier approval for the Woosh name and status-code table. Korean recovery text for the 932 codes, field testing of the guide, production signing and distribution remain open. |

## Latest Monitor changes

- Charging uses the selected eligible charger or lets the robot choose. Parking uses a selected eligible Station or the only eligible one on the current map. The confirmation checks the connection, Scene and map again before sending `ExecTask`. A rejected request shows the robot’s message and can be retried. [Charge and park flow](plans/00-initialize-app.spec.md#72-requests-per-feature)
- The **건너뛰기** control sends `ActionOrder.kWaitBreak` when the robot reports a wait. The manual charging button uses the original text from the supplied UI string table. Its command still needs a trace from the original app. [Monitor confirmations](../Doore/Features/Monitor/StationShortcutDialog.swift)

## Last verified results

The 2026-11-18 run used Xcode 27.2 (27B52) on macOS 27.2.1 arm64. Robot communication tests used `FakeRobotTransport`.

| Check | Destination | Result |
|---|---|---|
| Debug builds | macOS and generic iOS Simulator | Both passed |
| WooshKit package tests | macOS | 58 passed |
| Hosted app tests | macOS | 25 passed |
| Hosted app tests | iPhone 16 Pro, iOS 18.5 simulator | 26 passed |
| Hosted app tests | iPad Pro 11-inch (M4), iPadOS 18.5 simulator | 26 passed |
| Monitor interaction tests in a temporary UI harness | iPhone 16 Pro, iOS 18.5 simulator | 4 passed |

The four interaction tests covered charge and park confirmations, mode recovery, retry after a parking rejection and release of a waiting task. On-site acceptance still requires checking teleoperation stops on release, backgrounding, controller removal and link loss, then running the connect → initialize → send task → pause/resume → return to charge scenario. [Verification criteria](plans/00-initialize-app.spec.md#11-verification) · [Outstanding protocol and supplier questions](plans/00-initialize-app.spec.md#13-open-questions-and-missing-inputs)
