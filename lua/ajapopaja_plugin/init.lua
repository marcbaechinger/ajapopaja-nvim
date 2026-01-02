local state = require("ajapopaja_plugin.state")
local core = require("ajapopaja_plugin.core")
local history = require("ajapopaja_plugin.history")
local ui = require("ajapopaja_plugin.ui")
local utils = require("ajapopaja_plugin.utils")
local prompt_library = require("ajapopaja_plugin.prompt_library")

local M = {}

-- Status line functions

function M.stop_loading()
	state.is_loading = false
	state.sync_history()
	vim.cmd("redrawstatus")
end

function M.get_status()
	return state.is_loading and ("󱚣 Ajapopaja: " .. state.current_model) or state.current_model
end

-- Command Wrappers
-- These encapsulate the interaction logic for user-facing commands

function M.ajapopaja_select_model()
	ui.select("Selec the LLM to use", state.available_models, function(choice)
		vim.fn.AjapopajaSetModel(choice)
		state.current_model = choice
	end, state.current_model)
end

function M.ajapopaja_select_prompt()
	local selection = core.capture_context()
	if not selection then
		return
	end
	local filetype = utils.get_programming_language()
	ui.select_prompt(function(selected_prompt)
		local prompt = prompt_library.get_prompt(filetype, selected_prompt)
		core.transform(utils.format_prompt(prompt), selection)
	end, filetype)
end

function M.ajapopaja_transform()
	local selection_info = core.capture_context()
	if not selection_info then
		return
	end
	ui.create_multi_line_input("Describe transformation...", function(lines)
		local prompt = table.concat(lines, "\n")
		if prompt ~= "" then
			core.transform(prompt, selection_info)
		end
	end, selection_info.lang)
end

function M.ajapopaja_iterate_with_multiline_prompt(history_item)
	if not history_item.selection_info then
		return
	end
	ui.create_multi_line_input("Describe transformation...", function(lines)
		local prompt = table.concat(lines, "\n")
		if prompt ~= "" then
			core.transform(prompt, history_item.selection_info, vim.split(history_item.response, "\n"))
		end
	end, history_item.selection_info.lang)
end

function M.ajapopaja_review()
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

local function get_latest_transformation()
	if not state.call_uids["transform"] then
		state.sync_history()
	end
	local transformations = state.call_uids["transform"]
	local uid = transformations[#transformations]
	return vim.fn.AjapopajaGetHistoryItem("transform", uid)
end

function M.ajapopaja_apply_latest()
	local item = get_latest_transformation()
	if not item then
		vim.notify("Ajapopaja: No transformation history found.", vim.log.levels.WARN)
		return
	end
	core.replace_in_buffer(item)
end

function M.ajapopaja_insert_latest()
	local item = get_latest_transformation()
	if not item then
		vim.notify("Ajapopaja: No transformation history found.", vim.log.levels.WARN)
		return
	end
	core.insert_to_buffer(item)
end

function M.setup()
	history.setup(M)

	local commands = {
		AjapopajaHistory = history.open,
		AjapopajaSelectModel = M.ajapopaja_select_model,
		AjapopajaApplyLatest = M.ajapopaja_apply_latest,
		AjapopajaInsertLatest = M.ajapopaja_insert_latest,
	}

	for name, fn in pairs(commands) do
		vim.api.nvim_create_user_command(name, fn, {
			desc = "Ajapopaja: " .. name,
			range = true,
		})
	end

	-- Register Default Keybindings
	local keymap = vim.keymap.set

	-- Transformation of selected text or entire buffer
	keymap(
		{ "v", "n" },
		"<leader>as",
		M.ajapopaja_select_prompt,
		{ silent = true, desc = "Ajapopaja: Select a standard prompt" }
	)
	keymap(
		{ "v", "n" },
		"<leader>at",
		M.ajapopaja_transform,
		{ silent = true, desc = "Ajapopaja: Transform selection" }
	)
	keymap({ "v", "n" }, "<leader>ar", M.ajapopaja_review, { silent = true, desc = "Ajapopaja: Review" })
	keymap("n", "<leader>ap", M.ajapopaja_apply_latest, { desc = "Ajapopaja: Apply Latest Transformation" })
	keymap(
		{ "v", "n" },
		"<leader>ai",
		M.ajapopaja_insert_latest,
		{ desc = "Ajapopaja: Insert/replace Latest Transformation" }
	)
	keymap("n", "<leader>aw", history.open, { desc = "Ajapopaja: Open history window" })
	keymap("n", "<leader>am", M.ajapopaja_select_model, { desc = "Ajapopaja: Select LLM Model" })
end

return M
