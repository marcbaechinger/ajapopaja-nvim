local M = {

	available_models = {
		"qwen3-coder:30b",
		"gemma3:27b",
		"gpt-oss:20b",
		"devstral-small-2:latest",
		"codestral:22b",
		"mistral-small3.2:24b",
		"dolphin-mistral:7b",
		"qwen3:14b",
		"qwen3:30b",
		"gemma3:12b",
	},
	standard_prompts = {
		"Add code comments for edge cases",
		"Add comments explaining complex logic",
		"Add configuration options",
		"Add error handling and validation",
		"Add input validation and sanitization",
		"Add logging and debugging information",
		"Add or improve documentation",
		"Add type hints or annotations",
		"Complete the parts that are missing implementation",
		"Convert to use appropriate design patterns",
		"Convert to use modern language features",
		"Create a unit test class that tests this functionality thoroughly",
		"Create unit test functions that tests this functionality thoroughly",
		"Fix typos",
		"Implement proper exception handling",
		"Implement proper resource management",
		"Implement this function",
		"Improve code structure and organization",
		"Improve variable and function naming",
		"Optimize for performance",
		"Refactor to improve code readability",
	},
	-- History UI State
	selected_call_type = "transform",
	selected_index = {},
	selected_uids = {}, -- stores the currently selected uid for each call type
	call_uids = {}, -- stores the uids of all history items for each call type
	-- System State
	is_loading = false,
	current_model = "qwen3-coder:30b",
}

local function update_history_uids(call_type)
	local uids = vim.fn.AjapopajaGetHistoryUids(call_type)
	if uids then
		M.call_uids[call_type] = uids
		if #uids > 0 then
			M.selected_uids[call_type] = uids[#uids]
		end
	end
end

function M.sync_history()
	local init = not M.call_uids[M.selected_call_type]
	update_history_uids("transform")
	update_history_uids("review")
	if init then
		M.selected_index["transform"] = #M.call_uids["transform"]
		M.selected_index["review"] = #M.call_uids["review"]
	end
end

function M.select_call_type(call_type)
	local uids = M.call_uids[call_type]
	if not uids then
		return
	end
	M.selected_call_type = call_type
	M.selected_uids[call_type] = uids[#uids]
	M.selected_index[call_type] = #uids
end

function M.get_selected_index(call_type)
	local target_call_type = call_type or M.selected_call_type
	return M.selected_index[target_call_type] or 1
end

function M.next(call_type)
	local target_type = call_type or M.selected_call_type

	local uids = M.call_uids[target_type]
	if not uids or #uids < 1 then
		M.selected_index[call_type] = 0
		return
	end

	local current_uid = M.selected_uids[target_type]

	if not current_uid then
		M.selected_uids[target_type] = uids[1]
		M.selected_index[call_type] = 0
		return
	end

	local current_index = nil
	for i, uid in ipairs(uids) do
		if uid == current_uid then
			current_index = i
			break
		end
	end

	if current_index then
		local next_idx = (current_index % #uids) + 1
		M.selected_uids[target_type] = uids[next_idx]
		M.selected_index[target_type] = next_idx
	end
end

function M.prev(call_type)
	local target_type = call_type or M.selected_call_type

	local uids = M.call_uids[target_type]
	if not uids or #uids < 1 then
		M.selected_index[call_type] = 0
		return
	end

	local current_uid = M.selected_uids[target_type]

	if not current_uid then
		M.selected_uids[target_type] = uids[#uids]
		M.selected_index[call_type] = 0
		return
	end

	local current_index = nil
	for i, uid in ipairs(uids) do
		if uid == current_uid then
			current_index = i
			break
		end
	end

	if current_index then
		local prev_idx = current_index - 1
		if prev_idx < 1 then
			prev_idx = #uids
		end
		M.selected_uids[target_type] = uids[prev_idx]
		M.selected_index[target_type] = prev_idx
	end
end

return M
