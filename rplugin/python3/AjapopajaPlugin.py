import threading
from typing import Dict, Any, Optional
from uuid import uuid4
import aiohttp
import asyncio
import os
import pynvim
import textwrap
import traceback

from history import HistoryManager
from helpers import CallTypeManager, FormatUtil, get_plugin_path


OLLAMA_HOST = "http://localhost:11434"
OLLAMA_CHAT_URI = OLLAMA_HOST + "/api/chat"
OLLAMA_LIST_URI = OLLAMA_HOST + "/api/tags"

AJAPOPAJA_URI = "http://localhost:8000"
REQUEST_TIMEOUT_SECONDS = 60
CONNECTION_TIMEOUT_SECONDS = 2
HISTORY_DIR = os.path.expanduser("~/.ajapopaja/history/")
CALL_TYPES_FILE = get_plugin_path() / "call_types/default.json"


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
        self.available_models = list[dict[str, Any]]
        self.current_model = "qwen3-coder:30b"
        self.formatter = FormatUtil()
        self._http_session = None
        self._lock = asyncio.Lock()
        self._data_lock = threading.RLock()

    @property
    def ollama_host(self) -> str:
        """
        Retrieves the Ollama host from Neovim global variables or returns default.
        """
        # Checks for g:ajapopaja_ollama_host
        return self.vim.vars.get("ajapopaja_ollama_host", "http://localhost:11434")

    @property
    def ollama_chat_uri(self) -> str:
        """Get the Ollama chat API URI.

        Returns:
            str: The complete URI for the Ollama chat API endpoint.
        """
        return f"{self.ollama_host.rstrip('/')}/api/chat"

    @property
    def ollama_list_uri(self) -> str:
        """Get the Ollama list models API URI.

        Returns:
            str: The complete URI for the Ollama list models API endpoint.
        """
        return f"{self.ollama_host.rstrip('/')}/api/tags"

    @pynvim.function("AjapopajaGetCallTypes", sync=True)
    def get_call_types(self, _) -> list[str]:
        """Get all available call type names.

        Args:
            _ (Any): Unused parameter.

        Returns:
            list[str]: A list of all call type names.
        """
        return self.call_type_manager.get_all_call_type_names()

    def _set_available_models(self, available_models: list[dict[str, Any]]):
        """Set the available models.

        Args:
            available_models (list[dict[str, Any]]): List of model dictionaries containing model information.
        """
        with self._data_lock:
            self.models = available_models

    @pynvim.function("AjapopajaGetAvailableModels", sync=True)
    def get_available_models(self, _) -> list[str]:
        """Get the names of all available models.

        Args:
            _ (Any): Unused parameter.

        Returns:
            list[str]: A list of available model names.
        """
        with self._data_lock:
            return [model["name"] for model in self.models if "name" in model]

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
        """Get UIDs from history manager for the specified call type.

        Args:
            args: List containing the call type as the first element

        Returns:
            List of UIDs if call_type is valid, None if invalid call_type

        Example:
            :call AjapopajaGetHistoryUids(['buffer'])
        """
        if len(args) < 1:
            self._show_error("Missing argument call_type")
            return None

        call_type = args[0]
        if call_type not in self.history_manager.history:
            self._show_error("Invalid call_type")
            return None
        return self.history_manager.get_uids(call_type)

    @pynvim.function("AjapopajaGetHistoryItem", sync=True)
    def get_history_item(self, args) -> Optional[dict]:
        """Get a history item by call type and UID.

        Args:
            args: A list containing [call_type, uid] where call_type is the type of call
                  and uid is the unique identifier for the history item.

        Returns:
            Optional[dict]: The history item dictionary if found, None otherwise.

        Raises:
            None: This function handles invalid call_type internally and returns None.
        """
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
        if len(args) < 2:
            self._show_error("Missing argument")
            return None
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
            self.history_manager.persist_history_locked(call_type)
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
                ollama_chat_uri=self.ollama_chat_uri,
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
        """Handle shutdown cleanup for the HTTP session.

        This method gracefully closes the HTTP session when the application shuts down.
        If the session exists and is not already closed, it attempts to close it properly
        by either creating a task in the current event loop (if running) or running it
        synchronously (if the loop is not running). Any exceptions during the closing
        process are caught and ignored to prevent shutdown interruptions.

        The method ensures proper resource cleanup by checking:
        1. If the HTTP session exists
        2. If the session is not already closed
        3. Whether the event loop is running or needs synchronous execution

        Note: Exceptions during session closing are suppressed to allow graceful shutdown.
        """
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
        ollama_chat_uri: str,
    ) -> None:
        """
        Processes the LLM request and updates Neovim state.

        This method constructs a prompt from the selected text and user input,
        sends it to the configured LLM via Ollama, processes the response,
        saves the interaction to history, and updates the Neovim UI with the result.

        Args:
            selected_text: Text selected by the user for processing
            selection_info: Dictionary containing information about the selection including language
            call_type: Type of call being made (e.g., 'transform', 'review')
            user_prompt: User-provided prompt that overrides the default prompt
            config: Configuration dictionary containing system instructions, register,
                   response messages, and other call-specific settings
            model: LLM model to use for the request

        Raises:
            aiohttp.ClientError: When HTTP request fails
            TimeoutError: When request exceeds the configured timeout
            Exception: For other unexpected errors during processing

        Returns:
            None: Updates Neovim state and history but doesn't return a value
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

            async with session.post(ollama_chat_uri, json=payload) as response:
                if response.status >= 400:
                    error_text = await response.text()
                    raise Exception(f"HTTP {response.status}: {error_text}")

                try:
                    response_data = await response.json()
                    if (
                        "message" in response_data
                        and "content" in response_data["message"]
                    ):
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
                self.vim.exec_lua("require('ajapopaja').stop_loading()")
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

    @pynvim.function("AjapopajaGetAllModels", sync=False)
    def call_all_models(self, args) -> None:
        """
        Entry point for Lua to trigger getting all available ollama models.

        """
        asyncio.create_task(
            self._async_get_all_models(ollama_list_uri=self.ollama_list_uri)
        )

    async def _async_get_all_models(self, ollama_list_uri):
        """
        Retrieve and sort all available models from the Ollama API.

        Fetches the list of models from the Ollama service, sorts them by name,
        and handles various error conditions gracefully.

        Returns:
            list: A sorted list of model dictionaries, or empty list if error occurs.

        Raises:
            aiohttp.ClientError: When network communication fails
            KeyError: When response format is unexpected
            TimeoutError: When request exceeds timeout limit
        """
        try:
            sorted_models = []
            async with await self._get_session() as session:
                async with session.get(ollama_list_uri) as response:
                    response.raise_for_status()
                    data = await response.json()
                    models = data.get("models", [])
                    sorted_models = sorted(models, key=lambda x: x.get("name", ""))

            self._set_available_models(sorted_models)
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
        finally:
            self.vim.async_call(
                lambda: self.vim.exec_lua(
                    "require('ajapopaja').available_models_loaded()"
                )
            )

    def _report_llm_error(self, message: str, end_llm_use: bool = True):
        def on_error() -> None:
            if end_llm_use:
                self.llm_in_use = False
            self.vim.err_write(message)

        self.vim.async_call(on_error)

    @pynvim.function("AjapopajaRpcHealth", sync=True)
    def health_check(self, _) -> list[str]:
        # Return available call types.
        return ["transform", "review"]
