# AGENTS.md

Instructions for coding agents that work in this repository. [README.md](README.md) is for people; this file is for you. Read all of it before you change anything.

## Project overview

Woosh Mobile is the app name and window title in every supported language. 두레 (`Doore`) is the internal project codename. This SwiftUI app brings the original Woosh Mobile and Woosh Design workflows to iPhone, iPad and Mac using the robot's documented WebSocket API.

The repository includes a native Xcode project, the local WooshKit package, generated protocol types and tests.

Before you change something, read the document that covers it:

- `docs/ARCHITECTURE.md`: code structure and boundaries.
- `docs/DESIGN.md`: everything the user sees.
- `docs/plans/`: one specification per task. Read the one your task names.

Do not look for context outside these. If they disagree, DESIGN.md wins for what the user sees, a specification wins for behaviour and protocol, and ARCHITECTURE.md wins for code structure.

## Build and test commands

Use Swift 5.9 or later for the package and Xcode 16 or later for the application. If you rename a scheme or move a package, update this section in the same change.

```bash
swift test --package-path Packages/WooshKit
```

```bash
xcodebuild -project Doore.xcodeproj -scheme Doore -destination 'platform=macOS' build
```

```bash
xcodebuild -project Doore.xcodeproj -scheme Doore -destination 'generic/platform=iOS Simulator' build
```

```bash
xcodebuild -project Doore.xcodeproj -scheme Doore -destination 'platform=macOS' test
```

## Testing instructions

- Run the tests that cover your change before you report it done.
- Say plainly which commands you could not run, and why. A build you did not run is not a passing build.
- Add or update tests with every change in behaviour, even when nobody asks.
- WooshKit imports no SwiftUI, UIKit or AppKit, so its tests run without a simulator. Put logic there or in a store whenever you can, because that is where it can be tested.
- Tests run against `FakeRobotTransport`. A check that needs a real robot is never reported as passed.
- What must be tested is in [spec § 11](docs/plans/00-initialize-app.spec.md#11-verification).

## Code style

- **Language:** Swift, with Swift Concurrency. The session is an `actor`; notifications are an `AsyncStream`. Stores use the Observation framework (`@Observable`).
- **UI:** SwiftUI only, shared by all three platforms. Layout differs by platform; feature logic does not.
- **Structure:** dependencies point one way, views → stores → `RobotSession` → `RobotTransport`. The boundaries are in [ARCHITECTURE.md § 2.1](docs/ARCHITECTURE.md#21-boundaries).
- **Dependencies:** `swift-protobuf` is the only third-party dependency. Ask before adding another.
- **Names:** identifiers, comments and documentation are in English. Use the terms of the glossary in [ARCHITECTURE.md § 11](docs/ARCHITECTURE.md#11-glossary--acronyms) (`Scene`, `Station`, `TaskSet`, `Field`), not new synonyms.
- **Colors and sizes:** use the tokens in `Doore/DesignSystem/`. Never write a literal color or size in a view.
- **Strings:** every user-facing string goes in the string catalog, in three languages. Korean is the development language. The Simplified Chinese (`zh-Hans`) and English (`en`) values are copied from the original apps' string table and never retranslated. The rules are in [DESIGN.md § 12.1](docs/DESIGN.md#121-languages).
- **Documentation:** when a change makes a statement in `docs/` false, fix the document in the same change.
- **Specifications:** name a new one `docs/plans/[no]-[task-name].spec.md`: a two-digit number counting up from `00`, then the task in lowercase words joined by hyphens.

## Commit and pull request guidelines

- Commit messages follow Conventional Commits, for example `feat(monitor): add task control buttons` or `chore: initial commit`.
- One logical change per commit.
- **Never put a `Claude-Session:` line, or any other link to an agent session, in a commit message.** Such a link exposes a private session address to everyone who can read the history. The same holds for pull request text, code comments and documents. Remove the line if your tooling adds one.

## Security considerations

- **No credentials and no real robot data in the repository.** Examples use addresses in `192.0.2.0/24` and names like `예시-01`.
- **The app stays on the local network.** Do not add analytics, crash reporting, remote configuration or any other code that contacts the Internet.
- **One permission only:** local network access. Do not add location, camera, microphone or Bluetooth usage.
- **The app moves a physical machine.** Teleoperation must fail safe: releasing the joystick sends zero velocity twice, and backgrounding the app, leaving the screen, losing the connection or detaching a controller sends a stop immediately. Every change to teleoperation needs a test that shows the stop is sent. The requirements are in [spec § 9](docs/plans/00-initialize-app.spec.md#9-safety).
- **Vendor material stays out.** Do not add the original apps' code, icons or logos, and do not add the vendor's status code table until the owner confirms it may be used.

## Boundaries

- **Stay inside the scope.** The goal and the non-goals are in [spec § 1](docs/plans/00-initialize-app.spec.md#1-goal) and [§ 2](docs/plans/00-initialize-app.spec.md#2-non-goals). Ask before you do anything listed as a non-goal, even when it looks helpful.
- **Work on the milestone your task names,** and nothing later ([spec § 12](docs/plans/00-initialize-app.spec.md#12-milestones)).
- **Follow DESIGN.md exactly.** Do not add, remove, rename or reorder a control it specifies.
- **Never guess a wire name.** Message, field and enum names come from the restored `.proto` files.
- **Never guess a Chinese or English string.** They come from the original apps' string table.
- **Never fake a result that needs a person:** a check on a physical robot, a confirmation from the supplier, code signing or distribution.

Stop and ask the owner, instead of choosing, when:

- the task conflicts with a non-goal or with a boundary in ARCHITECTURE.md;
- you need a message, field or enum name that the `.proto` files do not give you;
- you need the original Chinese or English wording of a string and cannot find it;
- the specification marks the fact you depend on as *Inferred* or *Unverified* and you cannot isolate it behind one function;
- a screen, state or dialog you must build is not described in DESIGN.md;
- the only way forward needs a physical robot, a signing identity or the supplier.

Say what you found, what you would do by default, and what the answer changes.
