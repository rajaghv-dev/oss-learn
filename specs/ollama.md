# Ollama

> Local HTTP LLM server for chat, generate, and embedding endpoints.

| Field | Value |
|-------|-------|
| Category | ai / llm inference |
| Repo role | core |
| Install script | scripts/setup/ollama.sh |
| Validate suite | scripts/validate/ai.sh |
| Compose / config | setup/ollama/docker-compose.yml (alternative) |
| Default port(s) | 11434 |
| Default credentials | — |
| Resource footprint | server idle ~200 MB RAM + model load adds quantized weight size (smollm2:135m ~270 MB, llama3.2:1b ~1.3 GB); disk per model = same |

## What it is
Ollama is a single-binary daemon that serves quantized open LLMs (Llama 3,
Qwen, SmolLM, etc.) over a local HTTP API on port 11434. It bundles model
download, GGUF loading, KV-cache management, and prompt streaming behind one
CLI plus a REST surface modelled loosely on OpenAI's. The server runs
persistently and lazily loads each model into RAM on first request.

## Why it's in oss-learn
Provides a zero-config local LLM endpoint that other components (RAG,
embeddings, downstream notebooks) can call without external API keys or GPU
hardware. Same API contract whether the host is a laptop CPU or a GPU box,
which keeps every example portable across the platforms oss-learn targets
(Linux, macOS, WSL2).

## How this repo wires it up
- `scripts/setup/ollama.sh` installs the binary via the official
  `curl https://ollama.com/install.sh | sh` script, landing it system-wide at
  `/usr/local/bin/ollama` with libs in `/usr/local/lib/ollama/`.
- Model storage is redirected to repo-local `setup/data/ollama/models/` via
  the `OLLAMA_MODELS` env var so `cleanup.sh` (or `rm -rf oss-learn/`) wipes
  every weight without touching `~/.ollama/`.
- The default model is `smollm2:135m` (~270 MB, CPU-friendly); override with
  `--model=llama3.2:1b`, `--no-model` to skip the pull, or `OLLAMA_MODEL` in
  `.env` (the example file ships `llama3.2:1b`).
- The setup script starts `ollama serve` under `nohup`, writes its PID/log to
  `setup/state/ollama_server.{pid,log}`, then polls `/api/tags` for up to 15s
  before continuing.
- Verification POSTs prompt `1+1=` to `/api/generate` with `temperature=0`
  and `num_predict=8` and stamps `ollama_verify_<model>` once a non-empty
  response comes back.
- `scripts/validate/ai.sh` exercises the running server through
  `setup/self-tests/ollama/test_install.py` and `setup/validate/ollama.sh`.

## Key concepts
- **GGUF model** — The quantized weight format Ollama loads; a single file
  per model+quant level, identified by `<name>:<tag>`.
- **Modelfile** — Optional declarative recipe that layers a system prompt,
  parameters, or LoRA adapter onto a base model.
- **/api/generate** — Single-shot completion endpoint; streams JSON lines
  unless the request sets `"stream": false`.
- **/api/embeddings** — Vector endpoint used by the RAG example to populate
  pgvector with paragraph embeddings.
- **OLLAMA_MODELS** — Env var redirecting the model store to a repo-local
  path so cleanup is just `rm -rf` and multi-checkout caches stay isolated.
- **Stamps** — Per-step marker files (e.g. `ollama_install`,
  `ollama_model_<name>`) under `setup/state/` that make the script
  idempotent; `--force` clears them.

## Quick verification
```bash
curl -s http://localhost:11434/api/generate -d '{"model":"smollm2:135m","prompt":"hello","stream":false}'
```
Returns a JSON document with a non-empty `response` field once the model is
loaded into RAM.

## Common pitfalls
- The `ollama serve` PID written to `setup/state/ollama_server.pid` is lost
  after reboot — re-run `ollama serve` or wire up a systemd unit before the
  first request, otherwise `/api/tags` will hang and the verify probe in
  `scripts/setup/ollama.sh` will exit non-zero on a fresh boot.
- `OLLAMA_MODELS` must point at a path the running user can read and write;
  silently flipping back to the default `~/.ollama/` happens if perms are
  wrong, which then leaks weights outside the repo and breaks `cleanup.sh`.
- The first prompt against a freshly started server is slow because the
  quantized weights are being mmap'd and warmed into RAM (especially on
  cold-cache disks) — this is *not* a failure, keep client timeouts above
  30 s for `llama3.2:1b` and above 60 s for anything in the 7B+ range.
- Concurrent generates against *different* models will trigger eviction and
  reload of the previous model; pin one model per server (or run multiple
  `ollama serve` instances on different ports) if latency matters.
- The HTTP API ignores OpenAI-style auth headers entirely — never expose
  port 11434 beyond localhost without putting a reverse proxy with auth in
  front of it, since any caller can pull arbitrary models or generate.

## Related specs
- `specs/llama-cpp.md` — lower-level alternative; Ollama bundles llama.cpp
  underneath, so dropping down a layer gives finer control over quantization
  flags, sampler params, and binary build options at the cost of having to
  manage GGUF files and lifecycle yourself. Pick Ollama when you want the
  shortest path from `pull` to a callable HTTP endpoint, pick llama.cpp when
  you need to benchmark or pin a specific binary build, and remember that
  switching between them does *not* require re-downloading models because
  both consume the same GGUF files (subject to filename / location).
- `specs/pgvector.md` — paired storage for the RAG pipeline; the embed
  endpoint here writes vectors that pgvector indexes for similarity search,
  and the advanced example wires the two together end-to-end so you can see
  Ollama, the database, and the retrieval loop interacting in one script.
- `specs/prometheus.md` — scrape Ollama's metrics endpoint for latency,
  tokens-per-second, and KV-cache occupancy dashboards alongside the other
  oss-learn services that already register as scrape targets, giving a
  single-pane-of-glass view of the model + storage + queue stack.

## References
- Docs: https://github.com/ollama/ollama/blob/main/docs/api.md
- Source: https://github.com/ollama/ollama
- Model registry: https://ollama.com/library
