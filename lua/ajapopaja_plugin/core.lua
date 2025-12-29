local state = require("ajapopaja_plugin.state")
local utils = require("ajapopaja_plugin.utils")
local M = {}

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
	selection_info.hash = utils.calculate_range_hash(selection_info)
	return selection_info
end

-- Capture selection coordinates
function M.capture_context()
	local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
	vim.api.nvim_feedkeys(esc, "x", true)
	local s_pos = vim.fn.getpos("'<")
	local e_pos = vim.fn.getpos("'>")
	local buf = vim.api.nvim_get_current_buf()
	if s_pos[2] < 1 then
		-- capture entire buffer is no selection is applied
		local lines = vim.api.nvim_buf_line_count(buf)
		local last_line = lines > 0 and lines - 1 or 0
		local last_col = lines > 0 and #vim.api.nvim_buf_get_lines(buf, last_line, last_line + 1, false)[1] or 0
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
function M.execute_replacement(item)
	if not item then
		vim.notify("Ajapopaja: No valid context to apply.", vim.log.levels.WARN)
		return false
	end

	-- Optimistic Concurrency Control Check
	if item.selection_info.hash then
		local current_hash = utils.calculate_range_hash(item.selection_info)
		if current_hash ~= item.selection_info.hash then
			vim.api.nvim_err_writeln("Ajapopaja Security: Buffer changed since LLM request. Aborting.")
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
	vim.fn.AjapopajaAgentCall(table.concat(text_lines, "\n"), selection_info, "transform", prompt)
end

return M
