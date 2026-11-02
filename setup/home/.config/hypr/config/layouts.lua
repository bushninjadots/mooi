-- special_scale_factor was dropped in Hyprland 0.57 (hyprctl deprecated-config);
-- windows already fill the special workspace and the option no longer does anything.
hl.config({
    dwindle = {
        force_split = 2,
        preserve_split = true,
    },
    master = {
        new_on_top = 0,
        mfact = 0.5,
        orientation = "right",
    },
})
