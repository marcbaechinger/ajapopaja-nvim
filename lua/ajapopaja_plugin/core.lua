local state = require("ajapopaja_plugin.state")
local utils = require("ajapopaja_plugin.utils")
local M = {}

local visual_char = "v"
local visual_line = "V"
local visual_block = "\22"

local function get_text_lines(selection_info)
	return vim.api.nvim_buf_get_text(
		selection_info.buf_id,
		selection_info.start_row,
		selection_info.start_col,
		selection_info.end_row,
		selection_info.end_col,
		{}
	)
end

local function create_selection_info(bufnr, selection)
	if not bufnr or not selection then
		return nil
	end

	local selection_info = {
		buf_name = vim.api.nvim_buf_get_name(bufnr),
		buf_id = bufnr,
		start_row = selection[1],
		start_col = selection[2],
		end_row = selection[3],
		end_col = selection[4],
		lang = utils.get_programming_language(),
	}
	local lines = get_text_lines(selection_info)
	local indentation = math.huge
	for _, line in ipairs(lines) do
		local leading_whitespace_count = #line:match("^%s*")
		if leading_whitespace_count < indentation and leading_whitespace_count < #line then
			indentation = leading_whitespace_count
		end
	end
	selection_info.indentation = indentation
	selection_info.hash = utils.calculate_range_hash(selection_info)
	return selection_info
end

local function get_padded_lines(history_item)
	local lines = vim.split(history_item.response, "\n")
	local prefix = string.rep(" ", history_item.selection_info.indentation)
	for i, line in ipairs(lines) do
		lines[i] = prefix .. line
	end
	return lines
end

function M.insert_to_buffer(history_item)
	local bufnr = vim.api.nvim_get_current_buf()
	local mode = vim.api.nvim_get_mode().mode
	local lines = get_padded_lines(history_item)

	if mode == visual_char or mode == visual_line or mode == visual_block then
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

		local start_position = vim.fn.getpos("'<")
		local end_position = vim.fn.getpos("'>")

		local start_row = start_position[2] - 1
		local start_col = start_position[3] - 1
		local end_row = end_position[2] - 1
		local end_col = end_position[3]

		local last_line_content = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1] or ""
		local max_col = #last_line_content

		if end_col > max_col then
			end_col = max_col
		end

		if mode == visual_line then
			vim.api.nvim_buf_set_lines(bufnr, start_row, end_position[2], false, lines)
		else
			vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, lines)
		end
	else
		-- non visual mode. Insert at cursor position
		local type = #lines > 1 and "l" or "c"
		local after = false
		local follow = false
		vim.api.nvim_put(lines, type, after, follow)
	end
end

--- Captures the current context for selection operations.
-- This function handles both Visual Line mode ('V') and Normal mode ('n'),
-- returning a structured selection info object.
--
-- In Visual Line mode, it exits the mode to ensure accurate mark positions,
-- then calculates the precise start and end coordinates of the selection.
--
-- In Normal mode, it returns the entire buffer range.
--
-- @return table|nil Selection information object or nil if unsupported mode
function M.capture_context()
	local mode_info = vim.api.nvim_get_mode()
	local mode = mode_info.mode
	local buf = vim.api.nvim_get_current_buf()

	-- We explicitly exclude 'v' (charwise) and '^V' (blockwise)
	if mode ~= "V" and mode ~= "n" then
		vim.notify("Only V-line or normal mode supported", vim.log.levels.WARN)
		return nil
	end

	if mode == "n" then
		-- Returns entire buffer range: 0, 0, line_count-1, last_line_len
		local start_line, start_col, end_line, end_col = utils.get_entire_buffer_range(buf)
		return create_selection_info(buf, { start_line, start_col, end_line, end_col })
	end

	-- Exit Visual Line mode to ensure marks '< and '> are updated.
	local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
	vim.api.nvim_feedkeys(esc, "nx", true)

	local s_pos = vim.fn.getpos("'<")
	local e_pos = vim.fn.getpos("'>")

	-- Convert 1-indexed getpos to 0-indexed API coordinates
	local start_line = s_pos[2] - 1
	local start_col = 0 -- In V-line mode, we always start at the beginning of the line
	local end_line = e_pos[2] - 1

	-- Even though it's V-line mode, we fetch the actual length of the last line
	-- to provide a precise end_col for create_selection_info.
	local line_content = vim.api.nvim_buf_get_lines(buf, end_line, end_line + 1, false)[1]
	local end_col = line_content and #line_content or 0

	if start_line < 0 then
		local sl, sc, el, ec = utils.get_entire_buffer_range(buf)
		return create_selection_info(buf, { sl, sc, el, ec })
	end

	return create_selection_info(buf, {
		start_line,
		start_col,
		end_line,
		end_col,
	})
end

-- Replacement Logic with Safety Check
function M.replace_in_buffer(item)
	if item == nil or item == vim.NIL then
		vim.notify("Ajapopaja: No valid history item to apply.", vim.log.levels.WARN)
		return false
	end

	-- Optimistic Concurrency Control Check
	if item.selection_info.hash then
		local current_hash = utils.calculate_range_hash(item.selection_info)
		if current_hash ~= item.selection_info.hash then
			vim.notify("Ajapopaja Security: Buffer changed since LLM request. Aborting.", vim.log.levels.ERROR)
			return false
		end
	end

	local target_line_content = vim.api.nvim_buf_get_lines(
		item.selection_info.buf_id,
		item.selection_info.end_row,
		item.selection_info.end_row + 1,
		false
	)[1]

	if not target_line_content then
		return false
	end

	local actual_end_col = math.min(item.selection_info.end_col, #target_line_content)
	local lines = get_padded_lines(item)

	local success, err = pcall(function()
		vim.api.nvim_buf_set_text(
			item.selection_info.buf_id,
			item.selection_info.start_row,
			item.selection_info.start_col,
			item.selection_info.end_row,
			actual_end_col,
			lines
		)
	end)

	if success then
		vim.notify("Ajapopaja: Transformation applied.", vim.log.levels.INFO)
		return true
	else
		vim.api.nvim_err_writeln("Ajapopaja Error: " .. tostring(err))
		return false
	end
end

-- Orchestrate Transform Request
function M.transform(prompt, selection_info, code_lines)
	if not selection_info then
		vim.notify("Ajapopaja: No valid selection found")
		return
	end

	local text_lines = code_lines
	if not text_lines then
		text_lines = vim.api.nvim_buf_get_text(
			selection_info.buf_id,
			selection_info.start_row,
			selection_info.start_col,
			selection_info.end_row,
			selection_info.end_col,
			{}
		)
	end

	state.is_loading = true
	vim.cmd("redrawstatus")
	local success, err =
		pcall(vim.fn.AjapopajaLlmCall, table.concat(text_lines, "\n"), selection_info, "transform", prompt)
	if not success then
		state.is_loading = false
		vim.cmd("redrawstatus")
		vim.notify("Ajapopaja: Error calling agent: " .. tostring(err), vim.log.levels.ERROR)
	end
end

return M
