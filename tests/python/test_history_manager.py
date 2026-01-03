import pytest
from unittest.mock import patch

from history import HistoryManager


class TestHistoryManager:
    @pytest.fixture
    def history_manager(self):
        """Create a HistoryManager instance for testing."""
        with (
            patch("helpers.FilePathHelper.get_file_path") as mock_get_path,
            patch("helpers.JsonFileHandler.read_file") as mock_read_file,
        ):
            mock_get_path.return_value = "/mock/path"
            mock_read_file.return_value = []
            return HistoryManager("/mock/history/dir")

    @pytest.fixture
    def history_manager_with_data(self):
        """Create a HistoryManager instance with initial data."""
        with (
            patch("helpers.FilePathHelper.get_file_path") as mock_get_path,
            patch("helpers.JsonFileHandler.read_file") as mock_read_file,
        ):
            mock_get_path.return_value = "/mock/path"
            mock_read_file.return_value = [
                {"uid": "uid1", "data": "test1"},
                {"uid": "uid2", "data": "test2"},
            ]
            return HistoryManager("/mock/history/dir")

    def test_init_creates_history_dict(self, history_manager):
        """Test that HistoryManager initializes with correct structure."""
        assert hasattr(history_manager, "history")
        assert isinstance(history_manager.history, dict)
        assert "transform" in history_manager.history
        assert "review" in history_manager.history

    def test_load_history_returns_correct_structure(self, history_manager):
        """Test that _load_history returns correct dictionary structure."""
        with (
            patch("helpers.FilePathHelper.get_file_path") as mock_get_path,
            patch("helpers.JsonFileHandler.read_file") as mock_read_file,
        ):
            mock_get_path.return_value = "/mock/path/transform"
            mock_read_file.return_value = [{"uid": "test1"}]

            result = history_manager._load_history(["transform"])

            assert isinstance(result, dict)
            assert "transform" in result
            assert isinstance(result["transform"], list)

    def test_persist_history_writes_correctly(self, history_manager):
        """Test that _persist_history writes data correctly."""
        with (
            patch("helpers.FilePathHelper.get_file_path") as mock_get_path,
            patch("helpers.JsonFileHandler.write_file") as mock_write_file,
        ):
            mock_get_path.return_value = "/mock/path/transform"

            history_manager.history["transform"] = [{"uid": "test1"}]
            history_manager._persist_history("transform")

            mock_write_file.assert_called_once_with(
                "/mock/path/transform", [{"uid": "test1"}]
            )

    def test_save_history_item_without_uid_raise_key_error(self, history_manager):
        """Test that save_history adds item and trims history to 50 entries."""
        with (
            patch("helpers.FilePathHelper.get_file_path"),
            patch("helpers.JsonFileHandler.write_file"),
        ):
            with pytest.raises(KeyError) as exc_info:
                history_manager.save_history("transform", {"data": "data"})
            assert str(exc_info.value) == "'uid'"

    def test_save_history_adds_item_and_trims_to_50(self, history_manager):
        """Test that save_history adds item and trims history to 50 entries."""
        with (
            patch("helpers.FilePathHelper.get_file_path"),
            patch("helpers.JsonFileHandler.write_file"),
        ):
            # Add 55 items to test trimming
            for i in range(55):
                exception = history_manager.save_history(
                    "transform", {"uid": f"uid{i}", "data": f"data{i}"}
                )
                assert exception is None

            assert len(history_manager.history["transform"]) == 50

    def test_save_history_returns_exception_on_write_failure(self, history_manager):
        """Test that save_history returns exception when write fails."""
        with (
            patch("helpers.FilePathHelper.get_file_path"),
            patch(
                "helpers.JsonFileHandler.write_file",
                side_effect=IOError("Write failed"),
            ),
        ):
            exception = history_manager.save_history(
                "transform", {"uid": "uid1", "data": "test"}
            )
            assert isinstance(exception, IOError)
            assert str(exception) == "Write failed"

    def test_get_uids_returns_empty_list_when_no_history(self, history_manager):
        """Test that get_uids returns empty list when no history exists."""
        assert history_manager.get_uids("transform") == []

    def test_get_uids_returns_uids_from_history(self, history_manager_with_data):
        """Test that get_uids returns UIDs from history."""
        uids = history_manager_with_data.get_uids("transform")
        assert uids == ["uid1", "uid2"]

    def test_remove_by_uid_removes_correct_item(self, history_manager_with_data):
        """Test that remove_by_uid removes the correct item."""
        with (
            patch("helpers.FilePathHelper.get_file_path"),
            patch("helpers.JsonFileHandler.write_file"),
        ):
            # Remove first item
            result = history_manager_with_data.remove_by_uid("transform", "uid1")
            assert result == "uid2"  # Should return UID of next item

            # Verify item was removed
            uids = history_manager_with_data.get_uids("transform")
            assert uids == ["uid2"]

    def test_remove_by_uid_returns_none_when_no_item_found(
        self, history_manager_with_data
    ):
        """Test that remove_by_uid returns None when item not found."""
        result = history_manager_with_data.remove_by_uid("transform", "nonexistent")
        assert result is None

    def test_remove_by_uid_handles_last_item_removal(self, history_manager_with_data):
        """Test that remove_by_uid handles removal of last item correctly."""
        with (
            patch("helpers.FilePathHelper.get_file_path"),
            patch("helpers.JsonFileHandler.write_file"),
        ):
            # Remove last item
            result = history_manager_with_data.remove_by_uid("transform", "uid2")
            assert result is None  # No next item

    def test_save_history_thread_safety(self, history_manager):
        """Test that save_history is thread-safe."""
        import threading
        import time

        def save_items():
            for i in range(10):
                history_manager.save_history(
                    "transform", {"uid": f"uid{i}", "data": f"data{i}"}
                )
                time.sleep(0.001)

        # Create multiple threads
        threads = []
        for _ in range(5):
            t = threading.Thread(target=save_items)
            threads.append(t)
            t.start()

        # Wait for all threads to complete
        for t in threads:
            t.join()

        # Verify history was saved correctly
        assert len(history_manager.history["transform"]) == 50

    def test_save_history_creates_new_call_type_if_not_exists(self, history_manager):
        """Test that save_history creates new call type if it doesn't exist."""
        with (
            patch("helpers.FilePathHelper.get_file_path"),
            patch("helpers.JsonFileHandler.write_file"),
        ):
            exception = history_manager.save_history(
                "new_call_type", {"uid": "uid1", "data": "test"}
            )
            assert exception is None
            assert "new_call_type" in history_manager.history
            assert history_manager.history["new_call_type"] == [
                {"uid": "uid1", "data": "test"}
            ]
