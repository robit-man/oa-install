FROM nvidia/cuda:12.8.1-runtime-ubuntu24.04

ARG OLLAMA_VERSION=latest
ARG OA_VERSION=latest
ARG NODE_MAJOR=22

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm-256color
ENV COLORTERM=truecolor
ENV LANG=C.UTF-8

# System deps (single layer)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget ca-certificates gnupg git python3 python3-pip \
    build-essential procps htop tmux jq unzip \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y nodejs \
    && npm install -g pnpm \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Ollama from GitHub release (tar.zst archive)
RUN apt-get update && apt-get install -y --no-install-recommends zstd \
    && curl -fsSL -L -o /tmp/ollama.tar.zst \
       https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64.tar.zst \
    && mkdir -p /tmp/ollama-extract \
    && tar --use-compress-program=unzstd -xf /tmp/ollama.tar.zst -C /tmp/ollama-extract \
    && cp /tmp/ollama-extract/bin/ollama /usr/local/bin/ollama \
    && chmod +x /usr/local/bin/ollama \
    && cp -r /tmp/ollama-extract/lib/* /usr/local/lib/ 2>/dev/null || true \
    && rm -rf /tmp/ollama.tar.zst /tmp/ollama-extract \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Open Agents
RUN npm install -g open-agents-ai@${OA_VERSION}

# Create workspace with proper permissions
RUN mkdir -p /workspace /root/.open-agents /root/.ollama
WORKDIR /workspace

# Entrypoint script — starts Ollama daemon, pulls default model, launches OA
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose ports: Ollama (11434), OA API (11435)
EXPOSE 11434 11435

ENTRYPOINT ["/entrypoint.sh"]
