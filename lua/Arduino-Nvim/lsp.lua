-- Path to the configuration file where board and port are saved
local config_file = ".arduino_config.lua"

-- Load configuration function - searches from current file's directory
local function load_arduino_config()
	-- Get the directory of the current buffer/file
	local current_dir = vim.fn.expand("%:p:h")
	if current_dir == "" or current_dir == "." then
		current_dir = vim.fn.getcwd()
	end

	-- Try to find config file in current directory
	local config_path = current_dir .. "/" .. config_file

	-- Get absolute path
	local abs_config_path = vim.fn.fnamemodify(config_path, ":p")

	-- Check if file exists
	if vim.fn.filereadable(abs_config_path) == 0 then
		-- Fallback defaults if config file not found
		vim.notify("Config file not found at " .. abs_config_path .. ", using defaults", vim.log.levels.WARN)
		return {
			board = "arduino:avr:uno",
			port = "/dev/ttyACM0",
		}
	end

	local config = loadfile(abs_config_path)
	if config then
		local ok, settings = pcall(config)
		if ok and settings then
			return settings
		else
			vim.notify("Error loading config file: " .. tostring(settings), vim.log.levels.ERROR)
		end
	end
	-- Fallback defaults if config loading fails
	vim.notify("Config load failed, using defaults", vim.log.levels.WARN)
	return {
		board = "arduino:avr:uno",
		port = "/dev/ttyACM0",
	}
end

-- Check or create sketch.yaml with correct fqbn and port
local function check_or_create_sketch_yaml(settings)
	local yaml_file = "sketch.yaml"
	local ino_files = vim.fn.glob("*.ino", false, true)
	if #ino_files == 0 then
		return
	end
	local board = settings.board
	local port = settings.port

	if vim.fn.filereadable(yaml_file) == 0 then
		vim.notify("sketch.yaml not found. Creating with default settings.", vim.log.levels.INFO)
		local file = io.open(yaml_file, "w")
		if file then
			file:write("fqbn: " .. board .. "\n")
			file:write("port: " .. port .. "\n")
			file:close()
		end
	else
		local current_yaml = {}
		for line in io.lines(yaml_file) do
			local key, value = line:match("(%S+):%s*(%S+)")
			if key and value then
				current_yaml[key] = value
			end
		end

		if current_yaml["default_fqbn"] ~= board or current_yaml["default_port"] ~= port then
			vim.notify("Updating fqbn or port in sketch.yaml to match config.", vim.log.levels.INFO)
			local file = io.open(yaml_file, "w")
			if file then
				file:write("default_fqbn: " .. board .. "\n")
				file:write("default_port: " .. port .. "\n")
				file:close()
			else
				vim.notify("Error: Cannot update sketch file.", vim.log.levels.ERROR)
			end
		end
	end
end

-- Helper function to find executable in PATH
local function find_executable(name)
	local path = vim.fn.exepath(name)
	if path and path ~= "" then
		return path
	end
	return nil
end

-- Set up the Arduino language server with saved configuration
local function setup_arduino_lsp()
	-- Find required executables
	local clangd_path = find_executable("clangd") or "/usr/bin/clangd"
	local arduino_cli_config = vim.fn.expand("$HOME/.arduino15/arduino-cli.yaml")

	-- Check if arduino-language-server is available
	if not find_executable("arduino-language-server") then
		vim.notify("Error: arduino-language-server not found in PATH. Please install it.", vim.log.levels.ERROR)
		return
	end

	-- Get the root directory where the LSP will start
	local root_dir = vim.fn.getcwd()

	-- Load board configuration
	local settings = load_arduino_config()
	local board = settings.board or "arduino:avr:uno"

	vim.notify("Arduino LSP: Starting with FQBN = " .. board, vim.log.levels.INFO)

	-- Use lspconfig (deprecated but still works in Neovim 0.11+)
	require("lspconfig").arduino_language_server.setup({
		cmd = {
			"arduino-language-server",
			"-cli",
			"arduino-cli",
			"-cli-config",
			arduino_cli_config,
			"-clangd",
			clangd_path,
			"-fqbn",
			board,
		},
		filetypes = { "arduino", "cpp" },
		root_dir = function(_)
			return root_dir
		end,
		handlers = {},
	})
end

return {
	setup = setup_arduino_lsp,
}
