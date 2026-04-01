#!/bin/bash
set -e

# ── Colors ──
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       Open Agents — Docker Runtime           ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"

# ── 1. Start Ollama daemon ──
echo -e "${YELLOW}Starting Ollama daemon...${NC}"
ollama serve &>/tmp/ollama.log &
OLLAMA_PID=$!

# Wait for Ollama to be ready
for i in $(seq 1 30); do
  if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo -e "${GREEN}Ollama ready.${NC}"
    break
  fi
  sleep 1
done

# ── 2. Pull default model if not cached ──
DEFAULT_MODEL="${OA_MODEL:-qwen3:4b}"
if ! ollama list 2>/dev/null | grep -q "$DEFAULT_MODEL"; then
  echo -e "${YELLOW}Pulling ${DEFAULT_MODEL} (first run only)...${NC}"
  ollama pull "$DEFAULT_MODEL" || echo -e "${YELLOW}Model pull failed — you can pull manually with: ollama pull ${DEFAULT_MODEL}${NC}"
fi

# ── 3. GPU check ──
if command -v nvidia-smi &>/dev/null; then
  GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
  GPU_VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
  echo -e "${GREEN}GPU: ${GPU_NAME} (${GPU_VRAM}MB VRAM)${NC}"
else
  echo -e "${YELLOW}No NVIDIA GPU detected — running CPU-only.${NC}"
fi

# ── 4. Show status ──
echo ""
echo -e "${GREEN}Ready!${NC}"
echo -e "  Ollama: http://localhost:11434"
echo -e "  Model:  ${DEFAULT_MODEL}"
echo -e "  OA:     $(oa --version 2>/dev/null || echo 'installed')"
echo ""

# ── 5. Launch OA or custom command ──
if [ $# -eq 0 ]; then
  # Interactive mode — launch OA TUI
  exec oa
else
  # Custom command (e.g., oa serve, bash, etc.)
  exec "$@"
fi
