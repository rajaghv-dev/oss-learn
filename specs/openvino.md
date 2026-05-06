# OpenVINO

> Intel's CPU/iGPU inference toolkit for ONNX, IR, and PyTorch models.

| Field | Value |
|-------|-------|
| Category | ai / model inference |
| Repo role | optional |
| Install script | scripts/setup/openvino.sh |
| Validate suite | scripts/validate/ai.sh |
| Compose / config | — |
| Default port(s) | — |
| Default credentials | — |
| Resource footprint | pip wheel ~50 MB on disk (+ openvino-dev ~200 MB); IR runtime RAM depends on model and target device |

## What it is
OpenVINO is Intel's inference toolkit that compiles ONNX, PaddlePaddle,
TensorFlow, or PyTorch models into an Intermediate Representation (IR —
`.xml` graph + `.bin` weights) and runs them on CPU, integrated GPU, or NPU
through a single `Core` API. The PyPI `openvino` wheel includes the C++
runtime and Python bindings; `openvino-dev` adds Model Optimizer (`mo`),
`benchmark_app`, and accuracy tooling. Like ONNX Runtime it is library-only.

## Why it's in oss-learn
Demonstrates a vendor-tuned alternative to ONNX Runtime on the same hardware
so learners can compare graph compilation, INT8 quantization, and operator
fusion on CPU without needing a GPU. On Intel chips with AVX-VNNI / AMX it
typically outperforms ORT by a meaningful margin on the same `.onnx` file.

## How this repo wires it up
- `scripts/setup/openvino.sh` installs `openvino>=2024.1` (and best-effort
  `openvino-dev>=2024.1`) into the shared `venv/`. The `>=2024.1` floor is
  chosen because earlier wheels do not import cleanly on Python 3.12.
- Verification builds a tiny `Add` model with `ov.opset8`
  (`[1,3] + [1,3] -> [1,3]`), calls `core.compile_model(model, "CPU")`,
  runs `[1,2,3] + [4,5,6]`, and asserts the output equals `[5,7,9]` with
  `np.allclose`.
- `core.available_devices` is logged so users can immediately see whether
  the host exposes only `CPU` or also an iGPU/NPU plugin.
- Manifest at `setup/state/installs/openvino.yaml` records the venv path,
  packages (`openvino,openvino-dev`), and resolved version for `cleanup.sh`.
- `--build` is wired to clone `openvinotoolkit/openvino`, run cmake against
  the venv's Python, and `pip install` the produced wheel; the default path
  stays on PyPI for speed since a full source build is multi-hour.
- `scripts/validate/ai.sh` runs the pytest probe at
  `setup/self-tests/openvino/test_install.py` and the bash counterpart at
  `setup/validate/openvino.sh`.

## Key concepts
- **Core** — Top-level handle used to discover devices, read models, and
  compile them; cheap to construct, expected to be reused.
- **IR (.xml + .bin)** — OpenVINO's native format produced by Model
  Optimizer; loads faster than raw ONNX and supports per-layer device hints.
- **CompiledModel / InferRequest** — A device-bound graph plus a reusable
  inference request that holds input/output tensors so allocation costs are
  paid once.
- **Plugin / Device** — `CPU`, `GPU`, `NPU`, plus the meta-devices `AUTO`
  and `MULTI`; selected at `compile_model` time.
- **POT / NNCF** — Post-training Optimization Tool and Neural Network
  Compression Framework, the INT8 quantization toolkits shipped with
  `openvino-dev`.
- **opset8** — The operator set the verification model targets; chosen
  because every supported OpenVINO version since 2022.3 understands it.

## Quick verification
```bash
venv/bin/python3 -c "import openvino as ov; print(ov.__version__, ov.Core().available_devices)"
```
Prints the OpenVINO version and a device list including at least `CPU`.

## Common pitfalls
- The `openvino` wheel only supports Python ≥3.9 (and only certain 3.12
  patch versions on older OpenVINO releases) — `pip install openvino` will
  silently resolve to an ancient build on EOL Pythons, and the symptom is
  usually an obscure `ImportError: undefined symbol` rather than a clean
  version mismatch error, so check `python --version` before `pip` does.
- The iGPU plugin requires the `intel-opencl-icd` system package; without
  it `core.available_devices` will list only `CPU` even on a Tiger-Lake or
  newer laptop, and `compile_model(model, "GPU")` will raise at runtime.
  Install via `apt install intel-opencl-icd` and re-run setup.
- INT8 quantization needs `openvino-dev` (which pulls in POT / NNCF and
  ~200 MB of extra wheels); the runtime `openvino` wheel alone can *load*
  pre-quantized IR but cannot *produce* it from FP32 inputs, so you need
  the dev wheel on whichever box does the conversion.
- `core.read_model` against a `.onnx` file works but requires the producer
  to use a supported opset (currently 7-22 on OpenVINO 2024.x) — when in
  doubt, convert via `mo` or `ovc` to native IR first; the IR loader is
  noticeably faster and surfaces opset issues at conversion time, not
  inference time.
- The meta-device `AUTO` selects `GPU` when present and falls back to
  `CPU` silently — pin `"CPU"` explicitly when benchmarking against ONNX
  Runtime to keep the comparison apples-to-apples, otherwise you may be
  comparing two different devices without realising it.

## Related specs
- `specs/onnxruntime.md` — vendor-neutral alternative that runs the same
  ONNX graph on CPU without IR conversion; useful as a portability baseline
  and as the reference point against which OpenVINO's INT8 / VNNI / AMX
  speedups are measured in the advanced benchmarking example.

## References
- Docs: https://docs.openvino.ai/
- Source: https://github.com/openvinotoolkit/openvino
- Python API quickstart: https://docs.openvino.ai/2024/openvino-workflow/running-inference/integrate-openvino-with-your-application.html
