import pynvim
import textwrap
import json
import os
import asyncio
from agent_client.agent_client import AgentClient
from typing import Dict, Any, Optional


# Configuration and Constants
API_BASE_URL = "http://127.0.0.1:8000"
HISTORY_FILE = os.path.expanduser("~/.ajapopaja/history.json")

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

    def __init__(self, history_file: str) -> None:
        """Initialize the HistoryManager with a specified history file path.

        Args:
            history_file (str): Path to the JSON file where history is stored
        """
        self.history_file = history_file
        self.history: Dict[str, list] = self._load_history()

    def _load_history(self) -> Dict[str, list]:
        """Loads interaction history from the local cache file.

        Attempts to read and parse the history file. If the file doesn't exist
        or is invalid, initializes with an empty history structure.

        Returns:
            dict: Dictionary containing 'transform' and 'review' lists
        """
        if os.path.exists(self.history_file):
            try:
                with open(self.history_file, "r") as f:
                    return json.load(f)
            except (json.JSONDecodeError, IOError):
                pass
        return {"transform": [], "review": []}

    def _persist_history(self) -> None:
        """Helper to save the current history state to disk.

        Creates the directory structure if needed and writes the history
        to the specified file. Raises exceptions on write or serialization errors.

        Raises:
            IOError: If failed to write to the history file
            TypeError: If history data cannot be serialized to JSON
        """
        try:
            os.makedirs(os.path.dirname(self.history_file), exist_ok=True)
            with open(self.history_file, "w") as f:
                json.dump(self.history, f)
        except IOError as e:
            raise IOError(f"Failed to write history file '{self.history_file}': {e}")
        except TypeError as e:
            raise TypeError(f"Failed to serialize history data: {e}")

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
            self._persist_history()
        except (IOError, TypeError) as e:
            return e
        return None

    def get_history(self) -> Dict[str, list]:
        """Returns current history.

        Returns:
            dict: Current history dictionary containing all interactions
        """
        return self.history


class PromptBuilder:
    """Handles building structured prompts with optional code blocks."""

    @staticmethod
    def build_prompt(prompt: str, lang: str, selected_text: str) -> str:
        """Constructs a structured prompt with Markdown code blocks.

        Args:
            prompt (str): The main prompt text
            lang (str): Language identifier for the code block (e.g., 'python', 'javascript')
            selected_text (str): Text to be wrapped in a code block

        Returns:
            str: Combined prompt with optional code block
        """
        parts = []
        if prompt:
            parts.append(prompt)
        if selected_text:
            selected_text = textwrap.dedent(selected_text)
            lang_label = lang if lang else ""
            parts.append(f"\n\n```{lang_label}\n{selected_text}\n```")
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
        return "\n".join(result)


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
        self.history_manager = HistoryManager(HISTORY_FILE)
        self.current_model = "qwen3-coder:30b"
        self.prompt_builder = PromptBuilder()

    @pynvim.function("AjapopajaGetHistory", sync=True)
    def get_history(self, args) -> str:
        """
        Synchronous retrieval of history for the Lua UI.

        Returns:
            str: JSON string of the complete history
        """
        return json.dumps(self.history_manager.get_history())

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

    @pynvim.function("AjapopajaDeleteEntry", sync=True)
    def delete_entry(self, args) -> bool:
        """
        Deletes a specific entry by view type and index.

        Args:
            args: List containing [view_type, index]

        Returns:
            bool: True if deletion was successful, False otherwise
        """
        try:
            view = args[0]
            index = int(args[1]) - 1

            if view not in self.history_manager.history:
                self._show_error("Invalid view")
                return False

            view_history = self.history_manager.history[view]
            if not (0 <= index < len(view_history)):
                self._show_error("Invalid index")
                return False

            view_history.pop(index)
            return self._persist_and_handle_error()
        except ValueError:
            self._show_error("Index must be a number")
            return False
        except Exception as e:
            self._show_error(f"Unexpected error: {e}")
            return False

    def _persist_and_handle_error(self) -> bool:
        """
        Persist history and handle any errors during persistence.

        Returns:
            bool: True if persistence was successful, False otherwise
        """
        try:
            error = self.history_manager._persist_history()
            if error:
                self.vim.async_call(
                    lambda: self.vim.err_write(
                        f"Ajapopaja History Error: {str(error)}\n"
                    )
                )
            return True
        except Exception as e:
            self._show_error(f"Error when deleting history item {e}")
            return False

    def _show_error(self, message: str) -> None:
        """
        Display an error message to the user.

        Args:
            message: Error message to display
        """
        self.vim.api.nvim_echo(
            {"key": "error", "message": message},
            True,
            {"title": "Ajapopaja"},
        )

    @pynvim.function("AjapopajaClearHistory", sync=True)
    def clear_history(self, args) -> bool:
        """
        Clears all history for a specific view.

        Args:
            args: List containing the view type to clear

        Returns:
            bool: True if clearing was successful, False otherwise
        """
        try:
            view = args[0]
            if view in self.history_manager.history:
                self.history_manager.history[view] = []
                return self._persist_and_handle_error()
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

        selected_text = args[0] if len(args) > 0 else ""
        selection_info = args[1] if len(args) > 1 else {}
        call_type = args[2] if len(args) > 2 else "transform"
        user_prompt = args[3] if len(args) > 3 else ""
        config = CALL_TYPES[call_type]
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
        self.vim.command(f'echo "{config["prompt_sent_message"]}"')

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

            final_prompt = self.prompt_builder.build_prompt(
                user_prompt if user_prompt else config.get("prompt", ""),
                selection_info["lang"],
                selected_text,
            )

            response = await self.agent.chat(final_prompt)
            reply_text = response.reply

            if config.get("chomp"):
                reply_text = textwrap.dedent(
                    self.prompt_builder.strip_code_fence(reply_text)
                )

            history_item = {
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
                self.vim.exec_lua("require('ajapopaja_plugin').set_loading(false)")
                self.vim.command(f'echo "{config["response_received_message"]}"')

            self.vim.async_call(finalize)

        except Exception as e:

            def on_error(err: str = str(e)) -> None:
                self.agent_in_use = False
                self.vim.exec_lua("require('ajapopaja_plugin').set_loading(false)")
                self.vim.err_write(f"Ajapopaja API Error: {str(err)}\n")

            self.vim.async_call(on_error)
        finally:
            # Ensure agent is properly cleaned up
            try:
                await self.agent.release()
            except Exception as e:
                self._show_error(f"Releasing the agent failed: {e}")
