# syntax=docker/dockerfile:1
FROM oven/bun:1.3.14 AS base
WORKDIR /app

FROM base AS deps
WORKDIR /app
COPY package.json bun.lock ./
COPY patches ./patches/
COPY bun-patches ./bun-patches
COPY packages/ui/package.json ./packages/ui/
COPY packages/web/package.json ./packages/web/
COPY packages/electron/package.json ./packages/electron/
COPY packages/vscode/package.json ./packages/vscode/
COPY packages/mobile/package.json ./packages/mobile/
RUN bun install --frozen-lockfile --ignore-scripts

FROM deps AS builder
WORKDIR /app
COPY . .
RUN bun run build:web

FROM oven/bun:1.3.14 AS runtime
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
  git-lfs \
  htop \
  imagemagick \
  iproute2 \
  jq \
  less \
  lsof \
  build-essential \
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

# Node.js 22 LTS - apt's nodejs (20.x) is too old for openchamber (>=22) and
# oh-my-opencode deps like posthog-node (>=22.22.0)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get update && apt-get install -y --no-install-recommends nodejs \
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
RUN pip install --no-cache-dir --break-system-packages --ignore-installed playwright==1.61.0

# ---------- GitHub CLI ----------
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# ---------- lazygit ----------
RUN LAZYGIT_VERSION=0.63.1 && \
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
RUN EZA_VERSION=0.23.5 && \
    EZA_ARCH=$(case "$TARGETARCH" in arm64) echo "aarch64";; *) echo "x86_64";; esac) && \
    curl -fsSL -o /tmp/eza.tar.gz \
      "https://github.com/eza-community/eza/releases/download/v${EZA_VERSION}/eza_${EZA_ARCH}-unknown-linux-gnu.tar.gz" && \
    tar -C /usr/local/bin -xzf /tmp/eza.tar.gz && \
    rm /tmp/eza.tar.gz

# ---------- yq (YAML/JSON/XML processor) ----------
RUN YQ_VERSION=4.53.3 && \
    YQ_ARCH=$(case "$TARGETARCH" in arm64) echo "arm64";; *) echo "amd64";; esac) && \
    curl -fsSL -o /usr/local/bin/yq \
      "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${YQ_ARCH}" && \
    chmod +x /usr/local/bin/yq

# ---------- uv (fast Python package and project manager) ----------
RUN curl -fsSL https://astral.sh/uv/0.12.0/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh && \
    rm -rf /root/.cache/uv

# ---------- Python packages (data science, web, utilities) ----------
RUN pip install --no-cache-dir --break-system-packages --ignore-installed \
    requests==2.34.2 httpx==0.28.1 beautifulsoup4==4.15.0 lxml==6.1.1 \
    Pillow==12.3.0 openpyxl==3.1.5 python-docx==1.2.0 \
    pandas==3.0.5 numpy==2.5.1 matplotlib==3.11.1 seaborn==0.13.2 \
    rich==15.0.0 click==8.4.2 tqdm==4.70.0 apprise==1.12.0 \
    jinja2==3.1.6 pyyaml==6.0.3 python-dotenv==1.2.2 markdown==3.10.3 \
    fastapi==0.141.1 uvicorn==0.52.0 \
    pipx black

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

# cloudflared 2026.7.3 - update digest explicitly when upgrading
COPY --from=cloudflare/cloudflared@sha256:e39ee8da81ad5e05d77f38d2f51c60ca51bf2a8450ac3abab50c17fdb91d91bf /usr/local/bin/cloudflared /usr/local/bin/cloudflared

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
