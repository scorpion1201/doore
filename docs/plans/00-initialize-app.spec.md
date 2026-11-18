# Spec 00: Initialize the app

**Task:** initialize 두레. Starting from an empty repository, build the universal app that brings Woosh Mobile and Woosh Design to iPhone, iPad and Mac.

This specification says what 두레 must do and how it must behave toward a Woosh robot. It covers the whole product, from the first connection to the Design workspace. Scope is decided here: the goal, the non-goals and the milestones.

| To learn | Read |
|---|---|
| How the code is organized | [ARCHITECTURE.md](../ARCHITECTURE.md) |
| What the user sees, and the UI wording | [DESIGN.md](../DESIGN.md) |
| How to work in this repository | [AGENTS.md](../../AGENTS.md) |

**Implementation status.** The native project, local client, fake transport and restored schemas are present. Hardware acceptance, channel support and release verification are tracked in [§ 12](#12-milestones) and [§ 13](#13-open-questions-and-missing-inputs).

## 1. Goal

People who use a Mac, iPhone or iPad can operate, set up and configure the same Woosh robots without a Windows PC or an Android device.

Today that work needs the vendor's two apps: Woosh Mobile, which runs on Windows and Android, and Woosh Design, which runs on Windows. 두레 brings both to Apple platforms as one new SwiftUI app. It is not a port of their code. It talks to the robot over the robot's documented public API.

The work is finished when all of these are true:

1. One Xcode project builds one universal app for iOS 17, iPadOS 17 and macOS 14.
2. Every Woosh Mobile screen exists in 두레 with the same panels and the same buttons in the same order (milestones M2 and M3).
3. The Woosh Design workspace exists with its Monitor, Deploy and Statistics tabs (milestone M4).
4. For the same user action, 두레 sends the same request the original app sends and shows the same state.
5. The UI is Korean by default. A language setting switches it to Chinese or to English, and both use the original apps' own wording.

Four principles decide every case this document does not spell out:

- **Same features, same procedures.** Request order, mode restrictions and confirmation steps follow the original apps.
- **Public API first.** The documented WebSocket channel is the default. The dedicated channel is added only if the public API proves unable to do something the app needs.
- **The app creates no state.** It shows only what the robot reported. After a request, the screen changes when the robot's notification arrives.
- **Safety before convenience.** Teleoperation stops at once when the user lets go, when the app leaves the foreground, or when the connection drops.

## 2. Non-goals

Stop and ask before doing anything on this list, even when it looks helpful.

**Out of scope for the product**

- Changing robot firmware or the dispatch server. 두레 is only a client.
- Reusing the original apps' code, icons, logos or trademarks. Icons are SF Symbols plus newly drawn map markers.
- Reading or writing Woosh Design's local scene folder format. Scenes travel through the robot.
- Redesigning the UI. No tab bar, sidebar, inspector or new screen that DESIGN.md does not describe.
- Platforms other than iPhone, iPad and Mac.
- Internet services: accounts, cloud sync, analytics, crash-reporting SDKs, remote configuration. The app talks only to robots and dispatch servers on the local network.
- Permissions other than local network access. No location, camera, microphone or Bluetooth.
- Computing robot state inside the app, or optimistic UI. The robot is the only source of state.
- A dark appearance. DESIGN.md defines a light appearance only.
- Languages other than Korean, Chinese and English.
- Rewording the Chinese or the English. Both are the original apps' text, copied exactly.

**Deferred until a task asks for it**

- The dedicated ZeroMQ transport (ports 5410 and 5411). It is built only if M0 shows that the public API cannot do something the app needs.
- Anything that belongs to a later milestone than the one a task names.

**Not agent work — a person does these**

- M0, and any check that requires a physical robot.
- Confirming with the supplier that the Woosh name, the dedicated channel and the built-in status code table may be used.
- Code signing, provisioning, TestFlight, Apple Business Manager and notarization.

## 3. Evidence tags

Everything known about the robot protocol comes from analysing the two original apps against a **fake robot**. No real robot and no dispatch server was ever connected. Each fact below therefore carries one of four tags:

| Tag | Meaning | How to build on it |
|---|---|---|
| **Documented** | Stated in Woosh's public API documentation | Rely on it |
| **Observed** | Seen in a running original app or in its traffic with the fake robot | Rely on it |
| **Inferred** | Deduced from UI strings and protocol definitions | Isolate it behind one function so it can change in one place |
| **Unverified** | Needs a real robot or a dispatch server | Do not build on it without asking |

## 4. Robot interfaces

A robot exposes two unrelated ways in. The original apps use only the dedicated channel. 두레 uses the public API.

```
                                         Robot
 Woosh Mobile ──┐  ZeroMQ REQ/REP   ┌──────────────────────────────┐
 Woosh Design ──┼──────────────────▶│ request channel       :5410  │
 (Windows,      │  ZeroMQ PUB/SUB   │ notification channel  :5411  │
  Android)      └──────────────────▶│                              │
                                    │                              │
 두레            WebSocket + JSON    │                              │
 (iPhone, iPad, ───────────────────▶│ public API            :5480  │
  Mac)                              └──────────────┬───────────────┘
                                                   │ the robot connects out
                                                   ▼
                                    Dispatch server :5420
                                    assigns tasks to many robots
```

| Channel | Port | Wire format | Used by | Evidence |
|---|---|---|---|---|
| Dedicated request | 5410 on a robot, 5420 on a dispatch server | ZeroMQ REQ/REP, msgpack envelope, protobuf body | Woosh Mobile, Woosh Design | Observed (5420 is taken from a placeholder string) |
| Dedicated notification | request port + 1, so 5411 | ZeroMQ PUB/SUB, one topic per message type | Woosh Mobile, Woosh Design | Observed (dispatch side Unverified) |
| Public API | 5480 | HTTP POST and WebSocket, JSON | external integrations, 두레 | Documented |
| Log download | unknown | FTP | Woosh Design | Inferred |

Both channels carry the same protobuf message set and differ only in packaging. A request sequence observed on the dedicated channel can therefore be replayed on the public API unchanged.

The public documentation gives `169.254.128.2` as a robot's default address and states that the port is 5480, not 5410. Public API documentation: <https://wooshrobot.apifox.cn/> ([overview](https://wooshrobot.apifox.cn/doc-2385383.md), [velocity control](https://wooshrobot.apifox.cn/api-69849702.md), [task execution](https://wooshrobot.apifox.cn/api-69847550.md)).

What the three parties do:

- **Woosh Mobile** operates one robot on site: status, teleoperation, map building, station registration, tasks, robot settings.
- **Woosh Design** is the engineer's tool: it downloads a scene, edits fields, paths, stations and task sets, and uploads it again. It can also connect to a dispatch server and watch many robots.
- **The robot** answers requests and publishes a notification whenever its state changes. Nearly every status element in the apps is driven by those notifications.

## 5. Communication

두레 talks to the robot in two ways only: one reply per request, and a stream of notifications per topic. This section fixes the wire format and the timing. Where that code lives is in [ARCHITECTURE.md § 3](../ARCHITECTURE.md#3-core-components).

### 5.1 WebSocket wire format

| Item | Specification |
|---|---|
| Address | `ws://<IP>:5480`. The port can be changed in the connect dialog |
| Request | `{"type": "woosh.robot.RobotInfo", "body": {…}, "sn": 1}` |
| Reply | `{"type": …, "body": {…}, "ok": true, "msg": "…", "sn": 1}` |
| Matching | Increase `sn` by 1 for each request and wait for the reply with the same `sn` |
| Subscribe | `{"type": "woosh.Subscription", "body": {"sub": true, "topics": ["woosh.robot.PoseSpeed"]}}` |
| Notification | `{"type": "woosh.robot.PoseSpeed", "body": {…}}` |
| Timeout | 30 seconds by default, the original apps' default. Changeable in settings. A timeout fails the request and keeps the connection |
| Subscription policy | Right after connecting, one `woosh.Subscription` registers every topic the app always needs. Heavy topics, such as map-building data and lidar points, are added and removed by the screen that needs them |
| JSON rules | Standard protobuf JSON mapping. Field names are camelCase (`robotId`, `markNo`), bytes are Base64, 64-bit integers are strings. Accept an enum as either its number or its name |
| Authentication | If credentials are stored, send `Authorization: Basic`. The robot's default is no authentication |
| Liveness | Send WebSocket pings periodically. No pong means the connection is lost |

The same message set is also reachable over HTTP as `POST http://<IP>:5480/woosh/robot/RobotInfo`, with the request body as JSON. 두레 uses the WebSocket, because notifications need it.

### 5.2 Connection states and initial sync

The session moves through five states in this order.

1. **Disconnected.** The status bar shows 미연결.
2. **Connecting.** Open the socket and register subscriptions.
3. **Syncing.** Request, in the same order as Woosh Mobile (Observed): robot info (`RobotInfo`) → navigation path (`NavPath`) → costmap (`CostmapData`) → current scene data (`SceneData`).
4. **Ready.** Screens may send requests. From here on, updates arrive as notifications.
5. **Reconnecting.** On a drop, stop teleoperation, then retry with a delay that grows from 1 second to at most 10 seconds. On success, continue from step 2 and sync again.

Woosh Design uses a slightly different initial order (Observed): `RobotInfo` → `CostmapData` → `map.Download` of the current scene → `NavPath`. Use the Mobile order unless a Design feature proves to need the other.

### 5.3 Teleoperation command loop

- A timer runs only while a teleop screen is open **and** the input is not zero. It sends a velocity command (`Twist`) 15 times per second. The documented minimum is 10 per second; the original app sends about 16 (Observed).
- A command does not wait for its reply. A command that could not be sent in time is dropped, and only the newest value is sent.
- Stopping means sending zero velocity twice. If transmission stops entirely, the robot decelerates on its own (Documented); sending zero stops it immediately (Documented).
- Speed is the joystick deflection ratio multiplied by the selected maximum. Defaults are 0.2 m/s and 0.3 rad/s. With a maximum of 0.2 m/s the original sends 0.06, then 0.12 as the stick moves out (Observed).
- With the drive mode set to lateral or omnidirectional, the left stick also carries sideways motion.

### 5.4 Error handling

| Situation | Handling |
|---|---|
| Reply with `ok` false | Show the robot's `msg` unchanged. Do not change any displayed state |
| Timeout | Show "request failed". For a request that waits on a state change, such as starting map building, show "waiting for the robot to change state", as the original does |
| Connection lost | Stop teleoperation, show it in the status bar, reconnect automatically |
| Mode mismatch | Send nothing. Show the required mode and a button that switches to it |
| Message that cannot be decoded | Ignore it and write it to the log. Never stop the app |

### 5.5 Dedicated channel (reference only)

**Do not implement this unless a task asks for it.** The format is recorded here because it was fully confirmed against the fake robot (Observed) and would be expensive to rediscover.

| Kind | ZeroMQ frames | Body |
|---|---|---|
| Request | ① 4-byte request ID ② empty frame ③ msgpack array | The array is `[request number, time in ms, sender name, data]`. `data` is a protobuf `woosh.commu_pack.MessagePack` whose `body` (an `Any`) holds `type.googleapis.com/<message name>` and the request |
| Reply | Frames ① and ② echoed back, then ③ msgpack array | Same request number. In `data`, `ok` is the result, `msg` is a text for the user, `body` is the reply |
| Notification | ① topic frame ② msgpack array | The topic is `<message name>_woosh_commu`. The array is `[sequence number, time in ms, sender name, data]`, where `data` is the raw protobuf message with no wrapper |

- The original apps identify themselves as `woosh_mobile` or `woosh_design`.
- A subscription registers a message name as a topic prefix, for example `woosh.robot.PoseSpeed`.
- The connection is ZMTP 3.1 with the NULL security mechanism: no encryption and no authentication.
- The apps send a PING about every 30 seconds.
- Only one REQ socket and one SUB socket are needed. Implementing the ZMTP greeting, READY, PING/PONG and frame I/O directly on the Network framework is a small job. msgpack needs only four types: array, integer, string, binary.

## 6. Protocol reference

Exact field names, field numbers and enum cases are in the restored `.proto` files. The tables here tell you which message to look for; they do not replace the definitions. The message name is also the `type` value of the public API.

### 6.1 Message families

| Package | Purpose | Messages |
|---|---|---|
| `woosh.robot` (info) | Reading and receiving robot state | `RobotInfo`, `General`, `Setting`, `RobotState`, `Mode`, `PoseSpeed`, `Battery`, `Network`, `Scene`, `TaskProc`, `DeviceState`, `HardwareState`, `OperationState`, `Model`, `NavPath`, `ScannerData` |
| `woosh.robot` (requests) | Commanding the robot | `InitRobot`, `SetRobotPose`, `SwitchControlMode`, `SwitchWorkMode`, `SwitchMap`, `BuildMap`, `Deployment`, `ExecTask`, `ExecPreTask`, `ActionOrder`, `Twist`, `Speak`, `RobotWiFi`, `PowerOff`, `SetOccupancy`, `SetMuteCall`, `SetHoldMode`, `CountData` |
| `woosh.robot.setting` | Robot settings | `Identity`, `Server`, `AutoCharge`, `AutoPark`, `GoodsCheck`, `AutoHold`, `Power`, `Sound` |
| `woosh.robot.count` | Status codes and operating statistics | `StatusCode`, `AbnormalCodes`, `Operation`, `Task`, `Status` |
| `woosh.map` | Scenes and maps | `SceneList`, `SceneData`, `Download`, `Upload`, `Rename`, `Delete`, `SceneSync` |
| `woosh.map.mark` | Stations and markers | `Storage`, `Wormhole`, `ARTag`, `Beacon`, `Reflector`, each with `Create`, `Update`, `Delete`, `Find` |
| `woosh.map.field`, `woosh.map.path` | Fields and soft guides | 13 field types, `MonoPath`, `BidirectPath` |
| `woosh.task` | Task sets | `TaskSet`, `Task`, `WooshTaskSet`, `RepeatTask`, `CallTask`, `AddTask` |
| `woosh.ros` | Calling a robot action directly | `CallAction` (charge, lift, step move, basic navigation, arbitrary action), `Feedbacks` |
| `woosh.dispatch` | Dispatch server | `Robot`, `Robots`, `SwitchScene`, `ChargeSettings`, `FindTask`, `TaskOrder`, `AddTask` |

### 6.2 State values

The values are named here in plain English for reading; these are not UI strings. Display labels are in [DESIGN.md § 12](../DESIGN.md#12-vocabulary).

| Kind | Values |
|---|---|
| Robot state | uninitialized, idle, parking, in task, warning, fault, following, charging, building map |
| Control mode | automatic, manual, maintenance |
| Work mode | deploy, task, dispatch |
| Task type | pick, park, charge, carry |
| Task direction | load, unload |
| Task state | initial, ready, executing, paused, waiting for action, waiting for task, completed, cancelled, failed |
| Action type | navigate, step control, dock in, dock out, carry, wait, charge |
| Action order | start, pause, continue, cancel, recover, release wait, traffic control, release control |

### 6.3 Topics the original apps subscribe to

| Topics | Mobile | Design |
|---|---|---|
| `Setting`, `RobotState`, `Mode`, `PoseSpeed`, `Battery`, `Network`, `Scene`, `TaskProc`, `DeviceState`, `NavPath`, `Model`, `CostmapData`, `StatusCode`, `AbnormalCodes` | yes | yes |
| `BuildMapData`, `ScannerData`, `CameraData`, `RfRemoteController` (the call pager) | yes | no |

### 6.4 What each notification updates

| Notification | UI it drives | Evidence |
|---|---|---|
| `RobotState` | The state pill in the status bar; which buttons a screen shows (start ↔ save and cancel, and so on) | Observed |
| `Mode` | The work-mode selection; mode-mismatch messages | Observed |
| `PoseSpeed` | Position and heading of the robot marker on the map | Observed |
| `Battery` | Battery percentage in the status bar | Observed |
| `TaskProc` | The destination · task type · action · progress line over the map; the task control buttons | Observed |
| Setting, network, scene, device state | Settings values, the WiFi icon, map switches, status icons | Inferred |
| Status codes, abnormal codes | The status code dialog | Inferred |
| `BuildMapData` | The live map while building | Unverified: the fake robot could not produce data the original app would draw, in either raw-grid or PNG form |

### 6.5 Scene data

One scene groups several maps and the task definitions.

- **Scene:** name, list of maps, task information (repeat tasks, call tasks), action groups (a JSON string).
- **Map:** ID, name, resolution in metres per pixel, origin and end coordinates, map image (PNG), no-go image, traffic-control image, modification time.
- **Marker information:** floor name, stations, wormholes, beacons, QR codes, reflectors.
- **Station:** identity (ID, number, description), pose (docking pose and real pose), arrival mode, docking information, type-specific values.
- **Field information:** 13 field types and guide points. A field has a vertex list and driving rules.
- **Path information:** one-way and two-way paths, each with a point list, a width and an avoidance flag.

A scene folder as Woosh Design stores it appears to contain `scene.json` and `action_groups.json` per scene, and `map.png`, `map.yaml`, `keepout.png`, `traffic_keepout.png` plus station, field, soft-guide and task files per map (Inferred from file-name strings; the internal formats are Unverified). 두레 does not read or write this folder.

## 7. Feature flows

Every operation follows one pattern: send one request, check the reply's `ok`, then let notifications update the screen.

### 7.1 Mode gating

The robot has a control mode and a work mode, and each action needs a particular combination. When the mode is wrong, the app sends nothing and explains what is needed.

| Action | Required mode | Evidence |
|---|---|---|
| Send a task, charge, park | automatic control mode + task work mode | Observed |
| Build a map, add a station | automatic control mode + deploy work mode | Observed |
| Send a dispatch task | dispatch work mode | Inferred |
| Teleoperate | not charging; if a task is running, it must be paused | Inferred |

### 7.2 Requests per feature

| Feature | User action | Request sent | What changes on screen | Evidence | Milestone |
|---|---|---|---|---|---|
| Connect | Robot name button → enter IP → connect | Open the socket, subscribe, then the sync of [§ 5.2](#52-connection-states-and-initial-sync) | Status bar fills in; map and stations appear | Observed | M2 |
| Single task | Monitor: pick a station → 작업 → choose type, direction, action group → send | `ExecTask` | State becomes "in task"; destination and progress appear over the map | Inferred (dialog and status display Observed) | M2 |
| Task control | Pause, continue, cancel, skip → confirm | `ActionOrder` (pause and so on) | Progress reads "paused"; the button becomes "continue" | Observed | M2 |
| Charge, park | 충전 or 주차 → confirm | A charge task or a park task | State becomes charging, and so on | Inferred (confirm dialog Observed) | M2 |
| Teleoperation | Hold a joystick | `Twist` repeatedly, then zero twice on release | Robot marker moves on the map | Observed | M2 |
| Position init | Init tab → 제자리 초기화 → confirm | `InitRobot` using the recorded pose | Scene data is fetched again and the map redraws | Observed | M2 |
| Set pose | Init tab: long-press and drag the robot marker, set heading with the dial, release | `SetRobotPose` | Robot marker moves to the chosen pose | Inferred | M2 |
| Change a setting | A switch, a slider or a 수정 button | The per-item setting request (auto charge, auto park, battery thresholds, name, dispatch server, …) | The setting notification updates the control | Inferred | M2 |
| Build a map | Map → 지도 추가 → choose deploy mode → start → enter map name | `SwitchWorkMode`, then `BuildMap` (add) | State becomes "building map"; save and cancel buttons and the station panel appear | Observed | M3 |
| Save a map | Save → confirm | `BuildMap` (save) | State returns to idle; the start button returns | Observed | M3 |
| Register a station | Map → 스테이션 편집 → drive the robot to the spot → enter type and number → 스테이션 추가 | With precise deploy on: `Deployment` (collect markers), then create the station | The new station appears on the map | Observed (`Deployment`), Inferred (create request) | M3 |
| Task set | Task: pick a station → add a task, repeat → reorder → 작업 묶음 보내기 | `task.AddTask` or a repeat task | The set appears in Monitor's list and runs with the start button | Inferred | M3 |
| WiFi | List, add, reconnect, delete, switch to hotspot | The five commands of `RobotWiFi` | A notice while switching | Inferred | M3 |
| Device control | Run speech, step move, lift, … | `Speak`, `CallAction` | A success or failure notice | Inferred | M3 |

### 7.3 Woosh Design scene workflow (M4)

Woosh Design works in one direction: connect → download scene → edit → save → upload → switch scene. Editing happens on a local copy, and nothing reaches the robot before the upload.

| Step | User action | App behaviour | Evidence |
|---|---|---|---|
| Open a scene | Deploy → scene library → pick a scene → open | Fetch `SceneList`, download the chosen scene as a file bundle, show it on the canvas | Observed (list and download requests) |
| Edit | Pick a tool, add objects, edit values in the property panel | Only the local copy changes. An undo history is kept | Inferred |
| Precise deploy | Choose a robot ID, park the robot on the point, press 정밀 배치 or 배치 갱신 | Send `Deployment`; the robot corrects the station pose to where it actually localizes. Ask for confirmation if the robot is more than 1 m from the point | Inferred (the same request was Observed in Mobile) |
| Save | Save, or save and back up | Update the local scene. A backup keeps the map as it was before the edit | Inferred |
| Upload | Upload | Send the scene to the robot with `map.Upload`, incremental or full | Inferred |
| Switch scene | Switch scene | The robot changes its active scene and map with `SwitchMap`. Offers "also initialize the robot" | Inferred |

In 두레 the edited copy lives in the app's Documents folder. Before an upload the app shows how many items changed and asks for confirmation.

Other Design behaviour:

- Selecting a robot in the list moves the map to that robot's current map, position and running task.
- Pressing 내비게이션 and then tapping the map sends the robot to that point. It is allowed only when the robot is idle and the point is on the current map.
- Statistics queries the task history by period, robot and state, one page at a time.
- In dispatch mode the same screens act on many robots, and a task is sent to a chosen robot number or auto-assigned (Unverified).

## 8. Data

### 8.1 Screen-facing models

Data exchanged with the robot uses the generated protobuf types directly. A thin layer of screen-facing models sits on top.

| Model | Holds | Source message |
|---|---|---|
| `RobotSnapshot` | name, number, type, size, version, state, control and work mode, pose and speed, battery, network, current scene and map, device state bits | `RobotInfo` and the per-item notifications |
| `TaskProgress` | task ID, type, state, current action and its state, destination, message | `TaskProc` |
| `SceneModel` | scene name, maps, task information, action groups | `SceneData` |
| `MapModel` | ID, name, floor, resolution, origin, image, stations, fields, paths | `SceneData.Map` |
| `Station` | type, number, description, real pose and docking pose, arrival mode | `map.mark.Storage` and its siblings |
| `TaskSetDraft` | name, repeat count, tasks (target, type, direction, action group, wait time) | `task.WooshTaskSet` |
| `StatusCodeEntry` | code, severity, time, message, recovery steps | `count.StatusCode` plus the bundled code table |

### 8.2 Map coordinates

Map image pixels and robot coordinates in metres convert through the map's origin and resolution. The bottom-left corner of the image is the origin coordinate (Observed with the fake robot).

```
x_px = (x − x_origin) / resolution
y_px = H − (y − y_origin) / resolution
```

`H` is the image height in pixels. Headings are in radians, and counter-clockwise appears to be positive (Inferred). In the map image a light cell is free space, a black cell is an obstacle, and a grey cell is unexplored.

### 8.3 What the app stores

The robot keeps maps, tasks and settings. The app keeps only what lets it reconnect and redraw quickly: connection history, app settings, credentials, a scene cache, the scene being edited, and a communication log. The stores are listed in [ARCHITECTURE.md § 4](../ARCHITECTURE.md#4-data-stores).

## 9. Safety

These rules outrank convenience. Each needs a test.

- **Teleoperation stops by itself.** The app sends a stop when the user lets go, when the app goes to the background, when the screen changes, when the connection drops, and when a game controller detaches.
- **Teleoperation is refused** while the robot is charging, or while a task is running and not paused. The joysticks are disabled and the reason is shown.
- **iOS drops the connection in the background.** At the moment the app is backgrounded it stops teleoperation and sends a stop. On return it reconnects and syncs again.
- **Destructive and disruptive actions are confirmed:** delete, task cancel, map switch, power off, position init.
- **Several clients can connect to one robot at once** (Observed: Design and Mobile on the same fake robot). The app cannot enforce a single operator. It exposes the robot's occupancy switch so that a site can.
- **Nothing is encrypted.** The dedicated channel has no authentication and no encryption (Observed). The public API can use Basic authentication, off by default (Documented). The robot network should be separate from the office network. Credentials live only in the keychain.

## 10. Platform requirements

| Requirement | Detail |
|---|---|
| Minimum versions | iOS 17, iPadOS 17, macOS 14. Chosen so that the Observation framework and the map gesture APIs work from the same code on all three. The owner may raise them |
| Permissions | Local network access only. Location, camera, microphone and Bluetooth are not used. The settings are in [ARCHITECTURE.md § 7](../ARCHITECTURE.md#7-security-considerations) |
| Language | Chosen inside the app, not by the system. Korean on first launch, then whatever the user picks on the 정보 tab of Settings: Korean, Chinese or English. Where the wording comes from is in [DESIGN.md § 12.1](../DESIGN.md#121-languages) |
| Teleop input | On-screen joysticks and game controllers on every platform. On the Mac also the arrow keys and W, A, S, D, where releasing the key stops the robot. Every input device is reduced to one velocity value |
| Background | iOS does not keep the connection while the app is in the background ([§ 9](#9-safety)) |
| Screens per platform | [DESIGN.md § 1](../DESIGN.md#1-one-app-two-workspaces) and [§ 11](../DESIGN.md#11-platform-adaptation) |

## 11. Verification

Tests in WooshKit run against `FakeRobotTransport`. Anything that needs a real robot is listed separately and is never reported as passed by an agent.

| Area | What to test | Needs a real robot |
|---|---|---|
| Wire format | Serialized requests, replies and notifications match recorded fake-robot traffic. Unknown fields and empty replies are handled | no |
| Reconnect | Robot restart, WiFi change and app background/foreground all end in a reconnect and a full resync | fake robot for the logic; real robot to confirm |
| Teleop safety | Release, screen change, incoming call, connection loss and controller detach each produce a stop | fake robot for the commands sent; real robot to confirm it stops |
| Mode gating | In each of the four cases of [§ 7.1](#71-mode-gating) no request leaves and the guidance appears | no |
| Map rendering | Stations and the robot are drawn where the original app draws them | side-by-side comparison with the original |
| Screen sizes | iPhone portrait and landscape, iPad split view, Mac window resizing, large text settings | no |
| Site scenario | Connect → position init → send task → pause and continue → return to charge | yes |

### 11.1 Fake robot

`FakeRobotTransport` stands in for a robot. It answers requests with canned replies and emits state notifications, so that screens can be developed and tested with no robot. It must be able to replay at least: a successful connect and initial sync, a task that runs and is paused, a dropped connection, a reply with `ok` false, and a request that times out.

## 12. Milestones

Each milestone must meet its completion criteria before the next one starts.

| ID | Work | Deliverable | Done when an agent can verify | Done when a human has verified |
|---|---|---|---|---|
| **M0** Pre-verification | Check that port 5480 is open on a real robot and whether it needs authentication. Request robot info and subscribe to pose from a Mac WebSocket tool. Send each request of [§ 7.2](#72-requests-per-feature) and record whether it is supported | A message support table and a transport decision | — | Every M2 request and notification works over the public API, or an alternative is chosen for each one that does not |
| **M1** WooshKit | Generate Swift types from the restored definitions. Implement the transport, the session and the fake robot | The `WooshKit` package with unit tests | `swift test` passes: connect, initial sync, request/reply matching, timeout, `ok` false, reconnect with backoff, teleop loop timing and stop | The same connect, sync and reconnect tests pass against a real robot |
| **M2** Basic operation | App shell, home, status bar, connect dialog, Monitor, single task and task control, charge and park, teleoperation, position init, robot settings, status codes | First build for iPhone, iPad and Mac | The app builds for macOS and iOS. Store and session tests cover every M2 row of § 7.2, the mode gating and the teleop safety rules. Every M2 screen renders in each state of DESIGN.md § 10 with the fake robot | Side by side with Woosh Mobile, the same action sends the same request and shows the same state |
| **M3** Site setup | Map building and saving, scene and map management, station registration and deletion, task sets, WiFi, Device | Second build | Tests cover every M3 row of § 7.2 with the fake robot | On a new site, everything from building a map to running a task is done with Apple devices only |
| **M4** Design workspace | Scene editor (base map, fields, soft guides, points), action groups and task set editing, upload and scene switch, task history, dispatch connection and multi-robot monitor | The Design workspace on Mac and iPad | Editor model tests: add, move, delete, undo and redo, and the changed-item count before upload | A scene edited in 두레 can be downloaded and opened by Woosh Design, and the reverse |
| **M5** Release | Korean copy review, user guide, distribution | Release build | — | A site worker connects and sends a task using only the guide |

Feature scope by milestone, mapped to the original apps:

| Milestone | Features | Original screens |
|---|---|---|
| M2 | Connect and connection history, status display, Monitor map, single task and control, charge and park, teleoperation, position init, robot settings, status code guidance | Mobile: Monitor; Settings tabs Robot, Teleop, Init, About |
| M3 | Map building and saving, scene and map management, station add and delete, task set building and running, WiFi settings, device control | Mobile: Map, Task, Device; Settings tab WIFI |
| M4 | Scene editing, action group and task set editing, upload and scene switch, task history statistics, dispatch server connection and multi-robot monitoring | Design: everything |

## 13. Open questions and missing inputs

### 13.1 Open questions

These need a real robot or the supplier. They are ordered by how much they affect the design. Do not resolve one by guessing.

| Question | Why it matters | How it gets answered | Blocks |
|---|---|---|---|
| Is the public API (5480) on for the target robots, and does it need authentication? | It is the premise of the default transport | Request robot info on port 5480 from the robot's network | M1 on a real robot |
| Does the public API support every message the app needs? | Decides whether the dedicated transport must be built | Try each request of § 7.2 and each topic of § 6.3, especially map-building data, scene upload and WiFi settings | M2, M3 |
| What is the format of the live map data during map building? | It is the main display of the map-building screen | Start map building on a real robot and record the notifications | M3 |
| What is the structure of the action groups JSON? | It fills the "action group" list of the task request dialog. With an empty list no task can be sent | Read the string in a real robot's scene data | M2 |
| Which exact requests do charge, park and the Device screen send? | The basis for implementing them | The original app's log file records the names of the requests it sends | M2, M3 |
| How does a dispatch server connection work? | The basis for multi-robot features | Connect Woosh Design in dispatch mode where a dispatch server exists | M4 |
| What is the internal format of Woosh Design's local scene files? | Only matters if file-level compatibility is wanted | Download a scene on a real robot and inspect `map/robot` | not planned |
| Which devices (arms, lift column) does each robot model have? | Decides which groups the Device screen shows | Compare with the robot models in use | M3 |
| May the status code table and the Woosh name and logo be used? | Decides whether the app can be distributed | Ask the supplier | M5 |
| Korean translation of the 932 status codes | Site workers must be able to read the recovery steps | Plan the translation work | M5 |

### 13.2 Analysis material

The supplied analysis archive contains the 25 schemas, both UI string tables and 16 reference screenshots. WooshKit includes the restored schemas and generated Swift. The app carries its string catalog. Keep screenshots and extraction tools outside the app bundle.

| Folder | Contents | Needed for | Goes to |
|---|---|---|---|
| `proto` | The 25 Woosh message definitions restored from the executables | M1: generating Swift message types | `Packages/WooshKit/Protos/` |
| `ui-text` | Every UI string of both apps, Chinese original and English translation, by screen class | M2 onward: the Chinese and English UI strings, which are used unchanged. Also the basis for the Korean strings and for checking that no feature was missed | the `zh-Hans` and `en` values of the string catalog |
| `screens` | 16 screenshots of the original apps | Screen layout reference | reference only; do not ship |
| `tools` (absent from the supplied archive) | The fake robot and the extraction scripts (Python) | Checking the dedicated channel format; recorded traffic for tests | reference for `FakeRobotTransport` |

The archive does not include recorded public-API sessions against a physical robot. The fake transport uses synthetic fixtures.

The original executables also embed a status code table: 932 codes with recovery text, as JSON and as a four-sheet spreadsheet (electronic hardware, embedded software, algorithm system, application software). Do not add it to the repository until the owner confirms it may be used. Until then the app shows the raw code and the message the robot sent.

### 13.3 Decisions the owner still has to make

- The bundle identifier and the development team.
- The distribution method ([ARCHITECTURE.md § 6](../ARCHITECTURE.md#6-deployment--infrastructure)).
- Whether to raise the minimum OS versions.

## 14. Provenance

This document condenses "Woosh Design·Mobile 동작 분석 및 Apple 유니버설 앱 설계서" (2026-11-18), which analysed these builds:

| Target | Version | Build |
|---|---|---|
| Woosh Design (`Design.exe`) | app 1.1.25, communication 1.0.10, SDK 1.2.10 | 64-bit Windows, Qt 5, built 2026-05-21 |
| Woosh Mobile (`Mobile.exe`) | app 1.1.28, communication 1.0.10, SDK 1.2.11 | 64-bit Windows, Qt 5, built 2026-05-21 |
| `Mobile_v1.1.28.apk` | app 1.1.28 | Qt 5 for Android, arm64-v8a |

The analysis read configuration files and logs, extracted strings, Qt resources and protobuf definitions from the executables, ran both apps against a local fake robot, and compared the result with the public API documentation. It did not decompile anything and did not connect to a real robot or a dispatch server.

Where that document and the later UI specification disagree about what the user sees, the UI specification was followed. In particular the original design proposed a tab bar on iPhone and a sidebar on iPad and Mac, moved teleoperation and position init out of Settings, and mapped colors to system colors. None of that applies: DESIGN.md keeps the original home menu, keeps both tabs inside Settings, and defines its own color tokens.

The owner decided the language rules after both source documents were written: Korean by default, with Chinese and English switched from Settings and taken unchanged from the original apps.

Decisions made while writing these documents, which neither source states: the directory layout, the names `Doore` and `WooshKitTesting`, checking generated Swift into the repository, keeping app settings and connection history in user defaults, and keeping the vendor status code table out of the repository until its use is confirmed.
