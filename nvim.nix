{ pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    # lsp, форматтеры и утилиты, видимые только neovim
    extraPackages = with pkgs; [
      # go
      go
      gopls
      gotools # goimports
      # c
      clang-tools # clangd + clang-format
      # nix
      nil
      nixfmt
      # поиск и буфер обмена
      ripgrep
      fd
      wl-clipboard
    ];

    plugins = with pkgs.vimPlugins; [
      mini-nvim # mini.base16: тема из текущей схемы `theme`
      (nvim-treesitter.withPlugins (p: [
        p.go
        p.gomod
        p.gosum
        p.gowork
        p.c
        p.cpp
        p.make
        p.nix
        p.lua
        p.bash
        p.json
        p.yaml
        p.toml
        p.markdown
        p.markdown_inline
        p.vim
        p.vimdoc
        p.query
      ]))
      nvim-lspconfig
      blink-cmp
      friendly-snippets
      conform-nvim
      telescope-nvim
      telescope-fzf-native-nvim
      plenary-nvim
      nvim-web-devicons
      oil-nvim
      lualine-nvim
      gitsigns-nvim
      which-key-nvim
      nvim-autopairs
      indent-blankline-nvim
      fidget-nvim
    ];

    extraLuaConfig = ''
      -- ================= основа =================
      vim.g.mapleader = " "
      vim.g.maplocalleader = " "

      local o = vim.opt
      o.number = true
      o.relativenumber = true
      o.cursorline = true
      o.signcolumn = "yes"
      o.termguicolors = true
      o.mouse = "a"
      o.clipboard = "unnamedplus"
      o.ignorecase = true
      o.smartcase = true
      o.splitright = true
      o.splitbelow = true
      o.scrolloff = 8
      o.undofile = true
      o.updatetime = 250
      o.timeoutlen = 400
      o.expandtab = true
      o.shiftwidth = 2
      o.tabstop = 2
      o.smartindent = true
      o.wrap = false
      o.showmode = false
      o.laststatus = 3
      o.list = true
      o.listchars = { tab = "  ", trail = "·", nbsp = "␣" }
      o.fillchars = { eob = " " }

      -- go: настоящие табы, c: отступ 4
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "go",
        callback = function()
          vim.opt_local.expandtab = false
          vim.opt_local.tabstop = 4
          vim.opt_local.shiftwidth = 4
        end,
      })
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "c", "cpp" },
        callback = function()
          vim.opt_local.tabstop = 4
          vim.opt_local.shiftwidth = 4
        end,
      })

      -- подсветить скопированное
      vim.api.nvim_create_autocmd("TextYankPost", {
        callback = function() vim.hl.on_yank({ timeout = 150 }) end,
      })

      -- ================= тема =================
      -- цвета берутся из ~/.local/state/theme/current.json (команда `theme`),
      -- `theme set ...` перекрашивает и уже открытые окна neovim
      local function mix(a, b, t)
        local function rgb(h) return tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16) end
        local r1, g1, b1 = rgb(a)
        local r2, g2, b2 = rgb(b)
        local function f(x, y) return math.floor(x + (y - x) * t + 0.5) end
        return string.format("#%02x%02x%02x", f(r1, r2), f(g1, g2), f(b1, b2))
      end

      function ApplyTheme()
        local path = vim.fn.expand("~/.local/state/theme/current.json")
        local ok, t = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(path), "\n")) end)
        if not ok or type(t) ~= "table" then
          vim.cmd.colorscheme("habamax")
          return
        end
        local c = t.c -- c[1] = color0 ... c[16] = color15
        require("mini.base16").setup({
          palette = {
            base00 = t.bg,
            base01 = mix(t.bg, t.fg, 0.07),
            base02 = mix(t.bg, t.fg, 0.16),
            base03 = mix(t.bg, t.fg, 0.4),
            base04 = mix(t.bg, t.fg, 0.65),
            base05 = t.fg,
            base06 = t.fg,
            base07 = t.fg,
            base08 = c[10], -- красный
            base09 = mix(c[10], c[12], 0.5), -- оранжевый
            base0A = c[12], -- жёлтый
            base0B = c[11], -- зелёный
            base0C = c[15], -- голубой
            base0D = c[13], -- синий
            base0E = c[14], -- фиолетовый
            base0F = mix(c[10], t.bg, 0.3),
          },
        })
        vim.g.colors_name = "theme-" .. (t.name or "custom")
        if _G.LualineOpts then pcall(function() require("lualine").setup(_G.LualineOpts) end) end
      end
      ApplyTheme()

      -- ================= treesitter =================
      -- подсветка для всех языков, у которых есть парсер
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args) pcall(vim.treesitter.start, args.buf) end,
      })

      -- ================= автодополнение =================
      require("blink.cmp").setup({
        keymap = {
          preset = "enter",
          ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
          ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
        },
        appearance = { nerd_font_variant = "mono" },
        completion = {
          menu = { border = "rounded" },
          documentation = { auto_show = true, auto_show_delay_ms = 200, window = { border = "rounded" } },
          ghost_text = { enabled = true },
        },
        signature = { enabled = true, window = { border = "rounded" } },
        sources = { default = { "lsp", "path", "snippets", "buffer" } },
        fuzzy = { implementation = "prefer_rust" },
      })

      -- ================= lsp =================
      vim.lsp.config("*", { capabilities = require("blink.cmp").get_lsp_capabilities() })
      vim.lsp.config("gopls", {
        settings = {
          gopls = {
            staticcheck = true,
            usePlaceholders = true,
            analyses = { unusedparams = true },
            hints = { parameterNames = true, assignVariableTypes = true },
          },
        },
      })
      vim.lsp.config("clangd", {
        cmd = { "clangd", "--background-index", "--clang-tidy", "--header-insertion=never" },
      })
      vim.lsp.config("nil_ls", {
        settings = { ["nil"] = { formatting = { command = { "nixfmt" } } } },
      })
      vim.lsp.enable({ "gopls", "clangd", "nil_ls" })

      vim.diagnostic.config({
        virtual_text = { prefix = "●", spacing = 2 },
        severity_sort = true,
        float = { border = "rounded" },
      })

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local function m(keys, fn, desc)
            vim.keymap.set("n", keys, fn, { buffer = args.buf, desc = desc })
          end
          m("gd", vim.lsp.buf.definition, "go to definition")
          m("gD", vim.lsp.buf.declaration, "go to declaration")
          m("gr", vim.lsp.buf.references, "references")
          m("gi", vim.lsp.buf.implementation, "implementations")
          m("K", vim.lsp.buf.hover, "hover docs")
          m("<leader>rn", vim.lsp.buf.rename, "rename")
          m("<leader>ca", vim.lsp.buf.code_action, "code actions")
          m("<leader>e", vim.diagnostic.open_float, "line diagnostics")
          m("<leader>ih", function()
            vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = args.buf }), { bufnr = args.buf })
          end, "toggle inlay hints")
        end,
      })

      -- ================= форматирование при сохранении =================
      require("conform").setup({
        formatters_by_ft = {
          go = { "goimports", "gofmt" },
          c = { "clang_format" },
          cpp = { "clang_format" },
          nix = { "nixfmt" },
        },
        format_on_save = { timeout_ms = 1000, lsp_format = "fallback" },
      })

      -- ================= поиск =================
      local telescope = require("telescope")
      telescope.setup({
        defaults = {
          prompt_prefix = "   ",
          selection_caret = " ",
          sorting_strategy = "ascending",
          layout_config = { prompt_position = "top" },
        },
      })
      pcall(telescope.load_extension, "fzf")

      local tb = require("telescope.builtin")
      local map = vim.keymap.set
      map("n", "<leader>ff", tb.find_files, { desc = "find files" })
      map("n", "<leader>fg", tb.live_grep, { desc = "live grep" })
      map("n", "<leader>fb", tb.buffers, { desc = "buffers" })
      map("n", "<leader>fh", tb.help_tags, { desc = "help" })
      map("n", "<leader>fd", tb.diagnostics, { desc = "diagnostics" })
      map("n", "<leader>fs", tb.lsp_document_symbols, { desc = "document symbols" })
      map("n", "<leader><leader>", tb.find_files, { desc = "find files" })

      -- ================= остальное =================
      require("oil").setup({ view_options = { show_hidden = true } })
      map("n", "-", "<cmd>Oil<cr>", { desc = "open parent directory" })

      -- "auto" подстраивается под текущие цвета
      _G.LualineOpts = {
        options = {
          theme = "auto",
          globalstatus = true,
          component_separators = "",
          section_separators = { left = "", right = "" },
        },
      }
      require("lualine").setup(_G.LualineOpts)

      require("gitsigns").setup()
      require("which-key").setup()
      require("nvim-autopairs").setup()
      require("ibl").setup({ indent = { char = "│" }, scope = { enabled = true } })
      require("fidget").setup()

      map("n", "<leader>w", "<cmd>w<cr>", { desc = "save" })
      map("n", "<leader>q", "<cmd>q<cr>", { desc = "quit" })
      map("n", "<Esc>", "<cmd>nohlsearch<cr>")
      map("n", "<C-h>", "<C-w>h")
      map("n", "<C-j>", "<C-w>j")
      map("n", "<C-k>", "<C-w>k")
      map("n", "<C-l>", "<C-w>l")
      map("v", "J", ":m '>+1<cr>gv=gv", { desc = "move line down" })
      map("v", "K", ":m '<-2<cr>gv=gv", { desc = "move line up" })
      map("v", "<", "<gv")
      map("v", ">", ">gv")
    '';
  };
}
