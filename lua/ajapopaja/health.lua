local M = {}

-- Utility to run shell commands for dependency checking
local function cmd_exists(cmd)
	return vim.fn.executable(cmd) == 1
end

local function check_ollama_status()
	local health = vim.health or require("health")
	health.start("Ajapopaja Ollama Connectivity")

	local host = vim.g.ajapopaja_ollama_host or "http://localhost:11434"
	health.info("Configured host: " .. host)

	-- Use curl to check if Ollama is actually responding
	if cmd_exists("curl") then
		local res = vim.fn.system({ "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", host .. "/api/tags" })
		local status_code = tonumber(res)

		if status_code == 200 then
			health.ok("Ollama server is reachable and responding.")
		elseif status_code == 0 then
			health.error("Could not connect to Ollama. Is it running?", {
				"Check if 'ollama serve' is active.",
				"Ensure your firewall isn't blocking port 11434.",
			})
		else
			health.warn("Ollama returned status: " .. tostring(status_code))
		end
	else
		health.warn("curl not found; skipping network reachability test.")
	end
end

local function check_python_provider_path()
	local health = vim.health or require("health")
	health.start("Ajapopaja Provider Path")

	local host_prog = vim.g.python3_host_prog
	if not host_prog then
		health.warn("vim.g.python3_host_prog is not set.", {
			"The plugin requires a dedicated virtual environment.",
			"FIX: Run ':AjapopajaBootstrap' to create the environment and set this path automatically.",
		})
	else
		if vim.fn.executable(host_prog) == 1 then
			health.ok("python3_host_prog is set to a valid executable: " .. host_prog)
		else
			health.error("python3_host_prog is set but the executable was not found: " .. host_prog, {
				"FIX: Run ':AjapopajaBootstrap' to recreate the missing environment.",
			})
		end
	end
end

local function check_python_environment()
	local health = vim.health or require("health")
	health.start("Ajapopaja Python Environment")

	if vim.fn.has("python3") == 0 then
		health.error("Python 3 provider not found. Run :checkhealth provider")
		return
	end

	-- Check for the specific version of the plugin file to ensure it's loaded
	local rplugin_path = vim.api.nvim_get_runtime_file("rplugin/python3/AjapopajaPlugin.py", false)[1]
	if rplugin_path then
		health.ok("Found rplugin source at: " .. rplugin_path)
	else
		health.error("Ajapopaja rplugin file not found in runtimepath.")
	end
end

local function check_filesystem()
	local health = vim.health or require("health")
	health.start("Ajapopaja Filesystem")

	-- Check Prompts Directory
	local prompts = vim.api.nvim_get_runtime_file("prompts/default.md", false)[1]
	if prompts then
		local dir = vim.fn.fnamemodify(prompts, ":h")
		if vim.uv.fs_access(dir, "R") then
			health.ok("Prompt library is readable: " .. dir)
		else
			health.error("Prompt directory is not readable: " .. dir)
		end
	else
		health.error("Prompts directory not found. Reinstall the plugin.")
	end

	-- Check History Directory
	local history_dir = vim.fn.expand("~/.ajapopaja/history/")
	if vim.fn.isdirectory(history_dir) == 1 then
		if vim.uv.fs_access(history_dir, "W") then
			health.ok("History directory is writable: " .. history_dir)
		else
			health.error("History directory exists but is not writable: " .. history_dir)
		end
	else
		health.info("History directory does not exist yet (will be created on first use).")
	end
end

function M.can_call_rpc()
	local host_prog = vim.g.python3_host_prog
	if not host_prog or vim.fn.executable(host_prog) == 0 then
		return false, "Environment missing. Run :AjapopajaBootstrap"
	end

	-- We don't use exists(). We use a pcall to a non-destructive function.
	-- This triggers the lazy-loader. If it's in the manifest, Neovim will
	-- attempt to load it. If it's NOT in the manifest, pcall catches the error.
	local ok, _ = pcall(vim.fn.exists, "AjapopajaRpcHealth")

	-- If pcall fails or the function truly isn't in the manifest
	if not ok then
		return false, "RPC functions not registered. Run :UpdateRemotePlugins"
	end

	return true, nil
end

local function check_rpc_functions()
	local health = vim.health or require("health")
	health.start("Ajapopaja RPC Registration")

	local ready, err = M.can_call_rpc()
	if ready then
		health.ok("RPC functions are registered and executable.")
		local status, result = pcall(vim.fn.AjapopajaRpcHealth)
		if status then
			health.ok("Python RPC Bridge is responding.")
		else
			health.error("RPC Probe failed despite registration. Python host crashed.")
		end
	else
		health.warn(err)
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
	check_python_environment()
	check_python_provider_path()
	check_ollama_status()
	check_filesystem()
	check_rpc_functions()
	check_dependencies()
end

return M
