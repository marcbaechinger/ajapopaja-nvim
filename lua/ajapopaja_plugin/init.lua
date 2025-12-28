local M = {}

local buf, win
local last_active_buf = nil
local last_selection = nil
local current_view = "transform"
local current_index = 1
local history_cache = { transform = {}, review = {} }
local is_loading = false
local available_models = {
	"qwen3-coder:30b",
	"gemma3:27b",
	"gpt-oss:20b",
	"codestral:22b",
	"mistral-small3.2:24b",
	"dolphin-mistral:7b",
	"qwen3:14b",
	"qwen3:30b",
	"gemma3:12b",
}
local current_model = "qwen3-coder:30b"

-- Helper functions
--
-- Identify programming language based on buffer filetype
local function get_programming_language()
	local ft = vim.bo.filetype
	local map = { ["javascriptreact"] = "javascript", ["typescriptreact"] = "typescript", ["bash"] = "sh" }
	return map[ft] or (ft ~= "" and ft or "text")
end

-- Capture selection coordinates and move back to Normal mode
local function capture_context()
	last_active_buf = vim.api.nvim_get_current_buf()
	local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
	vim.api.nvim_feedkeys(esc, "x", true)

	local s_pos = vim.fn.getpos("'<")
	local e_pos = vim.fn.getpos("'>")

	-- Coordinates are 0-indexed for Neovim API compatibility
	if s_pos[2] > 0 then
		last_selection = {
			s_pos[2] - 1, -- start_line
			s_pos[3] - 1, -- start_col
			e_pos[2] - 1, -- end_line
			e_pos[3], -- end_col (exclusive)
			nil, -- hash placeholder
		}
	end
end

-- Helper to calculate SHA256 hash of a specific text range for safety checks
local function calculate_range_hash(buffer, selection)
	if not buffer or not selection then
		return nil
	end
	local lines = vim.api.nvim_buf_get_text(buffer, selection[1], selection[2], selection[3], selection[4], {})
	local content = table.concat(lines, "\n")
	return vim.fn.sha256(content)
end

-- Refresh history data from the Python remote plugin
local function sync_history()
	local raw_history = vim.fn.AjapopajaGetHistory()
	history_cache = vim.json.decode(raw_history)
end

-- Signal status change (triggered by Python backend via exec_lua)
function M.set_loading(state)
	is_loading = state
	vim.cmd("redrawstatus")
end

-- Getter for statusline components (e.g., Lualine)
function M.get_status()
	if is_loading then
		return "󱚣 Ajapopaja: " .. current_model
	end
	return ""
end

-- History managment
--
-- Execute text replacement with Optimistic Concurrency Control
local function execute_replacement(item)
	if not item or not last_active_buf or not last_selection then
		print("Ajapopaja: No valid context or content to apply.")
		return false
	end

	if last_selection[5] then
		local current_hash = calculate_range_hash(last_active_buf, last_selection)
		if current_hash ~= last_selection[5] then
			vim.api.nvim_err_writeln("Ajapopaja Security: Buffer changed since transformation started. Aborting.")
			return false
		end
	end

	local target_line_content =
		vim.api.nvim_buf_get_lines(last_active_buf, last_selection[3], last_selection[3] + 1, false)[1]
	if not target_line_content then
		return false
	end

	local actual_end_col = math.min(last_selection[4], #target_line_content)
	local lines = vim.split(item.response, "\n")

	local success, err = pcall(function()
		vim.api.nvim_buf_set_text(
			last_active_buf,
			last_selection[1],
			last_selection[2],
			last_selection[3],
			actual_end_col,
			lines
		)
	end)

	if success then
		print("Ajapopaja: Transformation applied.")
		return true
	else
		vim.api.nvim_err_writeln("Ajapopaja Error: " .. tostring(err))
		return false
	end
end

-- Apply the active item in the history window
local function apply_current_history()
	if current_view ~= "transform" then
		print("Ajapopaja: You can only apply transformations, not reviews.")
		return
	end

	local items = history_cache[current_view]
	if #items == 0 then
		return
	end

	current_index = math.max(1, math.min(current_index, #items))
	local item = items[current_index]

	if execute_replacement(item) then
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end
end

-- Delete current entry from history
local function delete_current_entry()
	local items = history_cache[current_view]
	if #items == 0 then
		return
	end

	local success = vim.fn.AjapopajaDeleteEntry(current_view, current_index)
	if success then
		sync_history()
		current_index = math.max(1, math.min(current_index, #history_cache[current_view]))
		M.render_history()
		print("Ajapopaja: Entry deleted.")
	end
end

-- Clear all history for the active view
local function clear_entire_history()
	vim.ui.select({ "Yes", "No" }, {
		prompt = "Clear all " .. current_view .. " history?",
	}, function(choice)
		if choice == "Yes" then
			local success = vim.fn.AjapopajaClearHistory(current_view)
			if success then
				sync_history()
				current_index = 1
				M.render_history()
				print("Ajapopaja: History cleared.")
			end
		end
	end)
end

-- UI elements --
--
-- Open a dialog for entering a multiline md prompt
local function create_multi_line_input(title, callback)
	local bufnr = vim.api.nvim_create_buf(false, true)

	-- 1. Set Buffer Options for Markdown
	-- Using vim.bo (buffer-local options) is preferred in modern Neovim Lua
	vim.bo[bufnr].filetype = "markdown"
	vim.bo[bufnr].syntax = "markdown"
	vim.bo[bufnr].bufhidden = "wipe" -- Automatically clean up memory

	-- 2. Window Layout (as before)
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

	-- 3. Window-local UI enhancements
	-- Ensure code blocks and formatting are rendered nicely
	vim.wo[winnr].wrap = true
	vim.wo[winnr].conceallevel = 2
	vim.wo[winnr].concealcursor = "nc"

	-- 4. Force Treesitter attachment (if available)
	-- This ensures modern highlighting even in temporary buffers
	local ok, ts = pcall(require, "nvim-treesitter.configs")
	if ok then
		vim.treesitter.start(bufnr, "markdown")
	end

	vim.cmd("startinsert")

	-- 5. Logic Handlers
	local function submit()
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		vim.api.nvim_win_close(winnr, true)
		if callback then
			callback(lines)
		end
	end

	-- Keybindings
	local opts = { buffer = bufnr, silent = true }
	vim.keymap.set("i", "<C-s>", submit, opts)
	vim.keymap.set("n", "<CR>", submit, opts)
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(winnr, true)
	end, opts)
end

-- Open the floating window to browse the history
local function open_window()
	sync_history()
	local items = history_cache[current_view]
	current_index = #items > 0 and math.min(current_index, #items) or 1

	buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })

	local screen_w = vim.api.nvim_get_option_value("columns", { scope = "global" })
	local screen_h = vim.api.nvim_get_option_value("lines", { scope = "global" })
	local w, h = math.ceil(screen_w * 0.8), math.ceil(screen_h * 0.8)

	win = vim.api.nvim_open_win(buf, true, {
		style = "minimal",
		relative = "editor",
		border = "rounded",
		width = w,
		height = h,
		row = math.ceil((screen_h - h) / 2),
		col = math.ceil((screen_w - w) / 2),
	})

	-- Window-local options for enhanced readability of reviews
	vim.api.nvim_set_option_value("wrap", true, { win = win })
	vim.api.nvim_set_option_value("linebreak", true, { win = win })
	vim.api.nvim_set_option_value("breakindent", true, { win = win })

	local map_opts = { buffer = buf, silent = true }
	vim.keymap.set("n", "l", function()
		current_index = math.min(current_index + 1, #history_cache[current_view])
		M.render_history()
	end, map_opts)
	vim.keymap.set("n", "h", function()
		current_index = math.max(current_index - 1, 1)
		M.render_history()
	end, map_opts)
	vim.keymap.set("n", "t", function()
		current_view = "transform"
		current_index = math.max(1, #history_cache.transform)
		M.render_history()
	end, map_opts)
	vim.keymap.set("n", "r", function()
		current_view = "review"
		current_index = math.max(1, #history_cache.review)
		M.render_history()
	end, map_opts)
	vim.keymap.set("n", "x", delete_current_entry, map_opts)
	vim.keymap.set("n", "C", clear_entire_history, map_opts)
	vim.keymap.set("n", "<CR>", apply_current_history, map_opts)
	vim.keymap.set("n", "q", "<cmd>close<CR>", map_opts)

	M.render_history()
end

-- Quickly apply the most recent transformation result
function M.ajapopaja_apply_latest()
	sync_history()
	local transforms = history_cache.transform
	if #transforms == 0 then
		print("Ajapopaja: No transformation history found.")
		return
	end
	execute_replacement(transforms[#transforms])
end

-- Model Selection UI
function M.ajapopaja_select_model()
	vim.ui.select(available_models, {
		prompt = "Select LLM Model:",
	}, function(choice)
		if choice then
			vim.fn.AjapopajaSetModel(choice)
			current_model = choice
		end
	end)
end

-- Render the history UI in the floating buffer
function M.render_history()
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local items = history_cache[current_view]
	local content = {}

	-- Defensive Index Clamping to prevent nil access
	if #items > 0 then
		current_index = math.max(1, math.min(current_index, #items))
	end

	local title = (current_view == "transform" and "Transformation" or "Review")
	if #items == 0 then
		content = { "# No " .. current_view .. " history found" }
	else
		local item = items[current_index]
		local controls = "Controls: [h/l] Nav | [t/r] Switch View | [x] Delete | [C] Clear All | [Enter] Apply"
		if current_view ~= "transform" then
			controls = "Controls: [h/l] Nav | [t/r] Switch View | [x] Delete | [C] Clear All"
		end
		content = {
			"**Prompt:** " .. (item.prompt or "N/A"),
			"**Model:** " .. (item.model or "Unknown"),
			controls,
			"---",
		}
		if current_view == "transform" then
			table.insert(content, "```" .. (item.lang or "text"))
			table.insert(content, item.response)
			table.insert(content, "```")
		else
			table.insert(content, item.response)
		end

		table.insert(content, "")
		table.insert(content, "---")
		table.insert(content, controls)
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(table.concat(content, "\n"), "\n"))
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	-- Update Floating Window Title
	local title_text = " Ajapopaja: " .. title .. " (" .. current_index .. "/" .. #items .. ") "
	vim.api.nvim_win_set_config(win, {
		title = { { title_text, "WhidHeader" } },
		title_pos = "center",
	})
end
-- Transformation Logic

local function transform(prompt)
	if not last_active_buf or not last_selection then
		print("Ajapopaja: No valid selection found.")
		return
	end

	-- Compute hash of the selection at start-time
	last_selection[5] = calculate_range_hash(last_active_buf, last_selection)

	local text_lines = vim.api.nvim_buf_get_text(
		last_active_buf,
		last_selection[1],
		last_selection[2],
		last_selection[3],
		last_selection[4],
		{}
	)
	local lang = get_programming_language()

	M.set_loading(true)
	vim.fn.AjapopajaAgentCall(table.concat(text_lines, "\n"), lang, "transform", prompt)
end

function M.ajapopaja_transform()
	capture_context()
	create_multi_line_input("Describe the code transformation...", function(lines)
		local instruction = table.concat(lines, "\n")
		if instruction ~= "" then
			transform(instruction)
		end
	end)
end

function M.ajapopaja_add_documentation()
	capture_context()
	transform("Add or improve the documentation")
end

function M.ajapopaja_implement_function()
	capture_context()
	transform("Implement this function")
end

function M.ajapopaja_add_unit_tests()
	capture_context()
	transform("Create unit tests to test the functionality thoroughly")
end

-- Review Logic

function M.ajapopaja_review()
	capture_context()
	if not last_active_buf or not last_selection then
		print("Ajapopaja: No valid selection found.")
		return
	end

	last_selection[5] = calculate_range_hash(last_active_buf, last_selection)

	local text_lines = vim.api.nvim_buf_get_text(
		last_active_buf,
		last_selection[1],
		last_selection[2],
		last_selection[3],
		last_selection[4],
		{}
	)
	if #text_lines == 0 then
		return
	end

	M.set_loading(true)
	vim.fn.AjapopajaAgentCall(table.concat(text_lines, "\n"), get_programming_language(), "review", "")
end

-- Plugin Setup
function M.setup()
	vim.keymap.set(
		{ "v" },
		"<leader>ad",
		M.ajapopaja_add_documentation,
		{ silent = true, desc = "Ajapopaja: Add or improve documentation" }
	)
	vim.keymap.set(
		{ "v" },
		"<leader>ai",
		M.ajapopaja_implement_function,
		{ silent = true, desc = "Ajapopaja: Implement function" }
	)
	vim.keymap.set(
		{ "v" },
		"<leader>au",
		M.ajapopaja_add_unit_tests,
		{ silent = true, desc = "Ajapopaja: Create unit test" }
	)
	vim.keymap.set(
		{ "v" },
		"<leader>at",
		M.ajapopaja_transform,
		{ silent = true, desc = "Ajapopaja: Transform selection..." }
	)
	vim.keymap.set(
		{ "n", "v" },
		"<leader>ar",
		M.ajapopaja_review,
		{ silent = true, desc = "Ajapopaja: Review selection" }
	)
	vim.keymap.set("n", "<leader>aw", open_window, { desc = "Ajapopaja: Open history window" })
	vim.keymap.set("n", "<leader>am", M.ajapopaja_select_model, { desc = "Ajapopaja: Select LLM Model" })
	vim.keymap.set("n", "<leader>ap", M.ajapopaja_apply_latest, { desc = "Ajapopaja: Apply Latest Transformation" })
end

return M
