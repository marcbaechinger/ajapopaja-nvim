local state = require("ajapopaja_plugin.state")
local core = require("ajapopaja_plugin.core")
local history = require("ajapopaja_plugin.history")
local ui = require("ajapopaja_plugin.ui")
local utils = require("ajapopaja_plugin.utils")

local M = {}

-- Backend Callbacks
-- These functions are designed to be called by the Python RPC host
function M.set_loading(state_val)
	state.is_loading = state_val
	vim.cmd("redrawstatus")
end

function M.get_status()
	return state.is_loading and ("󱚣 Ajapopaja: " .. state.current_model) or ""
end

-- Command Wrappers
-- These encapsulate the interaction logic for user-facing commands

function M.ajapopaja_select_model()
	vim.ui.select(state.available_models, { prompt = "Select LLM Model:" }, function(choice)
		if choice then
			vim.fn.AjapopajaSetModel(choice)
			state.current_model = choice
		end
	end)
end

function M.ajapopaja_apply_latest()
	history.sync_history()
	local transforms = state.history_cache.transform
	if #transforms == 0 then
		vim.notify("Ajapopaja: No transformation history found.", vim.log.levels.WARN)
		return
	end
	core.execute_replacement(transforms[#transforms])
end

local function ajapopaja_transform()
	local selection_info = core.capture_context()
	ui.create_multi_line_input("Describe transformation...", function(lines)
		local prompt = table.concat(lines, "\n")
		if prompt ~= "" then
			core.transform(prompt, selection_info)
		end
	end)
end

local function ajapopaja_review()
	local selection_info = core.capture_context()
	if not selection_info then
		vim.notify("Ajapopaja: No valid selection found.", vim.log.levels.WARN)
		return
	end

	local text_lines = vim.api.nvim_buf_get_text(
		selection_info.buf_id,
		selection_info.start_row,
		selection_info.start_col,
		selection_info.end_row,
		selection_info.end_col,
		{}
	)

	if #text_lines == 0 then
		return
	end

	state.is_loading = true
	vim.cmd("redrawstatus")
	vim.fn.AjapopajaAgentCall(table.concat(text_lines, "\n"), utils.get_programming_language(), "review", "")
end

-- Specialized Transformation Presets
local function ajapopaja_add_documentation()
	core.transform("Add or improve the documentation", core.capture_context())
end

local function ajapopaja_implement_function()
	core.transform("Implement this function", core.capture_context())
end

local function ajapopaja_add_unit_tests()
	core.transform("Create unit tests to test the functionality thoroughly", core.capture_context())
end

-- Plugin Setup
-- Registers all commands and default keybindings
function M.setup()
	local commands = {
		AjapopajaHistory = history.open,
		AjapopajaSelectModel = M.ajapopaja_select_model,
		AjapopajaApplyLatest = M.ajapopaja_apply_latest,
	}

	-- Register Named Commands for : prompt
	for name, fn in pairs(commands) do
		vim.api.nvim_create_user_command(name, fn, {
			desc = "Ajapopaja: " .. name,
			range = true,
		})
	end

	-- Register Default Keybindings
	local keymap = vim.keymap.set

	-- Visual Mode Transformations
	keymap(
		"v",
		"<leader>ad",
		ajapopaja_add_documentation,
		{ silent = true, desc = "Ajapopaja: Add/Improve documentation for selection" }
	)
	keymap(
		"v",
		"<leader>ai",
		ajapopaja_implement_function,
		{ silent = true, desc = "Ajapopaja: Implement function for selection" }
	)
	keymap(
		"v",
		"<leader>au",
		ajapopaja_add_unit_tests,
		{ silent = true, desc = "Ajapopaja: Create unit tests for selection" }
	)
	keymap("v", "<leader>at", ajapopaja_transform, { silent = true, desc = "Ajapopaja: Transform selection" })
	keymap("v", "<leader>ar", ajapopaja_review, { silent = true, desc = "Ajapopaja: Review" })

	keymap("n", "<leader>aw", history.open, { desc = "Ajapopaja: Open history window" })
	keymap("n", "<leader>am", M.ajapopaja_select_model, { desc = "Ajapopaja: Select LLM Model" })
	keymap("n", "<leader>ap", M.ajapopaja_apply_latest, { desc = "Ajapopaja: Apply Latest Transformation" })
end

return M
