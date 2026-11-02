hl.env("HYPRCURSOR_SIZE", "24")
-- Qt apps read their colours, style and icons from qt6ct (mooi writes its palette there, D91).
-- It was only in ~/.config/environment.d, which systemd services get but Hyprland's apps do not.
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
