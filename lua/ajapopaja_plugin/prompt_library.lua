local M = {}

--- Get the root path of the ajapopaja_plugin
-- @return string|nil The root path of the plugin or nil if not found
local function get_plugin_path()
	local paths = vim.api.nvim_get_runtime_file("lua/ajapopaja_plugin/history.lua", false)
	if #paths > 0 then
		return vim.fn.fnamemodify(paths[1], ":h:h:h")
	end
	return nil
end

local prompt_root = get_plugin_path() .. "/prompts"

--- Parse a markdown file containing prompts into a list of prompt objects
--- Each prompt is defined by a top-level heading (# Title) followed by content
--- @param filepath string Path to the markdown file containing prompts
--- @return table List of prompt objects with 'title' and 'content' fields
--- @return table Error prompt if file cannot be opened
function M.parse_markdown_prompts(filepath)
	local prompts = {}
	local file = io.open(filepath, "r")

	if not file then
		return {}, { { title = "Error", content = "Prompts file not found." } }
	end

	local current_prompt = nil

	for line in file:lines() do
		local title = line:match("^#%s+(.+)$")

		if title then
			if current_prompt then
				table.insert(prompts, current_prompt)
			end
			current_prompt = {
				title = title,
				content = "",
			}
		elseif current_prompt then
			if current_prompt.content == "" then
				current_prompt.content = line
			else
				current_prompt.content = current_prompt.content .. "\n" .. line
			end
		end
	end

	if current_prompt then
		current_prompt.content = vim.trim(current_prompt.content)
		table.insert(prompts, current_prompt)
	end

	file:close()
	return prompts, {}
end

--- Gets the file path for a given filetype
-- @param filetype string The type of file to get the path for
-- @return string The full file path including the root directory and .md extension
local function get_file_path(filetype)
	return prompt_root .. "/" .. filetype .. ".md"
end

--- Checks if a file can be read from the specified path
-- @param path_to_file string The path to the file to check
-- @return boolean true if the file can be opened for reading, false otherwise
local function can_read_from_file(path_to_file)
	local file = io.open(path_to_file, "r")
	if file then
		io.close(file)
		return true
	else
		return false
	end
end

local cached_prompts = {}

--- Get prompts for a given filetype, falling back to default if needed
--- @param filetype string? The filetype to get prompts for, or nil for default
--- @return table The prompts for the specified filetype
function M.get_prompts(filetype)
	local target_file_type = filetype or "default"
	local requested_file_type = target_file_type
	if not cached_prompts[requested_file_type] then
		local file_path = get_file_path(requested_file_type)
		if not can_read_from_file(file_path) then
			target_file_type = "default"
			file_path = get_file_path(target_file_type)
		end
		if cached_prompts[target_file_type] then
			cached_prompts[requested_file_type] = cached_prompts[target_file_type]
		else
			cached_prompts[requested_file_type] = M.parse_markdown_prompts(file_path)
			if target_file_type ~= requested_file_type then
				cached_prompts[target_file_type] = cached_prompts[requested_file_type]
			end
		end
	end
	return cached_prompts[target_file_type]
end

return M
