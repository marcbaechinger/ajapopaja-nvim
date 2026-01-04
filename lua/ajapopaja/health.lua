local M = {}

local function check_python_provider()
	local health = vim.health or require("health")
	health.start("Ajapopaja Python Provider")

	if vim.fn.has("python3") == 0 then
		health.error("Python 3 provider not found. Run :checkhealth provider")
	else
		health.ok("Python 3 provider is detected.")
	end
end

local function check_rpc_functions()
	local health = vim.health or require("health")
	health.start("Ajapopaja RPC Registration")

	local has_py3 = vim.fn.has("python3") == 1
	if not has_py3 then
		health.error("Python 3 host is not available.")
		return
	end

	local status, result = pcall(vim.fn.AjapopajaRpcHealth)

	if status then
		health.ok("Python RPC Bridge is active and responding.")
		if type(result) == "string" and result:sub(1, 1) == "{" then
			health.ok("Backend returned valid history schema.")
		end
	else
		health.error("RPC Probe failed.", {
			"Error details: " .. tostring(result),
			"Check if you have run :UpdateRemotePlugins",
			"Ensure your Python dependencies (like 'pynvim') are installed in the correct provider env.",
		})
	end
end

local function check_dependencies()
	local health = vim.health or require("health")
	health.start("Ajapopaja Dependencies")

	local has_ts, _ = pcall(require, "nvim-treesitter")
	if has_ts then
		health.ok("nvim-treesitter is installed.")
	else
		health.warn("nvim-treesitter not found. Syntax highlighting in previews might be limited.")
	end
end

function M.check()
	check_python_provider()
	check_rpc_functions()
	check_dependencies()
end

return M
