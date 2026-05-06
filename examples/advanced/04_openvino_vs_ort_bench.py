"""Benchmark the same FP32 MLP on ONNX Runtime CPU vs OpenVINO CPU.

Run:  python examples/advanced/04_openvino_vs_ort_bench.py
Prereq: bash scripts/setup/onnxruntime.sh && bash scripts/setup/openvino.sh
"""
import tempfile
import time
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
import openvino as ov
from onnx import TensorProto, helper, numpy_helper

IN_DIM, HIDDEN, OUT_DIM = 256, 512, 64
BATCH, ITERS = 8, 100
rng = np.random.default_rng(42)


def build_mlp(path: str) -> None:
    W1 = rng.standard_normal((IN_DIM, HIDDEN)).astype(np.float32) * 0.05
    W2 = rng.standard_normal((HIDDEN, OUT_DIM)).astype(np.float32) * 0.05
    x = helper.make_tensor_value_info("x", TensorProto.FLOAT, [None, IN_DIM])
    y = helper.make_tensor_value_info("y", TensorProto.FLOAT, [None, OUT_DIM])
    inits = [numpy_helper.from_array(W1, "W1"), numpy_helper.from_array(W2, "W2")]
    nodes = [
        helper.make_node("MatMul", ["x", "W1"], ["h0"]),
        helper.make_node("Relu", ["h0"], ["h1"]),
        helper.make_node("MatMul", ["h1", "W2"], ["h2"]),
        helper.make_node("Relu", ["h2"], ["y"]),
    ]
    graph = helper.make_graph(nodes, "mlp", [x], [y], inits)
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)], producer_name="oss-learn")
    model.ir_version = 9
    onnx.checker.check_model(model)
    onnx.save(model, path)


def percentiles(samples: list[float]) -> tuple[float, float]:
    s = sorted(samples)
    return s[ITERS // 2], s[int(ITERS * 0.9)]


tmp = Path(tempfile.mkdtemp(prefix="oss_bench_"))
onnx_path = tmp / "mlp.onnx"
build_mlp(str(onnx_path))
batch = rng.standard_normal((BATCH, IN_DIM)).astype(np.float32)

def time_runs(fn) -> list[float]:
    for _ in range(5):
        fn()
    out = []
    for _ in range(ITERS):
        t0 = time.perf_counter(); fn()
        out.append((time.perf_counter() - t0) * 1000.0)
    return out


ort_sess = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
ort_samples = time_runs(lambda: ort_sess.run(None, {"x": batch}))

core = ov.Core()
ov_compiled = core.compile_model(core.read_model(str(onnx_path)), "CPU")
ov_req = ov_compiled.create_infer_request()
ov_input = ov_compiled.inputs[0].get_any_name()
ov_samples = time_runs(lambda: ov_req.infer({ov_input: batch}))

ort_p50, ort_p90 = percentiles(ort_samples)
ov_p50, ov_p90 = percentiles(ov_samples)
print(f"workdir     : {tmp}")
print(f"batch       : {batch.shape}, iters={ITERS}")
print(f"ort version : {ort.__version__}")
print(f"ov version  : {ov.__version__} devices={core.available_devices}")
print()
print(f"{'engine':<14}  {'p50 ms':>8}  {'p90 ms':>8}")
print(f"{'onnxruntime':<14}  {ort_p50:>8.3f}  {ort_p90:>8.3f}")
print(f"{'openvino':<14}  {ov_p50:>8.3f}  {ov_p90:>8.3f}")
print(f"ratio p50   : ort/ov = {ort_p50/ov_p50:.2f}x")
print(f"ratio p90   : ort/ov = {ort_p90/ov_p90:.2f}x")
