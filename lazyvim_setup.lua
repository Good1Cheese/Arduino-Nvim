-- Minimal Arduino-Nvim setup for LazyVim
return {
    "yuukiflow/Arduino-Nvim",
    dir = vim.fn.stdpath("config") .. "/lua/Arduino-Nvim",
    dependencies = {
        "nvim-telescope/telescope.nvim",
        "neovim/nvim-lspconfig",
    },
    ft = "arduino",
    config = function()
        -- Set up LSP for Arduino files
        require("Arduino-Nvim.lsp").setup()

        -- Auto-load Arduino plugin for .ino files
        vim.api.nvim_create_autocmd("FileType", {
            pattern = "arduino",
            callback = function()
                require("Arduino-Nvim")
            end,
        })
    end,
}
