-- Copyright (c) 2026 Marc Baechinger
-- Licensed under the MIT License.

local state = require("ajapopaja.state")
local core = require("ajapopaja.core")
local ui = require("ajapopaja.ui")
local M = {}

local buf, win, prev_win
local plugin
local sync_callback

function M.setup(plugin_ref)
	plugin = plugin_ref
end

local function update_title()
	local title_text = " Ajapopaja: "
		.. state.selected_call_type
		.. " ("
		.. state.get_selected_index()
		.. "/"
		.. #state.call_uids[state.selected_call_type]
		.. ") "
	pcall(vim.api.nvim_win_set_config, win, {
		title = { { title_text, "WhidHeader" } },
		title_pos = "center",
	})
end

function M.render()
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local call_type = state.selected_call_type
	local uid = state.selected_uids[call_type]
	local uids = state.call_uids[call_type]
	local content = {}

	local not_found = { "# No history item found for call type '" .. state.selected_call_type .. "'" }
	if not uid or type(uid) == "userdata" then
		content = not_found
	else
		local item = vim.fn.AjapopajaGetHistoryItem(call_type, uid)
		if item == nil or type(item) == "userdata" then
			content = not_found
		else
			local prompt = item.prompt or "N/A"
			local model = item.model or "Unknown"
			local controls =
				"Controls: [h/l] Nav | [t/r] Switch View | [i/I] Iterate | [x] Delete | [C] Clear all | [Enter] Apply transformation"
			local prompt_lines = vim.split(prompt, "\n")
			table.insert(content, "**Prompt  :** " .. (prompt_lines[1] or "N/A"))
			if #prompt_lines > 1 then
				for i, line in ipairs(prompt_lines) do
					if i > 2 then
						table.insert(content, line)
					end
				end
			end
			table.insert(content, "**Model   :** " .. (model or "Unknown"))
			table.insert(content, controls)
			table.insert(content, "---")

			if state.selected_call_type == "transform" then
				table.insert(content, "```" .. (item.selection_info.lang or "text"))
				for _, line in ipairs(vim.split(item.response, "\n")) do
					table.insert(content, line)
				end
				table.insert(content, "```")
			else
				for _, line in ipairs(vim.split(item.response, "\n")) do
					table.insert(content, line)
				end
			end
		end
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	update_title()
end

local function refine()
	if #state.call_uids["transform"] < 1 then
		return
	end
	local uid = state.selected_uids["transform"]
	local item = vim.fn.AjapopajaGetHistoryItem("transform", uid)
	if item ~= nil then
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_set_current_win(win)
		end
		plugin.ajapopaja_iterate_with_multiline_prompt(item)
	end
end

local function refine_with_standard_prompt()
	if #state.call_uids["transform"] < 1 then
		return
	end
	local uid = state.selected_uids["transform"]
	local item = vim.fn.AjapopajaGetHistoryItem("transform", uid)
	if item ~= nil then
		ui.select_prompt(function(selectedPrompt)
			core.transform(selectedPrompt, item.selection_info, vim.split(item.response, "\n"))
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_set_current_win(win)
			end
		end, item.selection_info.lang)
	end
end

local function close_history_window()
	vim.api.nvim_win_close(win, true)
	if vim.api.nvim_win_is_valid(prev_win) then
		vim.api.nvim_set_current_win(prev_win)
	end
end

local function apply_transformation()
	local uid = state.selected_uids[state.selected_call_type]
	if uid == nil then
		return
	end
	local item = vim.fn.AjapopajaGetHistoryItem(state.selected_call_type, uid)
	if state.selected_call_type == "transform" and core.replace_in_buffer(item) then
		close_history_window()
	end
end

local function delete_current_item()
	local uid = state.selected_uids[state.selected_call_type]
	local new_uid = vim.fn.AjapopajaDeleteHistoryItem(state.selected_call_type, uid)
	if new_uid ~= nil and type(new_uid) ~= "userdata" then
		state.selected_uids[state.selected_call_type] = new_uid
	end
	state.sync_history()
	M.render()
end

local function select_call_type(call_type)
	if state.selected_call_type == call_type then
		return
	end
	state.select_call_type(call_type)
	M.render()
end

function M.open()
	prev_win = vim.api.nvim_get_current_win()
	if not state.call_uids[state.call_types[1]] then
		state.sync_history()
	end
	buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
	vim.api.nvim_set_option_value("readonly", true, { buf = buf })

	sync_callback = sync_callback
		or function()
			if vim.api.nvim_win_is_valid(win) then
				update_title()
			else
				state.remove_sync_callback(sync_callback)
			end
		end
	state.add_sync_callback(sync_callback)

	local w, h = math.ceil(vim.o.columns * 0.8), math.ceil(vim.o.lines * 0.8)
	win = vim.api.nvim_open_win(buf, true, {
		style = "minimal",
		relative = "editor",
		border = "rounded",
		width = w,
		height = h,
		row = math.ceil((vim.o.lines - h) / 2),
		col = math.ceil((vim.o.columns - w) / 2),
	})
	-- Enable text wrapping and visual improvements for the Markdown buffer
	vim.api.nvim_set_option_value("wrap", true, { win = win })
	vim.api.nvim_set_option_value("linebreak", true, { win = win })
	vim.api.nvim_set_option_value("breakindent", true, { win = win })

	local map_opts = { buffer = buf, silent = true }
	vim.keymap.set("n", "l", function()
		state.next()
		M.render()
	end, map_opts)
	vim.keymap.set("n", "x", delete_current_item, map_opts)
	vim.keymap.set("n", "C", function()
		vim.fn.AjapopajaClearHistory(state.selected_call_type)
		state.sync_history()
		M.render()
	end, map_opts)
	vim.keymap.set("n", "h", function()
		state.prev()
		M.render()
	end, map_opts)
	vim.keymap.set("n", "t", function()
		select_call_type("transform")
	end, map_opts)
	vim.keymap.set("n", "r", function()
		select_call_type("review")
	end, map_opts)
	vim.keymap.set("n", "I", refine_with_standard_prompt, map_opts)
	vim.keymap.set("n", "i", refine, map_opts)
	vim.keymap.set("n", "<CR>", apply_transformation, map_opts)
	vim.keymap.set("n", "q", close_history_window, map_opts)

	vim.api.nvim_create_autocmd("BufWinLeave", {
		buffer = buf,
		once = true,
		callback = function()
			if sync_callback then
				state.remove_sync_callback(sync_callback)
			end
		end,
	})
	-- render the window
	M.render()
end

return M
