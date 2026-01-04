-- Copyright (c) 2026 Marc Baechinger
-- Licensed under the MIT License.

local M = {

	-- History UI State
	selected_call_type = "transform",
	call_types = {},
	selected_index = {},
	selected_uids = {}, -- stores the currently selected uid for each call type
	call_uids = {}, -- stores the uids of all history items for each call type
	-- System State
	is_loading = false,
	available_models = {},
	is_fetching_models = false,
	current_model = "qwen3-coder:30b",
}

local function update_history_uids(call_type, init)
	local uids = vim.fn.AjapopajaGetHistoryUids(call_type)
	if uids then
		M.call_uids[call_type] = uids
		if init and #uids > 0 then
			M.selected_uids[call_type] = uids[#uids]
		end
	end
end

--- Translates the selected uid to the corresponding index in the
--- list of history items for a give call type
-- @param call_type string The type of call to set the index for
local function set_call_index_by_uid(call_type)
	local selected_uid = M.selected_uids[call_type]
	if selected_uid then
		for i, uid in ipairs(M.call_uids[call_type]) do
			if selected_uid == uid then
				M.selected_index[call_type] = i
				return
			end
		end
	end
end

local sync_callbacks = {}

function M.add_sync_callback(callback)
	for _, existing_callback in ipairs(sync_callbacks) do
		if existing_callback == callback then
			return
		end
	end
	table.insert(sync_callbacks, callback)
end

function M.remove_sync_callback(callback)
	for i, existing_callback in ipairs(sync_callbacks) do
		if existing_callback == callback then
			table.remove(sync_callbacks, i)
			return
		end
	end
end

local function call_all_sync_callbacks()
	for _, callback in ipairs(sync_callbacks) do
		callback()
	end
end

function M.sync_history(update_index)
	local uids = M.call_uids[M.selected_call_type]
	local init = update_index or not uids or #uids == 0
	if not M.call_types or #M.call_types == 0 then
		M.call_types = vim.fn.AjapopajaGetCallTypes()
	end
	for _, call_type in ipairs(M.call_types) do
		update_history_uids(call_type, init)
		if init then
			M.selected_index[call_type] = #M.call_uids[call_type]
		end
		set_call_index_by_uid(call_type)
	end
	call_all_sync_callbacks()
end

function M.select_call_type(call_type)
	local uids = M.call_uids[call_type]
	if not uids then
		return
	end
	M.selected_call_type = call_type
	if not M.selected_uids[call_type] then
		M.selected_uids[call_type] = uids[#uids]
		M.selected_index[call_type] = #uids
	end
end

function M.get_selected_index(call_type)
	local target_call_type = call_type or M.selected_call_type
	return M.selected_index[target_call_type] or 1
end

function M.next(call_type)
	local target_type = call_type or M.selected_call_type

	local uids = M.call_uids[target_type]
	if not uids or #uids < 1 then
		M.selected_index[call_type] = 1
		return
	end

	local current_uid = M.selected_uids[target_type]

	if not current_uid then
		M.selected_uids[target_type] = uids[1]
		M.selected_index[call_type] = 1
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
