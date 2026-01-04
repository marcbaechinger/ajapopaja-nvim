local state = require("ajapopaja.state")
local core = require("ajapopaja.core")
local history = require("ajapopaja.history")
local ui = require("ajapopaja.ui")
local utils = require("ajapopaja.utils")
local prompt_library = require("ajapopaja.prompt_library")

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

-- Command Wrappersthen
-- These encapsulate the interaction logic for user-facing commands
function M.available_models_loaded()
	state.available_models = vim.fn.AjapopajaGetAvailableModels()
	state.is_fetching_models = false
	vim.notify(
		"Ajapopaja - LLM list fetched. Number of available models: " .. #state.available_models,
		vim.log.levels.INFO,
		{ title = "Ajapopaja" }
	)
end

-- Function to trigger the fetch of available models
function M.refresh_models()
	state.is_fetching_models = true
	state.available_models = {}
	vim.fn.AjapopajaGetAllModels()
end

function M.ajapopaja_select_model()
	if state.is_fetching_models then
		vim.notify("Still fetching list of LLMs...", vim.log.levels.WARN)
		return
	end
	if #state.available_models == 0 then
		M.refresh_models()
		vim.notify("Fetching list of LLMs. Try selecting again in a sec.", vim.log.levels.WARN)
		return
	end
	ui.select("Selec the LLM to use", state.available_models, function(choice)
		vim.fn.AjapopajaSetModel(choice)
		state.current_model = choice
	end, state.current_model)
end

function M.ajapopaja_select_prompt(command_opts)
	local selection = core.capture_context(command_opts)
	if not selection then
		return
	end
	local filetype = utils.get_programming_language()
	ui.select_prompt(function(selected_prompt)
		local prompt = prompt_library.get_prompt(filetype, selected_prompt)
		core.transform(utils.format_prompt(prompt), selection)
	end, filetype)
end

function M.ajapopaja_transform(command_opts)
	local selection_info = core.capture_context(command_opts)
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

function M.ajapopaja_review(command_opts)
	local selection_info = core.capture_context(command_opts)
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
	local success, err = pcall(vim.fn.AjapopajaLlmCall, table.concat(text_lines, "\n"), selection_info, "review", "")
	if not success then
		state.is_loading = false
		vim.cmd("redrawstatus")
		vim.notify("Ajapopaja: Error calling agent: " .. tostring(err), vim.log.levels.ERROR)
	end
end

local function open_prompt_directory()
	local files = vim.api.nvim_get_runtime_file("prompts/default.md", false)

	if #files == 0 then
		vim.notify("Ajapopaja: Could not find prompts/default.md in runtimepath", vim.log.levels.ERROR)
		return
	end

	local prompt_dir = vim.fn.fnamemodify(files[1], ":h")

	vim.cmd("edit " .. prompt_dir)
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

function M.setup(opts)
	opts = opts or {}

	-- boostrap Python venv
	if not vim.g.python3_host_prog then
		local plugin_path = vim.api.nvim_get_runtime_file("rplugin/python3/AjapopajaPlugin.py", false)[1]
		if plugin_path then
			local root = vim.fn.fnamemodify(plugin_path, ":h:h:h")
			local venv_python = root .. "/.venv/bin/python3"
			if vim.fn.executable(venv_python) == 1 then
				vim.g.python3_host_prog = venv_python
			end
		end
	end

	vim.g.ajapopaja_ollama_host = opts.ollama_host or "http://localhost:11434"
	history.setup(M)
	local commands = {
		AjapopajaHistory = history.open,
		AjapopajaSelectModel = M.ajapopaja_select_model,
		AjapopajaRefreshModels = M.refresh_models,
		AjapopajaTransform = M.ajapopaja_transform,
		AjapopajaSelectPrompt = M.ajapopaja_select_prompt,
		AjapopajaReview = M.ajapopaja_review,
		AjapopajaApplyLatest = M.ajapopaja_apply_latest,
		AjapopajaInsertLatest = M.ajapopaja_insert_latest,
		AjapopajaEditPrompts = open_prompt_directory,
	}

	for name, fn in pairs(commands) do
		vim.api.nvim_create_user_command(name, function(options)
			fn(options)
		end, {
			desc = "Ajapopaja: " .. name,
			range = true,
		})
	end
	if opts.default_keymaps ~= false then
		-- Register Default Keybindings
		local keymap = vim.keymap.set
		keymap(
			{ "v", "n" },
			"<leader>as",
			"<cmd>AjapopajaSelectPrompt<CR>",
			{ silent = true, desc = "Ajapopaja: Select a standard prompt" }
		)
		keymap(
			{ "v", "n" },
			"<leader>ai",
			"<cmd>AjapopajaTransform<CR>",
			{ silent = true, desc = "Ajapopaja: Prompt for transformation" }
		)
		keymap({ "v", "n" }, "<leader>ar", "<cmd>AjapopajaReview<CR>", { silent = true, desc = "Ajapopaja: Review" })
		keymap("n", "<leader>at", "<cmd>AjapopajaApplyLatest<CR>", { desc = "Ajapopaja: Apply Latest Transformation" })
		keymap(
			{ "v", "n" },
			"<leader>ap",
			"<cmd>AjapopajaInsertLatest<CR>",
			{ desc = "Ajapopaja: Insert/replace Latest Transformation" }
		)
		keymap(
			"n",
			"<leader>ae",
			"<cmd>AjapopajaEditPrompts<CR>",
			{ desc = "Ajapopaja: Edit prompts (open prompt dir)" }
		)
		keymap("n", "<leader>ah", "<cmd>AjapopajaHistory<CR>", { desc = "Ajapopaja: Open history window" })
		keymap("n", "<leader>am", "<cmd>AjapopajaSelectModel<CR>", { desc = "Ajapopaja: Select LLM" })
		keymap("n", "<leader>aM", "<cmd>AjapopajaRefreshModels<CR>", { desc = "Ajapopaja: Refresh list of LLMs" })
		vim.api.nvim_create_user_command("AjapopajaBootstrap", function()
			require("ajapopaja.bootstrap").bootstrap()
		end, {})
	end

	local rpc_ready, err_msg = require("ajapopaja.health").can_call_rpc()
	if rpc_ready then
		vim.schedule(function()
			pcall(M.refresh_models)
		end)
	else
		vim.schedule(function()
			vim.notify("Ajapopaja: " .. err_msg, vim.log.levels.INFO)
		end)
	end
end

return M
