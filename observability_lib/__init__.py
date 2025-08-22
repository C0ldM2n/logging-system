import functools
import logging

import structlog
from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.trace import Status, StatusCode


def setup_observability(
    service_name: str, otel_collector_endpoint: str = "grpc://localhost:4317"
):
    resource = Resource(attributes={"service.name": service_name})

    # --- Трейсы ---
    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(
        BatchSpanProcessor(
            OTLPSpanExporter(endpoint=otel_collector_endpoint, insecure=True)
        )
    )
    trace.set_tracer_provider(tracer_provider)

    # --- Метрики ---
    metric_reader = PeriodicExportingMetricReader(
        OTLPMetricExporter(endpoint=otel_collector_endpoint, insecure=True)
    )
    meter_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
    metrics.set_meter_provider(meter_provider)

    # --- Логи ---
    logger_provider = LoggerProvider(resource=resource)
    logger_provider.add_log_record_processor(
        BatchLogRecordProcessor(
            OTLPLogExporter(endpoint=otel_collector_endpoint, insecure=True)
        )
    )
    otel_handler = LoggingHandler(level=logging.INFO, logger_provider=logger_provider)

    # --- Настройка стандартного логгера ---
    logging.basicConfig(
        level=logging.INFO, handlers=[otel_handler, logging.StreamHandler()]
    )
    LoggingInstrumentor().instrument(set_logging_format=False)

    # --- Structlog для удобного логирования ---
    structlog.configure(
        processors=[
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.stdlib.add_log_level,
            structlog.processors.JSONRenderer(),
        ],
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )
    log = structlog.get_logger(service_name)

    tracer = trace.get_tracer(f"{service_name}-tracer")
    meter = metrics.get_meter(f"{service_name}-meter")

    return log, tracer, meter


def instrumented(tracer):
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            with tracer.start_as_current_span(func.__name__) as span:
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    span.record_exception(e)
                    span.set_status(Status(StatusCode.ERROR, str(e)))
                    raise

        return wrapper

    return decorator
