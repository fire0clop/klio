from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    DATABASE_URL: str
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 10080  # 7 дней
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    ANTHROPIC_API_KEY: str
    ANTHROPIC_PROXY_URL: str = ""  # http://user:pass@host:port

    # ----- Social auth -----
    # iOS bundle ID — Apple uses it as audience claim in the identity_token.
    APPLE_CLIENT_ID: str = "com.klio.diary"
    # Google iOS OAuth client ID. Format: "1234567890-xxxx.apps.googleusercontent.com"
    # Used as audience claim when verifying Google id_token.
    GOOGLE_CLIENT_ID: str = ""


settings = Settings()
