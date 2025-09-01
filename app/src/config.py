from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings."""

    DEBUG: bool = True
    LOG_LEVEL: str = "INFO"

    OTEL_COLLECTOR_ENDPOINT: str = "localhost:4317"
    OTEL_USERNAME: str = ""
    OTEL_PASSWORD: str = ""

    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="UTF-8", extra="allow"
    )


settings = Settings()
