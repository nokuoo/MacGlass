# Security Policy

MacGlass requires disabling parts of SIP so the yabai Dock scripting addition can
inject into WindowServer. That lowers system security; only proceed if you
understand and accept the risk.

## Reporting a vulnerability

Please do not disclose exploitable details in a public issue. Use GitHub's
private Security Advisory reporting flow, or contact the maintainer directly.
We will confirm the impact as quickly as possible and credit you in the fix if
you would like.

## Security boundaries

- The app never stores administrator passwords; authorization happens only
  through the native macOS administrator dialog.
- Every external command is invoked with `Process.executableURL + arguments`;
  no shell strings are built.
- The app never changes SIP, NVRAM, or other system security settings on its
  own. SIP steps are always performed manually by the user.
- On quit, the app restores every window opacity it changed, then stops the
  yabai daemon it started.
- If a yabai daemon already exists, the app only reuses it and never force-stops
  or rewrites its configuration.

## Distribution

This project publishes source code and unsigned builds. Unsigned builds may be
blocked by Gatekeeper and need to be allowed manually in
System Settings → Privacy & Security. Proper signing and notarization only
change the distribution experience; they do not change the permission
boundaries above.
