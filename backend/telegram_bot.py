# ============================================================
# Browser Automation Studio — backend/telegram_bot.py
# M6: Telegram Bot Interface
#
# Runs as a standalone async process (supervisord managed).
# All browser actions go through FastAPI REST endpoints —
# this file NEVER imports browser.py or tasks.py directly.
#
# Required env vars:
#   TELEGRAM_BOT_TOKEN  — from @BotFather
#   TELEGRAM_CHAT_ID    — your personal Telegram user ID
#   APP_PASSWORD        — same password used for web UI login
#   APP_PORT            — defaults to 7860
# ============================================================

import asyncio
import base64
import io
import logging
import os
import sys

import httpx
from dotenv import load_dotenv
from telegram import Update
from telegram.constants import ParseMode
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

load_dotenv()

# ── Config ────────────────────────────────────────────────────
BOT_TOKEN   = os.getenv("TELEGRAM_BOT_TOKEN", "")
ALLOWED_ID  = int(os.getenv("TELEGRAM_CHAT_ID", "0"))
APP_PASSWORD = os.getenv("APP_PASSWORD", "admin")
BASE_URL    = f"http://localhost:{os.getenv('APP_PORT', '7860')}"

TASK_POLL_INTERVAL = 3      # seconds between status polls
TASK_TIMEOUT       = 600    # 10 minutes

# ── Logging ───────────────────────────────────────────────────
logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s [TelegramBot] %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("telegram_bot")

# ── JWT token cache (refreshed on startup / 401) ─────────────
_jwt_token: str = ""


async def _get_jwt() -> str:
    """Obtain a fresh JWT from FastAPI. Retries until FastAPI is up."""
    global _jwt_token
    for attempt in range(30):
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                r = await client.post(
                    f"{BASE_URL}/api/auth/login",
                    json={"password": APP_PASSWORD},
                )
                if r.status_code == 200:
                    _jwt_token = r.json()["access_token"]
                    log.info("JWT obtained from FastAPI.")
                    return _jwt_token
                log.warning("Login returned %s — retrying…", r.status_code)
        except Exception as e:
            log.warning("FastAPI not ready yet (%s) — waiting 5 s…", e)
        await asyncio.sleep(5)
    raise RuntimeError("Could not obtain JWT after 30 attempts. Is FastAPI running?")


def _headers() -> dict:
    return {"Authorization": f"Bearer {_jwt_token}"}


async def _api(method: str, path: str, **kwargs) -> httpx.Response:
    """Call FastAPI with auto-refresh on 401."""
    global _jwt_token
    async with httpx.AsyncClient(timeout=30) as client:
        r = await getattr(client, method)(
            f"{BASE_URL}{path}", headers=_headers(), **kwargs
        )
        if r.status_code == 401:
            log.info("JWT expired — refreshing…")
            await _get_jwt()
            r = await getattr(client, method)(
                f"{BASE_URL}{path}", headers=_headers(), **kwargs
            )
        return r


# ── Auth guard ────────────────────────────────────────────────
def authorized(update: Update) -> bool:
    uid = update.effective_user.id if update.effective_user else None
    return uid == ALLOWED_ID


async def deny(update: Update) -> None:
    log.warning("Unauthorized access attempt from user_id=%s", update.effective_user.id)
    await update.message.reply_text("⛔ Unauthorized.")


# ── /start  /help ─────────────────────────────────────────────
HELP_TEXT = """🤖 *Browser Automation Studio*

*Task commands*
`/task <objective>` — run any automation task
`/video <topic>` — run a video‑pipeline task
`/status` — current mode + last task summary

*Browser commands*
`/screenshot` — snapshot of Chrome right now
`/reset` — close stale tabs, navigate to blank

*Session commands*
`/session save <name>` — save Chrome login session
`/session load <name>` — restore saved session
`/session list` — list saved sessions

*System*
`/mode auto|manual` — switch operating mode
`/help` — show this message
"""


async def cmd_start(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not authorized(update):
        return await deny(update)
    await update.message.reply_text(HELP_TEXT, parse_mode=ParseMode.MARKDOWN)


async def cmd_help(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not authorized(update):
        return await deny(update)
    await update.message.reply_text(HELP_TEXT, parse_mode=ParseMode.MARKDOWN)


# ── Task submission + polling ─────────────────────────────────
async def _submit_and_poll(update: Update, objective: str) -> None:
    """Submit a task to FastAPI, poll for completion, edit the status message."""
    # Submit
    r = await _api("post", "/api/task/submit", json={"objective": objective, "mode": "auto"})
    if r.status_code != 200:
        await update.message.reply_text(f"❌ Submit failed: {r.text[:300]}")
        return

    task_id = r.json().get("id") or r.json().get("task_id")
    short   = task_id[:8]

    status_msg = await update.message.reply_text(
        f"⚙️ Task `{short}` started…\n_{objective[:80]}_",
        parse_mode=ParseMode.MARKDOWN,
    )

    # Poll
    elapsed = 0
    last_step = ""

    while elapsed < TASK_TIMEOUT:
        await asyncio.sleep(TASK_POLL_INTERVAL)
        elapsed += TASK_POLL_INTERVAL

        try:
            r2 = await _api("get", f"/api/task/{task_id}/status")
        except Exception as e:
            log.warning("Poll error: %s", e)
            continue

        if r2.status_code != 200:
            continue

        data   = r2.json()
        status = data.get("status", "")
        steps  = data.get("steps_done", 0)
        step_label = f"  _(step {steps})_" if steps else ""

        if status == "COMPLETED":
            result = data.get("result") or "Done."
            # Telegram message limit is 4096 chars
            truncated = result[:3800] if len(result) > 3800 else result
            await status_msg.edit_text(
                f"✅ Task `{short}` completed{step_label}\n\n{truncated}",
                parse_mode=ParseMode.MARKDOWN,
            )
            return

        if status == "FAILED":
            error = data.get("error") or "Unknown error."
            await status_msg.edit_text(
                f"❌ Task `{short}` failed\n_{error[:400]}_",
                parse_mode=ParseMode.MARKDOWN,
            )
            return

        if status == "CANCELLED":
            await status_msg.edit_text(f"🚫 Task `{short}` was cancelled.")
            return

        # Still RUNNING or PENDING — update in-place if step changed
        new_step = f"step {steps}" if steps else "pending"
        if new_step != last_step:
            last_step = new_step
            try:
                await status_msg.edit_text(
                    f"⚙️ Task `{short}` running… ({new_step})\n_{objective[:60]}_",
                    parse_mode=ParseMode.MARKDOWN,
                )
            except Exception:
                pass  # edit may fail if text hasn't changed — harmless

    # Timeout
    await status_msg.edit_text(
        f"⏳ Task `{short}` is taking a long time.\n"
        f"Check the web UI at {BASE_URL} for live progress."
    )


async def cmd_task(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not authorized(update):
        return await deny(update)
    objective = " ".join(ctx.args).strip() if ctx.args else ""
    if not objective:
        await update.message.reply_text("Usage: `/task <objective>`", parse_mode=ParseMode.MARKDOWN)
        return
    await _submit_and_poll(update, objective)


async def cmd_video(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not authorized(update):
        return await deny(update)
    topic = " ".join(ctx.args).strip() if ctx.args else ""
    if not topic:
        await update.message.reply_text("Usage: `/video <topic>`", parse_mode=ParseMode.MARKDOWN)
        return
    objective = (
        f"Search YouTube for videos about: {topic}. "
        f"Find the top 3 results, collect their titles, channel names, and view counts. "
        f"Return a formatted summary."
    )
    await _submit_and_poll(update, objective)


# ── /status ───────────────────────────────────────────────────
async def cmd_status(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not authorized(update):
        return await deny(update)

    try:
        r_mode  = await _api("get", "/api/mode")
        r_tasks = await _api("get", "/api/task/list")
    except Exception as e:
        await update.message.reply_text(f"❌ Status fetch failed: {e}")
        return

    mode = r_mode.json().get("mode", "UNKNOWN") if r_mode.status_code == 200 else "?"

    lines = [f"*Mode:* `{mode}`\n"]

    if r_tasks.status_code == 200:
        tasks = r_tasks.json().get("tasks", [])
        if tasks:
            recent = tasks[:3]  # already sorted desc by API
            lines.append("*Recent tasks:*")
            for t in recent:
                emoji = {
                    "COMPLETED": "✅", "FAILED": "❌",
                    "RUNNING": "⚙️", "PENDING": "⏳", "CANCELLED": "🚫",
                }.get(t.get("status", ""), "❓")
                obj = (t.get("objective") or "")[:50]
                lines.append(f"{emoji} `{t['id'][:8]}` — {obj}")
        else:
            lines.append("No tasks yet.")
    else:
        lines.append("_(could not fetch task list)_")

    await update.message.reply_text("\n".join(lines), parse_mode=ParseMode.MARKDOWN)


# ── /screenshot ───────────────────────────────────────────────
async def cmd_screenshot(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not authorized(update):
        return await deny(update)

    await update.message.reply_text("📸 Capturing…")

    try:
        r = await _api("post", "/api/browser/screenshot")
    except Exception as e:
        await update.message.reply_text(f"❌ Screenshot failed: {e}")
        return

    if r.status_code != 200:
        await update.message.reply_text(f"❌ API error {r.status_code}: {r.text[:200]}")
        return

    b64 = r.json().get("screenshot", "")
    if not b64:
        await update.message.reply_text("❌ Empty screenshot returned.")
        return

    img_bytes = base64.b64decode(b64)
    buf = io.BytesIO(img_bytes)
    buf.name = "screenshot.png"
    await update.message.reply_photo(photo=buf, caption="📸 Chrome screenshot")


# ── /reset ────────────────────────────────────────────────────
async def cmd_reset(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not authorized(update):
        return await deny(update)

    await update.message.reply_text("🔄 Resetting browser…")
    try:
        r = await _api("post", "/api/browser/reset")
        msg = r.json().get("message", "Reset done.") if r.status_code == 200 else f"Error {r.status_code}"
        await update.message.reply_text(f"✅ {msg}")
    except Exception as e:
        await update.message.reply_text(f"❌ Reset failed: {e}")


# ── /session ─────────────────────────────────────────────────
async def cmd_session(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not authorized(update):
        return await deny(update)

    args = ctx.args or []
    subcmd = args[0].lower() if args else ""

    if subcmd == "save":
        name = args[1] if len(args) > 1 else ""
        if not name:
            await update.message.reply_text("Usage: `/session save <name>`", parse_mode=ParseMode.MARKDOWN)
            return
        r = await _api("post", "/api/session/save", json={"name": name})
        if r.status_code == 200:
            data = r.json()
            size_kb = round(data.get("size_bytes", 0) / 1024, 1)
            await update.message.reply_text(f"✅ Session `{name}` saved ({size_kb} KB)", parse_mode=ParseMode.MARKDOWN)
        else:
            await update.message.reply_text(f"❌ Save failed: {r.text[:200]}")

    elif subcmd == "load":
        name = args[1] if len(args) > 1 else ""
        if not name:
            await update.message.reply_text("Usage: `/session load <name>`", parse_mode=ParseMode.MARKDOWN)
            return
        r = await _api("post", f"/api/session/load/{name}")
        if r.status_code == 200:
            count = r.json().get("cookies_count", "?")
            await update.message.reply_text(f"✅ Session `{name}` loaded ({count} cookies)", parse_mode=ParseMode.MARKDOWN)
        elif r.status_code == 404:
            await update.message.reply_text(f"❌ No session named `{name}` found.", parse_mode=ParseMode.MARKDOWN)
        else:
            await update.message.reply_text(f"❌ Load failed: {r.text[:200]}")

    elif subcmd == "list":
        r = await _api("get", "/api/session/list")
        if r.status_code != 200:
            await update.message.reply_text(f"❌ List failed: {r.text[:200]}")
            return
        sessions = r.json().get("sessions", [])
        if not sessions:
            await update.message.reply_text("No sessions saved yet.")
            return
        lines = ["*Saved sessions:*"]
        for s in sessions:
            size_kb = round(s.get("size_bytes", 0) / 1024, 1)
            lines.append(f"• `{s['name']}` — {size_kb} KB")
        await update.message.reply_text("\n".join(lines), parse_mode=ParseMode.MARKDOWN)

    else:
        await update.message.reply_text(
            "Usage:\n`/session save <name>`\n`/session load <name>`\n`/session list`",
            parse_mode=ParseMode.MARKDOWN,
        )


# ── /mode ─────────────────────────────────────────────────────
async def cmd_mode(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not authorized(update):
        return await deny(update)

    mode = (ctx.args[0] if ctx.args else "").upper()
    if mode not in ("AUTO", "MANUAL", "IDLE", "AUTONOMOUS"):
        await update.message.reply_text(
            "Usage: `/mode auto|manual|idle`", parse_mode=ParseMode.MARKDOWN
        )
        return

    # Map shorthand
    if mode == "AUTO":
        mode = "AUTONOMOUS"

    r = await _api("post", "/api/mode/switch", json={"mode": mode})
    if r.status_code == 200:
        new_mode = r.json().get("mode", mode)
        await update.message.reply_text(f"✅ Mode → `{new_mode}`", parse_mode=ParseMode.MARKDOWN)
    else:
        await update.message.reply_text(f"❌ Mode switch failed: {r.text[:200]}")


# ── Unknown message (non-command text) ───────────────────────
async def handle_text(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not authorized(update):
        return await deny(update)
    await update.message.reply_text(
        "Use /help to see available commands.",
        parse_mode=ParseMode.MARKDOWN,
    )


# ── Error handler ─────────────────────────────────────────────
async def error_handler(update: object, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    log.error("Unhandled exception: %s", ctx.error, exc_info=ctx.error)


# ── Main ──────────────────────────────────────────────────────
#
# PTB 20+ IMPORTANT:
#   Application.run_polling() creates and owns its own event loop.
#   You must NOT call it inside asyncio.run() — that creates a
#   nested-loop conflict and PTB exits cleanly with code 0, no error.
#
#   Correct pattern:
#     1. Do any async pre-work (JWT fetch) in a separate asyncio.run() call.
#     2. Build the Application synchronously.
#     3. Call app.run_polling() directly (blocking, not awaited).

def main() -> None:
    if not BOT_TOKEN:
        log.warning("TELEGRAM_BOT_TOKEN is not set. Bot disabled — exiting cleanly.")
        sys.exit(0)

    if ALLOWED_ID == 0:
        log.warning("TELEGRAM_CHAT_ID is not set — ALL users will be denied!")

    # Step 1: obtain JWT (async pre-work) in its own clean event loop
    log.info("Waiting for FastAPI to be ready before obtaining JWT…")
    asyncio.run(_get_jwt())

    # Step 2: build the PTB Application synchronously
    log.info("Building Telegram application…")
    app = (
        Application.builder()
        .token(BOT_TOKEN)
        .connect_timeout(30)
        .read_timeout(30)
        .write_timeout(30)
        .build()
    )

    # Register handlers
    app.add_handler(CommandHandler("start",      cmd_start))
    app.add_handler(CommandHandler("help",       cmd_help))
    app.add_handler(CommandHandler("task",       cmd_task))
    app.add_handler(CommandHandler("video",      cmd_video))
    app.add_handler(CommandHandler("status",     cmd_status))
    app.add_handler(CommandHandler("screenshot", cmd_screenshot))
    app.add_handler(CommandHandler("reset",      cmd_reset))
    app.add_handler(CommandHandler("session",    cmd_session))
    app.add_handler(CommandHandler("mode",       cmd_mode))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    app.add_error_handler(error_handler)

    # Step 3: PTB owns the event loop from here — call synchronously, NOT awaited
    log.info("Telegram bot starting (polling). Allowed user ID: %s", ALLOWED_ID)
    app.run_polling(
        allowed_updates=Update.ALL_TYPES,
        drop_pending_updates=True,   # skip messages sent while bot was offline
    )


if __name__ == "__main__":
    main()
