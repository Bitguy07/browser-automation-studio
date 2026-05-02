#!/usr/bin/env bash
# ============================================================
# Browser Automation Studio — setup_m6.sh
# Module 6: Telegram Bot Interface
#
# Run this from the project root (same directory as Dockerfile).
# Prerequisites: M1–M5 complete, container built and running.
# ============================================================

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${BOLD}[M6]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  Browser Automation Studio — M6 Setup        ║"
echo "║  Telegram Bot Interface                      ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Step 1: Verify .env has Telegram vars ─────────────────────
info "Checking .env for Telegram variables…"

if [ ! -f ".env" ]; then
    fail ".env not found. Copy .env.example to .env and fill in values."
fi

BOT_TOKEN=$(grep -E '^TELEGRAM_BOT_TOKEN=' .env | cut -d= -f2- | tr -d '"' | tr -d "'")
CHAT_ID=$(grep -E '^TELEGRAM_CHAT_ID=' .env | cut -d= -f2- | tr -d '"' | tr -d "'")

if [ -z "$BOT_TOKEN" ] || [ "$BOT_TOKEN" = "your_token_here" ]; then
    warn "TELEGRAM_BOT_TOKEN is not set in .env"
    echo ""
    echo "  1. Open Telegram → search @BotFather → send /newbot"
    echo "  2. Follow the prompts → copy the token (looks like 123456:ABC...)"
    echo "  3. Add to .env:  TELEGRAM_BOT_TOKEN=<your_token>"
    echo ""
    fail "Set TELEGRAM_BOT_TOKEN and re-run."
fi
ok "TELEGRAM_BOT_TOKEN found."

if [ -z "$CHAT_ID" ] || [ "$CHAT_ID" = "0" ]; then
    warn "TELEGRAM_CHAT_ID is not set in .env"
    echo ""
    echo "  1. Open Telegram → search @userinfobot → send /start"
    echo "  2. It replies with your numeric user ID"
    echo "  3. Add to .env:  TELEGRAM_CHAT_ID=<your_id>"
    echo ""
    fail "Set TELEGRAM_CHAT_ID and re-run."
fi
ok "TELEGRAM_CHAT_ID found: $CHAT_ID"

# ── Step 2: Copy telegram_bot.py into place ──────────────────
info "Installing backend/telegram_bot.py…"

# Backup existing stub
if [ -f "backend/telegram_bot.py" ]; then
    cp backend/telegram_bot.py backend/telegram_bot.py.bak
    ok "Existing file backed up → backend/telegram_bot.py.bak"
fi

# The real bot file should already be in this directory after running the
# guide instructions. If running from the project root after placing the
# file, this is a no-op.  Otherwise point to wherever you saved it.
if [ -f "telegram_bot_m6.py" ]; then
    cp telegram_bot_m6.py backend/telegram_bot.py
    ok "Copied telegram_bot_m6.py → backend/telegram_bot.py"
else
    ok "backend/telegram_bot.py already in place (no separate source file found)."
fi

# ── Step 3: Patch supervisord.conf telegram stanza ───────────
info "Patching supervisord.conf (telegram-bot stanza)…"

CONF="supervisord.conf"
cp "$CONF" "${CONF}.bak"
ok "supervisord.conf backed up → ${CONF}.bak"

# Replace autorestart=false with autorestart=true and add startretries + startsecs=10
python3 - <<'PYEOF'
import re, sys

with open("supervisord.conf", "r") as f:
    content = f.read()

# Find the telegram-bot block and update it
old_block = re.search(
    r'\[program:telegram-bot\].*?(?=\n\[|\Z)',
    content, re.DOTALL
)
if not old_block:
    print("WARN: [program:telegram-bot] block not found in supervisord.conf — please patch manually.")
    sys.exit(0)

new_block = """[program:telegram-bot]
command=/opt/venv/bin/python /app/backend/telegram_bot.py
directory=/app
autostart=true
autorestart=true
startsecs=10
startretries=10
priority=600
stdout_logfile=/var/log/supervisor/telegram.log
stderr_logfile=/var/log/supervisor/telegram.err
stdout_logfile_maxbytes=10MB
stderr_logfile_maxbytes=10MB
environment=PYTHONPATH="/app"
"""

content = content[:old_block.start()] + new_block + content[old_block.end():]
with open("supervisord.conf", "w") as f:
    f.write(content)
print("supervisord.conf patched successfully.")
PYEOF

ok "supervisord.conf updated."

# ── Step 4: Verify python-telegram-bot is in requirements.txt ─
info "Checking requirements.txt…"

if grep -q "python-telegram-bot" requirements.txt; then
    ok "python-telegram-bot already in requirements.txt."
else
    echo "python-telegram-bot>=21.2" >> requirements.txt
    ok "Added python-telegram-bot>=21.2 to requirements.txt."
fi

# ── Step 5: Rebuild Docker image ─────────────────────────────
info "Rebuilding Docker image (this installs any new pip packages)…"
docker compose build
ok "Docker image rebuilt."

# ── Step 6: Restart container ────────────────────────────────
info "Restarting container…"
docker compose down
docker compose up
ok "Container restarted."

# ── Step 7: Wait and check bot status ─────────────────────────
info "Waiting 20 s for services to start…"
sleep 20

CONTAINER=$(docker ps --filter "name=browser" -q | head -1)
if [ -z "$CONTAINER" ]; then
    warn "Could not find running container. Check: docker ps"
else
    echo ""
    info "Telegram bot supervisor status:"
    docker exec "$CONTAINER" supervisorctl status telegram-bot || true
    echo ""
    info "Last 20 lines of telegram.log:"
    docker exec "$CONTAINER" tail -20 /var/log/supervisor/telegram.log 2>/dev/null || true
fi

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  M6 Setup Complete                           ║"
echo "║                                              ║"
echo "║  Test your bot:                              ║"
echo "║    1. Open Telegram                          ║"
echo "║    2. Find your bot by username              ║"
echo "║    3. Send /help                             ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
