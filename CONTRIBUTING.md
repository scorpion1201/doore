# Contributing to 두레

Pull requests are welcome. This document lists what a pull request must satisfy to be merged. Read it before you start, because some of the rules decide whether a change is in scope at all.

## Before you write code

**Check the scope.** 두레 has a written [goal](docs/plans/00-initialize-app.spec.md#1-goal) and a list of [non-goals](docs/plans/00-initialize-app.spec.md#2-non-goals). A pull request that crosses a non-goal is closed, however good the code is. The ones people run into most:

- No redesign. Every screen keeps the original app's panels and button order, as recorded in [docs/DESIGN.md](docs/DESIGN.md).
- No dark appearance, no extra platforms, no extra languages.
- No Internet services: no accounts, analytics, crash reporting or remote configuration.
- No rewording of the Chinese or English text. Both are the original apps' wording, copied exactly.

**Open an issue first for anything larger than a small fix.** Say what you want to change and why, and wait for a reply. It costs you a few minutes and can save you a rejected pull request.

**Small fixes need no issue:** a typo, a broken link, a failing test, a bug with an obvious cause.

## What every pull request must satisfy

**One logical change.** A fix and a refactor are two pull requests. Smaller is reviewed sooner.

**It follows the design.** Do not add, remove, rename or reorder a control that [docs/DESIGN.md](docs/DESIGN.md) specifies. Colors and sizes come from the tokens in `Doore/DesignSystem/`, never from literal values in a view.

**It respects the boundaries.** Dependencies point one way: views → stores → `RobotSession` → `RobotTransport`. A view never opens a socket or builds a protocol message. The full list is in [docs/ARCHITECTURE.md § 2.1](docs/ARCHITECTURE.md#21-boundaries).

**The robot owns the state.** After a request succeeds, the screen changes when the robot's notification arrives. Do not set displayed state from the request you just sent.

**No guessed protocol names.** Message, field and enum names come from the generated code in WooshKit. If the one you need is missing, say so in the pull request instead of spelling it by hand.

**Strings come in three languages.** Every user-facing string goes in the string catalog in Korean, Simplified Chinese and English. The rules for each are in [docs/DESIGN.md § 12.1](docs/DESIGN.md#121-languages).

**It has tests.** A change in behaviour comes with a test that fails without it. Logic belongs in WooshKit or in a store, where it can be tested without a simulator.

**The documents stay true.** If your change makes a statement in `docs/`, `README.md` or `AGENTS.md` false, fix that statement in the same pull request.

**No new dependency.** `swift-protobuf` is the only third-party dependency. Propose another in an issue first.

## Safety

두레 moves a physical machine. A pull request that touches teleoperation must keep it fail-safe: letting go of the joystick, leaving the screen, backgrounding the app, losing the connection or detaching a controller stops the robot. Each of these needs a test that shows the stop command is sent. The requirements are in the [specification § 9](docs/plans/00-initialize-app.spec.md#9-safety).

## What must never be in a pull request

- **Credentials,** of any kind.
- **Real robot data:** addresses, names, serial numbers, maps of a real site. Examples use addresses in `192.0.2.0/24` and names like `예시-01`.
- **Vendor material:** code, icons, logos or screenshots of the original apps, or the vendor's status code table.
- **Links to an AI agent session,** such as a `Claude-Session:` line, in a commit message, the pull request text, a comment or a document. Such a link exposes a private address to everyone who can read the history.

## Run this before you open it

```bash
swift test --package-path Packages/WooshKit
```

```bash
xcodebuild -project Doore.xcodeproj -scheme Doore -destination 'platform=macOS' test
```

```bash
xcodebuild -project Doore.xcodeproj -scheme Doore -destination 'generic/platform=iOS Simulator' build
```

Setup is in the [README](README.md#build).

You do not need a robot. The tests run against a fake one. If you did try your change on a real robot, say which model and what you did. If there is something you could not verify, say that too. A check you did not run is not a passing check.

## Commits and the pull request itself

- **Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/),** for example `feat(monitor): add task control buttons` or `fix(session): stop teleop on disconnect`. The pull request title uses the same form.
- **Describe what changed and why.** Name the specification and milestone the change belongs to.
- **Say how you tested it:** the commands you ran and what they printed.
- **Attach pictures for a UI change,** before and after, on each platform the change affects.
- **Keep the branch current** with `main`, and do not rewrite history after a review has started.

## Changes written with a coding agent

They are welcome, on the same terms as any other change. The agent must follow [AGENTS.md](AGENTS.md), and you must have read and understood every line you submit. You are the author, and you answer the review. A `Co-Authored-By` line for the agent is fine. A link to its session is not.

## Review

A maintainer reviews every pull request. Expect questions and requests for changes; they are about the code, not about you.

## Reporting a bug or proposing a change

Open an issue. For a bug, give the device, the OS version, the robot model if one was involved, what you did, what you expected and what happened. Remove real addresses and names before you post a log.

## License

By submitting a pull request you agree that your contribution is licensed under the [MIT license](LICENSE) of this repository.
