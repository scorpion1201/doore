# Architecture Overview

This document gives agents and contributors a fast, complete picture of how the 두레 codebase is put together: where things live, which part talks to which, and where the boundaries are. Its sections follow the [architecture.md](https://architecture.md/) template.

**Nothing is built yet.** Until the first implementation task lands, this describes the structure the code must take. Update this document as the codebase evolves.

What the app must do, and every detail of the robot protocol, is in the [specification](plans/00-initialize-app.spec.md). What the user sees is in [DESIGN.md](DESIGN.md).

## 1. Project Structure

The tree is grouped by layer. Only `README.md`, `LICENSE`, `CONTRIBUTING.md`, `AGENTS.md`, `CLAUDE.md`, `assets/` and `docs/` exist today.

```
README.md                    what 두레 is, for people
LICENSE                      MIT
CONTRIBUTING.md              what a pull request must satisfy
AGENTS.md                    instructions for coding agents
CLAUDE.md                    symlink to AGENTS.md
assets/                      README pictures (design mockups) and the app icon artwork,
                             app-icon-*.png (DESIGN.md § 4.4)
docs/
  ARCHITECTURE.md            this file
  DESIGN.md                  screens, tokens, UI wording
  plans/                     one specification per task: [no]-[task-name].spec.md
    00-initialize-app.spec.md
                             goal, non-goals, protocol, flows, milestones
Doore.xcodeproj              one multiplatform app target: iOS, iPadOS, macOS
Doore/                       the app
  App/                       entry point, window scenes, Mac menu commands and shortcuts
  Features/                  views, one folder per screen area:
                             Home, StatusBar, Connect, Monitor, Map, Task,
                             Settings, Device, Design
  Stores/                    RobotStore, SceneStore, TaskStore, SettingsStore
  MapCanvas/                 the shared map view: image, stations, fields, paths, robot
  DesignSystem/              color and size tokens, shared controls
  Resources/                 asset catalog, string catalog
DooreTests/                  app-level tests
Packages/
  WooshKit/                  the robot client, a Swift package with no UI imports
    Protos/                  restored .proto files (not yet in the repository)
    Sources/WooshKit/        generated messages, transport, session, models
    Sources/WooshKitTesting/ FakeRobotTransport and canned robot data
    Tests/WooshKitTests/
```

| Path | Holds | Notes |
|---|---|---|
| `Doore/Features/<Area>/` | Views and view-only helpers for one screen area | Observes stores. Nothing else |
| `Doore/Stores/` | The four stores | Depend on WooshKit. The only objects views observe |
| `Doore/MapCanvas/` | The shared map view | Used by Monitor, Map, Task, Settings and the Design workspace |
| `Doore/DesignSystem/` | Tokens and shared controls from DESIGN.md | The only place that defines a color or a size |
| `Doore/Resources/` | Asset catalog and one string catalog | Korean source, with `zh-Hans` and `en` values |
| `Packages/WooshKit/Sources/WooshKit/` | Generated message types, `RobotTransport`, `WebSocketTransport`, `RobotSession`, screen-facing models | Imports no SwiftUI, UIKit or AppKit. Generated Swift is checked in, so a build needs no `protoc` |
| `Packages/WooshKit/Sources/WooshKitTesting/` | `FakeRobotTransport` and canned robot data | Used by unit tests, SwiftUI previews and running without a robot |
| `Packages/WooshKit/Protos/` | The 25 restored `.proto` files | Not yet in the repository: [spec § 13.2](plans/00-initialize-app.spec.md#132-inputs-that-are-not-in-this-repository-yet) |

`WooshKit` is a working name. It names the protocol, not the product.

## 2. High-Level System Diagram

```
 ┌─────────────────────────── Doore app ───────────────────────────┐
 │ Views (SwiftUI)     Home, StatusBar, Connect, Monitor, Map,     │
 │        │            Task, Settings, Device, Design              │
 │        ▼                                                        │
 │ Stores              RobotStore · SceneStore · TaskStore ·       │
 │        │            SettingsStore                               │
 └────────┼────────────────────────────────────────────────────────┘
          ▼
 ┌─────────────────────────── WooshKit ────────────────────────────┐
 │ RobotSession (actor)  connection lifetime, initial sync,        │
 │        │              subscriptions, request/reply matching,    │
 │        │              reconnect, teleop command loop            │
 │        ▼                                                        │
 │ RobotTransport        WebSocket JSON │ ZeroMQ      │ Fake robot │
 │                       (default)      │ (optional)  │ (tests)    │
 └──────────────────────────┼───────────────┼──────────────────────┘
                            ▼               ▼
                 ┌────────────────────────────────────────┐
                 │ Robot    public API :5480              │
                 │          dedicated channel :5410/:5411 │
                 └──────────────────┬─────────────────────┘
                                    ▼
                         Dispatch server :5420
```

**Requests travel down. Notifications travel up.** A view calls a store. The store calls the session. The session serializes one request, hands it to the transport and waits for the matching reply. Separately, the robot publishes notifications. The transport delivers them to the session, the session decodes them, the stores update, and the views redraw.

### 2.1 Boundaries

These hold everywhere. A change that breaks one is wrong even if it works.

| Boundary | Rule |
|---|---|
| Dependency direction | Views → stores → `RobotSession` → `RobotTransport`. Nothing points the other way |
| Views | Never open a socket, never build a protocol message, never call the session |
| Stores | Hold only what the robot reported. After a request succeeds, displayed state changes when the notification arrives, not before |
| Session | Does not know which transport it runs on, and never branches on the concrete transport type |
| Transport | Moves bytes. It does not interpret message contents |
| WooshKit | Imports no SwiftUI, UIKit or AppKit, so it builds and tests without a simulator |
| Wire names | Message, field and enum names come from the generated code. Nothing is spelled by hand |
| Unknown input | A message that cannot be decoded is logged and dropped. It never stops the app |
| Mode gating | A request the robot's current mode does not allow is never sent ([spec § 7.1](plans/00-initialize-app.spec.md#71-mode-gating)) |
| Teleoperation | No code path may leave a nonzero velocity stream running ([spec § 9](plans/00-initialize-app.spec.md#9-safety)) |
| Design system | Colors and sizes are defined once, in `Doore/DesignSystem/`. Views use tokens |

## 3. Core Components

### 3.1. Frontend

- **Name:** Doore, the universal app.
- **Description:** Everything the user sees and touches on iPhone, iPad and Mac. Layout differs per platform; feature views and stores are shared.
- **Technologies:** Swift, SwiftUI, the Observation framework (`@Observable` stores), SwiftUI `Canvas` and Core Graphics for the map, the GameController framework for teleop input.
- **Deployment:** Installed on the user's device. One multiplatform target for iOS 17, iPadOS 17 and macOS 14.

| Part | Contains | Responsible for |
|---|---|---|
| Views | `Doore/Features/`, `Doore/MapCanvas/`, `Doore/DesignSystem/` | Display and input |
| Stores | `RobotStore` (robot state), `SceneStore` (scenes and maps), `TaskStore` (tasks), `SettingsStore` (app settings) | Holding what the robot reported, publishing it to views, and turning a user intent into a session call |
| App | `Doore/App/` | Window scenes, Mac menu commands, keyboard shortcuts, stopping teleoperation when the app leaves the foreground |

### 3.2. Backend Services

None. 두레 has no server of its own. The robot plays that role, and it is described under [§ 5](#5-external-integrations--apis).

### 3.3. Client Library

- **Name:** WooshKit.
- **Description:** The robot client. It owns the connection, speaks the protocol, and exposes typed requests and a stream of typed notifications. It can be built, tested and reused without the app.
- **Technologies:** Swift Concurrency (`actor`, `AsyncStream`), `URLSessionWebSocketTask`, SwiftProtobuf.
- **Deployment:** A local Swift package, linked into the app.

| Part | Responsible for |
|---|---|
| Messages | Swift types generated from the restored `.proto` files. One set of types serializes to JSON for the public API and to binary for the dedicated channel |
| `RobotTransport` | The protocol below. One reply per request, and a stream of notifications |
| `WebSocketTransport` | The default transport: JSON over the public API on port 5480 |
| `RobotSession` | An `actor`. Connection lifetime, the initial sync order, subscriptions, matching replies to requests, reconnecting, repeating teleop commands |
| Models | The screen-facing models of [spec § 8.1](plans/00-initialize-app.spec.md#81-screen-facing-models), built from messages |
| `WooshKitTesting` | `FakeRobotTransport`, the third transport, which replays canned replies and notifications |

The transport boundary:

```swift
protocol RobotTransport: Sendable {
    func connect(to endpoint: Endpoint) async throws
    func disconnect() async
    /// Sends one request and waits for the matching reply.
    func request(type: String, body: Data, timeout: Duration) async throws -> Reply
    /// Subscribes to, or unsubscribes from, a set of topics.
    func setSubscription(_ topics: Set<String>, enabled: Bool) async throws
    /// Notifications and connection state changes.
    var events: AsyncStream<TransportEvent> { get }
}

struct Reply { let type: String; let body: Data; let ok: Bool; let message: String }

enum TransportEvent {
    case notification(type: String, body: Data)
    case stateChanged(ConnectionState)
}
```

The session puts typed functions on top of it. `session.send(ExecTask(...))` serializes the message, calls `request`, and throws an error carrying `message` when `ok` is false.

Two points are left to whoever implements the package, with one constraint each:

- `body` is JSON on the WebSocket transport and binary protobuf on the ZeroMQ transport. How the transport tells the session which encoding it uses is open. The session must not branch on the concrete transport type.
- Velocity commands are sent without waiting for a reply. Whether that is a second method or a variant of `request` is open. It must never queue: at most one value is pending, and the newest one wins.

### 3.4. Technology Choices

| Area | Choice | Reason |
|---|---|---|
| UI | SwiftUI, one multiplatform target | Three platforms share the screen code |
| Concurrency | Swift Concurrency: the session is an `actor`, notifications are an `AsyncStream` | Request ordering and reconnects without data races |
| Default transport | `URLSessionWebSocketTask` | The public API needs nothing beyond the operating system |
| Message code | Generated with SwiftProtobuf | One set of types for both JSON and binary |
| Map drawing | SwiftUI `Canvas` and Core Graphics | Stations, fields, paths and the robot are drawn over the map image |
| Teleop input | On-screen joysticks, the GameController framework, the keyboard | Every input device is reduced to one velocity value |
| Optional transport | libzmq as an XCFramework, or a Swift implementation of only the REQ and SUB parts of ZMTP | A fallback for robots where the public API is off or incomplete |

`swift-protobuf` is the only third-party dependency.

## 4. Data Stores

두레 has no database. The robot keeps maps, tasks and settings. The app keeps only what lets it reconnect and redraw quickly, and none of it is a source of truth for robot state.

### 4.1. App settings

- **Name:** App settings store.
- **Type:** User defaults.
- **Purpose:** Preferences and connection history.
- **Key contents:** connection history (IP, port, target, last robot name, last connection time); language (Korean until the user changes it); request timeout; teleop maximum speeds; drive mode; layer visibility.

### 4.2. Credentials

- **Name:** Credential store.
- **Type:** Keychain.
- **Purpose:** The user name and password for the public API's Basic authentication. Used only when a robot has authentication turned on.

### 4.3. Scene cache

- **Name:** Scene cache.
- **Type:** Files in the app container's Caches folder.
- **Purpose:** Showing the last known map quickly.
- **Key contents:** one folder per robot number and scene name. Overwritten with robot data on every connection.

### 4.4. Scene being edited

- **Name:** Editing workspace.
- **Type:** Files in the app's Documents folder.
- **Purpose:** The Design workspace's scene editor (milestone M4): the copy that is edited before an upload, and its backup.

### 4.5. Communication log

- **Name:** Communication log.
- **Type:** One text file per day in the app container.
- **Purpose:** Diagnosis. Names and numbers of requests, replies and notifications. Shareable from Settings.

### 4.6. Status code table

- **Name:** Status code table.
- **Type:** A read-only resource in the app bundle.
- **Purpose:** Recovery steps for each robot status code.
- **Key contents:** not yet in the repository, and not to be added until the owner confirms it may be used ([spec § 13.2](plans/00-initialize-app.spec.md#132-inputs-that-are-not-in-this-repository-yet)).

## 5. External Integrations / APIs

Every integration is on the local network. The app reaches nothing on the Internet.

| Service | Purpose | Integration method |
|---|---|---|
| Robot public API | Everything: state, commands, maps, tasks, settings | WebSocket with JSON on port 5480. Wire format in [spec § 5.1](plans/00-initialize-app.spec.md#51-websocket-wire-format); messages in [spec § 6](plans/00-initialize-app.spec.md#6-protocol-reference) |
| Dispatch server | Watching and tasking many robots (milestone M4) | The same client, with the connection target set to dispatch. The flow is unverified ([spec § 13.1](plans/00-initialize-app.spec.md#131-open-questions)) |
| Robot dedicated channel | A fallback if the public API cannot do something the app needs | ZeroMQ REQ/REP on port 5410 and PUB/SUB on 5411. Not built unless a task asks ([spec § 5.5](plans/00-initialize-app.spec.md#55-dedicated-channel-reference-only)) |

## 6. Deployment & Infrastructure

- **Cloud Provider:** None. The app has no server side.
- **Key Services Used:** None.
- **CI/CD Pipeline:** None yet.
- **Monitoring & Logging:** The on-device communication log of [§ 4.5](#45-communication-log). No telemetry, analytics or crash-reporting service.
- **Distribution:** Decided by the owner. The options are TestFlight for all three platforms, an Apple Business Manager custom app, or a Developer ID signed and notarized Mac build. Signing and distribution are done by a person.

## 7. Security Considerations

- **Authentication:** The robot's public API supports HTTP Basic authentication and has it off by default. When credentials are stored, the app sends `Authorization: Basic`.
- **Authorization:** None. A robot accepts every client that can reach it, and several clients can connect at once. The app cannot enforce a single operator; it exposes the robot's occupancy switch so that a site can.
- **Data Encryption:** None in transit. The public API is `ws://` and `http://`, and the dedicated channel has no encryption either. The robot network should be separate from the office network. At rest, credentials are in the keychain and nothing else is sensitive.
- **Key Security Tools/Practices:**
  - The app asks for one permission, local network access. Location, camera, microphone and Bluetooth are not used.
  - No credential, real robot address or real robot name is committed. Examples use `192.0.2.0/24` and names like `예시-01`.
  - The app moves a physical machine. The teleoperation rules of [spec § 9](plans/00-initialize-app.spec.md#9-safety) are safety requirements, and each has a test.

Platform settings these choices require:

| Item | Platform | Setting |
|---|---|---|
| Local network access | iOS, iPadOS | `NSLocalNetworkUsageDescription` in Info.plist. The system asks on the first connection |
| Unencrypted local connections | all | Enable `NSAllowsLocalNetworking` under App Transport Security |
| Outgoing connections | macOS | The sandbox entitlement for outgoing network connections |
| File access | macOS, iPadOS | Only for scene export and import and for sharing logs, limited to files the user picks |
| Game controllers | all | No permission needed |

## 8. Development & Testing Environment

- **Local Setup Instructions:** The build and test commands are in [AGENTS.md](../AGENTS.md#build-and-test-commands). A Mac with Xcode is required for the app. WooshKit needs only a Swift toolchain.
- **Testing Frameworks:** The test framework that ships with the toolchain. WooshKit tests run with `swift test` against `FakeRobotTransport`. App tests run with `xcodebuild test`. What must be tested is in [spec § 11](plans/00-initialize-app.spec.md#11-verification).
- **Code Quality Tools:** None configured yet.

## 9. Future Considerations / Roadmap

The work is built in milestones. Scope and completion criteria are in [spec § 12](plans/00-initialize-app.spec.md#12-milestones).

| ID | Milestone | What it adds to the structure |
|---|---|---|
| M0 | Pre-verification (human) | Nothing. It decides whether the default transport is enough |
| M1 | WooshKit | `Packages/WooshKit/` |
| M2 | Basic operation | `Doore.xcodeproj`, the app shell, the stores, the first feature folders |
| M3 | Site setup | The Map, Task and Device features |
| M4 | Design workspace | The Design feature, the scene editor, the editing workspace of [§ 4.4](#44-scene-being-edited) |
| M5 | Release (human-led) | Nothing |

Known architectural risks:

- **The public API has never been exercised on a real robot.** Everything is designed around it, and the transport boundary exists so that the ZeroMQ transport can be added without touching the session, the stores or the views.
- **The format of live map-building data is unknown.** The map canvas may need a second drawing path for it.
- **The dispatch connection is unverified.** Multi-robot features may change `RobotStore` from one robot to a collection.

## 10. Project Identification

- **Project Name:** 두레 (`Doore`)
- **Repository URL:** <https://github.com/scorpion1201/doore>
- **Primary Contact/Team:** the repository owner
- **Date of Last Update:** 2026-11-18

## 11. Glossary / Acronyms

The UI terms in Korean, Chinese and English are in [DESIGN.md § 12](DESIGN.md#12-vocabulary). The terms below are the ones the code uses.

- **Woosh Mobile, Woosh Design:** the vendor's original apps, for operating a robot and for editing scenes.
- **Public API:** the robot's documented HTTP and WebSocket interface on port 5480.
- **Dedicated channel:** the undocumented ZeroMQ interface the original apps use, on ports 5410 and 5411.
- **Dispatch server:** a server that assigns tasks to many robots.
- **Scene:** a named group of maps and task definitions.
- **Map:** one floor: an image, its resolution and origin, and the objects placed on it.
- **Station:** a point placed on a map, of any type, that a robot can be sent to. The protocol calls it `Storage`.
- **Field:** an area on a map with driving rules.
- **Soft guide:** a preferred path drawn on a map.
- **Task, task set:** one job for the robot, and an ordered list of them.
- **Action group:** the sequence of actions that carries out one task type.
- **Control mode, work mode:** two robot settings that together decide which requests are allowed.
- **Teleoperation (teleop):** driving the robot by hand.
- **Twist:** the velocity command, linear and angular, sent repeatedly during teleoperation.
- **Topic:** a message type the client subscribes to in order to receive notifications.
- **Fake robot:** `FakeRobotTransport`, which stands in for a robot in tests.
- **ATS:** App Transport Security.
- **ZMTP:** the ZeroMQ wire protocol.
