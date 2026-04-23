# ============================================================
# Browser Automation Studio — Dockerfile
# M2: Added scrot (screenshot tool)
# Base: Ubuntu 22.04 | Compatible with Hugging Face Spaces
# Primary port: 7860 (FastAPI) | VNC port: 6080
# ============================================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Kolkata

# ── System locale ─────────────────────────────────────────────
RUN apt-get update && apt-get install -y locales && \
    locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# ── Core system packages ──────────────────────────────────────
RUN apt-get update && apt-get install -y \
    curl wget git unzip ca-certificates gnupg \
    software-properties-common build-essential \
    libssl-dev libffi-dev \
    xvfb x11vnc \
    websockify \
    supervisor \
    fonts-liberation fonts-dejavu-core \
    netcat-openbsd procps htop nano \
    scrot \
    && rm -rf /var/lib/apt/lists/*

# ── Python 3.11 ───────────────────────────────────────────────
RUN add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update && apt-get install -y \
    python3.11 python3.11-dev python3.11-distutils python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11

# ── Node.js 18 ────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# ── Google Chrome (real binary, not Ubuntu snap stub) ─────────
# Ubuntu 22.04's chromium-browser is a snap stub that fails in Docker.
# Google Chrome stable provides a real binary at /usr/bin/google-chrome-stable
RUN apt-get update && apt-get install -y \
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libdrm2 libxkbcommon0 libxcomposite1 \
    libxdamage1 libxfixes3 libxrandr2 libgbm1 libasound2 \
    libcairo2 libpango-1.0-0 libgtk-3-0 libvulkan1 xdg-utils \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q -O /tmp/google-chrome.deb \
    https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get install -y /tmp/google-chrome.deb && \
    rm /tmp/google-chrome.deb && \
    rm -rf /var/lib/apt/lists/*

# Symlink so supervisord uses /usr/bin/chromium
RUN ln -sf /usr/bin/google-chrome-stable /usr/bin/chromium

# ── noVNC ─────────────────────────────────────────────────────
RUN git clone --depth=1 https://github.com/novnc/noVNC.git /opt/novnc && \
    git clone --depth=1 https://github.com/novnc/websockify.git /opt/novnc/utils/websockify

RUN ln -sf /opt/novnc/vnc.html /opt/novnc/index.html

WORKDIR /app

# ── Python dependencies ───────────────────────────────────────
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Node/React dependencies ───────────────────────────────────
COPY frontend/package.json ./frontend/
RUN cd frontend && npm install

# ── Copy all application code ─────────────────────────────────
COPY . .

# ── Build React frontend ──────────────────────────────────────
RUN cd frontend && npm run build

# ── Persistent data directory ─────────────────────────────────
RUN mkdir -p /data/cookies /data/outputs && \
    chmod -R 777 /data

RUN chmod +x /app/scripts/start.sh

EXPOSE 7860
EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:7860/health || exit 1

CMD ["/app/scripts/start.sh"]
