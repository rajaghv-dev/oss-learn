"""Load an .onnx file and print its IR version, opset, producer, and IO tensors.

Run:  python examples/beginner/04_onnx_load_inspect.py
Prereq: pip install onnx numpy   (already in repo's venv)
        Optional: ONNX_MODEL=/path/to/model.onnx
"""
import os
import tempfile
from pathlib import Path

import numpy as np
import onnx
from onnx import TensorProto, helper, numpy_helper

DTYPE_NAME = {v: k for k, v in TensorProto.DataType.items()}


def make_tiny_onnx(path: str) -> None:
    W = np.eye(3, dtype=np.float32)
    x = helper.make_tensor_value_info("x", TensorProto.FLOAT, [None, 3])
    y = helper.make_tensor_value_info("y", TensorProto.FLOAT, [None, 3])
    W_init = numpy_helper.from_array(W, "W")
    node = helper.make_node("MatMul", ["x", "W"], ["y"])
    graph = helper.make_graph([node], "tiny", [x], [y], [W_init])
    model = helper.make_model(
        graph,
        opset_imports=[helper.make_opsetid("", 17)],
        producer_name="oss-learn",
    )
    model.ir_version = 9
    onnx.save(model, path)


path = os.environ.get("ONNX_MODEL")
if not path or not Path(path).exists():
    path = str(Path(tempfile.gettempdir()) / "oss_learn_tiny.onnx")
    make_tiny_onnx(path)
    print(f"[note] ONNX_MODEL not set; generated tiny model at {path}")

model = onnx.load(path)
onnx.checker.check_model(model)

print(f"path        : {path}")
print(f"ir_version  : {model.ir_version}")
print(f"producer    : {model.producer_name or '<unset>'} {model.producer_version or ''}".strip())
print("opset       :")
for op in model.opset_import:
    print(f"  - domain={op.domain or 'ai.onnx':<10}  version={op.version}")


def describe(t):
    shape = []
    for d in t.type.tensor_type.shape.dim:
        shape.append(d.dim_value if d.dim_value > 0 else (d.dim_param or "?"))
    dtype = DTYPE_NAME.get(t.type.tensor_type.elem_type, str(t.type.tensor_type.elem_type))
    return f"name={t.name!r} shape={shape} dtype={dtype}"


print("inputs      :")
for t in model.graph.input:
    print(f"  - {describe(t)}")
print("outputs     :")
for t in model.graph.output:
    print(f"  - {describe(t)}")
