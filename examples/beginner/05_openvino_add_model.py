"""Build an Add graph with ov.opset8 and run it on the CPU device.

Run:  python examples/beginner/05_openvino_add_model.py
Prereq: bash scripts/setup/openvino.sh   (openvino in repo's venv)
"""
import numpy as np
import openvino as ov

opset = ov.opset8

a_param = opset.parameter(ov.Shape([1, 3]), ov.Type.f32, name="a")
b_param = opset.parameter(ov.Shape([1, 3]), ov.Type.f32, name="b")
add = opset.add(a_param, b_param)
model = ov.Model([add], [a_param, b_param], "add_1x3")

core = ov.Core()
print(f"openvino    : {ov.__version__}")
print(f"devices     : {core.available_devices}")

compiled = core.compile_model(model, "CPU")
infer_req = compiled.create_infer_request()

a = np.array([[1.0, 2.0, 3.0]], dtype=np.float32)
b = np.array([[4.0, 5.0, 6.0]], dtype=np.float32)
result = infer_req.infer({"a": a, "b": b})
out = list(result.values())[0]

expected = np.array([[5.0, 7.0, 9.0]], dtype=np.float32)
assert np.allclose(out, expected), f"unexpected output: {out}"

print(f"input a     : {a.tolist()}")
print(f"input b     : {b.tolist()}")
print(f"output      : {out.tolist()}")
print("status      : ok")
