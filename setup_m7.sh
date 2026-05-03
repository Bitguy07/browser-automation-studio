#!/usr/bin/env bash
# ============================================================
# Browser Automation Studio — setup_m7.sh
# Module 7: Integration — Chrome Profile Volume Mount
#
# What this script does:
#   1. Creates ./data/chrome-profile/ on the host
#   2. Adds the chrome-profile volume line to docker-compose.yml
#   3. Adds the SingletonLock cleanup block to scripts/start.sh
#   4. Fixes the telegram-bot supervisord stanza if still on M5 values
#   5. Rebuilds the Docker image
#   6. Restarts the container
#
# Run from the project root. Container should be stopped first.
# ============================================================

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${BOLD}[M7]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
note()  { echo -e "${CYAN}[NOTE]${NC} $*"; }

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  Browser Automation Studio — M7 Setup            ║"
echo "║  Chrome Profile Volume Mount                     ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Preflight checks ─────────────────────────────────────────
[ -f "docker-compose.yml" ]   || fail "docker-compose.yml not found. Run from project root."
[ -f "supervisord.conf" ]     || fail "supervisord.conf not found."
[ -f "scripts/start.sh" ]     || fail "scripts/start.sh not found."
[ -f "Dockerfile" ]           || fail "Dockerfile not found."
ok "Project root confirmed."

# ── Step 1: Stop container if running ─────────────────────────
info "Stopping any running container..."
docker compose down 2>/dev/null || true
ok "Container stopped."

# ── Step 2: Create chrome-profile directory on host ──────────
info "Creating data/chrome-profile/ on host..."
mkdir -p data/chrome-profile
ok "data/chrome-profile/ ready."

# ── Step 3: Patch docker-compose.yml ─────────────────────────
info "Patching docker-compose.yml (chrome-profile volume)..."
cp docker-compose.yml docker-compose.yml.bak
ok "Backed up → docker-compose.yml.bak"

python3 - <<'PYEOF'
import sys

with open("docker-compose.yml", "r") as f:
    content = f.read()

# Already patched?
if "chrome-profile" in content:
    print("docker-compose.yml already has chrome-profile volume — skipping.")
    sys.exit(0)

# Find the ./data:/data line and add the chrome-profile line after it
old = "      - ./data:/data"
new = (
    "      - ./data:/data\n"
    "      - ./data/chrome-profile:/root/.chrome-data   # M7: persist Chrome login sessions"
)

if old not in content:
    print("ERROR: Could not find '- ./data:/data' in docker-compose.yml.")
    print("Please add the following line manually under 'volumes:' in docker-compose.yml:")
    print("      - ./data/chrome-profile:/root/.chrome-data")
    sys.exit(1)

content = content.replace(old, new, 1)

with open("docker-compose.yml", "w") as f:
    f.write(content)

print("docker-compose.yml patched — chrome-profile volume added.")
PYEOF

ok "docker-compose.yml updated."

# ── Step 4: Patch scripts/start.sh ───────────────────────────
info "Patching scripts/start.sh (Chrome lock file cleanup)..."
cp scripts/start.sh scripts/start.sh.bak
ok "Backed up → scripts/start.sh.bak"

python3 - <<'PYEOF'
import sys

with open("scripts/start.sh", "r") as f:
    content = f.read()

# Already patched?
if "SingletonLock" in content:
    print("scripts/start.sh already has SingletonLock cleanup — skipping.")
    sys.exit(0)

# Insert the cleanup block just before 'exec /usr/bin/supervisord'
cleanup_block = """
# ── Clean Chrome lock files from previous run ─────────────────
# When /root/.chrome-data is volume-mounted, Chrome leaves behind
# SingletonLock / SingletonSocket on shutdown. Chrome refuses to
# start if it finds these stale files. Delete them before Chrome
# starts so it launches cleanly with the persisted profile.
echo "[start.sh] Cleaning Chrome lock files from previous run..."
rm -f /root/.chrome-data/SingletonLock
rm -f /root/.chrome-data/SingletonSocket
rm -f /root/.chrome-data/SingletonCookie
rm -f /root/.chrome-data/Default/Cookies-journal
rm -f /root/.chrome-data/Default/.org.chromium.Chromium.*
echo "[start.sh] Chrome lock cleanup done."

"""

target = "exec /usr/bin/supervisord"
if target not in content:
    print("ERROR: Could not find 'exec /usr/bin/supervisord' in scripts/start.sh.")
    print("Please add the SingletonLock cleanup block manually before the supervisord line.")
    sys.exit(1)

content = content.replace(target, cleanup_block + target, 1)

with open("scripts/start.sh", "w") as f:
    f.write(content)

print("scripts/start.sh patched — Chrome lock cleanup block added.")
PYEOF

chmod +x scripts/start.sh
ok "scripts/start.sh updated and executable."

# ── Step 5: Fix telegram-bot stanza if on M5 stub values ─────
info "Checking supervisord.conf telegram-bot stanza..."

python3 - <<'PYEOF'
import sys

with open("supervisord.conf", "r") as f:
    content = f.read()

changed = False

# Fix autorestart=false in telegram-bot block only
if "[program:telegram-bot]" in content:
    # Only patch the telegram-bot block, not globally
    lines = content.split("\n")
    in_telegram = False
    new_lines = []
    for line in lines:
        if line.strip() == "[program:telegram-bot]":
            in_telegram = True
        elif line.strip().startswith("[program:") and in_telegram:
            in_telegram = False

        if in_telegram:
            if "autorestart=false" in line:
                line = line.replace("autorestart=false", "autorestart=true")
                changed = True
            if "startsecs=0" in line and "startretries" not in line:
                line = line.replace("startsecs=0", "startsecs=10")
                changed = True

        new_lines.append(line)

    if changed:
        # Also ensure startretries=10 is present
        result = "\n".join(new_lines)
        if "startretries" not in result.split("[program:telegram-bot]")[1].split("[program:")[0]:
            result = result.replace(
                "[program:telegram-bot]\n",
                "[program:telegram-bot]\n# M6: corrected\n"
            )
        with open("supervisord.conf", "w") as f:
            f.write(result)
        print("Fixed telegram-bot stanza: autorestart=true, startsecs=10.")
    else:
        print("telegram-bot stanza already correct — no change needed.")
else:
    print("No [program:telegram-bot] found — skipping.")
PYEOF

ok "supervisord.conf checked."

# ── Step 6: Add chrome-profile to .gitignore ─────────────────
info "Updating .gitignore..."
if [ -f ".gitignore" ]; then
    if ! grep -q "chrome-profile" .gitignore; then
        echo "" >> .gitignore
        echo "# Chrome persistent profile (contains login sessions — treat as secrets)" >> .gitignore
        echo "data/chrome-profile/" >> .gitignore
        ok "Added data/chrome-profile/ to .gitignore."
    else
        ok "data/chrome-profile/ already in .gitignore."
    fi
else
    echo "data/chrome-profile/" > .gitignore
    ok "Created .gitignore with data/chrome-profile/."
fi

# ── Step 7: Rebuild Docker image ─────────────────────────────
info "Rebuilding Docker image..."
docker compose build
ok "Image rebuilt."

# ── Step 8: Start container ───────────────────────────────────
info "Starting container..."
docker compose up -d
ok "Container started in background."

# ── Step 9: Wait and verify ──────────────────────────────────
info "Waiting 30 s for all services to start..."
sleep 30

CONTAINER=$(docker ps --filter "name=browser" -q | head -1)
if [ -z "$CONTAINER" ]; then
    warn "Could not find running container. Check: docker ps"
    exit 1
fi

echo ""
info "Supervisor status:"
docker exec "$CONTAINER" supervisorctl status || true

echo ""
info "Verifying Chrome profile volume mount..."
docker exec "$CONTAINER" ls /root/.chrome-data/ 2>/dev/null \
    && ok "Chrome profile directory accessible inside container." \
    || warn "Chrome profile directory not visible yet — Chrome may still be starting."

echo ""
info "Health check:"
curl -s http://localhost:7860/health 2>/dev/null | python3 -m json.tool 2>/dev/null \
    || echo "(health endpoint not ready yet — wait a few more seconds)"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  M7 Setup Complete                               ║"
echo "║                                                  ║"
echo "║  Chrome login sessions now persist on disk.      ║"
echo "║                                                  ║"
echo "║  First-time login (do this once per site):       ║"
echo "║    1. Open http://localhost:7860                 ║"
echo "║    2. Log into any site via Chrome panel         ║"
echo "║    3. docker compose down && docker compose up   ║"
echo "║    4. Chrome is still logged in — automatically  ║"
echo "║                                                  ║"
echo "║  Saved to: ./data/chrome-profile/ on your host   ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
