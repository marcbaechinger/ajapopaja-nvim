local utils = require("ajapopaja_plugin.utils")
local format_prompt = utils.format_prompt

describe("format_prompt", function()
	it("should format title and content as a multiline prompt in markdown", function()
		local expected_prompt = "# Prompt\n\ncontent of prompt"

		local prompt = format_prompt({ title = "Prompt", content = "content of prompt" })

		assert.equals(expected_prompt, prompt)
	end)
	it("should format prompt with a only a title without markdown header", function()
		local expected_prompt = "Prompt"

		local prompt = format_prompt({ title = "Prompt", content = "" })

		assert.equals(expected_prompt, prompt)
	end)
	it("should handle nil content gracefully", function()
		local expected_prompt = "Prompt"

		local prompt = format_prompt({ title = "Prompt", content = nil })

		assert.equals(expected_prompt, prompt)
	end)
	it("should handle nil prompt and return a emtpy string", function()
		local expected_prompt = ""

		local prompt = format_prompt(nil)

		assert.equals(expected_prompt, prompt)
	end)
end)

describe("get_entire_buffer_range", function()
	it("should get the empty buffer range correctly", function()
		local buf = vim.fn.bufadd("test_buf")

		local start_line, start_col, end_line, end_col = utils.get_entire_buffer_range(buf)

		assert.equals(start_line, 0)
		assert.equals(start_col, 0)
		assert.equals(end_line, 0)
		assert.equals(end_col, 0)

		vim.api.nvim_buf_delete(buf, { unload = false, force = false })
	end)
	it("should get the buffer range correctly", function()
		local buf = vim.fn.bufadd("test_buf")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "b", "1234" })

		local start_line, start_col, end_line, end_col = utils.get_entire_buffer_range(buf)

		assert.equals(start_line, 0)
		assert.equals(start_col, 0)
		assert.equals(end_line, 2)
		assert.equals(end_col, 4)

		vim.api.nvim_buf_delete(buf, { unload = true, force = true })
	end)

	it("should get the single line buffer range correctly", function()
		local buf = vim.fn.bufadd("test_buf")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "1234" })

		local start_line, start_col, end_line, end_col = utils.get_entire_buffer_range(buf)

		assert.equals(start_line, 0)
		assert.equals(start_col, 0)
		assert.equals(end_line, 0)
		assert.equals(end_col, 4)

		vim.api.nvim_buf_delete(buf, { unload = true, force = true })
	end)
end)

describe("get_bufnr_from_path", function()
	it("should get the correct buf nr for a given path", function()
		local buf = vim.fn.bufadd("test_buf")

		local buf_nr = utils.get_bufnr_from_path("test_buf", false)

		assert.equals(buf_nr, buf)

		vim.api.nvim_buf_delete(buf, { unload = true, force = true })
	end)

	it("should get a different buf nr for a different path", function()
		local buf = vim.fn.bufadd("test_buf")
		local buf_other = vim.fn.bufadd("test_buf_other")

		local buf_nr = utils.get_bufnr_from_path("test_buf", false)

		assert.is_not.equals(buf_nr, buf_other)

		vim.api.nvim_buf_delete(buf, { unload = false, force = false })
		vim.api.nvim_buf_delete(buf_other, { unload = false, force = false })
	end)

	it("should get nil for a non-existing path", function()
		local buf_nr = utils.get_bufnr_from_path("test_buf_not_existing", false)

		assert.equals(buf_nr, nil)
	end)
end)

describe("calculate_range_hash", function()
	it("should calculate the same hash for the same selection", function()
		local buf = vim.fn.bufadd("buf_for_hash")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abcd", "1234" })

		local hash = utils.calculate_range_hash({
			buf_id = buf,
			start_row = 0,
			start_col = 0,
			end_row = 1,
			end_col = 4,
		})
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abcd" })
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abcd", "1234" })
		local hash_again = utils.calculate_range_hash({
			buf_id = buf,
			start_row = 0,
			start_col = 0,
			end_row = 1,
			end_col = 4,
		})

		assert.is.truthy(hash)
		assert.equals(hash, hash_again)

		vim.api.nvim_buf_delete(buf, { unload = true, force = true })
	end)

	it("should calculate a different hash for a different selection", function()
		local buf = vim.fn.bufadd("buf_for_hash")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abcd", "1234" })

		local hash = utils.calculate_range_hash({
			buf_id = buf,
			start_row = 0,
			start_col = 0,
			end_row = 1,
			end_col = 4,
		})
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abcd", "1234", "next line" })
		local hash_again = utils.calculate_range_hash({
			buf_id = buf,
			start_row = 0,
			start_col = 0,
			end_row = 1,
			end_col = 3,
		})

		assert.is.truthy(hash)
		assert.is_not.equals(hash, hash_again)

		vim.api.nvim_buf_delete(buf, { unload = true, force = true })
	end)

	it("should calculate a different hash for the same selection with different content", function()
		local buf = vim.fn.bufadd("buf_for_hash")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abcd", "1234" })

		local hash = utils.calculate_range_hash({
			buf_id = buf,
			start_row = 0,
			start_col = 0,
			end_row = 1,
			end_col = 4,
		})
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Abcd", "1234" })
		local hash_again = utils.calculate_range_hash({
			buf_id = buf,
			start_row = 0,
			start_col = 0,
			end_row = 1,
			end_col = 4,
		})

		assert.is.truthy(hash)
		assert.is.truthy(hash_again)
		assert.is_not.equals(hash, hash_again)

		vim.api.nvim_buf_delete(buf, { unload = true, force = true })
	end)

	it("should calculate a different hash for the same selection with different content white space", function()
		local buf = vim.fn.bufadd("buf_for_hash")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abcd", "1234" })

		local hash = utils.calculate_range_hash({
			buf_id = buf,
			start_row = 0,
			start_col = 0,
			end_row = 1,
			end_col = 4,
		})
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abcd", "1234 " })
		local hash_again = utils.calculate_range_hash({
			buf_id = buf,
			start_row = 0,
			start_col = 0,
			end_row = 1,
			end_col = 5,
		})

		assert.is.truthy(hash)
		assert.is.truthy(hash_again)
		assert.is_not.equals(hash, hash_again)

		vim.api.nvim_buf_delete(buf, { unload = true, force = true })
	end)
end)
