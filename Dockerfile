# ============================================================
# Browser Automation Studio — Dockerfile
# HF Spaces Free Tier + Storage Bucket optimized
#
# Key decisions:
#   1. python:3.11-slim base — eliminates Ubuntu Python install mess
#   2. /opt/venv PRESERVED — all pip packages install here so
#      USER 1000 at runtime never touches system Python paths
#      (supervisord.conf + start.sh both call /opt/venv/bin/python)
#   3. Chrome + deps with --no-install-recommends everywhere (saves ~400MB)
#   4. NO build-essential, NO software-properties-common
#   5. websockify installed into venv via pip
#   6. npm --omit=dev + node_modules deleted after build (~300MB saved)
#   7. /data NOT touched at build time — HF only mounts the bucket
#      at runtime; start.sh creates subdirs on first boot
#   8. Ollama installed at runtime by start.sh AFTER bucket is mounted
#      so binary + model live in /data/ollama (persistent across restarts)
# ============================================================

FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Kolkata
ENV HOME=/home/appuser
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# ── Locale ────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales && \
    locale-gen en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# ── Core system packages ──────────────────────────────────────
# REMOVED: software-properties-common (drags in 200MB+ GUI/desktop chain)
# REMOVED: build-essential/gcc/make (all Python wheels are pre-built binaries)
# REMOVED: htop, nano, scrot (debug-only tools, waste image space)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget git unzip ca-certificates gnupg \
    libssl-dev libffi-dev \
    xvfb x11vnc \
    fonts-liberation fonts-dejavu-core \
    netcat-openbsd procps \
    supervisor \
    zstd \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 18 ────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# ── Chrome shared library dependencies (minimal set) ──────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libdrm2 libxkbcommon0 libxcomposite1 \
    libxdamage1 libxfixes3 libxrandr2 libgbm1 libasound2 \
    libcairo2 libpango-1.0-0 libgtk-3-0 libvulkan1 xdg-utils \
    && rm -rf /var/lib/apt/lists/*

# ── Google Chrome stable ──────────────────────────────────────
# --no-install-recommends saves ~200MB of optional Chrome extras
RUN wget -q -O /tmp/google-chrome.deb \
    https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get install -y --no-install-recommends /tmp/google-chrome.deb && \
    rm /tmp/google-chrome.deb && \
    rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/google-chrome-stable /usr/bin/chromium && \
    ln -sf /usr/bin/google-chrome-stable /usr/bin/google-chrome

# ── noVNC ─────────────────────────────────────────────────────
RUN git clone --depth=1 https://github.com/novnc/noVNC.git /opt/novnc && \
    git clone --depth=1 https://github.com/novnc/websockify.git /opt/novnc/utils/websockify && \
    ln -sf /opt/novnc/vnc.html /opt/novnc/index.html

# ── App user (HF Spaces requires UID 1000) ────────────────────
RUN useradd -m -u 1000 -s /bin/bash appuser && \
    chown -R appuser:appuser /home/appuser

WORKDIR /app

# ── /opt/venv — ALL Python packages live here ─────────────────
# Rationale: python:3.11-slim's system Python is owned by root.
# A venv owned by appuser means USER 1000 can import everything
# without permission errors, and if any runtime pip install is
# ever needed it targets the venv, not the system.
# supervisord.conf and start.sh both reference /opt/venv/bin/python.
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# ── Python application dependencies ───────────────────────────
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Playwright (package only, no browser download) ────────────
RUN pip install --no-cache-dir playwright

# ── websockify via pip (avoids apt version inconsistency) ─────
RUN pip install --no-cache-dir websockify

# ── Node/React build ──────────────────────────────────────────
# --omit=dev: skip devDependencies (saves ~300MB in node_modules)
# node_modules deleted after build — not needed at runtime
COPY frontend/package.json frontend/package-lock.json* ./frontend/
RUN cd frontend && \
    npm install --omit=dev && \
    npm cache clean --force

COPY . .

RUN cd frontend && \
    npm run build && \
    npm cache clean --force && \
    rm -rf /app/frontend/node_modules

# ── Permissions ───────────────────────────────────────────────
# /data is intentionally NOT created here.
# HF mounts the storage bucket at /data only at runtime.
# start.sh will create /data subdirs on first boot.
RUN mkdir -p /var/log/supervisor && \
    chmod -R 777 /var/log/supervisor && \
    chmod -R 777 /tmp && \
    chown -R appuser:appuser /app && \
    chown -R appuser:appuser /opt/venv && \
    chown -R appuser:appuser /opt/novnc

# ── Runtime environment ───────────────────────────────────────
ENV OLLAMA_MODELS=/data/ollama
ENV OLLAMA_HOST=127.0.0.1:11434
ENV CHROME_EXECUTABLE_PATH=/usr/bin/google-chrome-stable
# HF_HOME → /data means huggingface_hub caches (tokenizers etc.)
# also persist in the bucket across restarts
ENV HF_HOME=/data/.huggingface

RUN chmod +x /app/scripts/start.sh

USER 1000

EXPOSE 7860
EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=5 \
    CMD curl -f http://localhost:7860/health || exit 1

CMD ["/app/scripts/start.sh"]