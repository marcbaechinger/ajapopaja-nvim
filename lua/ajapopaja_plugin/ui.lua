local M = {}

-- Open a dialog for entering a multiline md prompt
function M.create_multi_line_input(title, callback)
	local bufnr = vim.api.nvim_create_buf(false, true)

	vim.bo[bufnr].filetype = "markdown"
	vim.bo[bufnr].bufhidden = "wipe"

	local width = math.floor(vim.o.columns * 0.7)
	local height = math.floor(vim.o.lines * 0.5)
	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
		title = { { " " .. title .. " (Markdown) ", "FloatTitle" } },
		title_pos = "center",
	}

	local winnr = vim.api.nvim_open_win(bufnr, true, win_opts)

	vim.wo[winnr].wrap = true
	vim.wo[winnr].conceallevel = 2

	local ok, _ = pcall(require, "nvim-treesitter.configs")
	if ok then
		vim.treesitter.start(bufnr, "markdown")
	end

	vim.cmd("startinsert")

	local function submit()
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		vim.api.nvim_win_close(winnr, true)
		if callback then
			callback(lines)
		end
	end

	local opts = { buffer = bufnr, silent = true }
	vim.keymap.set("i", "<C-s>", submit, opts)
	vim.keymap.set("n", "<CR>", submit, opts)
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(winnr, true)
	end, opts)
end

---@param prompt string: The header for the selection UI
---@param options table: List of available choices
---@param callback function: Logic to execute on selection
---@param current? any: The currently active option (optional)
function M.select(prompt, options, callback, current)
	local items = vim.deepcopy(options)
	if current then
		for i, val in ipairs(items) do
			if val == current then
				table.remove(items, i)
				table.insert(items, 1, val)
				break
			end
		end
	end

	vim.ui.select(items, {
		prompt = prompt,
		format_item = function(item)
			if item == current then
				return item .. " (current)"
			end
			return item
		end,
	}, function(choice)
		if choice then
			callback(choice)
		end
	end)
end

return M
