.pragma library

// Default feed list (first run / "restore defaults") and the refresh presets
// the settings page cycles through. Shared by the reader panel and its page.

var FEEDS = [
    "https://hnrss.org/frontpage",
    "https://lobste.rs/rss",
    "https://www.phoronix.com/rss.php",
    "https://wiki.archlinux.org/index.php?title=Special:RecentChanges&feed=atom",
    "https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/portada",
    "https://e00-elmundo.uecdn.es/elmundo/rss/portada.xml",
    "https://www.abc.es/rss/2.0/portada.xml"
];

var REFRESH_PRESETS_MS = [300000, 600000, 1800000, 3600000];
