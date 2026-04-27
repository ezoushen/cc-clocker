#!/usr/bin/env bash
# Silent statusline: discard stdin, emit nothing. Claude Code requires the
# statusLine.command to consume its JSON payload; we let cc-clocker
# statusline-tee tap the stream for rate_limits, and this tail just
# absorbs whatever's left so claude doesn't render junk.
cat >/dev/null
