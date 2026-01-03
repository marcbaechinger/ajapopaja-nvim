local prompts =
	{ { title = "Mock Prompt 1", content = "content 1" }, { title = "Mock Prompt 2", content = "content 2" } }
local mock_prompt_lib = {
	get_prompts = function()
		return prompts
	end,
	get_prompt = function(_, prompt_title)
		for _, prompt in ipairs(prompts) do
			if prompt.title == prompt_title then
				return prompt
			end
		end
		return nil
	end,
}
package.loaded["ajapopaja_plugin.prompt_library"] = mock_prompt_lib

local ui = require("ajapopaja_plugin.ui")

local original_schedule = vim.schedule
local original_select = vim.ui.select

describe("select", function()
	it("should mark the current item and put it to the top", function()
		local original_select = vim.ui.select
		local ui_items = {}
		local options = nil
		vim.ui.select = function(items, opts, on_choice, index)
			ui_items = items
			options = opts
		end

		ui.select("prompt", { "a", "b", "c" }, function(choice)
			print(choice)
		end, "b")
		local current_formatted = options.format_item("b")

		assert.are_same({ "b", "a", "c" }, ui_items)
		assert.equals("b (current)", current_formatted)

		vim.ui.select = original_select
	end)
end)

describe("select_prompt", function()
	-- add a fake schedule that calls the passed in callback immediately.
	vim.schedule = function(fn)
		-- call blocking
		fn()
	end
	it("should pass the prompts of the prompt lib to ui.select", function()
		local captured_prompts = {}
		vim.ui.select = function(prompts, opts, choice_handler, index)
			captured_prompts = prompts
		end

		ui.select_prompt(function() end, "python")

		assert.are.same({ "Mock Prompt 1", "Mock Prompt 2" }, captured_prompts)
	end)

	it("should call the callback on selection in ui.select", function()
		local choice = "8e4e9fce-0ef3-422e-9eff-89ffd5fe6988"
		local captured_prompt = nil
		vim.ui.select = function(prompts, opts, choice_handler, index)
			choice_handler(choice)
		end
		local on_choice = function(selected_prompt)
			captured_prompt = selected_prompt
		end

		ui.select_prompt(on_choice, "python")

		assert.are.equal(captured_prompt, choice)
	end)
	vim.ui.select = original_select
	vim.schedule = original_schedule
end)

describe("create_multi_line_input", function()
	it("should pass all lines of the buffer on submit", function()
		local captured_prompt = nil
		local multi_line_input = ui.create_multi_line_input("title", function(prompt)
			captured_prompt = prompt
		end, "python")
		vim.api.nvim_buf_set_lines(multi_line_input.buf, 0, -1, false, { "aaa", "111", "   " })

		multi_line_input.submit()

		assert.are_same({ "aaa", "111", "   " }, captured_prompt)
	end)

	it("should insert standard prompt when 'get_prompt' is called", function()
		local original_select_prompt = ui.select_prompt
		ui.select_prompt = function(callback, filetype)
			callback("Mock Prompt 1")
		end
		local captured_prompt = nil
		local multi_line_input = ui.create_multi_line_input("title", function(prompt)
			captured_prompt = prompt
		end, "python")
		vim.api.nvim_buf_set_lines(multi_line_input.buf, 0, -1, false, { "aaa", "111", "   " })
		multi_line_input.get_prompt()

		multi_line_input.submit()

		assert.are_same({ "# Mock Prompt 1", "", "content 1" }, captured_prompt)

		ui.select_prompt = original_select_prompt
	end)

	it("should not call 'submit' callback on close_ui", function()
		local captured_prompt = nil
		local multi_line_input = ui.create_multi_line_input("title", function(prompt)
			captured_prompt = prompt
		end, "python")
		vim.api.nvim_buf_set_lines(multi_line_input.buf, 0, -1, false, { "aaa", "111", "   " })

		multi_line_input.close_ui()

		assert.is_nil(captured_prompt)
	end)

	it("should set window nr back to previous window on close_ui", function()
		local current_win = vim.api.nvim_get_current_win()
		local multi_line_input = ui.create_multi_line_input("title", function() end, "python")
		vim.api.nvim_buf_set_lines(multi_line_input.buf, 0, -1, false, { "aaa", "111", "   " })

		assert.is_not.are_same(current_win, vim.api.nvim_get_current_win())

		multi_line_input.close_ui()

		assert.are_same(current_win, vim.api.nvim_get_current_win())
	end)

	it("should set window nr back to previous window on submit", function()
		local current_win = vim.api.nvim_get_current_win()
		local multi_line_input = ui.create_multi_line_input("title", function() end, "python")
		vim.api.nvim_buf_set_lines(multi_line_input.buf, 0, -1, false, { "aaa", "111", "   " })

		assert.is_not.are_same(current_win, vim.api.nvim_get_current_win())

		multi_line_input.submit()

		assert.are_same(current_win, vim.api.nvim_get_current_win())
	end)
end)

vim.ui.select = original_select
vim.schedule = original_schedule
package.loaded["ajapopaja_plugin.prompt_library"] = nil
