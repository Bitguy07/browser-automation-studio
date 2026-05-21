# ============================================================
# Browser Automation Studio — Dockerfile
# FAST BUILD STRATEGY:
#   - React frontend is PRE-BUILT locally, copied from frontend/build/
#     (no npm install / npm run build at Docker build time)
#   - Chrome installed via official apt repo (cached, reliable)
#   - noVNC from release tarball (no git clone)
#   - Ollama + model pulled at runtime by start.sh (NOT at build time)
#   - Result: build in ~8-12 min reliably
# ============================================================

FROM ubuntu:22.04

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
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget git unzip ca-certificates gnupg \
    software-properties-common build-essential \
    libssl-dev libffi-dev \
    xvfb x11vnc supervisor \
    fonts-liberation fonts-dejavu-core \
    netcat-openbsd procps htop nano scrot \
    python3-websockify \
    && rm -rf /var/lib/apt/lists/*

# ── Python 3.11 ───────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 python3.11-dev python3.11-venv \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python  python  /usr/bin/python3.11 1

# ── Python venv ───────────────────────────────────────────────
RUN python3.11 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --upgrade pip setuptools wheel

# ── Chrome via official apt repo (reliable, cached) ──────────
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] \
    http://dl.google.com/linux/chrome/deb/ stable main" \
    > /etc/apt/sources.list.d/google-chrome.list && \
    apt-get update && apt-get install -y google-chrome-stable && \
    rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/google-chrome-stable /usr/bin/chromium && \
    ln -sf /usr/bin/google-chrome-stable /usr/bin/google-chrome

# ── noVNC from release tarball (no git clone needed) ─────────
RUN mkdir -p /opt/novnc && \
    curl -fsSL https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz \
    | tar -xz --strip-components=1 -C /opt/novnc && \
    ln -sf /opt/novnc/vnc.html /opt/novnc/index.html

WORKDIR /app

# ── Python dependencies (pip — cached by Docker layer) ───────
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Playwright package only (no browser download) ─────────────
RUN pip install --no-cache-dir playwright

# ── App code ─────────────────────────────────────────────────
COPY . .

# ── Directories and permissions ───────────────────────────────
RUN useradd -m -u 1000 -s /bin/bash appuser && \
    mkdir -p /data/cookies /data/outputs /data/downloads \
             /data/chrome-profile /data/ollama /data/logs \
             /var/log/supervisor && \
    chmod -R 777 /data && \
    chmod -R 777 /var/log/supervisor && \
    chmod -R 777 /tmp && \
    chown -R appuser:appuser /data && \
    chown -R appuser:appuser /app && \
    chown -R appuser:appuser /opt/venv

ENV OLLAMA_MODELS=/data/ollama
ENV OLLAMA_HOST=127.0.0.1:11434

RUN chmod +x /app/scripts/start.sh

USER 1000

EXPOSE 7860
EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=5 \
    CMD curl -f http://localhost:7860/health || exit 1

CMD ["/app/scripts/start.sh"]