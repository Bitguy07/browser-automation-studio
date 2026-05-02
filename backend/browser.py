# ============================================================
# Browser Automation Studio — backend/browser.py
# M5: Real browser automation via browser-use 0.12.6
#
# Uses browser-use's own LLM wrappers (NOT langchain):
#   browser_use.llm.google.chat.ChatGoogle
#   browser_use.llm.groq.chat.ChatGroq
# ============================================================

from __future__ import annotations

import base64
import json
import logging
import os
import subprocess
import traceback
import urllib.request
from datetime import datetime, timezone

from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger("browser")

# Enable browser-use's own logger so we can see step details in FastAPI logs
logging.getLogger("browser_use").setLevel(logging.INFO)

COOKIES_DIR   = os.getenv("COOKIES_DIR", "/data/cookies")
DATA_DIR      = os.getenv("DATA_DIR",    "/data")
DOWNLOADS_DIR = os.path.join(DATA_DIR, "downloads")

GROQ_API_KEY   = os.getenv("GROQ_API_KEY",   "")
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY", "")
PRIMARY_LLM    = os.getenv("PRIMARY_LLM",    "gemini").lower()

GEMINI_MODEL = "gemini-2.5-flash-lite"
GROQ_MODEL   = "meta-llama/llama-4-scout-17b-16e-instruct"

# ── System message injected into every agent run ─────────────
EXTEND_SYSTEM_MESSAGE = """
## Critical Rules

### Task Completion
- NEVER call done() until the objective is FULLY completed and verified.
- Read the current page state before deciding you are done.
- If you extracted information, confirm it matches what was requested.
- Always state exactly what you found/did in the done() text.

### Navigation
- Always start tasks by navigating to the correct URL first.
- If a site requires login and no session exists, report: "Login required. Please log in via Manual Mode and save the session."
- If a popup, cookie consent, or age verification appears, dismiss it first.
- If navigation fails, try an alternative approach or a different URL.

### Tab Management
- If the task needs a different site than currently open, open a new tab.
- Close tabs you opened when the task is done to keep the browser clean.

### Information Extraction
- For research tasks, always extract the specific data requested (numbers, names, dates, prices).
- Do not summarize or approximate — provide exact values from the page.
- If a page has multiple sections, scroll down to find all relevant information.

### Language
- Accept tasks in any language including Hindi, Hinglish, or mixed phrasing.
- "I want to see X" means find and play/open X.
- "Show me X" means navigate to X and display it.

### Error Handling
- On CAPTCHA: first try to solve it by yourself if still any problem latter appear then stop and report and give explanation of the alternative way to resolve the issue."
- On rate limit: wait and retry.
- On 404 or blocked page: try an alternative URL or search engine.

### Verification Before Done
Before calling done(), verify:
1. The current page URL matches where you were supposed to go
2. The information you extracted is visible on screen
3. Any action you took (click, search, play) actually happened
"""


# ════════════════════════════════════════════════════════════════
# LLM factory
# ════════════════════════════════════════════════════════════════

def _make_gemini_llm():
    from browser_use.llm.google.chat import ChatGoogle
    if not GOOGLE_API_KEY:
        raise RuntimeError("GOOGLE_API_KEY not set")
    return ChatGoogle(
        model=GEMINI_MODEL,
        api_key=GOOGLE_API_KEY,
    )


def _make_groq_llm():
    from browser_use.llm.groq.chat import ChatGroq
    if not GROQ_API_KEY:
        raise RuntimeError("GROQ_API_KEY not set")
    return ChatGroq(
        model=GROQ_MODEL,
        api_key=GROQ_API_KEY,
    )


def _build_llms():
    """Returns (primary_llm, fallback_llm, use_vision)."""
    if PRIMARY_LLM == "gemini" and GOOGLE_API_KEY:
        try:
            primary  = _make_gemini_llm()
            fallback = _make_groq_llm() if GROQ_API_KEY else None
            return primary, fallback, "auto"
        except Exception as e:
            logger.warning(f"Gemini init failed ({e}), falling back to Groq")

    if GROQ_API_KEY:
        primary  = _make_groq_llm()
        fallback = _make_gemini_llm() if GOOGLE_API_KEY else None
        return primary, fallback, False

    raise RuntimeError(
        "No LLM available. Set GOOGLE_API_KEY or GROQ_API_KEY in .env"
    )


# ════════════════════════════════════════════════════════════════
# CDP / Screenshot
# ════════════════════════════════════════════════════════════════

def _get_cdp_page():
    with urllib.request.urlopen("http://localhost:9222/json", timeout=5) as r:
        pages = json.loads(r.read())
    page = next((p for p in pages if p.get("type") == "page"), None)
    if not page:
        raise RuntimeError("No Chrome page via CDP")
    return page


def _cdp_screenshot():
    import websocket as wsc
    page   = _get_cdp_page()
    ws_url = page.get("webSocketDebuggerUrl")
    if not ws_url:
        raise RuntimeError("No webSocketDebuggerUrl")
    ws = wsc.create_connection(ws_url, timeout=8)
    try:
        ws.send(json.dumps({
            "id": 1, "method": "Page.captureScreenshot",
            "params": {"format": "png", "quality": 85},
        }))
        result = json.loads(ws.recv())
        if "result" in result and "data" in result["result"]:
            return result["result"]["data"]
        raise RuntimeError(f"CDP error: {result}")
    finally:
        ws.close()


def _scrot_screenshot():
    tmppath = f"/tmp/scrot_{os.getpid()}.png"
    try:
        env = {**os.environ, "DISPLAY": ":99"}
        r   = subprocess.run(["scrot", tmppath], capture_output=True,
                             text=True, timeout=10, env=env)
        if r.returncode != 0:
            raise RuntimeError(f"scrot: {r.stderr.strip()}")
        with open(tmppath, "rb") as f:
            return base64.b64encode(f.read()).decode()
    finally:
        if os.path.exists(tmppath):
            os.unlink(tmppath)


async def take_screenshot():
    try:
        return _cdp_screenshot()
    except Exception as e:
        logger.warning(f"CDP screenshot failed ({e}), trying scrot")
        return _scrot_screenshot()


# ════════════════════════════════════════════════════════════════
# Session management
# ════════════════════════════════════════════════════════════════

async def save_session(name: str) -> str:
    from playwright.async_api import async_playwright
    os.makedirs(COOKIES_DIR, exist_ok=True)
    safe  = "".join(c for c in name if c.isalnum() or c in "-_")
    if not safe:
        raise ValueError("Invalid session name")
    fpath = os.path.join(COOKIES_DIR, f"{safe}.json")
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://localhost:9222")
        try:
            if not browser.contexts:
                raise RuntimeError("No browser context")
            await browser.contexts[0].storage_state(path=fpath)
        finally:
            await browser.close()
    logger.info(f"Session saved: {safe}")
    return fpath


async def load_session(name: str) -> int:
    from playwright.async_api import async_playwright
    safe  = "".join(c for c in name if c.isalnum() or c in "-_")
    fpath = os.path.join(COOKIES_DIR, f"{safe}.json")
    if not os.path.exists(fpath):
        raise FileNotFoundError(f"Session not found: {fpath}")
    with open(fpath) as f:
        state = json.load(f)
    cookies = state.get("cookies", [])
    if not cookies:
        return 0
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp("http://localhost:9222")
        try:
            if not browser.contexts:
                raise RuntimeError("No browser context")
            ctx = browser.contexts[0]
            await ctx.clear_cookies()
            await ctx.add_cookies(cookies)
        finally:
            await browser.close()
    logger.info(f"Session loaded: {safe} ({len(cookies)} cookies)")
    return len(cookies)


async def reset_browser() -> str:
    from playwright.async_api import async_playwright
    closed = 0
    try:
        async with async_playwright() as p:
            browser = await p.chromium.connect_over_cdp("http://localhost:9222")
            try:
                for ctx in browser.contexts:
                    for page in ctx.pages[1:]:
                        await page.close()
                        closed += 1
                    if ctx.pages:
                        await ctx.pages[0].goto("about:blank")
            finally:
                await browser.close()
    except Exception as e:
        logger.warning(f"Browser reset partial: {e}")
    return f"Browser reset complete. Closed {closed} extra tab(s)."


# ════════════════════════════════════════════════════════════════
# Main task runner
# ════════════════════════════════════════════════════════════════

async def run_task(
    objective: str,
    task_id: str,
    ws_broadcast,
    update_task_status,
    update_task_step,
) -> str:
    from browser_use import Agent, BrowserSession

    os.makedirs(DOWNLOADS_DIR, exist_ok=True)

    try:
        primary_llm, fallback_llm, use_vision = _build_llms()
    except RuntimeError as e:
        raise RuntimeError(f"LLM init failed: {e}")

    step_count = [0]
    MAX_STEPS  = 500   # increased from 30 — complex tasks need more steps

    async def on_step(browser_state_summary, agent_output, step_number: int):
        step_count[0] = step_number
        current_url   = ""
        action_desc   = "Processing..."
        try:
            if hasattr(browser_state_summary, "url"):
                current_url = browser_state_summary.url or ""
        except Exception:
            pass
        try:
            if hasattr(agent_output, "action") and agent_output.action:
                action_desc = str(agent_output.action)[:200]
            elif hasattr(agent_output, "current_state"):
                cs = agent_output.current_state
                if hasattr(cs, "thought") and cs.thought:
                    action_desc = str(cs.thought)[:200]
        except Exception:
            pass

        logger.info(f"[{task_id[:8]}] Step {step_number}: {action_desc[:80]} | {current_url}")

        progress = min(int((step_number / MAX_STEPS) * 90), 90)
        update_task_step(task_id, step_number, MAX_STEPS, progress)
        await ws_broadcast({
            "type":    "task_update",
            "task_id": task_id,
            "status":  "RUNNING",
            "message": f"Step {step_number}: {action_desc}",
            "data": {
                "step": step_number, "url": current_url,
                "action": action_desc, "progress": progress,
                "step_bubble": True,
            },
            "timestamp": datetime.now(timezone.utc).isoformat(),
        })

    browser_session = BrowserSession(
        cdp_url="http://localhost:9222",
        keep_alive=True,
        highlight_elements=True,
        viewport={"width": 1280, "height": 720},
        downloads_path=DOWNLOADS_DIR,
    )

    agent = Agent(
        task=objective,
        llm=primary_llm,
        browser=browser_session,
        use_vision=use_vision,
        fallback_llm=fallback_llm,
        max_failures=5,
        step_timeout=180,
        max_actions_per_step=5,
        generate_gif=False,
        register_new_step_callback=on_step,
        extend_system_message=EXTEND_SYSTEM_MESSAGE,  # ← professional instructions
    )

    logger.info(f"[{task_id[:8]}] Agent starting: {objective[:80]}")
    await ws_broadcast({
        "type": "task_update", "task_id": task_id, "status": "RUNNING",
        "message": f"Agent starting: {objective[:60]}",
        "data": {"progress": 2},
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })

    try:
        history = await agent.run(max_steps=MAX_STEPS)
    except Exception as e:
        logger.error(f"[{task_id[:8]}] Agent failed:\n{traceback.format_exc()}")
        raise RuntimeError(f"Agent execution error: {e}")

    result = ""
    try:
        if hasattr(history, "final_result"):
            result = history.final_result() or ""
        elif hasattr(history, "result"):
            result = str(history.result())
        else:
            result = str(history)
    except Exception:
        result = "Task completed (result extraction failed)"

    if not result or result.strip() in ("None", ""):
        result = f"Task completed after {step_count[0]} step(s)."

    logger.info(f"[{task_id[:8]}] Done — steps: {step_count[0]} | result: {result[:100]}")
    return result
