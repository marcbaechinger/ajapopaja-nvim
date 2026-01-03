from typing import Dict, Any, Optional
import threading

from helpers import FilePathHelper, JsonFileHandler

__all__ = ["HistoryManager"]


class HistoryManager:
    """Manages loading and persisting interaction history."""

    def __init__(self, history_dir: str) -> None:
        """Initialize the HistoryManager with a specified history file path.

        Args:
            history_dir (str): Path to the directory where JSON files are stored
        """
        self.history_dir = history_dir
        self.history: Dict[str, list] = self._load_history(["transform", "review"])
        self._lock = threading.Lock()

    def _load_history(self, call_types: list[str]) -> Dict[str, list]:
        """Loads interaction history from the local cache file.

        Args:
            call_types (list[str]): List of call type identifiers to load history for

        Returns:
            dict: Dictionary mapping call type strings to lists of interaction records.
        """
        history = {}
        for call_type in call_types:
            file_path = FilePathHelper.get_file_path(self.history_dir, call_type)
            history[call_type] = JsonFileHandler.read_file(file_path)
        return history

    def persist_history_locked(self, call_type: str):
        """Persist history with exclusive locking to prevent concurrent modifications.

        This method acquires an internal lock before persisting history, ensuring
        thread safety when multiple threads might attempt to modify the history
        simultaneously.

        Args:
            call_type (str): The type of call to persist history for, used to
                            determine the appropriate history persistence logic
        """
        with self._lock:
            self._persist_history(call_type)

    def _persist_history(self, call_type: str) -> None:
        """Helper to save the current history state to disk.

        Args:
            call_type: The type of LLM call (transform, review, ...)

        Raises:
            IOError: If failed to write to the history file
            TypeError: If history data cannot be serialized to JSON
        """
        file_path = FilePathHelper.get_file_path(self.history_dir, call_type)
        JsonFileHandler.write_file(file_path, self.history[call_type])

    def save_history(self, call_type: str, item: dict[str, Any]) -> Optional[Exception]:
        """Persists a new interaction and trims to the last 50 entries.

        Args:
            call_type (str): Type of interaction ('transform' or 'review')
            item (any): The interaction item to be saved

        Returns:
            Exception or None: Exception if save fails, None otherwise
        """
        if "uid" not in item:
            raise KeyError("uid")
        with self._lock:
            if call_type not in self.history:
                self.history[call_type] = []

            self.history[call_type].append(item)
            self.history[call_type] = self.history[call_type][-50:]
            try:
                self._persist_history(call_type)
            except (IOError, TypeError) as e:
                return e
            return None

    def get_uids(self, call_type: str) -> list[str]:
        """Retrieve all UIDs associated with a specific call type from the history.

        Args:
            call_type (str): The type of call to retrieve UIDs for

        Returns:
            list[str]: A list of UIDs corresponding to the specified call type.
        """
        with self._lock:
            if call_type not in self.history:
                return []
            return [item["uid"] for item in self.history[call_type]]

    def remove_by_uid(self, call_type, uid):
        """Remove a call item from the specified call history by its unique identifier.

        Args:
            call_type (str): The type of call history to search (e.g., 'transform' or 'review')
            uid (str): The unique identifier of the call item to remove

        Returns:
            str or None: The UID of the call item that replaces the removed one at
                the given index in the list or None if the removed item was the
                last in the list.
        """
        with self._lock:
            call_history = self.history[call_type]
            index = -1
            for i, item in enumerate(call_history):
                if item["uid"] == uid:
                    index = i
                    break
            if index >= 0 and index < len(call_history):
                call_history.pop(index)
                return call_history[index]["uid"] if index < len(call_history) else None
            return None
