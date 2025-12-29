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

	-- History UI State
	current_view = "transform", -- "transform" or "review"
	current_index = 1,
	history_cache = { transform = {}, review = {} },

	-- System State
	is_loading = false,
	current_model = "qwen3-coder:30b",
}

return M
