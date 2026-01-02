from pathlib import Path
from typing import Dict, Any, Optional
from uuid import uuid4
import aiohttp
import asyncio
import json
import os
import pynvim
import re
import textwrap
import threading
import traceback


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


OLLAMA_HOST = "http://localhost:11434"
OLLAMA_CHAT_URI = OLLAMA_HOST + "/api/chat"
OLLAMA_LIST_URI = OLLAMA_HOST + "/api/tags"

AJAPOPAJA_URI = "http://localhost:8000"
REQUEST_TIMEOUT_SECONDS = 60
CONNECTION_TIMEOUT_SECONDS = 2
HISTORY_DIR = os.path.expanduser("~/.ajapopaja/history/")
CALL_TYPES_FILE = get_plugin_path() / "call_types/default.json"


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

    def save_history(self, call_type: str, item: Any) -> Optional[Exception]:
        """Persists a new interaction and trims to the last 50 entries.

        Args:
            call_type (str): Type of interaction ('transform' or 'review')
            item (any): The interaction item to be saved

        Returns:
            Exception or None: Exception if save fails, None otherwise
        """
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


@pynvim.plugin
class AjapopajaPlugin(object):
    """
    Neovim plugin for interacting with an LLM to assist with code editing tasks.

    This plugin provides functionality for:
    - Managing conversation history
    - Setting and switching LLM models
    - Making asynchronous LLM requests
    - Handling user prompts and responses
    """

    def __init__(self, vim):
        """
        Initialize the Ajapopaja plugin.

        Args:
            vim: Neovim instance for communication with the editor
        """
        self.vim = vim
        self.llm_in_use = False
        self.history_manager = HistoryManager(HISTORY_DIR)
        self.call_type_manager = CallTypeManager(CALL_TYPES_FILE)
        self.current_model = "qwen3-coder:30b"
        self.formatter = FormatUtil()
        self._http_session = None
        self._lock = asyncio.Lock()

    @pynvim.function("AjapopajaGetCallTypes", sync=True)
    def get_call_types(self, _) -> list[str]:
        return self.call_type_manager.get_all_call_type_names()

    @pynvim.function("AjapopajaSetModel", sync=True)
    def set_model(self, args) -> bool:
        """
        Updates the active LLM model.

        Args:
            args: List containing the new model name

        Returns:
            bool: True if model was successfully updated, False otherwise
        """
        if len(args) > 0:
            self.current_model = args[0]
            self.vim.command(f"echo 'Ajapopaja: Model set to {self.current_model}'")
            return True
        return False

    @pynvim.function("AjapopajaGetHistoryUids", sync=True)
    def get_history_uids(self, args) -> Optional[list[str]]:
        call_type = args[0]

        if call_type not in self.history_manager.history:
            self._show_error("Invalid call_type")
            return None
        return self.history_manager.get_uids(call_type)

    @pynvim.function("AjapopajaGetHistoryItem", sync=True)
    def get_history_item(self, args) -> Optional[dict]:
        call_type = args[0]
        uid = args[1]
        if call_type not in self.history_manager.history:
            self._show_error("Invalid call_type")
            return None
        for item in self.history_manager.history[call_type]:
            if item["uid"] == uid:
                return item
        return None

    @pynvim.function("AjapopajaDeleteHistoryItem", sync=True)
    def delete_history_item(self, args) -> Optional[str]:
        """
        Deletes a specific entry by call type and uid.

        Args:
            args: List containing [call_type, uid]

        Returns:
            str: The uid of the new item at the same index than the removed one.
        """
        try:
            call_type = args[0]
            uid = args[1]
            if call_type not in self.history_manager.history:
                self._show_error("Invalid call type")
            elif not uid:
                self._show_error("Invalid uid")
            else:
                uid = self.history_manager.remove_by_uid(call_type, uid)
                self._persist_and_handle_error(call_type)
                uids = self.history_manager.get_uids(call_type)
                if not uid and uids:
                    uid = uids[-1]
                return uid
        except ValueError:
            self._show_error("Index must be a number")
        except Exception as e:
            self._show_error(f"Unexpected error: {e}")
        return None

    def _persist_and_handle_error(self, call_type: str) -> bool:
        """
        Persist history and handle any errors during persistence.

        Returns:
            bool: True if persistence was successful, False otherwise
        """
        try:
            self.history_manager._persist_history(call_type)
            return True
        except Exception as e:
            self._show_error(
                f"Error when persisting history for calltype={call_type}: {e}"
            )
            return False

    def _show_error(self, message: str) -> None:
        """
        Display an error message to the user.

        Args:
            message: Error message to display
        """
        self.vim.err_write(f"Ajapopaja: {message}\n")

    def _show_message(self, message: str) -> None:
        """
        Display an informational message to the user and save it to :messages.
        """
        safe_message = message.replace("'", "''")
        self.vim.command(f"echomsg 'Ajapopaja: {safe_message}'")

    @pynvim.function("AjapopajaClearHistory", sync=True)
    def clear_history(self, args) -> bool:
        """
        Clears all history for a specific call type.

        Args:
            args: List containing the call type to clear

        Returns:
            bool: True if clearing was successful, False otherwise
        """
        try:
            call_type = args[0]
            if call_type in self.history_manager.history:
                self.history_manager.history[call_type] = []
                return self._persist_and_handle_error(call_type)
            else:
                self._show_error("View not found")
                return False
        except Exception as e:
            self._show_error(f"Unexpected error: {e}")
            return False

    @pynvim.function("AjapopajaLlmCall", sync=False)
    def call_llm(self, args) -> None:
        """
        Entry point for Lua to trigger an asynchronous LLM request.

        Args:
            args: List containing [selected_text, selection_info, call_type, user_prompt]
        """
        if self.llm_in_use:
            self.vim.command("echo 'Ajapopaja: LLM busy. Please wait.'")
            return
        elif len(args) < 3:
            self.vim.command("echo 'Ajapopaja: missing arguments when calling LLM'")
            return

        selected_text = args[0]
        selection_info = args[1]
        call_type = args[2]
        user_prompt = args[3]
        call_types = self.call_type_manager.get_all_call_types()
        if call_type not in call_types:
            self.vim.command(
                f"echo 'Ajapopaja: missing configuration for call type {call_type}'"
            )
            return
        config = call_types[call_type]
        model = self.current_model
        self.llm_in_use = True
        asyncio.create_task(
            self._async_llm_call(
                selected_text=selected_text,
                selection_info=selection_info,
                call_type=call_type,
                user_prompt=user_prompt,
                config=config,
                model=model,
            )
        )
        self.vim.command(f"echo '{config['prompt_sent_message']}'")

    async def _get_session(self):
        if self._http_session is None or self._http_session.closed:
            async with self._lock:
                if self._http_session is None or self._http_session.closed:
                    self._http_session = aiohttp.ClientSession(
                        timeout=aiohttp.ClientTimeout(
                            total=REQUEST_TIMEOUT_SECONDS,
                            connect=CONNECTION_TIMEOUT_SECONDS,
                        ),
                        headers={"Content-Type": "application/json"},
                    )
        return self._http_session

    async def _close_session(self):
        """Properly shut down the session and its connector."""
        async with self._lock:
            if self._http_session is not None and not self._http_session.closed:
                await self._http_session.close()
                self._http_session = None

    @pynvim.shutdown_hook
    def on_shutdown(self):
        if self._http_session and not self._http_session.closed:
            try:
                loop = asyncio.get_event_loop()
                if loop.is_running():
                    loop.create_task(self._close_session())
                else:
                    loop.run_until_complete(self._close_session())
            except Exception:
                pass

    async def _async_llm_call(
        self,
        selected_text: str,
        selection_info: Dict[str, Any],
        call_type: str,
        user_prompt: str,
        config: Dict[str, Any],
        model: str,
    ) -> None:
        """
        Handles the lifecycle of the LLM request and updates Neovim state.

        Args:
            selected_text: Text selected by the user
            selection_info: Information about the selection (language, etc.)
            call_type: Type of call being made
            user_prompt: User-provided prompt
            config: Configuration for the call type
            model: LLM model to use
        """
        try:
            final_prompt = self.formatter.build_prompt(
                user_prompt if user_prompt else config.get("prompt", ""),
                selection_info["lang"],
                selected_text,
            )

            instructions = config["system_instructions"]
            payload = {
                "model": model,
                "messages": [
                    {"role": "system", "content": instructions},
                    {"role": "user", "content": final_prompt},
                ],
                "stream": False,
            }

            session = await self._get_session()

            async with session.post(OLLAMA_CHAT_URI, json=payload) as response:
                if response.status >= 400:
                    error_text = await response.text()
                    raise Exception(f"HTTP {response.status}: {error_text}")

                try:
                    response_data = await response.json()
                    if "message" in response_data:
                        reply_text = response_data["message"]["content"]
                    else:
                        reply_text = "no message found"
                except Exception as e:
                    reply_text = f"error {str(e)}"

            if config.get("chomp"):
                reply_text = textwrap.dedent(
                    self.formatter.strip_code_fence(reply_text)
                )

            history_item = {
                "uid": str(uuid4()),
                "prompt": user_prompt or config.get("prompt", "Code Review"),
                "selection_info": selection_info,
                "response": reply_text,
                "model": model,
            }
            error = self.history_manager.save_history(call_type, history_item)
            if error:
                self.vim.async_call(
                    lambda: self.vim.err_write(
                        f"Ajapopaja History Error: {str(error)}\n"
                    )
                )

            def finalize():
                self.llm_in_use = False
                self.vim.funcs.setreg(config["register"], reply_text, "v")
                self.vim.exec_lua("require('ajapopaja_plugin').stop_loading()")
                self.vim.command(f'echo "{config["response_received_message"]}"')

            self.vim.async_call(finalize)

        except aiohttp.ClientError as e:
            self._report_llm_error(
                f"Ajapopaja: HTTP Error: {traceback.format_exception(e)}\n"
            )
        except TimeoutError:
            self._report_llm_error(
                f"Ajapopaja: Request timeout exeeded: {REQUEST_TIMEOUT_SECONDS} seconds\n"
            )
        except Exception as e:
            self._report_llm_error(
                f"Ajapopaja: Unknown Error: {traceback.format_exception(e)}\n"
            )

    async def getAllModels(self):
        try:
            async with await self._get_session() as session:
                async with session.get(OLLAMA_LIST_URI) as response:
                    response.raise_for_status()
                    data = await response.json()
                    models = data.get("models", [])
                    return sorted(models, key=lambda x: x.get("name", ""))
        except aiohttp.ClientError as e:
            self._report_llm_error(
                f"Ajapopaja: Failed to fetch models: {str(e)}", end_llm_use=False
            )
        except KeyError as e:
            self._report_llm_error(
                f"Ajapopaja: Unexpected response format: {str(e)}", end_llm_use=False
            )
        except TimeoutError:
            self._report_llm_error(
                f"Ajapopaja: Request timeout exeeded: {REQUEST_TIMEOUT_SECONDS} seconds\n",
                end_llm_use=False,
            )
        except Exception as e:
            self._report_llm_error(f"Ajapopaja: Unexpected error: {str(e)}")

    def _report_llm_error(self, message: str, end_llm_use: bool = True):
        def on_timeout_error() -> None:
            if end_llm_use:
                self.llm_in_use = False
            self.vim.err_write(message)

        self.vim.async_call(on_timeout_error)

    @pynvim.function("AjapopajaRpcHealth", sync=True)
    def health_check(self, _) -> list[str]:
        # Return available call types.
        return ["transform", "review"]
