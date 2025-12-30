local state = require("ajapopaja_plugin.state")
local core = require("ajapopaja_plugin.core")
local history = require("ajapopaja_plugin.history")
local ui = require("ajapopaja_plugin.ui")

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
	ui.select("Selec the LLM to use", state.available_models, function(choice)
		vim.fn.AjapopajaSetModel(choice)
		state.current_model = choice
	end, state.current_model)
end

function M.ajapopaja_apply_latest()
	history.sync_history()
	local transforms = state.history_cache.transform
	if #transforms == 0 then
		vim.notify("Ajapopaja: No transformation history found.", vim.log.levels.WARN)
		return
	end
	core.replace_in_buffer(transforms[#transforms])
end

function M.ajapopaja_insert_latest()
	history.sync_history()
	local transforms = state.history_cache.transform
	if #transforms == 0 then
		vim.notify("Ajapopaja: No transformation history found.", vim.log.levels.WARN)
		return
	end
	core.insert_to_buffer(transforms[#transforms])
end

local function ajapopaja_transform()
	local selection_info = core.capture_context()
	if not selection_info then
		return
	end
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
	local success, err =
		pcall(vim.fn.AjapopajaAgentCall, table.concat(text_lines, "\n"), selection_info, "review", "Review this code")
	if not success then
		state.is_loading = false
		vim.cmd("redrawstatus")
		vim.notify("Ajapopaja: Error calling agent: " .. tostring(err), vim.log.levels.ERROR)
	end
end

-- Specialized Transformation Presets
local function ajapopaja_select_prompt()
	local selection = core.capture_context()
	if not selection then
		return
	end
	ui.select("Select a prompt", state.standard_prompts, function(selected_prompt)
		core.transform(selected_prompt, selection)
	end, nil)
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
	keymap("v", "<leader>as", ajapopaja_select_prompt, { silent = true, desc = "Ajapopaja: Select a standard prompt" })

	keymap({ "v", "n" }, "<leader>at", ajapopaja_transform, { silent = true, desc = "Ajapopaja: Transform selection" })
	keymap({ "v", "n" }, "<leader>ar", ajapopaja_review, { silent = true, desc = "Ajapopaja: Review" })
	keymap(
		{ "v", "n" },
		"<leader>ai",
		M.ajapopaja_insert_latest,
		{ desc = "Ajapopaja: Insert/replace Latest Transformation" }
	)

	keymap("n", "<leader>aw", history.open, { desc = "Ajapopaja: Open history window" })
	keymap("n", "<leader>am", M.ajapopaja_select_model, { desc = "Ajapopaja: Select LLM Model" })
	keymap("n", "<leader>ap", M.ajapopaja_apply_latest, { desc = "Ajapopaja: Apply Latest Transformation" })
end

return M
