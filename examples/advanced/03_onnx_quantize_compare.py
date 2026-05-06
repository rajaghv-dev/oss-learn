"""Generate FP32 MLP, benchmark CPU inference, dynamic-quantize to INT8, re-bench.

Run:  python examples/advanced/03_onnx_quantize_compare.py
Prereq: pip install onnx onnxruntime numpy   (already in repo's venv)
"""
import tempfile
import time
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
from onnx import TensorProto, helper, numpy_helper
from onnxruntime.quantization import QuantType, quantize_dynamic

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


def bench(path: str, batch: np.ndarray) -> tuple[float, float, float]:
    sess = ort.InferenceSession(path, providers=["CPUExecutionProvider"])
    for _ in range(5):
        sess.run(None, {"x": batch})
    samples = []
    for _ in range(ITERS):
        t0 = time.perf_counter()
        sess.run(None, {"x": batch})
        samples.append((time.perf_counter() - t0) * 1000.0)
    s = sorted(samples)
    return s[ITERS // 2], s[int(ITERS * 0.9)], s[int(ITERS * 0.99)]


tmp = Path(tempfile.mkdtemp(prefix="oss_quant_"))
fp32 = tmp / "mlp_fp32.onnx"
int8 = tmp / "mlp_int8.onnx"
build_mlp(str(fp32))
quantize_dynamic(str(fp32), str(int8), weight_type=QuantType.QInt8)

batch = rng.standard_normal((BATCH, IN_DIM)).astype(np.float32)
fp32_p50, fp32_p90, fp32_p99 = bench(str(fp32), batch)
int8_p50, int8_p90, int8_p99 = bench(str(int8), batch)

print(f"workdir     : {tmp}")
print(f"fp32 size   : {fp32.stat().st_size/1024:.1f} KB")
print(f"int8 size   : {int8.stat().st_size/1024:.1f} KB")
print(f"batch       : {batch.shape}, iters={ITERS}")
print()
print(f"{'precision':<10}  {'p50 ms':>8}  {'p90 ms':>8}  {'p99 ms':>8}")
print(f"{'fp32':<10}  {fp32_p50:>8.3f}  {fp32_p90:>8.3f}  {fp32_p99:>8.3f}")
print(f"{'int8':<10}  {int8_p50:>8.3f}  {int8_p90:>8.3f}  {int8_p99:>8.3f}")
print(f"speedup p50 : {fp32_p50/int8_p50:.2f}x")
