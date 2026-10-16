# Claude Pulse

A macOS menu bar app for Claude Code. One glance shows:

- **Plan usage**: 5-hour and 7-day limits, local reset time, countdown, a pace marker (how much of the window has passed), and a burn-rate projection ("at this pace you hit 100% at 4:10 PM").
- **Every running session**: name, git branch, model, effort, context used (tokens / window and %), API-equivalent cost, lines changed, last activity.
- **Who needs you**: sessions waiting for a permission or for your input move to the top, the menu bar icon changes, and you get a notification.
- **Jump to the session**: click a row to bring its terminal to the front. Terminal.app and iTerm2 select the exact tab; other terminals just come forward. Right-click a row to copy the resume command, open the folder, or reveal the transcript.
- **Alerts**: a session finished its turn (with how long it worked and the first line of its reply; turns under 30s are skipped by default), limit thresholds (default 75/90/95%), context filling up (default 80%), and sessions needing you. Clicking a session's notification jumps to its terminal. Every notification sent is listed in `~/Library/Application Support/ClaudePulse/notifications.log`.

## Build and install

Needs macOS 14+ and the Xcode Command Line Tools (full Xcode is not required).

```sh
make install   # builds, copies to ~/Applications, launches
make dmg       # builds build/ClaudePulse-<version>.dmg for sharing
```

The app is ad-hoc signed, not notarized. After downloading the DMG and dragging the app to Applications, macOS blocks the first launch: open **System Settings → Privacy & Security → Open Anyway**, or run `xattr -dr com.apple.quarantine /Applications/ClaudePulse.app` once.

Then click the ✦ in the menu bar → **Connect**.

## How it gets its data

| Data | Source |
|---|---|
| Running sessions, name, folder, busy/idle | `~/.claude/sessions/<pid>.json` (written by Claude Code) |
| Model, effort, context, git branch | The tail of each session's transcript in `~/.claude/projects/` |
| 5h / 7d limits, exact context %, cost | The status line JSON Claude Code passes to `ClaudePulse --statusline` |
| Needs permission / waiting / working | Hook events passed to `ClaudePulse --hook` |

**Connect** edits `~/.claude/settings.json`:
- It sets `statusLine` to `ClaudePulse --statusline`. If you already had a status line, it keeps running and its output is still shown (Pulse only listens in). Otherwise Pulse prints a compact line: `Opus 5.5 high · ctx 14% · 5h 23% ↻2h13m · 7d 41%`.
- It adds a `ClaudePulse --hook` command to UserPromptSubmit, PostToolUse, Notification, Stop, PreCompact and SessionEnd. Each run takes about 30 ms.
- It saves a backup first (`settings.json.claudepulse-backup-<time>`). **Disconnect** removes only Pulse's entries and restores your old status line.

Running sessions pick up the change after a restart. The limits appear after the next reply in any connected session, and only on Pro/Max plans; Claude Code does not report them otherwise.

There are no network calls, no Keychain access and no undocumented APIs. Snapshots live in `~/Library/Application Support/ClaudePulse/`.

## Command line

```sh
ClaudePulse --status | --connect | --disconnect
ClaudePulse --snapshot out.png [--dark]   # render the panel with live data
```

The binary is at `~/Applications/ClaudePulse.app/Contents/MacOS/ClaudePulse`.

## Ideas for later

- Daily and monthly cost and token charts from the transcripts (incremental parse, deduped by message id + request id).
- Per-model weekly limits, once Claude Code exposes them in the status line.
- Answer permission prompts (Allow/Deny) from the menu bar through a PermissionRequest hook.
- Compaction counter per session.
- Ghostty, Kitty and VS Code tab-level jump.
- A WidgetKit widget.
