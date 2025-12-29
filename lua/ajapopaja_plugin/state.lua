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
	current_view = "transform", -- "transform" or "review"
	current_index = 1,
	history_cache = { transform = {}, review = {} },
	-- System State
	is_loading = false,
	current_model = "qwen3-coder:30b",
}

return M
