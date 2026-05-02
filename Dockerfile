# ============================================================
# Browser Automation Studio — Dockerfile
# M5: browser-use 0.12.6 + Playwright + Gemini/Groq
# Base: Ubuntu 22.04 | HF Spaces compatible
# Primary port: 7860 (FastAPI) | VNC: 6080
#
# Python strategy: venv at /opt/venv — zero path ambiguity
#   ENV PATH="/opt/venv/bin:$PATH" makes every RUN layer use
#   the same pip, python, and playwright binary automatically.
# ============================================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Kolkata

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

# ── Python 3.11 (Ubuntu 22.04 native — no PPA needed) ────────
RUN apt-get update && apt-get install -y \
    python3.11 python3.11-dev python3.11-venv \
    python3-distutils python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python  python  /usr/bin/python3.11 1

# ── Create venv — ALL packages go here, zero path confusion ──
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

WORKDIR /app

# ── Python dependencies (into /opt/venv via PATH) ─────────────
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Install Playwright browser ────────────────────────────────
# 'playwright' binary is at /opt/venv/bin/playwright (on PATH)
# No module path tricks needed — venv guarantees it.
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
# Explicitly install playwright CLI so the binary exists in the venv
# browser-use installs playwright as a lib but may not create the CLI binary
RUN pip install playwright && /opt/venv/bin/playwright install chromium --with-deps

# ── Node/React dependencies ───────────────────────────────────
COPY frontend/package.json ./frontend/
RUN cd frontend && npm install

# ── Copy application code ─────────────────────────────────────
COPY . .

# ── Build React frontend ──────────────────────────────────────
RUN cd frontend && npm run build

# ── Data directories ──────────────────────────────────────────
RUN mkdir -p /data/cookies /data/outputs /data/downloads && \
    chmod -R 777 /data

RUN chmod +x /app/scripts/start.sh

EXPOSE 7860
EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD curl -f http://localhost:7860/health || exit 1

CMD ["/app/scripts/start.sh"]
