"""Read ONNX with OpenVINO, save IR (.xml/.bin), reload, infer, assert match.

Run:  python examples/intermediate/05_openvino_onnx_to_ir.py
Prereq: bash scripts/setup/openvino.sh   (openvino in repo's venv)
        Optional: ONNX_MODEL=/path/to/model.onnx
"""
import os
import tempfile
from pathlib import Path

import numpy as np
import onnx
import openvino as ov
from onnx import TensorProto, helper, numpy_helper


def make_tiny_onnx(path: str) -> None:
    W = np.eye(3, dtype=np.float32)
    x = helper.make_tensor_value_info("x", TensorProto.FLOAT, [None, 3])
    y = helper.make_tensor_value_info("y", TensorProto.FLOAT, [None, 3])
    W_init = numpy_helper.from_array(W, "W")
    node = helper.make_node("MatMul", ["x", "W"], ["y"])
    graph = helper.make_graph([node], "tiny", [x], [y], [W_init])
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)], producer_name="oss-learn")
    model.ir_version = 9
    onnx.save(model, path)


onnx_path = os.environ.get("ONNX_MODEL")
if not onnx_path or not Path(onnx_path).exists():
    onnx_path = str(Path(tempfile.gettempdir()) / "oss_learn_tiny.onnx")
    make_tiny_onnx(onnx_path)
    print(f"[note] ONNX_MODEL not set; generated tiny model at {onnx_path}")

out_dir = Path("out")
out_dir.mkdir(exist_ok=True)
ir_xml = out_dir / "model.xml"

core = ov.Core()
print(f"openvino    : {ov.__version__}")
print(f"devices     : {core.available_devices}")

print(f"reading ONNX: {onnx_path}")
model = core.read_model(onnx_path)
ov.save_model(model, str(ir_xml))
print(f"saved IR    : {ir_xml} (+ {ir_xml.with_suffix('.bin')})")

reloaded = core.read_model(str(ir_xml))

input_name = model.inputs[0].get_any_name()
shape = [d if isinstance(d, int) and d > 0 else 4 for d in model.inputs[0].partial_shape.get_min_shape()]
rng = np.random.default_rng(0)
x = rng.standard_normal(size=shape).astype(np.float32)

orig_out = list(core.compile_model(model, "CPU").create_infer_request().infer({input_name: x}).values())[0]
ir_out = list(core.compile_model(reloaded, "CPU").create_infer_request().infer({input_name: x}).values())[0]

assert np.allclose(orig_out, ir_out, atol=1e-6), "IR roundtrip diverged from ONNX output"
print(f"input shape : {list(x.shape)}")
print(f"max |delta| : {np.max(np.abs(orig_out - ir_out)):.2e}")
print("status      : ok (ONNX <-> IR equivalent within 1e-6)")
