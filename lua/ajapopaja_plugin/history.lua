local state = require("ajapopaja_plugin.state")
local core = require("ajapopaja_plugin.core")
local M = {}

local buf, win

function M.sync_history()
	local raw_history = vim.fn.AjapopajaGetHistory()
	state.history_cache = vim.json.decode(raw_history)
end

function M.render()
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local items = state.history_cache[state.current_view]
	local content = {}

	if #items > 0 then
		state.current_index = math.max(1, math.min(state.current_index, #items))
	end

	if #items == 0 then
		content = { "# No " .. state.current_view .. " history found" }
	else
		local item = items[state.current_index]
		local controls = "Controls: [h/l] Nav | [t/r] Switch View | [x] Delete | [C] Clear | [Enter] Apply"
		table.insert(content, "**Prompt:** " .. (item.prompt or "N/A"))
		table.insert(content, "**Model:** " .. (item.model or "Unknown"))
		table.insert(content, controls)
		table.insert(content, "---")

		if state.current_view == "transform" then
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

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	local title_text = " Ajapopaja: " .. state.current_view .. " (" .. state.current_index .. "/" .. #items .. ") "
	pcall(vim.api.nvim_win_set_config, win, {
		title = { { title_text, "WhidHeader" } },
		title_pos = "center",
	})
end

function M.open()
	M.sync_history()
	local items = state.history_cache[state.current_view]
	state.current_index = #items > 0 and math.min(state.current_index, #items) or 1

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
		state.current_index = math.min(state.current_index + 1, #state.history_cache[state.current_view])
		M.render()
	end, map_opts)
	vim.keymap.set("n", "h", function()
		state.current_index = math.max(state.current_index - 1, 1)
		M.render()
	end, map_opts)
	vim.keymap.set("n", "t", function()
		state.current_view = "transform"
		M.render()
	end, map_opts)
	vim.keymap.set("n", "r", function()
		state.current_view = "review"
		M.render()
	end, map_opts)
	vim.keymap.set("n", "<CR>", function()
		local item = state.history_cache[state.current_view][state.current_index]
		if state.current_view == "transform" and core.execute_replacement(item) then
			vim.api.nvim_win_close(win, true)
		end
	end, map_opts)
	vim.keymap.set("n", "q", "<cmd>close<CR>", map_opts)

	M.render()
end

return M
