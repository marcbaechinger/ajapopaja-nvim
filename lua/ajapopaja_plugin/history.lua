local state = require("ajapopaja_plugin.state")
local core = require("ajapopaja_plugin.core")
local M = {}

local buf, win

function M.render()
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local call_type = state.selected_call_type
	local uid = state.selected_uids[call_type]
	local uids = state.call_uids[call_type]
	local content = {}

	local not_found = { "# No history item found for call type '" .. state.selected_call_type .. "'" }
	if not uid then
		content = not_found
	else
		local item = vim.fn.AjapopajaGetHistoryItem(call_type, uid)
		if item == nil or type(item) == "userdata" then
			content = not_found
		else
			local prompt = item.prompt or "N/A"
			local model = item.model or "Unknown"
			local controls = "Controls: [h/l] Nav | [t/r] Switch View | [x] Delete | [C] Clear | [Enter] Apply"
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

	local title_text = " Ajapopaja: "
		.. state.selected_call_type
		.. " ("
		.. state.get_selected_index()
		.. "/"
		.. #uids
		.. ") "
	pcall(vim.api.nvim_win_set_config, win, {
		title = { { title_text, "WhidHeader" } },
		title_pos = "center",
	})
end

function M.open()
	if not state.call_uids[state.call_types[1]] then
		state.sync_history()
	end
	buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
	vim.api.nvim_set_option_value("readonly", true, { buf = buf })

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
	vim.keymap.set("n", "x", function()
		local index = state.get_selected_index()
		vim.fn.AjapopajaDeleteEntry(state.selected_call_type, index)
		state.sync_history()
		M.render()
	end, map_opts)
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
		state.select_call_type("transform")
		M.render()
	end, map_opts)
	vim.keymap.set("n", "r", function()
		state.select_call_type("review")
		M.render()
	end, map_opts)
	vim.keymap.set("n", "<CR>", function()
		local item =
			vim.fn.AjapopajaGetHistoryItem(state.selected_call_type, state.selected_uids[state.selected_call_type])
		if state.selected_call_type == "transform" and core.replace_in_buffer(item) then
			vim.api.nvim_win_close(win, true)
		end
	end, map_opts)
	vim.keymap.set("n", "q", "<cmd>close<CR>", map_opts)
	M.render()
end

return M
