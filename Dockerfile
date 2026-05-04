# ============================================================
# Browser Automation Studio — Dockerfile
# M8: Hugging Face Spaces deployment
#
# Key changes from M7:
#   - Ollama installed for local Qwen2.5-VL-7B-Instruct (Q4)
#   - USER 1000 directive (HF security requirement)
#   - /data persistent directory owned by user 1000
#   - Layer caching optimized (deps before code)
#   - Ollama model pulled at build time into image layer
#     so it survives container restarts on HF
#
# LLM priority:
#   1. Qwen2.5-VL-7B (Ollama, local, FREE, vision)
#   2. Gemini 2.5 Flash Lite (API, fallback)
#   3. Groq llama-4-scout  (API, last resort)
# ============================================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Kolkata
ENV HOME=/home/appuser

# ── Locale ────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y locales && \
    locale-gen en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# ── Core system packages ──────────────────────────────────────
RUN apt-get update && apt-get install -y \
    curl wget git unzip ca-certificates gnupg \
    software-properties-common build-essential \
    libssl-dev libffi-dev \
    xvfb x11vnc websockify supervisor \
    fonts-liberation fonts-dejavu-core \
    netcat-openbsd procps htop nano scrot \
    && rm -rf /var/lib/apt/lists/*

# ── Python 3.11 ───────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    python3.11 python3.11-dev python3.11-venv \
    python3-distutils python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python  python  /usr/bin/python3.11 1

# ── Python venv ───────────────────────────────────────────────
RUN python3.11 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --upgrade pip setuptools wheel

# ── Node.js 18 ────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# ── Chrome dependencies ───────────────────────────────────────
RUN apt-get update && apt-get install -y \
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libdrm2 libxkbcommon0 libxcomposite1 \
    libxdamage1 libxfixes3 libxrandr2 libgbm1 libasound2 \
    libcairo2 libpango-1.0-0 libgtk-3-0 libvulkan1 xdg-utils \
    && rm -rf /var/lib/apt/lists/*

# ── Google Chrome stable ──────────────────────────────────────
RUN wget -q -O /tmp/google-chrome.deb \
    https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get install -y /tmp/google-chrome.deb && \
    rm /tmp/google-chrome.deb && \
    rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/google-chrome-stable /usr/bin/chromium

# ── noVNC ─────────────────────────────────────────────────────
RUN git clone --depth=1 https://github.com/novnc/noVNC.git /opt/novnc && \
    git clone --depth=1 https://github.com/novnc/websockify.git /opt/novnc/utils/websockify && \
    ln -sf /opt/novnc/vnc.html /opt/novnc/index.html

# ── Ollama ────────────────────────────────────────────────────
# Ollama manages local LLM serving.
# We install it system-wide so it runs as a background service.
RUN curl -fsSL https://ollama.com/install.sh | sh

# ── Create app user (HF Spaces requires UID 1000) ─────────────
RUN useradd -m -u 1000 -s /bin/bash appuser && \
    mkdir -p /home/appuser && \
    chown -R appuser:appuser /home/appuser

WORKDIR /app

# ── Python dependencies ───────────────────────────────────────
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Playwright browser ────────────────────────────────────────
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN pip install playwright && /opt/venv/bin/playwright install chromium --with-deps

# ── Node/React dependencies ───────────────────────────────────
COPY frontend/package.json ./frontend/
RUN cd frontend && npm install

# ── Copy application code ─────────────────────────────────────
COPY . .

# ── Build React frontend ──────────────────────────────────────
RUN cd frontend && npm run build

# ── Data directories (owned by appuser for HF compatibility) ──
RUN mkdir -p /data/cookies /data/outputs /data/downloads \
             /data/chrome-profile /data/ollama \
             /var/log/supervisor /var/run && \
    chmod -R 777 /data && \
    chown -R appuser:appuser /data && \
    chown -R appuser:appuser /app && \
    chown -R appuser:appuser /opt/venv && \
    chmod -R 777 /var/log/supervisor && \
    chmod -R 777 /var/run

# ── Ollama model directory → persistent /data/ollama ──────────
# Point Ollama's model storage to /data so models survive
# container restarts when /data is a mounted HF persistent store.
ENV OLLAMA_MODELS=/data/ollama
ENV OLLAMA_HOST=127.0.0.1:11434

# ── Pull Qwen2.5-VL-7B at build time ──────────────────────────
# This bakes the model into the image layer so it is immediately
# available on HF without a startup download.
# The model is ~5GB — HF image storage supports this.
#
# NOTE: If the build times out on HF (rare), comment this line
# and use the PULL_MODEL_ON_STARTUP=true env var instead —
# the start.sh script handles the deferred pull.

# ///////////////////////////////////
# \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

# RUN ollama serve & \
#     sleep 5 && \
#     ollama pull qwen2.5vl:7b-instruct-q4_K_M && \
#     pkill ollama || true

RUN chmod +x /app/scripts/start.sh

# ── Switch to non-root user (HF requirement) ──────────────────
USER 1000

EXPOSE 7860
EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -f http://localhost:7860/health || exit 1

CMD ["/app/scripts/start.sh"]