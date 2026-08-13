# ClaudeMonitor

A native macOS menu bar app for watching your Claude Code sessions: running processes (CPU/MEM/working directory) and your current usage block (tokens, cost, burn rate) via [ccusage](https://github.com/ryoppippi/ccusage) — all live in the menu bar, no terminal window needed.

Built with SwiftUI + Swift Package Manager, no Xcode project required.

## Requirements

- macOS 13.0 (Ventura) or later
- [Xcode Command Line Tools](https://developer.apple.com/xcode/resources/) (`xcode-select --install`) — free, no Apple Developer account needed
- Node.js with `npx` on your `PATH` if you want the usage-block section populated (it shells out to `npx ccusage`); the app works fine without it, the usage section just shows "unavailable"

## Install

### Option A: Build from source (recommended — no security warnings)

```bash
git clone https://github.com/sr-albert/watchagents.git
cd watchagents
./Scripts/build-app.sh
open ~/Applications/ClaudeMonitor.app
```

Since you're building the app yourself, macOS never flags it as downloaded-from-the-internet, so there's no Gatekeeper warning.

### Option B: Pre-built release

Download the zipped app from the [Releases](https://github.com/sr-albert/watchagents/releases) page, then:

```bash
unzip ClaudeMonitor.zip -d ~/Applications
```

The app isn't notarized (that requires a paid Apple Developer account), so the first time you open it macOS will warn that it's from an "unidentified developer." To open it anyway:

- Right-click (or Control-click) `ClaudeMonitor.app` in Finder → **Open** → confirm **Open** in the dialog, **or**
- Run `xattr -cr ~/Applications/ClaudeMonitor.app` in Terminal to clear the quarantine flag, then open normally.

You only need to do this once.

## Usage

Launch the app and look for the bolt icon in your menu bar — it shows your current usage-block token percentage next to it. Click it to see:

- Your active Claude Code sessions (PID, CPU%, MEM%, working directory)
- Total CPU/MEM usage across sessions
- The current usage block: tokens used/remaining, cost, burn rate, and time until reset
- A **Launch at Login** toggle
- **Quit**

## Development

```bash
swift build      # debug build
swift test        # run the test suite
swift run         # run without packaging into an .app (menu bar icon still appears)
```

See `Scripts/build-app.sh` for how the release `.app` bundle is assembled (ad-hoc code signed, `LSUIElement` set so there's no Dock icon).

## License

MIT — see [LICENSE](LICENSE).
