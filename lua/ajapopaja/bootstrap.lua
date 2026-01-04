local M = {}

function M.bootstrap()
	local plugin_path = vim.api.nvim_get_runtime_file("rplugin/python3/AjapopajaPlugin.py", false)[1]
	local root = vim.fn.fnamemodify(plugin_path, ":h:h:h")
	local venv_path = root .. "/.venv"
	local python_bin = venv_path .. "/bin/python3"

	vim.notify("Ajapopaja: Provisioning virtual environment...", vim.log.levels.INFO)

	-- Using -m venv and pip install
	local cmd = string.format(
		"python3 -m venv %s && %s -m pip install pynvim aiohttp",
		vim.fn.shellescape(venv_path),
		vim.fn.shellescape(python_bin)
	)

	vim.fn.jobstart(cmd, {
		on_exit = function(_, exit_code)
			if exit_code == 0 then
				-- CRITICAL: Update the global variable in the current session
				vim.g.python3_host_prog = python_bin

				vim.notify("Ajapopaja: Environment ready. Syncing RPC manifest...", vim.log.levels.INFO)

				-- Use schedule to ensure the g:variable is propagated before the shell call
				vim.schedule(function()
					-- We use pcall because UpdateRemotePlugins might still complain
					-- if the internal provider state is corrupted
					local success, err = pcall(vim.cmd, "UpdateRemotePlugins")
					if success then
						vim.notify("Ajapopaja: Bootstrap complete! Please restart Neovim.", vim.log.levels.WARN)
					else
						vim.notify("Ajapopaja: RPC sync failed: " .. tostring(err), vim.log.levels.ERROR)
						print("Manual fix: Restart Neovim and run :UpdateRemotePlugins manually.")
					end
				end)
			else
				vim.notify("Ajapopaja: Bootstrap failed (Exit " .. exit_code .. ")", vim.log.levels.ERROR)
			end
		end,
	})
end

return M
