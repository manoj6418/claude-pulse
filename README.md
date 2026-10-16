# Claude Pulse

A macOS menu bar app for Claude Code. One glance shows:

- **Plan usage**: 5-hour and 7-day limits, local reset time, countdown, a pace marker (how much of the window has passed), and a burn-rate projection ("at this pace you hit 100% at 4:10 PM").
- **Every running session**: name, git branch, model, effort, context used (tokens / window and %), API-equivalent cost, lines changed, last activity.
- **What each session is doing now**: "Running go test ./... · 42s", "Editing edd.go", "Thinking · 3m", and a warning when a session has been quiet for 10+ minutes. Also each session's share of the last hour's spend, an "auto-compact soon" warning near the end of the context window, and how many times it compacted.
- **Is it OK, and what did it leave behind**: per session, git state ("3 uncommitted", "2 unpushed", "clean"), prompt cache ("cache 97% · warm 41m", or "cold" once it expired and the next message costs more), background agents running, a red line when the last command failed ("Failed: go test · Exit code 1"), and the last 10 steps (click the arrow on a row).
- **Labels**: right-click a session to pin it to the top, rename it or give it a colour.
- **More alerts**: a command still running after 15 minutes, a session that closed with uncommitted or unpushed work, a daily spend budget (80% and 100%), and daily or Friday summaries. Alerts stay quiet while that session's terminal is the app in front.
- **New session**: the + button starts `claude` in a recent project folder, in Terminal or iTerm.
- **Online (each can be turned off)**: a banner when status.claude.com reports a problem, and a note when a newer Claude Pulse release is on GitHub.
- **History and today**: a small chart of usage in each limit card, and a **Today** line with cost and tokens, split by model and project.
- **Phone alerts** (optional, off by default): "finished" and "needs permission" also go to your phone through [ntfy](https://ntfy.sh). By default they carry only the session name and what happened, never the command or reply text.
- **Keyboard**: ⌃⌥C opens the panel from anywhere; ⌘↩ allows and ⌘⌫ denies the top permission prompt.
- **Tidy list**: group sessions by project, hide sessions idle for 30+ minutes, and a two-bar menu bar icon (5-hour on top, 7-day below).
- **Who needs you**: sessions waiting for a permission or for your input move to the top, the menu bar icon changes, and you get a notification.
- **Answer permission prompts without switching**: when a session asks to run a tool, its card shows the command with **Allow / Always allow / Deny**, and so does the notification. The terminal prompt stays open too; whichever you answer first wins. Plan approvals and Claude's questions stay in the terminal.
- **Jump to the session**: click a row to bring its terminal to the front. Terminal.app and iTerm2 select the exact tab; other terminals just come forward. Right-click a row to copy the resume command, open the folder, or reveal the transcript.
- **Alerts** (on by default): a session finished its turn (with how long it worked and the first line of its reply; turns under 30s are skipped), a session needs permission, and plan usage reaching 90%. Off by default: waiting for your input, and context almost full. A **Recent** list in the panel keeps the last few events. Clicking a session's notification jumps to its terminal. Every notification sent is listed in `~/Library/Application Support/ClaudePulse/notifications.log`.

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
- It adds a `ClaudePulse --hook` command to UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, Notification, Stop, PreCompact, SessionEnd, SubagentStart and SubagentStop (each run takes about 30 ms), and to PermissionRequest, where it waits for your answer from the panel for up to 10 minutes. Allow needs an unlocked Mac.
- It saves a backup first (`settings.json.claudepulse-backup-<time>`). **Disconnect** removes only Pulse's entries and restores your old status line.

Running sessions pick up the change after a restart. The limits appear after the next reply in any connected session, and only on Pro/Max plans; Claude Code does not report them otherwise.

Network calls are limited to the Claude status page and GitHub's latest-release check (both can be turned off in Settings → Online) and phone alerts if you turn them on. No Keychain access, no undocumented APIs. Snapshots live in `~/Library/Application Support/ClaudePulse/`.

## Command line

```sh
ClaudePulse --status | --connect | --disconnect
ClaudePulse --snapshot out.png [--dark] [--settings]   # render the panel with live data
ClaudePulse --toggle-panel | --test-notification | --phone-test
```

The binary is at `~/Applications/ClaudePulse.app/Contents/MacOS/ClaudePulse`.

## Ideas for later

- Per-model weekly limits, once Claude Code exposes them in the status line.
- Answer permission prompts (Allow/Deny) from the menu bar through a PermissionRequest hook.
- Compaction counter per session.
- Ghostty, Kitty and VS Code tab-level jump.
- A WidgetKit widget.
