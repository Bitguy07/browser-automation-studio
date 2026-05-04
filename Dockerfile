# ============================================================
# Browser Automation Studio — Dockerfile
# M8: Hugging Face Spaces deployment
#
# Fixes applied:
#   - zstd added to core packages (required by Ollama installer)
#   - Ollama model pull removed from build (pulled on first startup)
#   - supervisord socket/pid moved to /tmp (writable by USER 1000)
#   - /var/log/supervisor and /tmp made world-writable
#   - USER 1000 kept (HF requirement)
# ============================================================

FROM ubuntu:22.04


# Cache bust — increment this number to force HF full rebuild
ARG CACHEBUST=1


ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Kolkata
ENV HOME=/home/appuser

# ── Locale ────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y locales zstd && \
    locale-gen en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# ── Core system packages (zstd required by Ollama installer) v2 ──
RUN apt-get update && apt-get install -y \
    curl wget git unzip ca-certificates gnupg \
    software-properties-common build-essential \
    libssl-dev libffi-dev \
    xvfb x11vnc websockify supervisor \
    fonts-liberation fonts-dejavu-core \
    netcat-openbsd procps htop nano scrot \
    zstd \
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
# zstd is now installed above so this will succeed
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

# ── Directories and permissions ───────────────────────────────
# /tmp is always writable by all users — use it for supervisord
# socket and pid so USER 1000 can write to them
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

# NOTE: Model is NOT pulled at build time.
# Set PULL_MODEL_ON_STARTUP=true as HF Secret.
# On first startup start.sh pulls the model into /data/ollama
# which is your persistent HF Storage Bucket — never re-downloads.

RUN chmod +x /app/scripts/start.sh

# ── Switch to non-root user (HF requirement) ──────────────────
USER 1000

EXPOSE 7860
EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -f http://localhost:7860/health || exit 1

CMD ["/app/scripts/start.sh"]
