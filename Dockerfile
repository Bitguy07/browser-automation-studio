# ============================================================
# Browser Automation Studio — Dockerfile
# OPTIMIZED FOR HUGGING FACE SPACES FREE TIER:
#   - No build-essential/dev headers (all packages have wheels)
#   - uv instead of pip (10-100x faster dependency install)
#   - Ollama binary installed at build time (~80MB)
#   - React frontend PRE-BUILT locally (frontend/build/)
#   - Chrome via official apt repo
#   - noVNC from release tarball
#   - Model pulled at RUNTIME by supervisord (not build time)
#   - Target build time: ~5-8 minutes
# ============================================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Kolkata
ENV HOME=/home/appuser
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# ── System packages (single layer, NO build tools) ───────────
# Removed: build-essential, libssl-dev, libffi-dev, python3.11-dev,
#          software-properties-common, git, wget, unzip, htop, nano
# All Python packages have pre-built amd64 wheels — no compiler needed.
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales \
    curl ca-certificates gnupg zstd \
    xvfb x11vnc supervisor \
    fonts-liberation fonts-dejavu-core \
    netcat-openbsd procps scrot \
    python3-websockify \
    python3.11 python3.11-venv \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python  python  /usr/bin/python3.11 1

# ── Chrome via official apt repo (cached, reliable) ──────────
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] \
    http://dl.google.com/linux/chrome/deb/ stable main" \
    > /etc/apt/sources.list.d/google-chrome.list && \
    apt-get update && apt-get install -y --no-install-recommends google-chrome-stable && \
    rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/google-chrome-stable /usr/bin/chromium && \
    ln -sf /usr/bin/google-chrome-stable /usr/bin/google-chrome

# ── noVNC from release tarball (no git clone needed) ─────────
RUN mkdir -p /opt/novnc && \
    curl -fsSL https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz \
    | tar -xz --strip-components=1 -C /opt/novnc && \
    ln -sf /opt/novnc/vnc.html /opt/novnc/index.html

# ── Ollama binary (~80MB — installed at build to save startup) ─
RUN curl -fsSL https://ollama.com/install.sh | sh

# ── uv — fast Python package installer (replaces pip) ────────
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# ── Python venv ──────────────────────────────────────────────
RUN python3.11 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
ENV VIRTUAL_ENV="/opt/venv"

WORKDIR /app

# ── Python dependencies (uv — cached by Docker layer) ────────
COPY requirements.txt .
RUN uv pip install --no-cache -r requirements.txt

# ── App code ─────────────────────────────────────────────────
COPY . .

# ── Directories and permissions ──────────────────────────────
RUN useradd -m -u 1000 -s /bin/bash appuser && \
    mkdir -p /data/cookies /data/outputs /data/downloads \
             /data/chrome-profile /data/ollama /data/logs \
             /var/log/supervisor && \
    chmod -R 777 /data && \
    chmod -R 777 /var/log/supervisor && \
    chmod -R 777 /tmp && \
    chown -R appuser:appuser /data && \
    chown -R appuser:appuser /app && \
    chown -R appuser:appuser /opt/venv && \
    chmod +x /app/scripts/start.sh /app/scripts/pull_model.sh

ENV OLLAMA_MODELS=/data/ollama
ENV OLLAMA_HOST=127.0.0.1:11434

USER 1000

EXPOSE 7860
EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=5 \
    CMD curl -f http://localhost:7860/health || exit 1

CMD ["/app/scripts/start.sh"]