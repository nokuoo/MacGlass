# Contributing

Thanks for taking the time to improve MacGlass.

## Development environment

- macOS 13 or later
- Xcode Command Line Tools (provides `swift`, `codesign`, `iconutil`)

## Local checks

Run at least the following before opening a pull request:

```bash
swift test
swift build -c release --product MacGlass
./scripts/build-app.sh
```

`build-app.sh` runs the tests, builds the app bundle, and verifies the signature.
Before publishing a release, also check:

```bash
codesign --verify --deep --strict dist/MacGlass.app
```

## Code conventions

- Follow the Swift 6 concurrency model; keep UI and state updates on the
  MainActor.
- Invoke external commands through parameterized process calls. Never
  concatenate shell strings.
- When you change the opacity range, shortcuts, or window filtering, update the
  matching tests in `Tests/MacGlassCoreTests/`.
- Keep the bundle identifier and signing identifier aligned on
  `com.macglass.app`; do not change only one of them.

## Commits and pull requests

- One pull request should address one topic; avoid unrelated formatting churn.
- Describe the reproduction steps, the changes, and how you verified them.
- For changes touching SIP, Accessibility, administrator authorization, or
  process invocation, call out the security impact explicitly.
