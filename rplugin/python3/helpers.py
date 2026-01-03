from pathlib import Path
from typing import Dict, Any
import json
import os
import re
import textwrap

__all__ = [
    "get_plugin_path",
    "CallTypeManager",
    "FilePathHelper",
    "JsonFileHandler",
    "FormatUtil",
]


def get_plugin_path() -> Path:
    """
    Returns the absolute path to the root of the Neovim plugin.
    Equivalent to the Lua runtime-file discovery.
    """
    current_file = Path(__file__).resolve()

    try:
        plugin_root = current_file.parents[2]
        if plugin_root.exists():
            return plugin_root
    except IndexError as e:
        raise e
    raise ValueError("plugin root not found")


class CallTypeManager:
    """Manages call types loaded from a JSON file for configuration and lookup."""

    def __init__(self, file_path: Path):
        """Initialize the CallTypeManager with a file path.

        Args:
            file_path (Path): Path to the JSON file containing call type definitions
        """
        self.call_types = self._load_call_types(file_path)

    def _load_call_types(self, file_path: Path) -> Dict[str, Any]:
        """Load call types from a JSON file.

        Args:
            file_path (Path): Path to the JSON file containing call type definitions

        Returns:
            Dict[str, Any]: Dictionary containing all call type definitions

        Raises:
            FileNotFoundError: If the specified file does not exist
            json.JSONDecodeError: If the file contains invalid JSON
        """
        try:
            with open(file_path, "r") as file:
                return json.load(file)
        except FileNotFoundError as e:
            raise e
        except json.JSONDecodeError as e:
            raise e

    def get_call_type(self, call_type: str) -> Dict[str, Any]:
        """Get a specific call type by name.

        Args:
            call_type (str): Name of the call type to retrieve

        Returns:
            Dict[str, Any]: Dictionary containing the call type definition,
                           or empty dict if not found
        """
        return self.call_types.get(call_type, {})

    def get_all_call_types(self) -> Dict[str, Any]:
        """Get all call types.

        Returns:
            Dict[str, Any]: Dictionary containing all call type definitions
        """
        return self.call_types

    def get_all_call_type_names(self) -> list[str]:
        """Get all call type names.

        Returns:
            list[str]: List of all call type names
        """
        return list(self.call_types)


class FilePathHelper:
    """Helper class for file path operations."""

    @staticmethod
    def get_file_path(history_dir: str, call_type: str) -> Path:
        """Construct the file path for a given call type.

        Args:
            history_dir (str): Path to the directory where JSON files are stored
            call_type (str): Type of LLM call (transform, review, ...)

        Returns:
            Path: The constructed file path
        """
        return Path(history_dir) / f"{call_type}.json"


class JsonFileHandler:
    """Handles file operations."""

    @staticmethod
    def read_file(file_path: Path) -> list:
        """Read and parse a JSON file.

        Args:
            file_path (Path): Path to the JSON file

        Returns:
            list: The parsed JSON data as a list
        """
        try:
            with open(file_path, "r") as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            return []

    @staticmethod
    def write_file(file_path: Path, data: list) -> None:
        """Write data to a JSON file.

        Args:
            file_path (Path): Path to the JSON file
            data (list): Data to be written to the file

        Raises:
            IOError: If failed to write to the history file
            TypeError: If history data cannot be serialized to JSON
        """
        try:
            os.makedirs(os.path.dirname(file_path), exist_ok=True)
            with open(file_path, "w") as f:
                json.dump(data, f)
        except IOError as e:
            raise IOError(f"Failed to write history file '{file_path}': {e}")
        except TypeError as e:
            raise TypeError(f"Failed to serialize history data: {e}")


class FormatUtil:
    """Handles building structured prompts with optional code blocks."""

    @staticmethod
    def build_prompt(prompt: str, lang: str, selected_code: str) -> str:
        """Constructs a structured prompt with Markdown code blocks.

        Args:
            prompt (str): The main prompt text
            lang (str): Language identifier for the code block (e.g., 'python', 'javascript')
            selected_code (str): Text to be wrapped in a code block

        Returns:
            str: Combined prompt with optional code block
        """
        parts = []
        if prompt:
            parts.append(prompt)
        if selected_code:
            selected_code = textwrap.dedent(selected_code)
            lang_label = lang if lang else ""
            parts.append(f"\n\n```{lang_label}\n{selected_code}\n```")
        return "".join(parts)

    @staticmethod
    def strip_code_fence(text: str) -> str:
        """Removes Markdown code delimiters from LLM responses.

        Args:
            text (str): Text potentially containing Markdown code blocks

        Returns:
            str: Text with code delimiters removed, leaving only the content
        """
        lines = text.splitlines()
        result = []
        inside_code = False
        has_fences = False
        for line in lines:
            if re.match("^`{3}[a-z]+\\s*$", line):
                inside_code = True
                has_fences = True
            elif line.startswith("```"):
                inside_code = not inside_code
                has_fences = True
            elif inside_code:
                result.append(line)
        return "\n".join(result if has_fences else lines)
