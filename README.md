---
title: Browser Automation Studio
emoji: 🤖
colorFrom: purple
colorTo: pink
sdk: docker
pinned: false
app_port: 7860
---

# Browser Automation Studio

A self-hosted AI browser automation platform running on Hugging Face Spaces.

Control a real Chrome browser using natural language from a web UI or Telegram.

Local AI model: Qwen2.5-VL-7B-Instruct (vision-language, runs inside this Space)
Fallback: Gemini 2.5 Flash Lite then Groq llama-4-scout

## Usage

Open the Space URL, log in with your password, then type a task.

## Telegram Commands

/task objective - Run any automation task
/screenshot - Get current Chrome screenshot
/status - Current mode and last 3 tasks
/help - All commands
