local M = {}

-- Identify programming language based on buffer filetype
function M.get_programming_language()
	local ft = vim.bo.filetype
	local map = {
		["javascriptreact"] = "javascript",
		["typescriptreact"] = "typescript",
		["bash"] = "sh",
	}
	return map[ft] or (ft ~= "" and ft or "text")
end

-- Helper to calculate SHA256 hash of a specific text range for safety checks
function M.calculate_range_hash(selection_info)
	if not selection_info then
		return nil
	end
	local success, lines = pcall(
		vim.api.nvim_buf_get_text,
		selection_info.buf_id,
		selection_info.start_row,
		selection_info.start_col,
		selection_info.end_row,
		selection_info.end_col,
		{}
	)
	if not success then
		return nil
	end
	return vim.fn.sha256(table.concat(lines, "\n"))
end

--- Resolves a file path back to a buffer handle.
--- @param path string The absolute path to the file.
--- @param create_if_missing boolean Whether to load the file if it's not currently open.
--- @return number|nil bufnr The buffer handle or nil if not found/loadable.
function M.get_bufnr_from_path(path, create_if_missing)
	if path == "" or path == nil then
		return nil
	end

	local bufnr = vim.fn.bufnr(path)

	if bufnr ~= -1 then
		if not vim.api.nvim_buf_is_loaded(bufnr) then
			vim.fn.bufload(bufnr)
		end
		return bufnr
	end

	if create_if_missing then
		bufnr = vim.fn.bufnr(path, true)
		vim.fn.bufload(bufnr)
		return bufnr
	end

	return nil
end

return M
