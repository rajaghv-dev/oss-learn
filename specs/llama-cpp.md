# llama.cpp

> C++ GGUF inference runtime with CLI, HTTP server, and benchmark binaries.

| Field | Value |
|-------|-------|
| Category | AI / LLM inference |
| Repo role | optional |
| Install script | scripts/setup/llama_cpp.sh |
| Validate suite | scripts/validate/ai.sh |
| Compose / config | — |
| Default port(s) | 8084 (llama-server, when launched manually) |
| Default credentials | — |

## What it is
llama.cpp is the reference C/C++ implementation for running LLaMA-family
transformer models with aggressive CPU quantization (GGUF). It ships a
one-shot CLI (`llama-cli`), a streaming HTTP server (`llama-server`), and a
throughput benchmark (`llama-bench`), all linked against `libllama.so`. The
runtime targets vanilla CPUs first, with optional CUDA / Vulkan / Metal
backends not used in this CPU-only setup.

## Why it's in oss-learn
Provides a transparent, low-level alternative to Ollama where you control the
binary, model file, and quantization level directly — useful for measuring
CPU performance, comparing GGUF quants, or embedding inference into custom
code. Ollama itself is built on llama.cpp, so this is the layer underneath.

## How this repo wires it up
- `scripts/setup/llama_cpp.sh` defaults to the prebuilt `ubuntu-x64` zip from
  the `ggml-org/llama.cpp` release tag `b4738` (overridable via the
  `LLAMA_BUILD` env var), flat-installed to `setup/llama_cpp/install/`.
- `--build` clones the same tag and runs `cmake -DGGML_NATIVE=ON` plus
  `cmake --build` for a CPU-native SIMD binary; output is normalised to the
  same flat layout as the prebuilt path so callers always find
  `llama-cli` at one stable location.
- A 350 MB verification GGUF (`Qwen2.5-0.5B-Instruct-Q4_K_M`) is downloaded
  once to `setup/state/verify_model.gguf` and run with
  `llama-cli -p "Q: What is 2+2? A:" -n 16 --temp 0 -no-cnv` to confirm the
  full load+infer pipeline before stamping `llama_cpp_verify`.
- `LD_LIBRARY_PATH` is exported during setup so `libllama.so` next to the
  binaries resolves correctly without a system-wide install.
- Manifest at `setup/state/installs/llama_cpp.yaml` records `cli`, `server`,
  build tag, variant, and verify-model path so `cleanup.sh` knows what to
  remove.
- `scripts/validate/ai.sh` simply checks that `llama-cli` exists on PATH or
  inside the install dir; the heavier inference probe lives in
  `setup/validate/llamacpp.sh`.

## Key concepts
- **GGUF** — Single-file model format used by both llama.cpp and Ollama;
  embeds weights, tokenizer, and metadata so one file is fully self-contained.
- **Quantization (Q4_K_M, Q8_0, ...)** — Trade-off between RAM/CPU cost and
  accuracy; Q4_K_M is the common CPU sweet spot, Q8_0 is closest to FP16.
- **llama-cli vs llama-server** — CLI for one-shot inference and chat;
  server exposes an OpenAI-compatible HTTP API on `--port 8084` here.
- **GGML_NATIVE** — Build flag enabling CPU-specific SIMD (AVX2 / AVX-512 /
  AMX) for the host machine when building from source.
- **-no-cnv** — Disables interactive conversation mode so a CLI invocation
  completes after `-n` tokens and exits, suitable for automation.
- **Manifest + stamps** — Per-step marker files under `setup/state/` plus a
  YAML manifest let `cleanup.sh` remove every artefact this script created.

## Quick verification
```bash
setup/llama_cpp/install/llama-cli -m setup/state/verify_model.gguf -p "hello" -n 16 --temp 0 -no-cnv
```
Prints generated tokens and exits 0 once the binary, shared lib, and GGUF all
load.

## Suggested example progression
- **Beginner** — `examples/beginner/03_llama_cli_oneshot.py` — subprocess
  wrapper around `llama-cli` for a single prompt *(planned)*
- **Intermediate** — `examples/intermediate/04_llama_server_http.py` — start
  `llama-server` and stream completions over HTTP *(planned)*
- **Advanced** — `examples/advanced/02_llama_bench_quant_compare.py` — run
  `llama-bench` across Q4/Q5/Q8 quants and chart tokens/sec *(planned)*

## References
- Docs: https://github.com/ggml-org/llama.cpp/tree/master/examples
- Source: https://github.com/ggml-org/llama.cpp
