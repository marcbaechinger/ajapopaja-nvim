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
function M.calculate_range_hash(buffer, selection)
	if not buffer or not selection then
		return nil
	end
	local success, lines =
		pcall(vim.api.nvim_buf_get_text, buffer, selection[1], selection[2], selection[3], selection[4], {})
	if not success then
		return nil
	end
	return vim.fn.sha256(table.concat(lines, "\n"))
end

return M
