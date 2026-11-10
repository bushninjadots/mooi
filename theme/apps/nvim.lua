-- written by mooi (theme/apps/nvim.lua, `mooi apps-sync`): Neovim in the wallpaper's colours. Worn by
-- plugin/mooi-theme.lua while Settings → Theme & colour → Neovim is on; `:colorscheme mooi` wears it by hand.
vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then vim.cmd("syntax reset") end
vim.o.termguicolors = true
vim.g.colors_name = "mooi"
local c = {
    bg = "{{colors.surface.default.hex}}", bg2 = "{{colors.surface_container.default.hex}}",
    bg3 = "{{colors.surface_container_high.default.hex}}", fg = "{{colors.on_surface.default.hex}}",
    dim = "{{colors.on_surface_variant.default.hex}}", line = "{{colors.outline_variant.default.hex}}",
    primary = "{{colors.primary.default.hex}}", secondary = "{{colors.secondary.default.hex}}",
    tertiary = "{{colors.tertiary.default.hex}}", error = "{{colors.error.default.hex}}",
    pc = "{{colors.primary_container.default.hex}}", onpc = "{{colors.on_primary_container.default.hex}}",
}
local function hl(group, opts) vim.api.nvim_set_hl(0, group, opts) end
hl("Normal", { fg = c.fg, bg = c.bg }); hl("NormalFloat", { fg = c.fg, bg = c.bg2 }); hl("FloatBorder", { fg = c.line, bg = c.bg2 })
hl("Comment", { fg = c.dim, italic = true }); hl("String", { fg = c.tertiary }); hl("Character", { fg = c.tertiary })
hl("Number", { fg = c.secondary }); hl("Boolean", { fg = c.secondary }); hl("Constant", { fg = c.secondary })
hl("Identifier", { fg = c.fg }); hl("Function", { fg = c.primary, bold = true }); hl("Statement", { fg = c.primary })
hl("Keyword", { fg = c.primary, italic = true }); hl("Type", { fg = c.secondary }); hl("Special", { fg = c.tertiary })
hl("PreProc", { fg = c.secondary }); hl("Operator", { fg = c.dim }); hl("Delimiter", { fg = c.dim })
hl("LineNr", { fg = c.line }); hl("CursorLineNr", { fg = c.primary, bold = true }); hl("CursorLine", { bg = c.bg2 })
hl("Visual", { bg = c.pc, fg = c.onpc }); hl("Search", { bg = c.pc, fg = c.onpc }); hl("IncSearch", { bg = c.primary, fg = c.bg })
hl("Pmenu", { fg = c.fg, bg = c.bg2 }); hl("PmenuSel", { fg = c.onpc, bg = c.pc }); hl("PmenuThumb", { bg = c.line })
hl("StatusLine", { fg = c.fg, bg = c.bg3 }); hl("StatusLineNC", { fg = c.dim, bg = c.bg2 }); hl("WinSeparator", { fg = c.line })
hl("SignColumn", { bg = c.bg }); hl("Folded", { fg = c.dim, bg = c.bg2 }); hl("MatchParen", { fg = c.primary, bold = true })
hl("DiagnosticError", { fg = c.error }); hl("DiagnosticWarn", { fg = c.tertiary }); hl("DiagnosticInfo", { fg = c.secondary })
hl("DiagnosticHint", { fg = c.dim }); hl("DiffAdd", { fg = c.primary }); hl("DiffDelete", { fg = c.error }); hl("DiffChange", { fg = c.tertiary })
for from, to in pairs({ ["@function"] = "Function", ["@keyword"] = "Keyword", ["@string"] = "String", ["@type"] = "Type",
                        ["@variable"] = "Identifier", ["@constant"] = "Constant", ["@comment"] = "Comment", ["@number"] = "Number" }) do
    hl(from, { link = to })
end
