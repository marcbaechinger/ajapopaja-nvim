local state = require("ajapopaja_plugin.state")
local utils = require("ajapopaja_plugin.utils")
local M = {}

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
	local indentation = 0
	if lines and lines[1] then
		indentation = #lines[1]:match("^%s*")
	end
	vim.notify("aindentation='" .. indentation .. "'")
	selection_info.indentation = indentation
	selection_info.hash = utils.calculate_range_hash(selection_info)
	return selection_info
end

function M.insert_to_buffer(history_item)
	local bufnr = vim.api.nvim_get_current_buf()
	local mode = vim.api.nvim_get_mode().mode
	local lines = vim.split(history_item.response, "\n")

	if mode == "v" or mode == "V" or mode == "\22" then
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

		local s_pos = vim.fn.getpos("'<")
		local e_pos = vim.fn.getpos("'>")

		local start_row = s_pos[2] - 1
		local start_col = s_pos[3] - 1
		local end_row = e_pos[2] - 1
		local end_col = e_pos[3]

		local last_line_content = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1] or ""
		local max_col = #last_line_content

		if end_col > max_col then
			end_col = max_col
		end

		if mode == "V" then
			local prefix = string.rep(" ", history_item.selection_info.indentation)
			if #lines > 0 then
				lines[1] = prefix .. lines[1]
			end
			vim.api.nvim_buf_set_lines(bufnr, start_row, e_pos[2], false, lines)
		else
			vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, lines)
		end
	else
		local type = #lines > 1 and "l" or "c"
		local after = false
		local follow = false
		vim.api.nvim_put(lines, type, after, follow)
	end
end

-- Capture selection coordinates
function M.capture_context()
	local mode = vim.api.nvim_get_mode().mode
	if mode ~= "V" then
		vim.notify("Only line selection mode supported (V-line)", vim.log.levels.ERROR)
		return nil
	end
	local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
	vim.api.nvim_feedkeys(esc, "x", true)
	local s_pos = vim.fn.getpos("'<")
	local e_pos = vim.fn.getpos("'>")
	local buf = vim.api.nvim_get_current_buf()
	local line_count = vim.api.nvim_buf_line_count(buf)
	if s_pos[2] < 1 then
		-- capture entire buffer is no selection is applied
		local last_line = line_count > 0 and line_count - 1 or 0
		local last_col = line_count > 0 and #vim.api.nvim_buf_get_lines(buf, last_line, last_line + 1, false)[1] or 0
		return create_selection_info(buf, {
			0, -- start_line
			0, -- start_col
			last_line, -- end_line
			last_col, -- end_col
		})
	end
	return create_selection_info(buf, {
		s_pos[2] - 1, -- start_line
		s_pos[3] - 1, -- start_col
		e_pos[2] - 1, -- end_line
		e_pos[3], -- end_col
	})
end

-- Replacement Logic with Safety Check
function M.replace_in_buffer(item)
	if not item then
		vim.notify("Ajapopaja: No valid context to apply.", vim.log.levels.WARN)
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
	local lines = vim.split(item.response, "\n")
	local prefix = string.rep(" ", item.selection_info.indentation)
	if #lines > 0 then
		lines[1] = prefix .. lines[1]
	end

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
function M.transform(prompt, selection_info)
	if not selection_info then
		vim.notify("Ajapopaja: No valid selection found")
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

	state.is_loading = true
	vim.cmd("redrawstatus")
	local success, err =
		pcall(vim.fn.AjapopajaAgentCall, table.concat(text_lines, "\n"), selection_info, "transform", prompt)
	if not success then
		state.is_loading = false
		vim.cmd("redrawstatus")
		vim.notify("Ajapopaja: Error calling agent: " .. tostring(err), vim.log.levels.ERROR)
	end
end

return M
