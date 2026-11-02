-- The on_created_empty workspace rule is deprecated in Hyprland 0.57 (hyprctl deprecated-config);
-- the replacement is the workspace.created event plus the workspace's .is_empty field.
-- Same effect as the old rule: kitty opens on the empty special workspace.
hl.on("workspace.created", function(ws)
    if ws.addressable_name == "special:special" and ws.is_empty then
        hl.exec_cmd("kitty", { workspace = "special:special" })
    end
end)
