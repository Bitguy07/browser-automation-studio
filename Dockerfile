# ============================================================
# Browser Automation Studio — Dockerfile
# HF Spaces — Final production version
#
# Design principle: BUILD FAST, RUN HEAVY
#   - No Ollama in build (installs at first container startup)
#   - No model pull in build (pulled at first container startup)
#   - Build only does: apt, python, node, chrome, playwright, react
#   - Build completes in ~10-15 minutes reliably
#   - First startup takes ~15 min (Ollama + model download, once only)
#   - All subsequent startups are fast (model cached in /data/ollama)
#
# Cache bust: increment to force full HF rebuild
ARG CACHEBUST=1
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
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget git unzip ca-certificates gnupg \
    software-properties-common build-essential \
    libssl-dev libffi-dev \
    xvfb x11vnc websockify supervisor \
    fonts-liberation fonts-dejavu-core \
    netcat-openbsd procps htop nano scrot \
    zstd \
    && rm -rf /var/lib/apt/lists/*

# ── Python 3.11 ───────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
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
RUN apt-get update && apt-get install -y --no-install-recommends \
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

# ── NO OLLAMA IN BUILD ────────────────────────────────────────
# Ollama is installed at first container startup by start.sh
# This avoids HF build timeouts from large downloads
# The binary is cached in /data/ollama after first install

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

# ── Directories and permissions ───────────────────────────────
RUN mkdir -p /data/cookies /data/outputs /data/downloads \
             /data/chrome-profile /data/ollama /data/logs \
             /var/log/supervisor && \
    chmod -R 777 /data && \
    chmod -R 777 /var/log/supervisor && \
    chmod -R 777 /tmp && \
    chown -R appuser:appuser /data && \
    chown -R appuser:appuser /app && \
    chown -R appuser:appuser /opt/venv

# ── Ollama config ─────────────────────────────────────────────
ENV OLLAMA_MODELS=/data/ollama
ENV OLLAMA_HOST=127.0.0.1:11434

RUN chmod +x /app/scripts/start.sh

# ── Switch to non-root user (HF requirement) ──────────────────
USER 1000

EXPOSE 7860
EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=5 \
    CMD curl -f http://localhost:7860/health || exit 1

CMD ["/app/scripts/start.sh"]
