from uuid import uuid4
import pynvim
from pathlib import Path
import textwrap
import json
import os
import asyncio
from agent_client.agent_client import AgentClient
from typing import Dict, Any, Optional


# Configuration and Constants
API_BASE_URL = "http://127.0.0.1:8000"
HISTORY_DIR = os.path.expanduser("~/.ajapopaja/history/")

# Configuration for different LLM workflows
CALL_TYPES = {
    "transform": {
        "system_instructions": "You are an expert engineer helping developers to improve their code. Your output is ONLY the code transformation requested, with no conversational filler or markdown markers unless explicitly asked.",
        "prompt_sent_message": "Code sent for transformation...",
        "response_received_message": "Transformation complete. Register 'c' updated. Use \\\"cp to paste.",
        "chomp": True,
        "register": "c",
    },
    "review": {
        "system_instructions": "You are an expert engineer. Provide a rigorous code review focusing on correctness, efficiency, and readability. Use Markdown formatting.",
        "prompt": "Review this code",
        "prompt_sent_message": "Code sent for review...",
        "response_received_message": "Review complete. Register 'r' updated. Use \\\"rp to paste.",
        "chomp": False,
        "register": "r",
    },
}


class HistoryManager:
    """Manages loading and persisting interaction history.

    This class handles loading interaction history from a local cache file,
    persisting new interactions, and maintaining a maximum of 50 entries
    per interaction type.
    """

    def __init__(self, history_dir: str) -> None:
        """Initialize the HistoryManager with a specified history file path.

        Args:
            history_dir (str): Path to the directory where JSON files are stored
        """
        self.history_dir = Path(history_dir)
        self.history: Dict[str, list] = self._load_history(["transform", "review"])

    def _load_history(self, call_types: list[str]) -> Dict[str, list]:
        """Loads interaction history from the local cache file.

        Attempts to read and parse the history file for each call type. If the file
        doesn't exist or is invalid (JSON decode error or IO error), initializes
        with an empty list for that call type.

        Args:
            call_types (list[str]): List of call type identifiers to load history for

        Returns:
            dict: Dictionary mapping call type strings to lists of interaction records.
                  Keys are the call types, values are lists of history entries.
                  Example: {"transform": [...], "review": [...]}
        """
        history = {}

        for call_type in call_types:
            history_file = self.history_dir / f"{call_type}.json"
            if os.path.exists(history_file):
                try:
                    with open(history_file, "r") as f:
                        history[call_type] = json.load(f)
                except (json.JSONDecodeError, IOError):
                    history[call_type] = []
            else:
                history[call_type] = []

        return history

    def _persist_history(self, call_type: str) -> None:
        """Helper to save the current history state to disk.

        Creates the directory structure if needed and writes the history
        to the specified file. Raises exceptions on write or serialization errors.

        Args:
            call_type: The type of LLM call (transform, review, ...)

        Raises:
            IOError: If failed to write to the history file
            TypeError: If history data cannot be serialized to JSON
        """
        json_file = self.history_dir / f"{call_type}.json"
        try:
            os.makedirs(os.path.dirname(json_file), exist_ok=True)
            with open(json_file, "w") as f:
                json.dump(self.history[call_type], f)
        except IOError as e:
            raise IOError(f"Failed to write history file '{json_file}': {e}")
        except TypeError as e:
            raise TypeError(f"Failed to serialize history data for {call_type}: {e}")

    def save_history(self, call_type: str, item: Any) -> Optional[Exception]:
        """Persists a new interaction and trims to the last 50 entries.

        Appends the new item to the specified call type history and ensures
        the history doesn't exceed 50 entries by keeping only the most recent.

        Args:
            call_type (str): Type of interaction ('transform' or 'review')
            item (any): The interaction item to be saved

        Returns:
            Exception or None: Exception if save fails, None otherwise
        """
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
        """
        Retrieve all UIDs associated with a specific call type from the history.

        Args:
            call_type (str): The type of call to retrieve UIDs for

        Returns:
            list[str]: A list of UIDs corresponding to the specified call type.
                       Returns an empty list if the call type doesn't exist in history.
        """
        if call_type not in self.history:
            return []
        uids = []
        for item in self.history[call_type]:
            uids.append(item["uid"])
        return uids

    def remove_by_uid(self, call_type, uid):
        """
        Remove a call item from the specified call history by its unique identifier.

        Args:
            call_type (str): The type of call history to search (e.g., 'transform' or 'review')
            uid (str): The unique identifier of the call item to remove

        Returns:
            str or None: The UID of the call item that replaces the removed one at
                the given index in the list or None if the removed item was the
                last in the list.
        """
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
        for line in lines:
            if line.startswith("```"):
                inside_code = not inside_code
            elif inside_code:
                result.append(line)
        return "\n".join(result if len(result) else lines)


@pynvim.plugin
class AjapopajaPlugin(object):
    """
    Neovim plugin for interacting with an LLM agent to assist with code editing tasks.

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
        self.agent = AgentClient(API_BASE_URL)
        self.agent_in_use = False
        self.history_manager = HistoryManager(HISTORY_DIR)
        self.current_model = "qwen3-coder:30b"
        self.formatter = FormatUtil()

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

    @pynvim.function("AjapopajaDeleteEntry", sync=True)
    def delete_entry(self, args) -> Optional[str]:
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

    @pynvim.function("AjapopajaAgentCall", sync=False)
    def call_agent(self, args) -> None:
        """
        Entry point for Lua to trigger an asynchronous LLM request.

        Args:
            args: List containing [selected_text, selection_info, call_type, user_prompt]
        """
        if self.agent_in_use:
            self.vim.command("echo 'Ajapopaja: Agent busy. Please wait.'")
            return
        elif len(args) < 4:
            self.vim.command("echo 'Ajapopaja: missing arguments when calling agent'")
            return

        selected_text = args[0]
        selection_info = args[1]
        call_type = args[2]
        user_prompt = args[3]
        config = CALL_TYPES[call_type]
        if not config:
            self.vim.command(
                f"echo 'Ajapopaja: missing configuration for call type {call_type}'"
            )
            return

        model = self.current_model
        self.agent_in_use = True
        asyncio.create_task(
            self._async_agent_call(
                selected_text=selected_text,
                selection_info=selection_info,
                call_type=call_type,
                user_prompt=user_prompt,
                config=config,
                model=model,
            )
        )
        self.vim.command(f"echo '{config['prompt_sent_message']}'")

    async def _async_agent_call(
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
            agent_uid, _ = await self.agent.create_agent(
                "vim_agent",
                config["system_instructions"],
                agent_type="plain",
                model=model,
            )

            if not agent_uid:
                raise Exception("Failed to create agent session.")

            final_prompt = self.formatter.build_prompt(
                user_prompt if user_prompt else config.get("prompt", ""),
                selection_info["lang"],
                selected_text,
            )

            response = await self.agent.chat(final_prompt)
            reply_text = response.reply

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
                self.agent_in_use = False
                self.vim.funcs.setreg(config["register"], reply_text, "v")
                self.vim.exec_lua("require('ajapopaja_plugin').stop_loading()")
                self.vim.command(f'echo "{config["response_received_message"]}"')

            self.vim.async_call(finalize)

        except Exception as e:

            def on_error(err: str = str(e)) -> None:
                self.agent_in_use = False
                self.vim.exec_lua("require('ajapopaja_plugin').stop_loading()")
                self.vim.err_write(f"Ajapopaja API Error: {str(err)}\n")

            self.vim.async_call(on_error)
        finally:
            # Ensure agent is properly cleaned up
            try:
                await self.agent.release()
            except Exception as e:
                self._show_error(f"Releasing the agent failed: {e}")

    @pynvim.function("AjapopajaRpcHealth", sync=True)
    def health_check(self, _) -> list[str]:
        # Return available call types.
        return ["transform", "review"]
