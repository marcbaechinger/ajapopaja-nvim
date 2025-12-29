local state = require("ajapopaja_plugin.state")
local utils = require("ajapopaja_plugin.utils")
local M = {}

-- Capture selection coordinates
function M.capture_context()
	state.last_active_buf = vim.api.nvim_get_current_buf()
	local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
	vim.api.nvim_feedkeys(esc, "x", true)

	local s_pos = vim.fn.getpos("'<")
	local e_pos = vim.fn.getpos("'>")

	if s_pos[2] > 0 then
		state.last_selection = {
			s_pos[2] - 1, -- start_line
			s_pos[3] - 1, -- start_col
			e_pos[2] - 1, -- end_line
			e_pos[3], -- end_col
			nil, -- hash
		}
	end
end

-- Replacement Logic with Safety Check
function M.execute_replacement(item)
	if not item or not state.last_active_buf or not state.last_selection then
		vim.notify("Ajapopaja: No valid context to apply.", vim.log.levels.WARN)
		return false
	end

	-- Optimistic Concurrency Control Check
	if state.last_selection[5] then
		local current_hash = utils.calculate_range_hash(state.last_active_buf, state.last_selection)
		if current_hash ~= state.last_selection[5] then
			vim.api.nvim_err_writeln("Ajapopaja Security: Buffer changed since LLM request. Aborting.")
			return false
		end
	end

	local target_line_content = vim.api.nvim_buf_get_lines(
		state.last_active_buf,
		state.last_selection[3],
		state.last_selection[3] + 1,
		false
	)[1]

	if not target_line_content then
		return false
	end

	local actual_end_col = math.min(state.last_selection[4], #target_line_content)
	local lines = vim.split(item.response, "\n")

	local success, err = pcall(function()
		vim.api.nvim_buf_set_text(
			state.last_active_buf,
			state.last_selection[1],
			state.last_selection[2],
			state.last_selection[3],
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
function M.transform(prompt)
	if not state.last_active_buf or not state.last_selection then
		return
	end

	state.last_selection[5] = utils.calculate_range_hash(state.last_active_buf, state.last_selection)
	local text_lines = vim.api.nvim_buf_get_text(
		state.last_active_buf,
		state.last_selection[1],
		state.last_selection[2],
		state.last_selection[3],
		state.last_selection[4],
		{}
	)

	state.is_loading = true
	vim.cmd("redrawstatus")

	vim.fn.AjapopajaAgentCall(table.concat(text_lines, "\n"), utils.get_programming_language(), "transform", prompt)
end

return M
