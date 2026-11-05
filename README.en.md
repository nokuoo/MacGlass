# MacGlass

Make any visible macOS window translucent from the menu bar.

MacGlass does not overlay a screenshot, apply a filter, or fake transparency.
It uses the [yabai](https://github.com/koekeishiya/yabai) Dock scripting addition
to call a private WindowServer interface and change the target window's own
alpha value. The transparency survives Space switches, dragging, and resizing.

## Requirements

- macOS 13 or later
- Intel (x86_64) or Apple Silicon (arm64)
- SIP **Filesystem Protections** and **Debugging Restrictions** disabled, which
  yabai needs to inject into Dock
- Accessibility permission for MacGlass

MacGlass bundles yabai `7.1.25` (universal binary) under the MIT License. If
`/usr/local/bin/yabai` or `/opt/homebrew/bin/yabai` exists, MacGlass uses the
system installation instead.

## 1. Disable the SIP restrictions yabai needs

Shut the Mac down completely, then follow the steps below. Unlock FileVault
first if it is enabled.

1. On Intel Macs, hold `Command + R` while booting. On Apple Silicon Macs,
   hold the power button until startup options appear, then choose Options.
2. Choose **Utilities → Terminal** from the menu bar.
3. Run:

```bash
csrutil enable --without fs --without debug
```

4. Reboot normally and verify in a regular terminal:

```bash
csrutil status
```

You should see:

```text
Filesystem Protections: disabled
Debugging Restrictions: disabled
```

Do not run `csrutil disable`, and do not disable Apple Internal, NVRAM, or any
other protection. Changing SIP reduces system security; whether to accept that
trade-off is your decision.

The **Developer Tools** switch in System Settings → Privacy & Security **cannot
replace** this step. It only allows local developer tools that fail system
policy to run; it does not change the SIP bits required by `task_for_pid`.

On Apple Silicon, if loading the scripting addition reports a missing
`-arm64e_preview_abi`, append the boot argument yabai requires and reboot.
Check the existing value first so you do not overwrite it:

```bash
nvram boot-args
# Only if the output above is empty:
sudo nvram boot-args="-arm64e_preview_abi"
```

## 2. Download a release

Every release ships two architecture-specific packages. Download the one that
matches your Mac:

| Mac | Download |
| --- | --- |
| Intel | `MacGlass-<version>-x86_64-unsigned.dmg` |
| Apple Silicon | `MacGlass-<version>-arm64-unsigned.dmg` |

Open the DMG and drag `MacGlass.app` into `Applications`.

The packages are **not signed with a Developer ID and are not notarized**, so
Gatekeeper will block the first launch. After confirming the download came from
this repository, allow it in **System Settings → Privacy & Security → Open
Anyway**, or run:

```bash
xattr -d com.apple.quarantine /Applications/MacGlass.app
```

Prefer the `.zip` asset if you want to verify the published SHA-256 first:

```bash
shasum -a 256 -c MacGlass-<version>-<arch>-unsigned.dmg.sha256
ditto -x -k MacGlass-<version>-<arch>-unsigned.zip /tmp/macglass
ditto /tmp/macglass/MacGlass.app /Applications/MacGlass.app
open /Applications/MacGlass.app
```

## 3. Build from source

```bash
git clone https://github.com/nokuoo/MacGlass.git
cd MacGlass
chmod +x scripts/*.sh
./scripts/build-app.sh
```

The result is `dist/MacGlass.app`. To install it:

```bash
./scripts/install-app.sh
open /Applications/MacGlass.app
```

`build-app.sh` builds for the host architecture. To produce the release
packages for both architectures locally:

```bash
./scripts/package-release.sh 1.0.0 x86_64
./scripts/package-release.sh 1.0.0 arm64
```

## 4. First launch

The main window opens automatically the first time. After that, clicking the
menu bar icon shows or hides the same window.

1. If **Accessibility** shows **Not allowed**, click **Open Settings** and go to:

```text
System Settings → Privacy & Security → Accessibility
```

Allow `MacGlass`. The status updates automatically when you return; no restart
is required.
2. Click **Enable Engine**. macOS asks for an administrator password to run
   `yabai --load-sa`. The password goes only to the native authorization dialog;
   MacGlass never stores it.

When everything is ready, the status list turns green:

```text
yabai / Filesystem Protections / Debugging Restrictions / Accessibility /
Scripting Addition / yabai Daemon
```

## Usage

1. Click the menu bar icon.
2. Select a window from the list.
3. Drag the 5%–100% slider.
4. Click **Restore Original** or choose **Restore All Windows** from the
   overflow menu.
5. Quitting MacGlass automatically restores every modified window.

You can also skip the window list and use global shortcuts on the frontmost
window:

```text
Control + Option + ←    decrease opacity (more transparent)
Control + Option + →    increase opacity (less transparent)
```

A single press changes opacity by 5%. Hold for more than 120 ms and it keeps
adjusting until you release; the range is clamped to 5%–100%. The shortcuts
require Accessibility permission, and the window list always shows each
window's current opacity.

Original opacities are recorded in
`~/Library/Application Support/MacGlass/opacity-journal.json`. If the app
crashes, the next launch tries to restore them so windows are not left
translucent.

## Architecture

```text
MacGlass/
├── Package.swift
├── Resources/Info.plist
├── Resources/AppIcon.icns
├── Sources/
│   ├── MacGlass/
│   │   ├── AppDelegate.swift       # Menu bar, context menu, restore on quit
│   │   ├── AppModel.swift          # Window selection, slider, state, restore
│   │   ├── ContentView.swift       # SwiftUI control panel
│   │   ├── GlobalHotKey.swift       # Carbon global hot keys
│   │   ├── KeyHoldMonitor.swift     # Physical key hold tracking
│   │   ├── OpacityJournal.swift    # Crash recovery journal
│   │   ├── ProcessRunner.swift     # Parameterized, shell-free process calls
│   │   ├── YabaiClient.swift       # yabai queries and opacity commands
│   │   ├── YabaiEngine.swift       # SIP/AX/SA/daemon lifecycle
│   │   └── YabaiLocator.swift
│   └── MacGlassCore/
│       ├── OpacityPolicy.swift     # Opacity bounds and command arguments
│       ├── SIPStatus.swift         # csrutil status parsing
│       └── YabaiWindow.swift       # Query model and window filtering
├── Tests/MacGlassCoreTests/
├── Vendor/yabai
└── scripts/build-app.sh
```

## Diagnostics

```bash
"dist/MacGlass.app/Contents/MacOS/MacGlass" --diagnose
```

Exit codes:

- `0`: yabai, the daemon, and the scripting addition are all ready
- `2`: the environment is not ready; stdout lists every check

Load the scripting addition manually:

```bash
sudo env SUDO_UID="$(id -u)" SUDO_USER="$(id -un)" \
  "./Vendor/yabai" --load-sa
```

Start the engine manually (debugging only):

```bash
"./Vendor/yabai" \
  --config "$HOME/Library/Application Support/MacGlass/yabairc"
```

## FAQ

**A window is missing from the list**

MacGlass only lists `AXStandardWindow` windows that yabai has an AX reference
for. Move the window to the current visible Space first; native fullscreen
windows, system panels, sheets, and some cross-Space windows are not listed.

**"failed to connect to socket"**

The yabai daemon is not running. Click **Recheck**, or inspect:

```bash
tail -n 100 "$HOME/Library/Application Support/MacGlass/yabai.log"
```

**Scripting addition unavailable**

Confirm both lines are `disabled` in `csrutil status`, then click **Enable
Engine** again. `yabai --load-sa` needs administrator rights; if osascript is
blocked by automation permissions, run the manual command above.

**Breaks after Dock restarts**

Restarting Dock clears the injected payload. Click **Enable Engine** again, or
re-run `sudo ... yabai --load-sa` in a terminal.

**Accessibility is allowed but the app still says it is not**

Default builds are ad-hoc signed, so rebuilding changes the CDHash and macOS
can revoke the previous grant. Toggle `MacGlass` off and on in Accessibility;
the app refreshes automatically. If you rebuild often, sign with a stable
Apple Development or Developer ID certificate:

```bash
MACGLASS_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" \
  ./scripts/build-app.sh
```

**The app will not quit**

That means at least one window failed to restore. The app deliberately blocks
quitting so it does not leave translucent windows behind. Fix the yabai error
and try again; as a last resort, force quit from Activity Monitor and log out
to restore window alpha.

## Uninstall

1. Click **Restore All Windows** in MacGlass, then quit normally.
2. Delete the app.
3. If no other yabai configuration uses it, remove the scripting addition:

```bash
sudo "/Applications/MacGlass.app/Contents/Resources/yabai" --uninstall-sa
```

4. Remove logs and configuration:

```bash
find "$HOME/Library/Application Support/MacGlass" -depth -delete
```

5. To restore SIP, boot into Recovery and run `csrutil enable`.

## Security boundaries

- MacGlass never stores administrator passwords.
- Every command is invoked through `Process.executableURL + arguments`; no
  shell strings are concatenated.
- The opacity floor is 5%, so a window cannot be made invisible by accident.
- On quit, windows are restored before the yabai daemon started by this app is
  stopped.
- If a yabai daemon already exists, MacGlass reuses it and never force-stops or
  rewrites its configuration.

## License

MacGlass itself is MIT licensed; see `LICENSE`.

The bundled yabai binary is MIT licensed, copyright Åsmund Vikane. The full text
is in `Vendor/yabai-LICENSE.txt`.
