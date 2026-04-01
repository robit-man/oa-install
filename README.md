# oa-install

One-command installer for [Open Agents](https://github.com/robit-man/open-agents) in Docker. Full GPU passthrough, persistent workspace, works on Linux/macOS/Windows.

## Quick Start

### Linux / macOS / WSL
```bash
curl -fsSL https://raw.githubusercontent.com/robit-man/oa-install/main/install.sh | bash
```

### Windows (PowerShell)
```powershell
irm https://raw.githubusercontent.com/robit-man/oa-install/main/install.ps1 | iex
```

## What It Does

1. Installs Docker (if missing)
2. Installs NVIDIA Container Toolkit (Linux + GPU)
3. Builds Docker image with: Node.js 22, Ollama, Open Agents
4. Creates `oa-docker` launcher command
5. Starts OA with interactive terminal

## Usage

```bash
# Interactive TUI (default)
oa-docker

# API server mode
oa-docker oa serve

# Shell access
oa-docker bash

# Custom model
OA_MODEL=qwen3:27b oa-docker
```

## Architecture

```
Host Machine
  |
  +-- Docker Container (nvidia/cuda:12.8.1-runtime-ubuntu24.04)
  |     |
  |     +-- Ollama daemon (port 11434)
  |     +-- Open Agents CLI (port 11435 for API)
  |     +-- Node.js 22 + pnpm
  |     +-- Python 3 + pip
  |     +-- Git, curl, build tools
  |     |
  |     +-- /workspace (mounted from host)
  |
  +-- GPU passthrough (--gpus all)
  +-- Host network (--network host)
  +-- Persistent volumes:
        ~/.ollama    -> /root/.ollama    (model cache)
        ~/.open-agents -> /root/.open-agents (config + memory)
        ~/oa-workspace -> /workspace     (projects)
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `OA_MODEL` | `qwen3:4b` | Ollama model to pull on first run |
| `OA_VERSION` | `latest` | Open Agents npm version |
| `OA_WORKSPACE` | `~/oa-workspace` | Host directory mounted as `/workspace` |
| `OA_GPU` | `auto` | GPU mode: `auto`, `nvidia`, `none` |

## Docker Compose

For persistent deployments:

```bash
git clone https://github.com/robit-man/oa-install
cd oa-install
docker compose up -d
docker compose exec oa bash
```

## GPU Support

| Platform | GPU | Method |
|----------|-----|--------|
| Linux + NVIDIA | Full CUDA | `--gpus all` + nvidia-container-toolkit |
| Linux + AMD | ROCm | Not yet supported (planned) |
| macOS + Apple Silicon | Metal via Ollama | Ollama uses Metal natively (no Docker GPU) |
| Windows + NVIDIA | CUDA via WSL2 | Docker Desktop WSL2 backend |

## Troubleshooting

### Docker permission denied
```bash
sudo usermod -aG docker $USER
# Log out and back in
```

### GPU not detected in container
```bash
# Verify nvidia-container-toolkit
nvidia-ctk --version
# Restart Docker
sudo systemctl restart docker
```

### Model too large for VRAM
```bash
# Use a smaller model
OA_MODEL=qwen3:4b oa-docker
```

## License

MIT
