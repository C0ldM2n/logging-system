import os
import sys
import time
from random import randint

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from observability_lib import instrumented, setup_observability

log, tracer, meter = setup_observability(service_name="db-consumer-service")

processed_messages_counter = meter.create_counter(
    "processed_messages_total",
    description="Total number of messages processed by the consumer",
)


@instrumented(tracer)
def save_to_database(message: dict):
    log.info("Сохранение в БД...", message_id=message["id"])
    time.sleep(randint(2, 5) / 10)
    if randint(1, 10) == 1:
        raise ConnectionError("Не удалось подключиться к базе данных!")
    log.info("Сообщение успешно сохранено.", message_id=message["id"])


@instrumented(tracer)
def consume_message():
    message_id = randint(1000, 2000)
    user_id = f"user_{randint(1, 100)}"
    local_log = log.bind(user_id=user_id)

    local_log.info("Получено новое сообщение.", message_id=message_id)
    save_to_database({"id": message_id, "user": user_id})
    processed_messages_counter.add(1, {"status": "success"})
    local_log.info("Сообщение полностью обработано.", message_id=message_id)


if __name__ == "__main__":
    try:
        while True:
            try:
                consume_message()
            except Exception as e:
                log.error("Ошибка при обработке сообщения.", error=str(e))
                processed_messages_counter.add(1, {"status": "error"})
            time.sleep(1)
    except KeyboardInterrupt:
        log.info("Сервис останавливается.")
