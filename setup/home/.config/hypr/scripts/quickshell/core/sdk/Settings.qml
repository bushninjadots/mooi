pragma Singleton
import QtQuick
import "."

// ═══════════════════════════════════════════════════════════════════════════
// Settings — the GLOBAL settings store (the shell's settings.json).
//
// A singleton SettingsStore bound to ~/.config/hypr/settings.json. It holds the
// CORE settings + the shell's plugin metadata (plugins.<id>.enabled/.config).
// Each PLUGIN owns a separate SettingsStore for its own settings file, so a
// plugin's state never mixes with the core (the plugin is self-contained).
// ═══════════════════════════════════════════════════════════════════════════

SettingsStore { }
