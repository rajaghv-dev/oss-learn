# ONNX Runtime

> Cross-framework inference engine for `.onnx` graphs on CPU.

| Field | Value |
|-------|-------|
| Category | ai / model inference |
| Repo role | core |
| Install script | scripts/setup/onnxruntime.sh |
| Validate suite | scripts/validate/ai.sh |
| Compose / config | — |
| Default port(s) | — |
| Default credentials | — |
| Resource footprint | pip wheel ~12 MB on disk; model RAM = ONNX file size + activations (typically 1.5–3x file size at peak) |

## What it is
ONNX Runtime (ORT) is Microsoft's portable inference engine for models
exported to the ONNX graph format from PyTorch, TensorFlow, scikit-learn, and
other frameworks. The CPU build (`onnxruntime` on PyPI) loads `.onnx` files
through `InferenceSession` and executes them via a C++ kernel set with
optional graph-level optimizations (constant folding, operator fusion,
layout transforms). It is library-only — no daemon, no port, just a Python
import.

## Why it's in oss-learn
Gives the project a framework-agnostic way to run pretrained models (vision,
classification, embeddings) without dragging in PyTorch or TensorFlow, and is
the baseline against which OpenVINO is compared on the exact same CPU and
graph.

## How this repo wires it up
- `scripts/setup/onnxruntime.sh` installs `onnxruntime` (CPU-only — never
  `onnxruntime-gpu`) plus `numpy>=1.24` and `onnx` into the shared `venv/`.
  The `--build` flag is a documented stub that points at the upstream cmake
  flow rather than running it automatically.
- Verification builds an in-memory `MatMul` graph via `onnx.helper`
  (shapes `[2,3] @ [3,2] -> [2,2]`, opset 13), runs it through
  `InferenceSession(..., providers=["CPUExecutionProvider"])`, and asserts
  the result equals `numpy.A @ B` with `np.allclose`.
- A second pytest-friendly probe re-runs the same MatMul and emits a JSON
  `{import, providers, cpu_inference}` block consumed by the script's
  PASS/FAIL summary; setup exits 1 if `cpu_inference` does not pass.
- CPU capability flags (AVX2 / AVX-512 / VNNI) are read from `/proc/cpuinfo`
  and logged so users can correlate INT8 quantization speedups with hardware.
- Manifest at `setup/state/installs/onnxruntime.yaml` records package name,
  version, and the `get_available_providers()` list at install time.
- `scripts/validate/ai.sh` runs `setup/self-tests/onnxruntime/test_install.py`
  via pytest and `setup/validate/onnxruntime.sh` as a bash counterpart.

## Key concepts
- **InferenceSession** — Loads a model (file path, bytes, or NumPy array) and
  exposes `.run(output_names, input_dict)` as the single hot path.
- **Execution Provider** — Backend the graph runs on; this repo uses
  `CPUExecutionProvider` only, but the API allows DML/CUDA/CoreML/etc.
- **Opset** — ONNX operator set version the model targets; mismatches between
  exporter and runtime cause load-time `InvalidGraph` errors.
- **Graph optimization level** — `ORT_DISABLE_ALL` ... `ORT_ENABLE_ALL`
  controls fusion and constant folding before execution; higher levels
  trade load time for steady-state throughput.
- **Quantization (INT8 / VNNI)** — Reduces a model to int8 weights; CPUs with
  AVX-VNNI accelerate this by roughly 2x over plain AVX2.
- **Providers list** — `ort.get_available_providers()` returns the backends
  compiled into the wheel; the CPU-only wheel reports just
  `CPUExecutionProvider`.

## Quick verification
```bash
venv/bin/python3 -c "import onnxruntime as ort; print(ort.__version__, ort.get_available_providers())"
```
Prints the ORT version and a provider list containing `CPUExecutionProvider`.

## Common pitfalls
- Opset mismatch between `torch.onnx.export(..., opset_version=N)` and the
  ORT wheel raises `InvalidGraph` at load time — pin the same opset on both
  sides (this repo's verification graph in `setup/self-tests/onnxruntime/`
  uses opset 13, which is supported by every ORT release oss-learn targets)
  and bump them together when upgrading.
- The CPU-only `onnxruntime` wheel will not use a GPU even if CUDA or
  ROCm is present on the host; you must explicitly install
  `onnxruntime-gpu` (which oss-learn does *not* ship) and request
  `CUDAExecutionProvider` in the providers list at session construction.
- Installing both `onnxruntime` and `onnxruntime-gpu` in the same venv
  shadows one another silently depending on import order — pick exactly
  one per venv and verify with `ort.get_available_providers()` after
  install.
- Dynamic quantization shrinks weights to int8 but the inference speedup
  only materializes on CPUs with AVX-VNNI (Cascade Lake / Ice Lake and
  newer); older Skylake-class chips show little or no gain and can even
  regress on small models.
- `InferenceSession` is not safe to share across forked processes; create
  one session per worker rather than sharing a Python object across a
  multiprocessing pool, otherwise threadpool state corrupts.

## Related specs
- `specs/openvino.md` — Intel-tuned alternative engine that ingests the
  exact same ONNX graph; useful for side-by-side CPU benchmarking on the
  same host so you can quantify the gap between a vendor-neutral runtime
  and one tuned for the chip you actually have.

## References
- Docs: https://onnxruntime.ai/docs/
- Source: https://github.com/microsoft/onnxruntime
- Python API reference: https://onnxruntime.ai/docs/api/python/api_summary.html
