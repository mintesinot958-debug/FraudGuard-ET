import os
from dataclasses import dataclass

from dotenv import load_dotenv

load_dotenv()


@dataclass(frozen=True)
class Settings:
    app_env: str
    database_url: str
    jwt_secret: str
    jwt_expire_minutes: int
    admin_emails: frozenset[str]
    cors_origins: tuple[str, ...]
    groq_api_key: str | None


def get_settings() -> Settings:
    # `or` (not a getenv default) so an empty JWT_SECRET= line also falls back.
    secret = os.getenv("JWT_SECRET") or "dev-only-change-this-secret-before-deployment"
    app_env = os.getenv("APP_ENV", "development")
    if app_env == "production" and (
        secret == "dev-only-change-this-secret-before-deployment"
        or secret.startswith("replace-with")
        or len(secret) < 32
    ):
        raise RuntimeError("Set JWT_SECRET to a random value of at least 32 characters.")

    # In development, allow all origins to avoid CORS issues.
    default_cors = "*" if app_env == "development" else "http://localhost:8765,http://127.0.0.1:8765"

    return Settings(
        app_env=app_env,
        database_url=os.getenv("DATABASE_URL", "sqlite:///./fraudguard.db"),
        jwt_secret=secret,
        jwt_expire_minutes=int(os.getenv("JWT_EXPIRE_MINUTES", "60")),
        admin_emails=frozenset(
            email.strip().lower()
            for email in os.getenv("ADMIN_EMAILS", "").split(",")
            if email.strip()
        ),
        cors_origins=tuple(
            origin.strip()
            for origin in os.getenv("CORS_ORIGINS", default_cors).split(",")
            if origin.strip()
        ),
        groq_api_key=os.getenv("GROQ_API_KEY", "").strip() or None,
    )


settings = get_settings()
