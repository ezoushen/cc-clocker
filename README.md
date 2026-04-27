# cc-clocker

Keeps Claude Code 5-hour AND 7-day subscription windows adjacent without gaps.

After whichever window resets next (5h or 7d), fires a tiny ephemeral Claude Code ping 30 seconds later. Pings use Haiku, no tools, no MCP, no session persistence — minimum quota burn.

## How it works

1. Walks `~/.claude/projects/**/*.jsonl` to find the start of the currently
   active **5h** window (Anthropic's rolling 5-hour quota) — for window N,
   start = first message with `ts >= start_{N-1} + 5h`. `reset_5h = start + 5h`.
2. The **7d** weekly window is NOT auto-detected — it resets on a server-side
   schedule (subscription anchor) that local jsonl can't reproduce. Export
   `CC_CLOCKER_NEXT_7D_RESET=<ISO8601 UTC>` to opt in.
3. Picks the **sooner** of the two resets as the next ping target.
4. Schedules a ping at `next_reset + 30s`.
5. Fires `claude -p "reply with: ok" --no-session-persistence ...` at that time.
6. Records the ping in `~/.local/share/cc-clocker/clocker.db` with `which_window` (5h/7d/manual).
7. Loops.

## Install

```sh
git clone <repo> cc-clocker
cd cc-clocker
./install.sh
```

## Usage

```sh
cc-clocker doctor       # verify deps + auth
cc-clocker tick         # fire one ping now
cc-clocker status       # show last + 5h + 7d + next fire
cc-clocker log 50       # last 50 pings
cc-clocker run          # foreground daemon
cc-clocker stop         # stop daemon
```

For background autostart, see `contrib/launchd/` (macOS) or `contrib/systemd/` (Linux).

## Auth

Uses your existing Claude Code OAuth subscription. Run `claude` once to log in. `--bare` is intentionally NOT used — it would force `ANTHROPIC_API_KEY` and bypass the subscription window we're trying to keep warm.

## Hooks

There is **no native flag** to suppress user-level hooks while keeping OAuth — `--bare` and `CLAUDE_CODE_SIMPLE=1` both flip auth to API-key mode, which would bypass the OAuth subscription window cc-clocker exists to keep warm. `--settings` is additive, not overriding. So every ping spawns a real `claude` subprocess and your user-level `SessionStart`, `UserPromptSubmit`, `Stop`, `SessionEnd` hooks **will** fire.

Mitigation: the daemon exports `CC_CLOCKER_PING=1` in the ping env. Gate every hook command on it as the first line:

```sh
[ -n "$CC_CLOCKER_PING" ] && exit 0
```

The ping passes `--tools ""`, so `PreToolUse` / `PostToolUse` / `SubagentStart` / `SubagentStop` never fire. `Notification` / `PermissionRequest` only fire on permission events, also out of scope here. Run `cc-clocker doctor` to see how many user hooks are configured and need gating.

## Files

- DB: `~/.local/share/cc-clocker/clocker.db`
- PID: `~/.local/state/cc-clocker/pid`
- Daemon logs: `/tmp/cc-clocker.{out,err}.log`

Override with `CC_CLOCKER_HOME`, `CC_CLOCKER_STATE`, `CC_CLAUDE_HOME`.

## Tests

```sh
make test       # bats
make lint       # shellcheck
```
