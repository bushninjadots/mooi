# Sysmon

A configurable floating system monitor for the equisdots desktop: a small card
showing live **CPU / RAM / temperature** bars, placed in any corner — plus a
lightweight **CPU/RAM bar island** (`bar/Sysmon.qml`, the core "Resources"
slot).

Demonstrates the plugin architecture end-to-end:

- **Host adapter** (`host/Sysmon.qml`) — publishes an overlay surface through
  the SDK **surface manager** (`surfaces` descriptor, only while the floating
  monitor is enabled) and reads live stats via the injected handle
  (`host.stats` = SysData) and the palette (`host.colors`).
- **Bar module** (`bar/Sysmon.qml`, manifest `provides.bar.modules.sysmon`) —
  the core `sysmon` slot resolves it; it reads the core `SysData` singleton
  and opens the floating monitor on click.
- **Settings page** (`settings/SysmonPage.qml`) — the Plugins group's dynamic
  `p_sysmon` page, built with the stable public kit (`qs.ui.bar.edit`).
- **Manifest** — `toggle: sysmon.enabled`, `scope: sysmon`, `api.requires`,
  `compat.host`, `defaultEnabled: true` (installed by default; the floating
  monitor stays opt-in through `panelEnabled`).

## Settings schema (`settings.json` → `sysmon`)

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` (defaultEnabled) | master switch (manifest toggle) |
| `panelEnabled` | `false` | show the floating monitor card |
| `position` | `"top-right"` | `top-left` \| `top-right` \| `bottom-left` \| `bottom-right` |
| `uiScale` | `1.0` | card scale (0.6–2.0) |
| `opacity` | `0.85` | panel background opacity |
| `showCpu` / `showRam` / `showTemp` | `true` | which metrics to draw |

## Layout

```
sysmon/
├── plugin.json
├── bar/Sysmon.qml
├── host/Sysmon.qml
├── settings/SysmonPage.qml
└── README.md
```
