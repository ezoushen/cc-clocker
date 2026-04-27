# cc-clocker

Keeps Claude Code 5-hour AND 7-day subscription windows adjacent without gaps.

After whichever window resets next (5h or 7d), fires a tiny ephemeral Claude Code ping 30 seconds later. Pings use Haiku, no tools, no MCP, no session persistence — minimum quota burn.

## How it works

1. Scans `~/.claude/projects/**/*.jsonl` to find:
   - earliest message in last 5h → `reset_5h = start_5h + 5h`
   - earliest message in last 7d → `reset_7d = start_7d + 7d`
2. Picks the **sooner** reset as the next ping target.
3. Schedules a ping at `next_reset + 30s`.
4. Fires `claude -p "reply with: ok" --no-session-persistence ...` at that time.
5. Records the ping in `~/.local/share/cc-clocker/clocker.db` with `which_window` (5h/7d/manual).
6. Loops.

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

Each ping launches a real `claude` subprocess, so user-level hooks fire. The daemon exports `CC_CLOCKER_PING=1` in the ping env — gate noisy hooks on that variable to skip pings:

```sh
[ -n "$CC_CLOCKER_PING" ] && exit 0
```

`CLAUDE_CODE_SIMPLE` is intentionally NOT set, because doing so would force `ANTHROPIC_API_KEY` auth (same as `--bare`) and bypass the OAuth subscription window cc-clocker is meant to keep warm.

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
