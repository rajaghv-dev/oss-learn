# llama.cpp

> C++ GGUF inference runtime with CLI, HTTP server, and benchmark binaries.

| Field | Value |
|-------|-------|
| Category | ai / llm inference |
| Repo role | optional |
| Install script | scripts/setup/llama_cpp.sh |
| Validate suite | scripts/validate/ai.sh |
| Compose / config | — |
| Default port(s) | 8084 (llama-server, when launched manually) |
| Default credentials | — |
| Resource footprint | binaries ~30 MB on disk; model RAM = quantized weight size (e.g. Qwen2.5-0.5B Q4_K_M ~350 MB, llama3-8B Q4_K_M ~5 GB) |

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

## Common pitfalls
- The prebuilt `ubuntu-x64` binaries from the `ggml-org/llama.cpp` release
  are compiled for a baseline AVX2 target and may segfault or run
  sub-optimally on hosts with different SIMD flags (older Sandy Bridge or
  newer AVX-512 / AMX chips) — fall back to `--build` so `GGML_NATIVE=ON`
  emits the right kernel for the local CPU instead of the lowest common
  denominator.
- Only the GGUF format is loadable; raw HuggingFace `.bin`/`.safetensors`
  or PyTorch checkpoints must be converted with `convert_hf_to_gguf.py`
  first, then optionally re-quantized with `llama-quantize`. Mixing model
  formats across runs is a common source of "tensor not found" errors.
- `libllama.so` lives next to the binary inside `setup/llama_cpp/install/`,
  not in `/usr/lib`; always export `LD_LIBRARY_PATH` to that directory or
  invoke the binaries from the install dir, otherwise the dynamic loader
  fails before `main()` even runs.
- `llama-cli` defaults to interactive conversation mode — pass `-no-cnv`
  for deterministic one-shot scripting, otherwise it will hang on stdin
  inside CI / scripts and time out the calling shell.
- `llama-server` listens on `127.0.0.1` by default; set `--host 0.0.0.0`
  consciously and only when you mean to expose it on the network, since
  there is no built-in auth and any caller can send arbitrary prompts.

## Suggested example progression
- **Beginner** — `examples/beginner/03_llama_cli_oneshot.py` — subprocess
  wrapper around `llama-cli` for a single prompt *(existing)*
- **Intermediate** — `examples/intermediate/04_llama_server_http.py` — start
  `llama-server` and stream completions over HTTP *(existing)*
- **Advanced** — `examples/advanced/02_llama_bench_quant_compare.py` — run
  `llama-bench` across Q4/Q5/Q8 quants and chart tokens/sec *(existing)*

## Related specs
- `specs/ollama.md` — higher-level wrapper around llama.cpp with a model
  registry, lifecycle daemon, and OpenAI-compatible HTTP surface; pick
  Ollama when you want zero-friction model management, drop down to
  llama.cpp here when you need raw control over the binary, the GGUF file,
  or the sampler parameters for benchmarking and quant comparison work.

## References
- Docs: https://github.com/ggml-org/llama.cpp/tree/master/examples
- Source: https://github.com/ggml-org/llama.cpp
- HTTP server reference: https://github.com/ggml-org/llama.cpp/blob/master/examples/server/README.md
