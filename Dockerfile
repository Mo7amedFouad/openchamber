# syntax=docker/dockerfile:1
FROM oven/bun:1 AS base
WORKDIR /app

FROM base AS deps
WORKDIR /app
COPY package.json bun.lock ./
COPY packages/ui/package.json ./packages/ui/
COPY packages/web/package.json ./packages/web/
COPY packages/vscode/package.json ./packages/vscode/
RUN bun install --ignore-scripts

FROM deps AS builder
WORKDIR /app
COPY . .
RUN bun run build:web

FROM oven/bun:1 AS runtime
ARG TARGETARCH
WORKDIR /home/openchamber

RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  bat \
  ca-certificates \
  curl \
  fd-find \
  ffmpeg \
  fonts-inter \
  fzf \
  git \
  htop \
  imagemagick \
  iproute2 \
  jq \
  less \
  lsof \
  build-essential \
  nodejs \
  npm \
  openssh-client \
  pandoc \
  pkg-config \
  postgresql-client \
  procps \
  python3 \
  python3-pip \
  python3-venv \
  redis-tools \
  ripgrep \
  sqlite3 \
  strace \
  tmux \
  tree \
  unzip \
  vim \
  wget \
  zip \
  && rm -rf /var/lib/apt/lists/*

# ---------- Headless browser (Chromium + Xvfb + fonts) ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
  chromium \
  xvfb \
  fonts-liberation2 \
  fonts-dejavu-core \
  fonts-noto-core \
  fonts-noto-color-emoji \
  && rm -rf /var/lib/apt/lists/*

ENV CHROME_PATH=/usr/bin/chromium \
  PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
  CHROMIUM_FLAGS="--no-sandbox --disable-gpu --disable-dev-shm-usage"

# ---------- bat/fd symlinks (Debian names them batcat/fdfind) ----------
RUN ln -sf /usr/bin/batcat /usr/local/bin/bat 2>/dev/null || true \
  && ln -sf /usr/bin/fdfind /usr/local/bin/fd 2>/dev/null || true

# ---------- Playwright (uses system Chromium via env vars) ----------
RUN pip install --no-cache-dir --break-system-packages playwright==1.60.0

# ---------- GitHub CLI ----------
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# ---------- lazygit ----------
RUN LAZYGIT_VERSION=0.62.0 && \
    LAZYGIT_ARCH=$(case "$TARGETARCH" in arm64) echo "arm64";; *) echo "x86_64";; esac) && \
    curl -fsSL -o /tmp/lazygit.tar.gz \
      "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_${LAZYGIT_ARCH}.tar.gz" && \
    tar -C /usr/local/bin -xzf /tmp/lazygit.tar.gz lazygit && \
    rm /tmp/lazygit.tar.gz

# ---------- delta (git diff pager) ----------
RUN DELTA_VERSION=0.19.2 && \
    DELTA_DEB_ARCH=$(case "$TARGETARCH" in arm64) echo "arm64";; *) echo "amd64";; esac) && \
    curl -fsSL -o /tmp/delta.deb \
      "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${DELTA_DEB_ARCH}.deb" && \
    dpkg -i /tmp/delta.deb && \
    rm /tmp/delta.deb

# ---------- eza (modern ls replacement) ----------
RUN EZA_VERSION=0.23.4 && \
    EZA_ARCH=$(case "$TARGETARCH" in arm64) echo "aarch64";; *) echo "x86_64";; esac) && \
    curl -fsSL -o /tmp/eza.tar.gz \
      "https://github.com/eza-community/eza/releases/download/v${EZA_VERSION}/eza_${EZA_ARCH}-unknown-linux-gnu.tar.gz" && \
    tar -C /usr/local/bin -xzf /tmp/eza.tar.gz && \
    rm /tmp/eza.tar.gz

# ---------- Python packages (data science, web, utilities) ----------
RUN pip install --no-cache-dir --break-system-packages \
    requests==2.34.2 httpx==0.28.1 beautifulsoup4==4.14.3 lxml==6.1.1 \
    Pillow==12.2.0 openpyxl==3.1.5 python-docx==1.2.0 \
    pandas==3.0.3 numpy==2.4.6 matplotlib==3.10.9 seaborn==0.13.2 \
    rich==15.0.0 click==8.4.1 tqdm==4.67.3 apprise==1.10.0 \
    jinja2==3.1.6 pyyaml==6.0.3 python-dotenv==1.2.2 markdown==3.10.2 \
    fastapi==0.136.3 uvicorn==0.48.0

RUN rm -f /usr/local/bin/dotenv

# Replace the base image's 'bun' user (UID 1000) with 'openchamber'
# so mounted volumes with 1000:1000 ownership work correctly.
RUN userdel bun \
  && groupadd -g 1000 openchamber \
  && useradd -u 1000 -g 1000 -m -s /bin/bash openchamber \
  && chown -R openchamber:openchamber /home/openchamber

# Switch to openchamber user
USER openchamber

ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}

RUN npm config set prefix /home/openchamber/.npm-global && mkdir -p /home/openchamber/.npm-global && \
  mkdir -p /home/openchamber/.local /home/openchamber/.config /home/openchamber/.ssh && \
  npm install -g opencode-ai && \
  npm install -g \
    typescript tsx \
    pnpm \
    vite esbuild \
    eslint prettier \
    serve nodemon concurrently \
    dotenv-cli \
    wrangler vercel netlify-cli \
    pm2 \
    prisma drizzle-kit \
    lighthouse @lhci/cli \
    sharp-cli \
    json-server http-server

COPY --from=cloudflare/cloudflared:2026.3.0 /usr/local/bin/cloudflared /usr/local/bin/cloudflared

ENV NODE_ENV=production

COPY scripts/docker-entrypoint.sh /home/openchamber/openchamber-entrypoint.sh

COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/packages/web/node_modules ./packages/web/node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/packages/web/package.json ./packages/web/package.json
COPY --from=builder /app/packages/web/bin ./packages/web/bin
COPY --from=builder /app/packages/web/server ./packages/web/server
COPY --from=builder /app/packages/web/dist ./packages/web/dist

EXPOSE 3000

ENTRYPOINT ["sh", "/home/openchamber/openchamber-entrypoint.sh"]
