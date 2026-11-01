"""Stages on their own threads, joined by queues, so a frame costs only its slowest stage.

The queues stay in RAM: they hold JPEG that is not encrypted yet, which must not reach a disk.
"""

import threading
from collections import deque
from typing import Callable, List, Optional

_POLL_S = 0.1  # Stop requests are noticed within this


class FrameQueue:
    """FIFO with a limit. When full it drops its oldest item, or makes put() wait."""

    def __init__(self, capacity: int, drop_oldest: bool):
        self.capacity = capacity
        self.dropped = 0
        self.closed = False
        self._drop_oldest = drop_oldest
        self._items = deque()
        self._changed = threading.Condition()

    def __len__(self) -> int:
        return len(self._items)

    def put(self, item) -> None:
        with self._changed:
            while len(self._items) >= self.capacity and not self.closed:
                if self._drop_oldest:
                    self._items.popleft()
                    self.dropped += 1
                else:
                    self._changed.wait(_POLL_S)
            if not self.closed:
                self._items.append(item)
                self._changed.notify_all()

    def get(self):
        """Returns the oldest item, or None once the queue is closed and empty."""
        with self._changed:
            while not self._items and not self.closed:
                self._changed.wait(_POLL_S)
            item = self._items.popleft() if self._items else None
            self._changed.notify_all()
            return item

    def wait_until_holding(self, count: int) -> None:
        """Returns when `count` items wait here, or no more can come."""
        with self._changed:
            while len(self._items) < count and not self.closed:
                self._changed.wait(_POLL_S)

    def close(self) -> None:
        """No more items: what is here can still be read."""
        with self._changed:
            self.closed = True
            self._changed.notify_all()

    def abort(self) -> None:
        with self._changed:
            self.closed = True
            self._items.clear()
            self._changed.notify_all()


class Stages:
    """Runs functions on their own threads. The first error stops them all and is kept for the caller."""

    def __init__(self, stages: List[Callable[[], None]], abort: Callable[[], None]):
        self._abort = abort
        self.failure: Optional[Exception] = None
        self._threads = [threading.Thread(target=self._run, args=(stage,), daemon=True) for stage in stages]

    def _run(self, stage: Callable[[], None]) -> None:
        try:
            stage()
        except Exception as error:  # Raised again on the thread that reports it
            self.failure = self.failure or error
            self._abort()

    def start(self) -> None:
        for thread in self._threads:
            thread.start()

    def alive(self) -> bool:
        return any(thread.is_alive() for thread in self._threads)

    def join(self, timeout: float) -> None:
        for thread in self._threads:
            thread.join(timeout)
