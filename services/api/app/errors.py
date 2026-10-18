class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str, *, retry_after: int | None = None):
        self.status = status
        self.code = code
        self.message = message
        self.retry_after = retry_after
