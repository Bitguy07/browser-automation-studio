---
title: Browser Automation Studio
emoji: 🤖
colorFrom: purple
colorTo: pink
sdk: docker
pinned: false
app_port: 7860
startup_duration_timeout: 1h
---

# Browser Automation Studio

A self-hosted AI browser automation platform running on Hugging Face Spaces.

Control a real Chrome browser using natural language from a web UI or Telegram.

**Default AI**: Gemini 2.5 Flash Lite / Groq llama-4-scout (API-based, starts in seconds)  
**Optional local AI**: Qwen2.5-VL-7B via Ollama — stored in your attached storage bucket so it only downloads once

## Storage Bucket Setup (Required for Ollama / persistence)

1. Go to your Space **Settings → Storage Buckets**
2. Attach bucket: `Bitguy07/browser-automation-studio-data`
3. Set mount path: `/data`
4. Access mode: **Read-write**

Once attached, `/data` is persistent across restarts. The Ollama binary and Qwen model live in `/data/bin` and `/data/ollama` respectively — downloaded once, reused forever.

## HF Space Secrets

Set these in **Settings → Variables and Secrets**:

| Secret | Required | Description |
|--------|----------|-------------|
| `SECRET_KEY` | ✅ | JWT signing key (any random 32-char string) |
| `ADMIN_PASSWORD` | ✅ | Login password for the web UI |
| `GEMINI_API_KEY` | ✅ | Free at [aistudio.google.com](https://aistudio.google.com) |
| `GROQ_API_KEY` | ✅ | Free at [console.groq.com](https://console.groq.com) |
| `ENABLE_OLLAMA` | optional | Set `true` to use local Qwen model (requires bucket) |
| `PULL_MODEL_ON_STARTUP` | optional | Set `true` on first boot to download Qwen (~4.5GB, once) |
| `TELEGRAM_BOT_TOKEN` | optional | For Telegram bot integration |

**First-time Ollama setup**: Set both `ENABLE_OLLAMA=true` AND `PULL_MODEL_ON_STARTUP=true`, let the Space start (takes ~20 min first time, model downloads to bucket). After that, set `PULL_MODEL_ON_STARTUP=false` — model is already in the bucket.

## Telegram Commands

```
/task <objective>   — Run any automation task
/screenshot         — Get current Chrome screenshot  
/status             — Current mode and last 3 tasks
/help               — All commands
```

## Usage

Open the Space URL → log in with your `ADMIN_PASSWORD` → type a task in natural language.