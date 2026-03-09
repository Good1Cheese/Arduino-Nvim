local M = {}

-- Load dependencies
require("Arduino-Nvim.libGetter")

-- Default settings
M.board = "arduino:avr:uno"
M.port = "/dev/ttyUSB0"
M.baudrate = 115200
local config_file = ".arduino_config.lua"

-- Utility functions
local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

local function strip_ansi_codes(line)
    return line:gsub("\27%[[0-9;]*m", "")
end

local function split_string_by_newlines(input)
    local result = {}
    for line in input:gmatch("[^\r\n]+") do
        table.insert(result, line)
    end
    return result
end

-- Configuration functions
function M.save_config()
    local file = io.open(config_file, "w")
    if file then
        file:write("return {\n")
        file:write(string.format("  board = %q,\n", M.board))
        file:write(string.format("  port = %q,\n", M.port))
        file:write(string.format("  baudrate = %q,\n", M.baudrate))
        file:write("}\n")
        file:close()
    else
        vim.notify("Error: Cannot write to config file.", vim.log.levels.ERROR)
    end
end

function M.load_or_create_config()
    if vim.fn.filereadable(config_file) == 0 then
        local file = io.open(config_file, "w")
        if file then
            file:write("local M = {}\n")
            file:write("M.board = '" .. M.board .. "'\n")
            file:write("M.port = '" .. M.port .. "'\n")
            file:write("M.baudrate =" .. M.baudrate .. "\n")
            file:write("return M\n")
            file:close()
        end
    else
        local config = loadfile(config_file)
        if config then
            local ok, settings = pcall(config)
            if ok and settings then
                M.board = settings.board or M.board
                M.port = settings.port or M.port
                M.baudrate = settings.baudrate or M.baudrate
            end
        end
    end
end

M.load_or_create_config()

-- UI functions
function M.status()
    local buf, win, opts = M.create_floating_cli_monitor()
    local data = string.format("Board: %s\nPort: %s\nBaudrate: %s", M.board, M.port, M.baudrate)
    M.append_to_buffer({ data }, buf, win, opts)
end

function M.create_floating_cli_monitor()
    local width = vim.o.columns
    local initial_height = 5
    local buf = vim.api.nvim_create_buf(false, true)
    local opts = {
        relative = "editor",
        width = width,
        height = initial_height,
        row = vim.o.lines - initial_height - 2,
        col = 0,
        style = "minimal",
        border = "rounded",
    }
    local win = vim.api.nvim_open_win(buf, true, opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "<cmd>lua vim.api.nvim_win_close(" .. win .. ", false)<CR>",
        { noremap = true, silent = true })
    return buf, win, opts
end

local function adjust_window_height(win, buf, opts)
    local line_count = vim.api.nvim_buf_line_count(buf)
    local new_height = math.min(line_count, vim.o.lines - 2)
    opts.height = new_height
    opts.row = vim.o.lines - new_height - 2
    vim.api.nvim_win_set_config(win, opts)
end

function M.append_to_buffer(lines, buf, win, opts)
    if type(lines) == "string" then
        lines = { lines }
    end
    local processed_lines = {}
    for _, line in ipairs(lines) do
        local split_lines = split_string_by_newlines(line)
        vim.list_extend(processed_lines, split_lines)
    end
    local cleaned_lines = vim.tbl_map(strip_ansi_codes, processed_lines)
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, cleaned_lines)
    adjust_window_height(win, buf, opts)
end

-- Settings functions
function M.set_com(port)
    M.port = trim(port)
    vim.notify("Port set to: " .. port)
    M.save_config()
end

function M.set_board(board)
    M.board = trim(board)
    vim.notify("Board set to: " .. board)
    M.save_config()
end

function M.set_baudrate(baudrate)
    M.baudrate = trim(baudrate)
    vim.notify("Baud rate set to: " .. baudrate)
    M.save_config()
end

-- Helper functions
local function check_arduino_cli()
    if vim.fn.exepath("arduino-cli") == "" then
        vim.notify("Error: arduino-cli not found in PATH. Please install it first.", vim.log.levels.ERROR)
        return false
    end
    return true
end

-- Compile and upload functions
function M.check()
    if not check_arduino_cli() then
        return
    end

    local buf, win, opts = M.create_floating_cli_monitor()
    local cmd = "arduino-cli compile --fqbn " .. M.board .. " " .. vim.fn.expand("%:p:h")

    vim.fn.jobstart(cmd, {
        stdout_buffered = false,
        on_stdout = function(_, data)
            if data then
                M.append_to_buffer(data, buf, win, opts)
            end
        end,
        on_stderr = function(_, data)
            if data then
                local error_lines = {}
                for _, line in ipairs(data) do
                    local cleaned_line = strip_ansi_codes(line)
                    if cleaned_line:match("%S") then
                        table.insert(error_lines, "Error: " .. cleaned_line)
                    end
                end
                if #error_lines > 0 then
                    M.append_to_buffer(error_lines, buf, win, opts)
                end
            end
        end,
        on_exit = function(_, exit_code)
            if exit_code == 0 then
                M.append_to_buffer({ "--- Code checked successfully. ---" }, buf, win, opts)
            else
                M.append_to_buffer({ "--- Code check failed. ---" }, buf, win, opts)
            end
        end,
    })
end

function M.upload()
    if not check_arduino_cli() then
        return
    end

    local buf, win, opts = M.create_floating_cli_monitor()
    local compile_cmd = "arduino-cli compile --fqbn " .. M.board .. " " .. vim.fn.expand("%:p:h")
    local upload_cmd = "arduino-cli upload -p "
        .. M.port
        .. " --fqbn "
        .. M.board
        .. " --verify "
        .. vim.fn.expand("%:p:h")

    local function start_upload()
        vim.fn.jobstart(upload_cmd, {
            stdout_buffered = false,
            on_stdout = function(_, data)
                if data then
                    M.append_to_buffer(data, buf, win, opts)
                end
            end,
            on_stderr = function(_, data)
                if data and #data > 0 and data[1]:match("%S") then
                    M.append_to_buffer(
                        vim.tbl_map(function(line)
                            return "Error: " .. line
                        end, data),
                        buf,
                        win,
                        opts
                    )
                end
            end,
            on_exit = function(_, exit_code)
                if exit_code == 0 then
                    M.append_to_buffer({ "--- Upload Complete ---" }, buf, win, opts)
                else
                    M.append_to_buffer({ "--- Upload Failed ---" }, buf, win, opts)
                end
            end,
        })
    end

    vim.fn.jobstart(compile_cmd, {
        stdout_buffered = false,
        on_stdout = function(_, data)
            if data then
                M.append_to_buffer(data, buf, win, opts)
            end
        end,
        on_stderr = function(_, data)
            if data and #data > 0 and data[1]:match("%S") then
                M.append_to_buffer(
                    vim.tbl_map(function(line)
                        return "Error: " .. line
                    end, data),
                    buf,
                    win,
                    opts
                )
            end
        end,
        on_exit = function(_, exit_code)
            if exit_code == 0 then
                M.append_to_buffer({ "--- Compilation Complete, Starting Upload ---" }, buf, win, opts)
                start_upload()
            else
                M.append_to_buffer({ "--- Compilation Failed ---" }, buf, win, opts)
            end
        end,
    })
end

-- Board and port selection
function M.select_board_gui(callback)
    if not check_arduino_cli() then
        return
    end

    local handle = io.popen("arduino-cli board listall --format json")
    if not handle then
        vim.notify("Error: Failed to execute arduino-cli board listall", vim.log.levels.ERROR)
        return
    end
    local result = handle:read("*a")
    handle:close()

    local ok, data = pcall(vim.json.decode, result)
    if not ok then
        vim.notify("Error parsing JSON from arduino-cli: " .. tostring(data), vim.log.levels.ERROR)
        return
    end

    local boards = {}
    if ok and data and data.boards then
        for _, board in ipairs(data.boards) do
            local board_name = board.name or "Unknown Board"
            local fqbn = board.fqbn
            if fqbn then
                table.insert(boards, {
                    display = board_name,
                    fqbn = fqbn,
                    ordinal = board_name,
                })
            end
        end
    end

    if #boards == 0 then
        print("No Arduino boards found in the list.")
        return
    end

    require("telescope.pickers")
        .new({}, {
            prompt_title = "Select Arduino Board",
            finder = require("telescope.finders").new_table({
                results = boards,
                entry_maker = function(entry)
                    return {
                        value = entry.fqbn,
                        display = entry.display,
                        ordinal = entry.ordinal,
                    }
                end,
            }),
            sorter = require("telescope.config").values.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, map)
                local actions = require("telescope.actions")
                local action_state = require("telescope.actions.state")

                local function on_select()
                    local selection = action_state.get_selected_entry()
                    if selection then
                        M.set_board(selection.value)
                        actions.close(prompt_bufnr)
                        if callback then
                            callback()
                        end
                    end
                end

                map("i", "<CR>", on_select)
                map("n", "<CR>", on_select)
                return true
            end,
        })
        :find()
end

function M.select_port_gui()
    if not check_arduino_cli() then
        return
    end

    local handle = io.popen("arduino-cli board list")
    if not handle then
        vim.notify("Error: Failed to execute arduino-cli board list", vim.log.levels.ERROR)
        return
    end
    local result = handle:read("*a")
    handle:close()

    local ports = {}
    for line in result:gmatch("[^\r\n]+") do
        if line:match("^/dev/tty") or line:match("^/dev/cu") or line:match("^COM") then
            table.insert(ports, line:match("^(%S+)"))
        end
    end

    if #ports == 0 then
        vim.notify("No connected COM ports found.", vim.log.levels.ERROR)
        return
    end

    require("telescope.pickers")
        .new({}, {
            prompt_title = "Select Arduino Port",
            finder = require("telescope.finders").new_table({ results = ports }),
            sorter = require("telescope.config").values.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, map)
                map("i", "<CR>", function()
                    local selection = require("telescope.actions.state").get_selected_entry()
                    if selection then
                        M.set_com(selection[1])
                    end
                    require("telescope.actions").close(prompt_bufnr)
                end)
                return true
            end,
        })
        :find()
end

function M.InoList()
    if not check_arduino_cli() then
        return
    end

    local buf, win, opts = M.create_floating_cli_monitor()
    local handle = io.popen("arduino-cli board list")
    if not handle then
        vim.notify("Error: Failed to execute arduino-cli board list", vim.log.levels.ERROR)
        return
    end
    local result = handle:read("*a")
    handle:close()
    M.append_to_buffer({ result }, buf, win, opts)
end

function M.gui()
    M.select_board_gui(function()
        local handle = io.popen("arduino-cli board list")
        if handle then
            local result = handle:read("*a")
            handle:close()
            if result:match("^/dev/tty") or result:match("^COM") then
                M.select_port_gui()
            else
                vim.notify("No Arduino boards connected. Skipping port selection.", vim.log.levels.INFO)
            end
        else
            vim.notify("Failed to check for connected boards.", vim.log.levels.WARN)
        end
    end)
end

-- Serial monitor
function M.monitor()
    if not check_arduino_cli() then
        return
    end

    local buf = vim.api.nvim_create_buf(false, true)
    local win_width = math.floor(vim.o.columns * 0.8)
    local win_height = math.floor(vim.o.lines * 0.8)
    local win_opts = {
        relative = "editor",
        width = win_width,
        height = win_height,
        row = math.floor((vim.o.lines - win_height) / 2),
        col = math.floor((vim.o.columns - win_width) / 2),
        style = "minimal",
        border = "rounded",
    }
    local win = vim.api.nvim_open_win(buf, true, win_opts)

    local config_info = {
        "Arduino Serial Monitor",
        "======================",
        "Board: " .. M.board,
        "Port: " .. M.port,
        "",
        "Getting monitor configuration...",
    }
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, config_info)

    local describe_cmd = "arduino-cli monitor -p " .. M.port .. " --describe"
    vim.fn.jobstart(describe_cmd, {
        stdout_buffered = false,
        on_stdout = function(_, data)
            if data then
                local filtered_lines = {}
                for _, line in ipairs(data) do
                    if line:match("%S") and not line:match("%[32m") and not line:match("%[0m") then
                        table.insert(filtered_lines, line)
                    end
                end
                if #filtered_lines > 0 then
                    vim.api.nvim_buf_set_lines(buf, -1, -1, false, filtered_lines)
                end
            end
        end,
        on_exit = function()
            vim.api.nvim_buf_set_lines(buf, -1, -1, false,
                { "", "Starting monitor...", "Press CTRL-C or Esc to exit.", "" })

            local serial_command = string.format("arduino-cli monitor -p %s -b %s", M.port, M.board)
            local term_buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_win_set_buf(win, term_buf)

            vim.fn.termopen(serial_command, {
                cwd = vim.fn.expand("%:p:h"),
                on_exit = function(_, exit_code)
                    if exit_code ~= 0 and vim.api.nvim_buf_is_valid(term_buf) then
                        vim.api.nvim_buf_set_lines(term_buf, -1, -1, false,
                            { "", "Monitor exited with code: " .. exit_code })
                    end
                end,
            })

            vim.api.nvim_buf_set_keymap(term_buf, "t", "<C-c>", "<C-\\><C-n>:bd!<CR>", { noremap = true, silent = true })
            vim.api.nvim_buf_set_keymap(term_buf, "n", "<C-c>", ":bd!<CR>", { noremap = true, silent = true })
            vim.api.nvim_buf_set_keymap(term_buf, "t", "<Esc>", "<C-\\><C-n>:bd!<CR>", { noremap = true, silent = true })
            vim.api.nvim_buf_set_keymap(term_buf, "n", "<Esc>", ":bd!<CR>", { noremap = true, silent = true })

            vim.cmd("startinsert")
        end,
    })

    vim.api.nvim_buf_set_keymap(buf, "t", "<C-c>", "<C-\\><C-n>:bd!<CR>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, "n", "<C-c>", ":bd!<CR>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, "t", "<Esc>", "<C-\\><C-n>:bd!<CR>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":bd!<CR>", { noremap = true, silent = true })
end

-- User commands
vim.api.nvim_create_user_command("InoSelectBoard", function()
    M.select_board_gui()
end, {})

vim.api.nvim_create_user_command("InoSelectPort", function()
    M.select_port_gui()
end, {})

vim.api.nvim_create_user_command("InoCheck", function()
    M.check()
end, {})

vim.api.nvim_create_user_command("InoGUI", function()
    M.gui()
end, {})

vim.api.nvim_create_user_command("InoMonitor", function()
    M.monitor()
end, {})

vim.api.nvim_create_user_command("InoSetBaud", function(opts)
    M.set_baudrate(opts.args)
end, { nargs = 1 })

vim.api.nvim_create_user_command("InoUpload", function()
    M.upload()
end, {})

vim.api.nvim_create_user_command("InoUploadSlow", function()
    M.baudrate = "1200"
    vim.notify("Trying upload with 1200 baud rate...", vim.log.levels.INFO)
    M.upload()
end, {})

vim.api.nvim_create_user_command("InoUploadReset", function()
    local buf, win, opts = M.create_floating_cli_monitor()
    M.append_to_buffer({ "--- Attempting upload with manual reset ---" }, buf, win, opts)

    local reset_cmd = "stty -f " .. M.port .. " 1200"
    M.append_to_buffer({ "Resetting board..." }, buf, win, opts)
    os.execute(reset_cmd)

    vim.defer_fn(function()
        local upload_cmd = "arduino-cli upload -p " .. M.port .. " --fqbn " .. M.board .. " " .. vim.fn.expand("%:p:h")
        M.append_to_buffer({ "Starting upload after reset..." }, buf, win, opts)

        vim.fn.jobstart(upload_cmd, {
            stdout_buffered = false,
            on_stdout = function(_, data)
                if data then
                    M.append_to_buffer(data, buf, win, opts)
                end
            end,
            on_stderr = function(_, data)
                if data and #data > 0 and data[1]:match("%S") then
                    M.append_to_buffer(
                        vim.tbl_map(function(line)
                            return "Error: " .. line
                        end, data),
                        buf,
                        win,
                        opts
                    )
                end
            end,
            on_exit = function(_, exit_code)
                if exit_code == 0 then
                    M.append_to_buffer({ "--- Upload with reset Complete ---" }, buf, win, opts)
                else
                    M.append_to_buffer({ "--- Upload with reset Failed ---" }, buf, win, opts)
                end
            end,
        })
    end, 2000)
end, {})

vim.api.nvim_create_user_command("InoStatus", function()
    M.status()
end, {})

vim.api.nvim_create_user_command("InoList", function()
    M.InoList()
end, {})

return M
