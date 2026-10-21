#!/bin/bash
# Starts llama-server (shipped inside Ollama) on the Qwen 3.5 4B q4_K_M weights Ollama downloaded.
# Ollama itself forces Qwen 3.5 to one request at a time; llama-server runs SLOTS stories together.
# --cache-ram 512: its prompt cache defaults to 8 GB and grew the server to 8.3 GB in testing.
set -e
MODEL_TAG=${MODEL_TAG:-qwen3.5/4b-q4_K_M}; SLOTS=${SLOTS:-3}; PORT=${PORT:-8081}
manifest=~/.ollama/models/manifests/registry.ollama.ai/library/$MODEL_TAG
digest=$(python3 -c "import json,sys; m=json.load(open(sys.argv[1])); print([l['digest'] for l in m['layers'] if l['mediaType'].endswith('image.model')][0])" "$manifest")
server=$(ls /opt/homebrew/Cellar/ollama/*/libexec/lib/ollama/llama-server | tail -1)
exec "$server" --model ~/.ollama/models/blobs/${digest/:/-} --port $PORT --host 127.0.0.1 --no-webui \
  -c $((SLOTS * 5120)) -np $SLOTS -cb --no-jinja --chat-template chatml --cache-type-k q8_0 --cache-type-v q8_0 \
  --flash-attn on -b 512 -ub 256 --cache-ram 512 --ctx-checkpoints 2
