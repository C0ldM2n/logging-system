# observability_lib/__init__.py

import functools
import logging
import os
import base64  # <-- Новое: Импортируем base64 для кодирования

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


def setup_observability(service_name: str):
    # --- Новое: Чтение конфигурации из окружения ---
    # Получаем эндпоинт коллектора. По умолчанию - localhost для локальной разработки.
    otel_collector_endpoint = os.environ.get(
        "OTEL_COLLECTOR_ENDPOINT", "localhost:4317"
    )

    # Получаем учетные данные для аутентификации
    otel_user = os.environ.get("OTEL_USERNAME")
    otel_pass = os.environ.get("OTEL_PASSWORD")

    resource = Resource(attributes={"service.name": service_name})

    # --- Новое: Формирование заголовков для аутентификации ---
    auth_headers = {}
    if otel_user and otel_pass:
        credentials = f"{otel_user}:{otel_pass}".encode("utf-8")
        encoded_credentials = base64.b64encode(credentials).decode("utf-8")
        auth_headers["Authorization"] = f"Basic {encoded_credentials}"
        print(
            "Observability: Используется аутентификация для подключения к OTel Collector."
        )
    else:
        print("Observability: OTel Collector используется без аутентификации.")

    # --- Трейсы ---
    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(
        BatchSpanProcessor(
            # <-- Изменено: Добавлены headers
            OTLPSpanExporter(
                endpoint=otel_collector_endpoint, insecure=True, headers=auth_headers
            )
        )
    )
    trace.set_tracer_provider(tracer_provider)

    # --- Метрики ---
    metric_reader = PeriodicExportingMetricReader(
        # <-- Изменено: Добавлены headers
        OTLPMetricExporter(
            endpoint=otel_collector_endpoint, insecure=True, headers=auth_headers
        )
    )
    meter_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
    metrics.set_meter_provider(meter_provider)

    # --- Логи ---
    logger_provider = LoggerProvider(resource=resource)
    logger_provider.add_log_record_processor(
        BatchLogRecordProcessor(
            # <-- Изменено: Добавлены headers
            OTLPLogExporter(
                endpoint=otel_collector_endpoint, insecure=True, headers=auth_headers
            )
        )
    )
    otel_handler = LoggingHandler(level=logging.INFO, logger_provider=logger_provider)

    # --- Настройка стандартного логгера ---
    # Убедимся, что предыдущие обработчики удалены, чтобы избежать дублирования логов
    for handler in logging.root.handlers[:]:
        logging.root.removeHandler(handler)

    logging.basicConfig(
        level=logging.INFO, handlers=[otel_handler, logging.StreamHandler(sys.stdout)]
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

    print(
        f"Observability для сервиса '{service_name}' успешно настроено. Эндпоинт: {otel_collector_endpoint}"
    )

    return log, tracer, meter


def instrumented(tracer):
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            with tracer.start_as_current_span(func.__name__) as span:
                try:
                    result = func(*args, **kwargs)
                    span.set_status(Status(StatusCode.OK))
                    return result
                except Exception as e:
                    span.record_exception(e)
                    span.set_status(Status(StatusCode.ERROR, str(e)))
                    raise

        return wrapper

    return decorator
