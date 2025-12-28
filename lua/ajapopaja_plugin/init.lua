local M = {}

-- Internal State
local buf, win
local last_active_buf = nil
-- last_selection now includes the original text hash for safety
local last_selection = nil -- { s_line, s_col, e_line, e_col, hash }
local current_view = "transform"
local current_index = 1
local history_cache = { transform = {}, review = {} }

-- Identify programming language based on buffer filetype
local function get_programming_language()
	local ft = vim.bo.filetype
	local map = { ["javascriptreact"] = "javascript", ["typescriptreact"] = "typescript", ["bash"] = "sh" }
	return map[ft] or (ft ~= "" and ft or "text")
end

-- Capture selection and context (Buffer and 0-indexed coordinates)
local function capture_context()
	last_active_buf = vim.api.nvim_get_current_buf()
	local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
	vim.api.nvim_feedkeys(esc, "x", true)

	local s_pos = vim.fn.getpos("'<")
	local e_pos = vim.fn.getpos("'>")

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

-- Refresh history from Python backend
local function sync_history()
	local raw_history = vim.fn.AjapopajaGetHistory()
	history_cache = vim.json.decode(raw_history)
end

-- Helper to calculate hash of a text range
local function calculate_range_hash(buffer, selection)
	local lines = vim.api.nvim_buf_get_text(buffer, selection[1], selection[2], selection[3], selection[4], {})
	local content = table.concat(lines, "\n")
	return vim.fn.sha256(content)
end

-- Internal function to execute text replacement with safety checks
local function execute_replacement(item)
	if not item or not last_active_buf or not last_selection then
		print("Ajapopaja: No valid context or content to apply.")
		return false
	end

	-- SAFETY CHECK: Verify if the buffer content has changed since capture
	if last_selection[5] then
		local current_hash = calculate_range_hash(last_active_buf, last_selection)
		if current_hash ~= last_selection[5] then
			vim.api.nvim_err_writeln(
				"Ajapopaja Security: The buffer content has changed since the transformation started. Apply aborted to prevent code corruption."
			)
			return false
		end
	end

	-- Retrieve target line text to calculate valid byte length for clamping
	local target_line_content =
		vim.api.nvim_buf_get_lines(last_active_buf, last_selection[3], last_selection[3] + 1, false)[1]
	if not target_line_content then
		return false
	end

	local actual_end_col = math.min(last_selection[4], #target_line_content)
	local lines = vim.split(item.response, "\n")

	-- Execute text replacement
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
		print("Ajapopaja: Transformation applied successfully.")
		return true
	else
		vim.api.nvim_err_writeln("Ajapopaja Error: " .. tostring(err))
		return false
	end
end

-- Apply the current transformation from history window
local function apply_current_history()
	if current_view ~= "transform" then
		print("Ajapopaja: You can only apply transformations, not reviews.")
		return
	end

	local items = history_cache[current_view]
	-- Defensive check: Index clamping
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
		-- Recalculate index after deletion
		current_index = math.max(1, math.min(current_index, #history_cache[current_view]))
		M.render_history()
		print("Ajapopaja: Entry deleted.")
	end
end

-- Clear all history for the current view
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

function M.ajapopaja_apply_latest()
	sync_history()
	local transforms = history_cache.transform
	if #transforms == 0 then
		print("Ajapopaja: No transformation history found.")
		return
	end
	execute_replacement(transforms[#transforms])
end

-- Render history UI in the floating window using Markdown
function M.render_history()
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local items = history_cache[current_view]
	local content = {}

	-- ARCHITECTURAL FIX: Always clamp the index before rendering to prevent nil indexing
	if #items > 0 then
		current_index = math.max(1, math.min(current_index, #items))
	end

	if #items == 0 then
		content = { "# No " .. (current_view == "transform" and "Transformation" or "Review") .. " history found" }
	else
		local item = items[current_index]
		content = {
			"# "
				.. (current_view == "transform" and "Transformation" or "Review")
				.. " ("
				.. current_index
				.. "/"
				.. #items
				.. ")",
			"**Prompt:** " .. (item.prompt or "N/A"),
			"---",
		}

		-- Logic for conditional fencing: transformations are fenced, reviews are raw markdown
		if current_view == "transform" then
			table.insert(content, "```" .. (item.lang or "text"))
			table.insert(content, item.response)
			table.insert(content, "```")
		else
			table.insert(content, item.response)
		end

		table.insert(content, "")
		table.insert(content, "---")
		table.insert(content, "Controls: [h/l] Nav | [t/r] Switch View | [x] Delete | [C] Clear All | [Enter] Apply")
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(table.concat(content, "\n"), "\n"))
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	local title_text = " Ajapopaja: " .. (current_view == "transform" and "Transformation" or "Review") .. " "
	if #items > 0 then
		title_text = title_text .. "(" .. current_index .. "/" .. #items .. ") "
	end

	vim.api.nvim_win_set_config(win, {
		title = { { title_text, "WhidHeader" } },
		title_pos = "center",
	})
end

local function open_window()
	sync_history()
	-- Reset or clamp index upon opening
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

-- Trigger an LLM transformation
function M.ajapopaja_transform()
	capture_context()
	if not last_active_buf or not last_selection then
		print("Ajapopaja: No valid selection found.")
		return
	end

	-- Capture the hash of the selection at start
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
	vim.ui.input({ prompt = "Enter transformation prompt: " }, function(input)
		if input and input ~= "" then
			vim.fn.AjapopajaAgentCall(table.concat(text_lines, "\n"), lang, "transform", input)
		end
	end)
end

-- Trigger an LLM code review
function M.ajapopaja_review()
	capture_context()
	if not last_active_buf or not last_selection then
		print("Ajapopaja: No valid selection found.")
		return
	end

	-- Capture hash for reviews as well, though reviews are read-only
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
	vim.fn.AjapopajaAgentCall(table.concat(text_lines, "\n"), get_programming_language(), "review", "")
end

-- Plugin Setup and Keybindings
function M.setup()
	local opts = { silent = true }
	vim.keymap.set({ "n", "v" }, "<leader>ajt", M.ajapopaja_transform, opts)
	vim.keymap.set({ "n", "v" }, "<leader>ajr", M.ajapopaja_review, opts)
	vim.keymap.set("n", "<leader>ajw", open_window, opts)
	vim.keymap.set("n", "<leader>ajp", M.ajapopaja_apply_latest, { desc = "Ajapopaja: Apply Latest Transformation" })
end

return M
