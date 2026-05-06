"""Emit a parent + child span and three metrics to the OTel Collector via OTLP/HTTP.

Run:  python examples/advanced/02_otel_emit.py
Prereq: bash start.sh   (OTel Collector on localhost:4318)
        pip install opentelemetry-api opentelemetry-sdk \
                    opentelemetry-exporter-otlp-proto-http
"""
import os
import time

from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

OTLP = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")
resource = Resource.create({"service.name": "oss-learn-example"})

trace.set_tracer_provider(TracerProvider(resource=resource))
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint=f"{OTLP}/v1/traces"))
)

reader = PeriodicExportingMetricReader(
    OTLPMetricExporter(endpoint=f"{OTLP}/v1/metrics"),
    export_interval_millis=2000,
)
metrics.set_meter_provider(MeterProvider(resource=resource, metric_readers=[reader]))

tracer = trace.get_tracer(__name__)
meter = metrics.get_meter(__name__)
counter = meter.create_counter("demo_requests_total", description="example counter")
histogram = meter.create_histogram("demo_latency_ms", unit="ms")

with tracer.start_as_current_span("parent_op") as parent:
    parent.set_attribute("user.id", 42)
    for i in range(5):
        with tracer.start_as_current_span(f"child_{i}"):
            time.sleep(0.05)
            counter.add(1, {"endpoint": "/predict"})
            histogram.record(50 + i * 10, {"endpoint": "/predict"})

trace.get_tracer_provider().shutdown()
metrics.get_meter_provider().shutdown()
print("emitted 1 parent + 5 child spans and 5 counter/histogram points")
print(f"check Grafana → Explore → tempo/prometheus at the relevant URL")
