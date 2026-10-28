import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    firebase_project_id: str = ""
    allowed_origins: tuple[str, ...] = ()
    resume_uploads_enabled: bool = False
    resume_worker_enabled: bool = False

    @classmethod
    def from_environment(cls):
        origins = tuple(
            origin.strip()
            for origin in os.getenv("ALLOWED_ORIGINS", "").split(",")
            if origin.strip()
        )
        if "*" in origins:
            raise ValueError("Use explicit ALLOWED_ORIGINS, not a wildcard.")
        return cls(
            os.getenv("FIREBASE_PROJECT_ID", "").strip(),
            origins,
            os.getenv("RESUME_UPLOADS_ENABLED", "").lower() == "true",
            os.getenv("RESUME_WORKER_ENABLED", "").lower() == "true",
        )
