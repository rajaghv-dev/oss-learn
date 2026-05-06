"""Build a tiny linear ONNX model in-memory and run inference with onnxruntime.

Run:  python examples/intermediate/03_onnx_inference.py
Prereq: pip install onnx onnxruntime numpy   (already in repo's venv)
"""
import numpy as np
import onnx
import onnxruntime as ort
from onnx import TensorProto, helper, numpy_helper

W = np.array([[2.0, -1.0, 0.5]], dtype=np.float32)
b = np.array([0.1], dtype=np.float32)

x = helper.make_tensor_value_info("x", TensorProto.FLOAT, [None, 3])
y = helper.make_tensor_value_info("y", TensorProto.FLOAT, [None, 1])
W_init = numpy_helper.from_array(W.T, "W")
b_init = numpy_helper.from_array(b, "b")
matmul = helper.make_node("MatMul", ["x", "W"], ["xW"])
add = helper.make_node("Add", ["xW", "b"], ["y"])
graph = helper.make_graph([matmul, add], "linear", [x], [y], [W_init, b_init])
model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)])
model.ir_version = 9
onnx.checker.check_model(model)

sess = ort.InferenceSession(model.SerializeToString(), providers=["CPUExecutionProvider"])
batch = np.array([[1.0, 2.0, 3.0], [0.0, 0.0, 0.0], [1.5, -2.0, 4.0]], dtype=np.float32)
out = sess.run(["y"], {"x": batch})[0]

print("inputs           -> output")
for inp, pred in zip(batch, out):
    print(f"  {inp}  ->  {pred[0]:+.3f}")
