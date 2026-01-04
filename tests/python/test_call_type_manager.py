# Copyright (c) 2026 Marc Baechinger
# Licensed under the MIT License.

import json
import pytest
from pathlib import Path
from unittest.mock import mock_open, patch

from AjapopajaPlugin import (
    CallTypeManager,
)


class TestCallTypeManager:
    """Unit tests for CallTypeManager class."""

    def test_init_success(self):
        """Test successful initialization with valid file."""
        # Mock JSON data
        mock_data = {
            "call_type_1": {"id": 1, "name": "Type 1"},
            "call_type_2": {"id": 2, "name": "Type 2"},
        }

        with patch("builtins.open", mock_open(read_data=json.dumps(mock_data))):
            manager = CallTypeManager(Path("dummy_path.json"))
            assert manager.call_types == mock_data

    def test_init_file_not_found(self):
        """Test initialization with non-existent file."""
        with patch("builtins.open", side_effect=FileNotFoundError("File not found")):
            with pytest.raises(FileNotFoundError):
                CallTypeManager(Path("non_existent.json"))

    def test_init_invalid_json(self):
        """Test initialization with invalid JSON file."""
        with patch("builtins.open", mock_open(read_data="invalid json")):
            with pytest.raises(json.JSONDecodeError):
                CallTypeManager(Path("invalid.json"))

    def test_load_call_types_success(self):
        """Test _load_call_types method with valid data."""
        mock_data = {"type1": {"id": 1}, "type2": {"id": 2}}

        with patch("builtins.open", mock_open(read_data=json.dumps(mock_data))):
            manager = CallTypeManager(Path("dummy.json"))
            result = manager._load_call_types(Path("dummy.json"))
            assert result == mock_data

    def test_load_call_types_file_not_found(self):
        """Test _load_call_types method with non-existent file."""
        with patch("builtins.open", side_effect=FileNotFoundError("File not found")):
            with pytest.raises(FileNotFoundError):
                CallTypeManager(Path("dummy.json"))

    def test_load_call_types_invalid_json(self):
        """Test _load_call_types method with invalid JSON."""
        with patch("builtins.open", mock_open(read_data="invalid json")):
            with pytest.raises(json.JSONDecodeError):
                CallTypeManager(Path("dummy.json"))

    def test_get_call_type_exists(self):
        """Test get_call_type method with existing call type."""
        mock_data = {
            "type1": {"id": 1, "name": "Type 1"},
            "type2": {"id": 2, "name": "Type 2"},
        }

        with patch("builtins.open", mock_open(read_data=json.dumps(mock_data))):
            manager = CallTypeManager(Path("dummy.json"))
            result = manager.get_call_type("type1")
            assert result == {"id": 1, "name": "Type 1"}

    def test_get_call_type_not_exists(self):
        """Test get_call_type method with non-existing call type."""
        mock_data = {"type1": {"id": 1}, "type2": {"id": 2}}

        with patch("builtins.open", mock_open(read_data=json.dumps(mock_data))):
            manager = CallTypeManager(Path("dummy.json"))
            result = manager.get_call_type("nonexistent")
            assert result == {}

    def test_get_all_call_types(self):
        """Test get_all_call_types method."""
        mock_data = {"type1": {"id": 1}, "type2": {"id": 2}}

        with patch("builtins.open", mock_open(read_data=json.dumps(mock_data))):
            manager = CallTypeManager(Path("dummy.json"))
            result = manager.get_all_call_types()
            assert result == mock_data

    def test_get_all_call_type_names(self):
        """Test get_all_call_type_names method."""
        mock_data = {"type1": {"id": 1}, "type2": {"id": 2}, "type3": {"id": 3}}

        with patch("builtins.open", mock_open(read_data=json.dumps(mock_data))):
            manager = CallTypeManager(Path("dummy.json"))
            result = manager.get_all_call_type_names()
            assert result == ["type1", "type2", "type3"]
