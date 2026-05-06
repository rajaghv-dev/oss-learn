"""
ONNX Runtime tests with dummy inference examples.

Verifies:
  - onnxruntime package is importable
  - CPUExecutionProvider is available
  - Can create a trivial ONNX model in-memory and run inference
  - Batch inference works
  - Input/output name introspection works
"""
import pytest

try:
    import onnxruntime as ort
    import numpy as np
    ONNX_AVAILABLE = True
except ImportError:
    ONNX_AVAILABLE = False

pytestmark = pytest.mark.skipif(
    not ONNX_AVAILABLE,
    reason="onnxruntime or numpy not installed — run: bash setup.sh --step onnxruntime"
)


# ── Helper: build a tiny ONNX model ──────────────────────────────────────────

def _make_linear_model():
    """
    Returns bytes of a minimal ONNX model: y = x * 2.0 + 1.0
    Built with onnx protobuf helpers, no training framework required.
    """
    import onnx
    from onnx import helper, TensorProto, numpy_helper
    import numpy as _np

    weight = numpy_helper.from_array(_np.array([2.0], dtype=_np.float32), name="weight")
    bias   = numpy_helper.from_array(_np.array([1.0], dtype=_np.float32), name="bias")

    mul_out = helper.make_node("Mul",  inputs=["x", "weight"], outputs=["mul_out"])
    add_out = helper.make_node("Add",  inputs=["mul_out", "bias"], outputs=["y"])

    graph = helper.make_graph(
        [mul_out, add_out],
        "linear",
        [helper.make_tensor_value_info("x", TensorProto.FLOAT, [None, 1])],
        [helper.make_tensor_value_info("y", TensorProto.FLOAT, [None, 1])],
        initializer=[weight, bias],
    )
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)])
    return model.SerializeToString()


# ── Tests ─────────────────────────────────────────────────────────────────────

def test_onnxruntime_import():
    """onnxruntime package is importable."""
    assert ort.__version__ is not None
    print(f"\n  onnxruntime version: {ort.__version__}")


def test_cpu_execution_provider_available():
    """CPUExecutionProvider is in the available providers list."""
    providers = ort.get_available_providers()
    assert "CPUExecutionProvider" in providers, f"CPU provider missing from {providers}"
    print(f"\n  available providers: {providers}")


def test_runtime_version_string():
    """ort.get_device() returns a usable device string."""
    device = ort.get_device()
    assert isinstance(device, str)
    assert len(device) > 0
    print(f"\n  device: {device}")


@pytest.fixture(scope="module")
def session():
    """Session for the trivial linear model."""
    try:
        model_bytes = _make_linear_model()
    except ImportError:
        pytest.skip("onnx package not installed — install with: pip install onnx")
    sess = ort.InferenceSession(model_bytes, providers=["CPUExecutionProvider"])
    return sess


def test_session_input_name(session):
    """InferenceSession can introspect input names."""
    inputs = session.get_inputs()
    assert len(inputs) >= 1
    assert inputs[0].name == "x"


def test_session_output_name(session):
    """InferenceSession can introspect output names."""
    outputs = session.get_outputs()
    assert len(outputs) >= 1
    assert outputs[0].name == "y"


def test_single_inference(session):
    """y = x * 2 + 1 produces the correct scalar result."""
    x = np.array([[3.0]], dtype=np.float32)
    result = session.run(["y"], {"x": x})
    y = result[0][0][0]
    assert abs(y - 7.0) < 1e-5, f"Expected 7.0, got {y}"
    print(f"\n  x=3.0 → y={y} (expected 7.0)")


def test_batch_inference(session):
    """Batch inference over 5 dummy inputs produces correct outputs."""
    xs = np.array([[1.0], [2.0], [3.0], [4.0], [5.0]], dtype=np.float32)
    expected = np.array([[3.0], [5.0], [7.0], [9.0], [11.0]], dtype=np.float32)
    results = session.run(["y"], {"x": xs})
    y_batch = results[0]
    assert np.allclose(y_batch, expected, atol=1e-5), f"Batch mismatch: {y_batch}"
    print(f"\n  batch [1-5] → {y_batch.flatten().tolist()}")


def test_zero_input(session):
    """x=0.0 → y=1.0 (bias check)."""
    x = np.array([[0.0]], dtype=np.float32)
    result = session.run(["y"], {"x": x})
    y = result[0][0][0]
    assert abs(y - 1.0) < 1e-5, f"Expected 1.0 for x=0, got {y}"


def test_negative_input(session):
    """Negative input: x=-1.0 → y=-1.0."""
    x = np.array([[-1.0]], dtype=np.float32)
    result = session.run(["y"], {"x": x})
    y = result[0][0][0]
    assert abs(y - (-1.0)) < 1e-5, f"Expected -1.0, got {y}"
