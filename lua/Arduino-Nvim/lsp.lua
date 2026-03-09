-- Path to the configuration file where board and port are saved
local config_file = ".arduino_config.lua"

-- Load configuration function - searches from current file's directory
local function load_arduino_config()
    local current_dir = vim.fn.expand("%:p:h")
    if current_dir == "" or current_dir == "." then
        current_dir = vim.fn.getcwd()
    end

    local config_path = current_dir .. "/" .. config_file
    local abs_config_path = vim.fn.fnamemodify(config_path, ":p")

    if vim.fn.filereadable(abs_config_path) == 0 then
        return { board = "arduino:avr:uno", port = "/dev/ttyACM0" }
    end

    local config = loadfile(abs_config_path)
    if config then
        local ok, settings = pcall(config)
        if ok and settings then
            return settings
        end
    end

    return { board = "arduino:avr:uno", port = "/dev/ttyACM0" }
end

-- Check or create sketch.yaml with correct fqbn and port
local function check_or_create_sketch_yaml(settings)
    local yaml_file = "sketch.yaml"
    local ino_files = vim.fn.glob("*.ino", false, true)
    if #ino_files == 0 then return end

    local board = settings.board
    local port = settings.port

    if vim.fn.filereadable(yaml_file) == 0 then
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
            if key and value then current_yaml[key] = value end
        end

        if current_yaml["default_fqbn"] ~= board or current_yaml["default_port"] ~= port then
            local file = io.open(yaml_file, "w")
            if file then
                file:write("default_fqbn: " .. board .. "\n")
                file:write("default_port: " .. port .. "\n")
                file:close()
            end
        end
    end
end

-- Helper function to find executable in PATH
local function find_executable(name)
    local path = vim.fn.exepath(name)
    return (path and path ~= "") and path or nil
end

-- Set up the Arduino language server with saved configuration
local function setup_arduino_lsp()
    local clangd_path = find_executable("clangd") or "/usr/bin/clangd"
    local arduino_cli_config = vim.fn.expand("$HOME/.arduino15/arduino-cli.yaml")

    if not find_executable("arduino-language-server") then
        vim.notify("Error: arduino-language-server not found in PATH. Please install it.", vim.log.levels.ERROR)
        return
    end

    local settings = load_arduino_config()
    local board = settings.board or "arduino:avr:uno"

    check_or_create_sketch_yaml(settings)

    -- 🔑 Register config with CALLBACK-style root_dir (Neovim 0.11+)
    vim.lsp.config("arduino_language_server", {
        cmd = {
            "arduino-language-server",
            "-cli", "arduino-cli",
            "-cli-config", arduino_cli_config,
            "-clangd", clangd_path,
            "-fqbn", board,
        },
        filetypes = { "arduino", "cpp" },

        -- 🔑 CRITICAL: root_dir as function with callback
        root_dir = function(bufnr, on_dir)
            local fname = vim.api.nvim_buf_get_name(bufnr)
            if fname and fname ~= "" then
                on_dir(vim.fn.fnamemodify(fname, ":p:h"))
            else
                on_dir(vim.fn.getcwd())
            end
        end,

        -- 🔑 CRITICAL: Limit capabilities to avoid crashes
        capabilities = {
            textDocument = {
                semanticTokens = vim.NIL,
            },
            workspace = {
                semanticTokens = vim.NIL,
            },
        },
    })

    -- Enable the server
    vim.lsp.enable("arduino_language_server")
end

return { setup = setup_arduino_lsp }
