import pytest
from unittest.mock import patch

from AjapopajaPlugin import (
    HistoryManager,
)


class TestHistoryManager:
    @pytest.fixture
    def mock_history_dir(self):
        return "/tmp/test_history"

    @pytest.fixture
    def history_manager(self, mock_history_dir):
        with (
            patch("AjapopajaPlugin.FilePathHelper.get_file_path") as mock_get_path,
            patch("AjapopajaPlugin.JsonFileHandler.read_file") as mock_read_file,
        ):
            mock_get_path.return_value = "/tmp/test_history/transform.json"
            mock_read_file.return_value = []

            manager = HistoryManager(mock_history_dir)
            return manager

    @pytest.fixture
    def history_manager_with_data(self, mock_history_dir):
        with (
            patch("AjapopajaPlugin.FilePathHelper.get_file_path") as mock_get_path,
            patch("AjapopajaPlugin.JsonFileHandler.read_file") as mock_read_file,
        ):
            mock_get_path.side_effect = lambda dir, call_type: f"{dir}/{call_type}.json"
            mock_read_file.side_effect = [
                [{"uid": "uid1", "data": "test1"}, {"uid": "uid2", "data": "test2"}],
                [{"uid": "uid3", "data": "test3"}],
            ]

            manager = HistoryManager(mock_history_dir)
            return manager

    def test_init(self, mock_history_dir):
        with (
            patch("AjapopajaPlugin.FilePathHelper.get_file_path") as mock_get_path,
            patch("AjapopajaPlugin.JsonFileHandler.read_file") as mock_read_file,
        ):
            mock_get_path.side_effect = lambda dir, call_type: f"{dir}/{call_type}.json"
            mock_read_file.side_effect = [[], []]

            manager = HistoryManager(mock_history_dir)

            assert manager.history_dir == mock_history_dir
            assert "transform" in manager.history
            assert "review" in manager.history
            assert manager.history["transform"] == []
            assert manager.history["review"] == []

    def test_load_history(self, mock_history_dir):
        with (
            patch("AjapopajaPlugin.FilePathHelper.get_file_path") as mock_get_path,
            patch("AjapopajaPlugin.JsonFileHandler.read_file") as mock_read_file,
        ):
            mock_get_path.side_effect = lambda dir, call_type: f"{dir}/{call_type}.json"
            mock_read_file.return_value = [{"uid": "uid1", "data": "test"}]

            manager = HistoryManager(mock_history_dir)

            assert manager.history["transform"] == [{"uid": "uid1", "data": "test"}]
            assert manager.history["review"] == [{"uid": "uid1", "data": "test"}]

    def test_save_history_success(self, history_manager):
        with patch.object(history_manager, "_persist_history") as mock_persist:
            mock_persist.return_value = None

            exception = history_manager.save_history(
                "transform", {"uid": "uid1", "data": "test"}
            )

            assert exception is None
            assert len(history_manager.history["transform"]) == 1
            assert history_manager.history["transform"][0]["uid"] == "uid1"

    def test_save_history_persistence_failure(self, history_manager):
        with patch.object(history_manager, "_persist_history") as mock_persist:
            mock_persist.side_effect = IOError("Write failed")

            exception = history_manager.save_history(
                "transform", {"uid": "uid1", "data": "test"}
            )

            assert isinstance(exception, IOError)
            assert history_manager.history["transform"][0]["uid"] == "uid1"

    def test_save_history_trim_to_50(self, history_manager):
        with patch.object(history_manager, "_persist_history"):
            # Add 55 items to test trimming
            for i in range(55):
                history_manager.save_history(
                    "transform", {"uid": f"uid{i}", "data": f"test{i}"}
                )

            assert len(history_manager.history["transform"]) == 50
            assert history_manager.history["transform"][0]["uid"] == "uid5"
            assert history_manager.history["transform"][-1]["uid"] == "uid54"

    def test_get_uids_empty_history(self, history_manager):
        uids = history_manager.get_uids("transform")
        assert uids == []

    def test_get_uids_with_data(self, history_manager_with_data):
        uids = history_manager_with_data.get_uids("transform")
        assert uids == ["uid1", "uid2"]

    def test_remove_by_uid_success(self, history_manager_with_data):
        result = history_manager_with_data.remove_by_uid("transform", "uid1")
        assert result == "uid2"  # Should return the uid of the next item
        assert len(history_manager_with_data.history["transform"]) == 1
        assert history_manager_with_data.history["transform"][0]["uid"] == "uid2"

    def test_remove_by_uid_last_item(self, history_manager_with_data):
        result = history_manager_with_data.remove_by_uid("transform", "uid2")
        assert result is None  # No next item
        assert len(history_manager_with_data.history["transform"]) == 1
        assert history_manager_with_data.history["transform"][0]["uid"] == "uid1"

    def test_remove_by_uid_not_found(self, history_manager_with_data):
        result = history_manager_with_data.remove_by_uid("transform", "nonexistent")
        assert result is None
        assert len(history_manager_with_data.history["transform"]) == 2

    def test_remove_by_uid_empty_history(self, history_manager):
        result = history_manager.remove_by_uid("transform", "uid1")
        assert result is None

    def test_get_uids(self, history_manager_with_data):
        transforms = history_manager_with_data.get_uids("transform")
        reviews = history_manager_with_data.get_uids("review")

        assert transforms == ["uid1", "uid2"]
        assert reviews == ["uid3"]

    def test_persist_history_io_error(self, history_manager):
        with patch("AjapopajaPlugin.JsonFileHandler.write_file") as mock_write:
            mock_write.side_effect = IOError("Disk full")

            with pytest.raises(IOError):
                history_manager._persist_history("transform")

    def test_persist_history_type_error(self, history_manager):
        with patch("AjapopajaPlugin.JsonFileHandler.write_file") as mock_write:
            mock_write.side_effect = TypeError("Cannot serialize")

            with pytest.raises(TypeError):
                history_manager._persist_history("transform")
