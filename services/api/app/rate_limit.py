"""Bounded per-process throttling for verified profile identities."""

from collections import OrderedDict
from math import ceil
from threading import Lock
from time import monotonic

from app.errors import ApiError


class ProfileRateLimiter:
    def __init__(self, limit=60, window_seconds=60, max_accounts=4096, clock=monotonic):
        self.limit = limit
        self.window = window_seconds
        self.max_accounts = max_accounts
        self.clock = clock
        self.accounts = OrderedDict()
        self.lock = Lock()

    def check(self, uid):
        with self.lock:
            # Read time under the lock so concurrent insertion order stays chronological.
            now = self.clock()
            # Insertion order is window-start order; never retain unbounded identities.
            while self.accounts:
                first_uid, (started, _) = next(iter(self.accounts.items()))
                if now - started < self.window:
                    break
                del self.accounts[first_uid]
            if uid not in self.accounts:
                if len(self.accounts) >= self.max_accounts:
                    raise ApiError(503, "profile_busy", "Profile service is busy. Please retry.")
                self.accounts[uid] = (now, 0)
            started, count = self.accounts[uid]
            if count >= self.limit:
                retry = max(1, ceil(self.window - (now - started)))
                raise ApiError(
                    429,
                    "profile_rate_limited",
                    "Too many profile requests. Please wait.",
                    retry_after=retry,
                )
            self.accounts[uid] = (started, count + 1)
