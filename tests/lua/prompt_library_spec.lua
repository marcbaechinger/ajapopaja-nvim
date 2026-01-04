-- Copyright (c) 2026 Marc Baechinger
-- Licensed under the MIT License.

local prompt_library = require("ajapopaja.prompt_library")

local original_open = prompt_library.open_file
describe("parse_markdown_prompts", function()
	local function override_open_file(mock_file)
		prompt_library.open_file = function()
			return mock_file
		end
	end

	it("should use the mocked open_file function", function()
		local mock_file = {
			lines = function()
				return coroutine.wrap(function()
					coroutine.yield("# Test Title")
					coroutine.yield("Test Content")
				end)
			end,
			close = function() end,
		}

		override_open_file(mock_file)
		local prompts = prompt_library.parse_markdown_prompts("anything")

		assert.are.equal("Test Title", prompts[1].title)
		assert.are.equal("Test Content", prompts[1].content)
	end)

	it("should return a prompt for each top level header", function()
		local mock_file = {
			lines = function()
				return coroutine.wrap(function()
					coroutine.yield("# Test Title")
					coroutine.yield("Test Content")
					coroutine.yield("")
					coroutine.yield("* item 1")
					coroutine.yield("* item 2")
					coroutine.yield("")
					coroutine.yield("##Test Content")
					coroutine.yield("")
					coroutine.yield("Some text")
					coroutine.yield("")
					coroutine.yield("# Test Title 2")
					coroutine.yield("Test Content 2")
					coroutine.yield("# Test Title 3")
					coroutine.yield("# Test Title 4")
					coroutine.yield("# Test Title 5")
				end)
			end,
			close = function() end,
		}
		override_open_file(mock_file)

		local prompts = prompt_library.parse_markdown_prompts("/dev/null/mocked.md")

		assert.are.equal("Test Title", prompts[1].title)
		assert.are.equal("Test Title 2", prompts[2].title)
		assert.are.equal("Test Title 3", prompts[3].title)
		assert.are.equal("Test Title 4", prompts[4].title)
		assert.are.equal("Test Title 5", prompts[5].title)
		assert.are.equal("Test Content\n\n* item 1\n* item 2\n\n##Test Content\n\nSome text\n", prompts[1].content)
		assert.are.equal("Test Content 2", prompts[2].content)
		assert.are.equal("", prompts[3].content)
		assert.are.equal("", prompts[4].content)
		assert.are.equal("", prompts[5].content)
	end)

	it("should skip leading markdown before a first top level header", function()
		local mock_file = {
			lines = function()
				return coroutine.wrap(function()
					coroutine.yield("Test Content")
					coroutine.yield("# Test Title 2")
					coroutine.yield("Test Content 2")
					coroutine.yield("# Test Title 3")
					coroutine.yield("# Test Title 4")
					coroutine.yield("# Test Title 5")
				end)
			end,
			close = function() end,
		}
		override_open_file(mock_file)

		local prompts = prompt_library.parse_markdown_prompts("/dev/null/mocked.md")

		assert.are.equal("Test Title 2", prompts[1].title)
		assert.are.equal("Test Title 3", prompts[2].title)
		assert.are.equal("Test Title 4", prompts[3].title)
		assert.are.equal("Test Title 5", prompts[4].title)
		assert.are.equal("Test Content 2", prompts[1].content)
		assert.are.equal("", prompts[2].content)
		assert.are.equal("", prompts[3].content)
		assert.are.equal("", prompts[4].content)
	end)

	it("should return empty list of prompts if no top leader header present", function()
		local mock_file = {
			lines = function()
				return coroutine.wrap(function()
					coroutine.yield("Test Content")
				end)
			end,
			close = function() end,
		}
		override_open_file(mock_file)

		local prompts = prompt_library.parse_markdown_prompts("/dev/null/mocked.md")

		assert.are.equal(0, #prompts)
	end)

	it("should return empty table if reading from file fails", function()
		prompt_library.open_file = function()
			return nil
		end

		local prompts = prompt_library.parse_markdown_prompts("/dev/null/mocked.md")

		assert.is_table(prompts)
		assert.are_equal(0, #prompts)
	end)

	prompt_library.open_file = original_open
end)

local function endswith(str, suffix)
	return str:sub(-#suffix) == suffix
end

describe("get_prompts", function()
	local original_fs_access = vim.uv.fs_access
	vim.uv.fs_access = function(file_path)
		if endswith(file_path, "python.md") or endswith(file_path, "default.md") then
			return true
		end
		return false
	end
	local original_parse_markdown_prompts = prompt_library.parse_markdown_prompts
	local python_prompts = {
		{ title = "python title 1", content = "python content 1" },
		{ title = "python title 2", content = "python content 2" },
		{ title = "python title 3", content = "python content 3" },
	}
	local default_prompts = {
		{ title = "default title 1", content = "default content 1" },
		{ title = "default title 2", content = "default content 2" },
		{ title = "default title 3", content = "default content 3" },
	}
	prompt_library.parse_markdown_prompts = function(path)
		if endswith(path, "python.md") then
			return python_prompts
		else
			return default_prompts
		end
	end

	it("should return filetype specific prompts if filetype file exists", function()
		assert.are_same(prompt_library.get_prompts("python"), python_prompts)
	end)

	it("should return default prompts if filetype file does not exist", function()
		assert.are_same(prompt_library.get_prompts("javascript"), default_prompts)
		assert.are_same(prompt_library.get_prompts("kabeljau"), default_prompts)
	end)

	it("should return default prompts if filetype is not specified (nil)", function()
		assert.are_same(prompt_library.get_prompts(), default_prompts)
		assert.are_same(prompt_library.get_prompts(nil), default_prompts)
	end)

	prompt_library.parse_markdown_prompts = original_parse_markdown_prompts
	vim.uv.fs_access = original_fs_access
end)

describe("get_prompt", function()
	local original_fs_access = vim.uv.fs_access
	vim.uv.fs_access = function(file_path)
		if endswith(file_path, "python.md") or endswith(file_path, "default.md") then
			return true
		end
		return false
	end
	local original_parse_markdown_prompts = prompt_library.parse_markdown_prompts
	local python_prompts = {
		{ title = "python title 1", content = "python content 1" },
		{ title = "python title 2", content = "python content 2" },
		{ title = "python title 3", content = "python content 3" },
	}
	local default_prompts = {
		{ title = "default title 1", content = "default content 1" },
		{ title = "default title 2", content = "default content 2" },
		{ title = "default title 3", content = "default content 3" },
	}
	prompt_library.parse_markdown_prompts = function(path)
		if endswith(path, "python.md") then
			return python_prompts
		else
			return default_prompts
		end
	end

	it("should return filetype specific prompts if filetype file exists", function()
		assert.are_same(prompt_library.get_prompt("python", "python title 2"), python_prompts[2])
	end)

	it("should return default prompts if filetype file does not exist", function()
		assert.are_same(prompt_library.get_prompt("javascript", "default title 2"), default_prompts[2])
		assert.are_same(prompt_library.get_prompt("kabeljau", "default title 3"), default_prompts[3])
	end)

	it("should return nil if prompt title does not exist", function()
		assert.is_nil(prompt_library.get_prompt("javascript", "not existing"))
		assert.is_nil(prompt_library.get_prompt("kabeljau", "python title 1"))
		assert.is_nil(prompt_library.get_prompt("python", "default title 1"))
	end)

	prompt_library.parse_markdown_prompts = original_parse_markdown_prompts
	vim.uv.fs_access = original_fs_access
end)
