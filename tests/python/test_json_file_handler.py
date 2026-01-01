import json
import os
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

from AjapopajaPlugin import (
    JsonFileHandler,
)


class TestJsonFileHandler:
    def test_read_file_valid_json(self):
        """Test reading a valid JSON file."""
        # Create a temporary JSON file
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            test_data = [{"name": "test1"}, {"name": "test2"}]
            json.dump(test_data, f)
            temp_file_path = f.name

        try:
            result = JsonFileHandler.read_file(Path(temp_file_path))
            assert result == test_data
        finally:
            os.unlink(temp_file_path)

    def test_read_file_invalid_json(self):
        """Test reading a file with invalid JSON."""
        # Create a temporary file with invalid JSON
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write('{"invalid": json}')
            temp_file_path = f.name

        try:
            result = JsonFileHandler.read_file(Path(temp_file_path))
            assert result == []
        finally:
            os.unlink(temp_file_path)

    def test_read_file_file_not_found(self):
        """Test reading a non-existent file."""
        non_existent_path = Path("non_existent_file.json")
        result = JsonFileHandler.read_file(non_existent_path)
        assert result == []

    def test_write_file_success(self):
        """Test writing data to a JSON file successfully."""
        with tempfile.TemporaryDirectory() as temp_dir:
            file_path = Path(temp_dir) / "test.json"
            test_data = [{"name": "test1"}, {"name": "test2"}]

            JsonFileHandler.write_file(file_path, test_data)

            # Verify file was created and contains correct data
            with open(file_path, "r") as f:
                result = json.load(f)
                assert result == test_data

    def test_write_file_create_directory(self):
        """Test writing to a file with non-existent directory."""
        with tempfile.TemporaryDirectory() as temp_dir:
            file_path = Path(temp_dir) / "subdir" / "test.json"
            test_data = [{"name": "test1"}]

            JsonFileHandler.write_file(file_path, test_data)

            # Verify directory was created and file contains correct data
            assert file_path.exists()
            with open(file_path, "r") as f:
                result = json.load(f)
                assert result == test_data

    def test_write_file_io_error(self):
        """Test writing file when IOError occurs."""
        with tempfile.TemporaryDirectory() as temp_dir:
            file_path = Path(temp_dir) / "test.json"
            test_data = [{"name": "test1"}]

            # Mock open to raise IOError
            with patch("builtins.open", side_effect=IOError("Permission denied")):
                with pytest.raises(IOError, match="Failed to write history file"):
                    JsonFileHandler.write_file(file_path, test_data)

    def test_write_file_type_error(self):
        """Test writing file when TypeError occurs during serialization."""
        with tempfile.TemporaryDirectory() as temp_dir:
            file_path = Path(temp_dir) / "test.json"
            test_data = [{"name": "test1"}]

            # Mock json.dump to raise TypeError
            with patch("json.dump", side_effect=TypeError("Cannot serialize object")):
                with pytest.raises(TypeError, match="Failed to serialize history data"):
                    JsonFileHandler.write_file(file_path, test_data)

    def test_write_file_empty_data(self):
        """Test writing empty data to a JSON file."""
        with tempfile.TemporaryDirectory() as temp_dir:
            file_path = Path(temp_dir) / "empty.json"
            test_data = []

            JsonFileHandler.write_file(file_path, test_data)

            # Verify file was created and contains empty list
            with open(file_path, "r") as f:
                result = json.load(f)
                assert result == test_data

    def test_read_file_empty_file(self):
        """Test reading an empty JSON file."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write("")
            temp_file_path = f.name

        try:
            result = JsonFileHandler.read_file(Path(temp_file_path))
            assert result == []
        finally:
            os.unlink(temp_file_path)

    def test_read_file_whitespace_only(self):
        """Test reading a file with only whitespace."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write("   \n  \t  ")
            temp_file_path = f.name

        try:
            result = JsonFileHandler.read_file(Path(temp_file_path))
            assert result == []
        finally:
            os.unlink(temp_file_path)
