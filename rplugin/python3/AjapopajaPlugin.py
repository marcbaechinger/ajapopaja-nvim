import pynvim
import json
import os
import asyncio
from agent_client.agent_client import AgentClient

# Configuration and Constants
API_BASE_URL = "http://127.0.0.1:8000"
HISTORY_FILE = os.path.expanduser("~/.cache/ajapopaja_history.json")

# Configuration for different LLM workflows
# 'chomp' determines if we strip markdown code fences for direct buffer injection
CALL_TYPES = {
    "transform": {
        "system_instructions": "You are an expert engineer helping developers to improve their code. Your output is ONLY the code transformation requested, with no conversational filler or markdown markers unless explicitly asked.",
        "prompt_sent_message": "Code sent for transformation...",
        "response_received_message": "Transformation complete. Register 'c' updated. Use \"cp to paste.",
        "chomp": True,
        "register": "c",
    },
    "review": {
        "system_instructions": "You are an expert engineer. Provide a rigorous code review focusing on correctness, efficiency, and readability. Use Markdown formatting.",
        "prompt": "Review this code",
        "prompt_sent_message": "Code sent for review...",
        "response_received_message": "Review complete. Register 'r' updated. Use \"rp to paste.",
        "chomp": False,
        "register": "r",
    },
}


@pynvim.plugin
class AjapopajaPlugin(object):
    def __init__(self, vim):
        self.vim = vim
        self.agent = AgentClient(API_BASE_URL)
        self.agent_in_use = False
        self.history = self._load_history()
        self.current_model = "gemma3:27b"  # Default model state

    def _load_history(self):
        """Loads interaction history from the local cache file."""
        if os.path.exists(HISTORY_FILE):
            try:
                with open(HISTORY_FILE, "r") as f:
                    return json.load(f)
            except (json.JSONDecodeError, IOError):
                pass
        return {"transform": [], "review": []}

    def _persist_history(self):
        """Helper to save the current history state to disk."""
        try:
            os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)
            with open(HISTORY_FILE, "w") as f:
                json.dump(self.history, f)
        except IOError as e:
            err = e
            self.vim.async_call(
                lambda: self.vim.err_write(f"Ajapopaja History Error: {str(err)}\n")
            )

    def _save_history(self, call_type, item):
        """Persists a new interaction and trims to the last 50 entries."""
        if call_type not in self.history:
            self.history[call_type] = []

        self.history[call_type].append(item)
        self.history[call_type] = self.history[call_type][-50:]
        self._persist_history()

    @pynvim.function("AjapopajaGetHistory", sync=True)
    def get_history(self, args):
        """Synchronous retrieval of history for the Lua UI."""
        return json.dumps(self.history)

    @pynvim.function("AjapopajaSetModel", sync=True)
    def set_model(self, args):
        """Updates the active LLM model."""
        if len(args) > 0:
            self.current_model = args[0]
            self.vim.command(f"echo 'Ajapopaja: Model set to {self.current_model}'")
            return True
        return False

    @pynvim.function("AjapopajaDeleteEntry", sync=True)
    def delete_entry(self, args):
        """Deletes a specific entry by view type and index."""
        try:
            view = args[0]  # 'transform' or 'review'
            index = int(args[1]) - 1  # Convert Lua 1-index to Python 0-index

            if view in self.history and 0 <= index < len(self.history[view]):
                self.history[view].pop(index)
                self._persist_history()
                return True
        except (ValueError, IndexError, KeyError, TypeError):
            pass
        return False

    @pynvim.function("AjapopajaClearHistory", sync=True)
    def clear_history(self, args):
        """Clears all history for a specific view."""
        try:
            view = args[0]
            if view in self.history:
                self.history[view] = []
                self._persist_history()
                return True
        except (KeyError, IndexError):
            pass
        return False

    @pynvim.function("AjapopajaAgentCall", sync=False)
    def call_agent(self, args):
        """Entry point for Lua to trigger an asynchronous LLM request."""
        if self.agent_in_use:
            self.vim.command("echo 'Ajapopaja: Agent busy. Please wait.'")
            return

        # Extract arguments from Lua call
        selected_text = args[0] if len(args) > 0 else ""
        lang = args[1] if len(args) > 1 else ""
        call_type = args[2] if len(args) > 2 else "transform"
        user_prompt = args[3] if len(args) > 3 else ""

        if call_type not in CALL_TYPES:
            self.vim.command(f'echo "Ajapopaja Error: Unknown call type {call_type}"')
            return

        config = CALL_TYPES[call_type]
        self.agent_in_use = True
        self.vim.command(f'echo "{config["prompt_sent_message"]}"')

        # Schedule the async task to prevent UI blocking
        asyncio.create_task(
            self._async_agent_call(
                selected_text=selected_text,
                lang=lang,
                call_type=call_type,
                user_prompt=user_prompt,
                config=config,
            )
        )

    async def _async_agent_call(
        self, selected_text, lang, call_type, user_prompt, config
    ):
        """Handles the lifecycle of the LLM request and updates Neovim state."""
        try:
            # 1. Initialize the Agent Session using the currently selected model
            agent_uid, _ = await self.agent.create_agent(
                "vim_agent",
                config["system_instructions"],
                agent_type="plain",
                model=self.current_model,
            )

            if not agent_uid:
                raise Exception("Failed to create agent session.")

            # 2. Build and send the prompt
            final_prompt = self._build_prompt(
                user_prompt if user_prompt else config.get("prompt", ""),
                lang,
                selected_text,
            )

            response = await self.agent.chat(final_prompt)
            reply_text = response.reply

            # 3. Process the response (strip fences if it's a transformation)
            if config.get("chomp"):
                reply_text = self._strip_code_fence(reply_text)

            # 4. Update internal history
            history_item = {
                "prompt": user_prompt or config.get("prompt", "Code Review"),
                "lang": lang,
                "response": reply_text,
            }
            self._save_history(call_type, history_item)

            # 5. Success Callback
            def finalize():
                self.agent_in_use = False
                # Set the register (c or r) with the result
                self.vim.funcs.setreg(config["register"], reply_text, "v")
                # Signal Lua to hide loading indicator
                self.vim.exec_lua("require('ajapopaja_plugin').set_loading(false)")
                self.vim.command(f'echo "{config["response_received_message"]}"')

            self.vim.async_call(finalize)

        except Exception as e:
            err = e

            # 6. Error Callback
            def on_error():
                self.agent_in_use = False
                # Ensure indicator is cleared even on failure
                self.vim.exec_lua("require('ajapopaja_plugin').set_loading(false)")
                self.vim.err_write(f"Ajapopaja API Error: {str(err)}\n")

            self.vim.async_call(on_error)
        finally:
            # 7. Server-side cleanup
            await self.agent.release(delete_resources=True)

    def _build_prompt(self, prompt, lang, selected_text):
        """Constructs a structured prompt with Markdown code blocks."""
        parts = []
        if prompt:
            parts.append(prompt)
        if selected_text:
            lang_label = lang if lang else ""
            parts.append(f"\n\n```{lang_label}\n{selected_text}\n```")
        return "".join(parts)

    def _strip_code_fence(self, text):
        """Removes Markdown code delimiters from LLM responses for clean buffer injection."""
        lines = text.strip().splitlines()
        if not lines:
            return text
        if lines and lines[0].startswith("```"):
            lines.pop(0)
        if lines and lines[-1].startswith("```"):
            lines.pop(-1)
        return "\n".join(lines).strip()
