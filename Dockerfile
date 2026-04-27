# cc-clocker reference image.
#
# Goal: a single container where you can `claude /login` once (OAuth) and
# then run the cc-clocker daemon to keep your subscription windows warm.
#
# Persistent state lives in three mounted volumes:
#   /root/.claude                  -> Claude Code OAuth credentials
#   /root/.cc-clocker              -> rate-limits cache, app payload
#   /root/.local/share/cc-clocker  -> SQLite db (pings + accounts)
#
# Build:
#   docker build -t cc-clocker:latest .
#
# Run (interactive shell with cc-clocker on PATH):
#   docker run -it --rm \
#     -v cc-clocker-claude:/root/.claude \
#     -v cc-clocker-cache:/root/.cc-clocker \
#     -v cc-clocker-data:/root/.local/share/cc-clocker \
#     cc-clocker:latest

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Base toolchain + Node.js 22 (Claude Code CLI requirement) + Anthropic CLI.
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash ca-certificates curl git gnupg jq sqlite3 less \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g @anthropic-ai/claude-code \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# cc-clocker source lives under /opt so the user's home volume mounts don't
# shadow it.
WORKDIR /opt/cc-clocker
COPY bin /opt/cc-clocker/bin
COPY lib /opt/cc-clocker/lib
COPY contrib /opt/cc-clocker/contrib
COPY README.md install.sh Makefile /opt/cc-clocker/
RUN chmod +x /opt/cc-clocker/bin/cc-clocker /opt/cc-clocker/install.sh \
    && ln -sf /opt/cc-clocker/bin/cc-clocker /usr/local/bin/cc-clocker

# Pre-create the home dirs so first-run never trips on missing parents.
RUN mkdir -p /root/.claude /root/.cc-clocker /root/.local/share/cc-clocker /root/.local/state/cc-clocker

VOLUME ["/root/.claude", "/root/.cc-clocker", "/root/.local/share/cc-clocker"]

WORKDIR /root

CMD ["/bin/bash", "-l"]
