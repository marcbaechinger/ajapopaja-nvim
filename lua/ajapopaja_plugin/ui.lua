local M = {}

local standard_prompts = {
	"Add or improve documentation",
	"Complete the missing parts that are missing implementation",
	"Create a unit test class that tests this functionality thouroughly",
	"Fix typos",
}

function M.create_multi_line_input(title, callback)
	local prev_win = vim.api.nvim_get_current_win()
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

	local function close_ui()
		if vim.api.nvim_win_is_valid(winnr) then
			vim.api.nvim_win_close(winnr, true)
		end
		if vim.api.nvim_win_is_valid(prev_win) then
			vim.api.nvim_set_current_win(prev_win)
		end
	end

	local function submit()
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		close_ui()
		if callback then
			callback(lines)
		end
	end

	local function get_standard_prompt()
		M.select("Choose a prompt", standard_prompts, function(selected_prompt)
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(selected_prompt, "\n"))
				if vim.api.nvim_win_is_valid(winnr) then
					vim.api.nvim_set_current_win(winnr)
					vim.cmd("startinsert!")
				end
			end
		end)
	end

	local opts = { buffer = bufnr, silent = true }
	vim.keymap.set("i", "<C-s>", submit, opts)
	vim.keymap.set("n", "<CR>", submit, opts)
	vim.keymap.set("n", "p", get_standard_prompt, opts)
	vim.keymap.set("n", "q", close_ui, opts)
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
			return item == current and (item .. " (current)") or item
		end,
	}, function(choice)
		vim.schedule(function()
			if choice then
				callback(choice)
			end
		end)
	end)
end

return M
