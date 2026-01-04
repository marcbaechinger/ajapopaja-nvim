local core = require("ajapopaja.core")
local assert = require("luassert")

describe("capture_context", function()
	it("should get the current buf nr and cursoe position in normal mode", function()
		local buf = vim.fn.bufadd("buf_capture_context.py")
		local buf_name = vim.api.nvim_buf_get_name(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abc", "12345678" })
		vim.api.nvim_set_current_buf(buf)

		local context = core.capture_context()

		assert.is_table(context)
		if context ~= nil then
			assert.are_equal("python", context.lang)
			assert.are_equal(buf_name, context.buf_name)
			assert.are_equal(buf, context.buf_id)
			assert.are_equal(0, context.start_row)
			assert.are_equal(0, context.start_col)
			assert.are_equal(1, context.end_row)
			assert.are_equal(8, context.end_col)
		end

		vim.api.nvim_buf_delete(buf, { unload = true, force = true })
	end)

	it("should get the current buf nr and selection in V-line mode", function()
		local buf = vim.fn.bufadd("buf_capture_context.py")
		local buf_name = vim.api.nvim_buf_get_name(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abc", "1234", "xyz" })
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		vim.cmd("normal! VG")

		local context = core.capture_context()

		assert.is_table(context)
		if context ~= nil then
			assert.are_equal("python", context.lang)
			assert.are_equal(buf_name, context.buf_name)
			assert.are_equal(buf, context.buf_id)
			assert.are_equal(0, context.start_row)
			assert.are_equal(0, context.start_col)
			assert.are_equal(2, context.end_row)
			assert.are_equal(3, context.end_col)
		end
		vim.api.nvim_buf_delete(buf, { unload = true, force = true })
	end)

	it("should return nil in V-character mode and notify user", function()
		-- spy on vim.notify
		local history_was_called = false
		local original_notify = vim.notify
		vim.notify = function(msg, level, opts)
			if msg == "Only V-line or normal mode supported" then
				history_was_called = true
			end
			original_notify(msg, level, opts)
		end

		local buf = vim.fn.bufadd("buf_capture_context.py")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abc", "1234", "xyz" })
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		vim.cmd("normal! vG")

		assert.is_nil(core.capture_context())
		assert.is_true(history_was_called)

		vim.api.nvim_buf_delete(buf, { unload = true, force = true })
	end)
end)
