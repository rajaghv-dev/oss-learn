"""Emit a single counter to OTLP/HTTP and watch it land in Prometheus as oss_*.

Run:  python examples/intermediate/05_otel_emit_metric.py
Prereq: bash start.sh   (OTel Collector on localhost:4318)
        pip install opentelemetry-api opentelemetry-sdk \
                    opentelemetry-exporter-otlp-proto-http
"""
import os
import sys

try:
    from opentelemetry import metrics
    from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
    from opentelemetry.sdk.metrics import MeterProvider
    from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
    from opentelemetry.sdk.resources import Resource
except ImportError as err:
    print(f"missing opentelemetry packages: {err}")
    sys.exit(0)

OTLP = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")
resource = Resource.create({"service.name": "oss-learn-counter-demo"})

reader = PeriodicExportingMetricReader(
    OTLPMetricExporter(endpoint=f"{OTLP}/v1/metrics"),
    export_interval_millis=1000,
)
metrics.set_meter_provider(MeterProvider(resource=resource, metric_readers=[reader]))

meter = metrics.get_meter(__name__)
counter = meter.create_counter("demo_counter_total", description="example counter")

try:
    for _ in range(10):
        counter.add(1, {"endpoint": "/hello"})
    metrics.get_meter_provider().shutdown()
except (ConnectionRefusedError, OSError) as err:
    print(f"otel-collector unreachable at {OTLP}: {err}")
    sys.exit(0)

print("emitted 10 counter increments to demo_counter_total")
print(f"check Prometheus at PROMETHEUS_URL/graph?g0.expr=oss_demo_counter_total_total")
