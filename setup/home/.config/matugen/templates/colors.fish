# Terracotta theme for fish and fzf - rendered by matugen
# Edit ~/.config/matugen/templates/colors.fish and run `matugen theme-sync`

# Syntax highlighting (terracotta palette)
set -g fish_color_normal f1dedc
set -g fish_color_command e88556
set -g fish_color_keyword ca8c52
set -g fish_color_quote a3c699
set -g fish_color_redirection 8ab2c5
set -g fish_color_end ca8c52
set -g fish_color_error ff6b6b
set -g fish_color_param f1dedc
set -g fish_color_comment 949699
set -g fish_color_selection --background=84403d
set -g fish_color_operator a2ceda
set -g fish_color_escape b6ccb8
set -g fish_color_autosuggestion 949699
set -g fish_color_cancel ff6b6b
set -g fish_color_search_match --background=84403d
set -g fish_color_valid_path --underline

# Completion pager.
set -g fish_pager_color_progress 949699
set -g fish_pager_color_prefix e88556
set -g fish_pager_color_completion f1dedc
set -g fish_pager_color_description 949699
set -g fish_pager_color_selected_background --background=84403d

# fzf takes the same palette, so Ctrl-R and Ctrl-T match the terminal they open
# in. Appended to whatever options are already set rather than replacing them.
set -gx FZF_DEFAULT_OPTS "$FZF_DEFAULT_OPTS \
--color=fg:#f1dedc,bg:-1,hl:#e88556 \
--color=fg+:#f1dedc,bg+:#84403d,hl+:#e88556 \
--color=info:#ca8c52,prompt:#e88556,pointer:#ca8c52 \
--color=marker:#ca8c52,spinner:#949699,header:#8ab2c5 \
--color=border:#534341"
