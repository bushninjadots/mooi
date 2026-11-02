import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../../core"
import "../../core" as Notifications

// ═══════════════════════════════════════════════════════════════════════════
// shell · notifications — service + popups
//
// Self-contained notifications layer (ported from Main.qml + the popup):
//   - NotificationServer ingests notifications and keeps the live objects.
//   - historyModel keeps every notification (consumed by the future
//     notification center, e.g. the battery popup).
//   - The popup window shows the active ones (capped by the personalization
//     API: notifications.maxVisible).
// Shell.qml mounts this component once.
// ═══════════════════════════════════════════════════════════════════════════
Item {
    id: root

    property bool isStartup: false
    property real uiScale: 1.0

    // History for panels (newest first).
    readonly property alias historyModel: globalNotificationHistory
    // Live QObjects by uid (actions/reply need the original object).
    property var liveNotifs: ({})
    property int _popupCounter: 0

    ListModel { id: globalNotificationHistory }
    ListModel { id: activePopupsModel }

    function removePopup(uid) {
        for (let i = 0; i < activePopupsModel.count; i++) {
            if (activePopupsModel.get(i).uid === uid) {
                activePopupsModel.remove(i);
                break;
            }
        }
        delete root.liveNotifs[uid];
    }

    NotificationServer {
        id: globalNotificationServer
        bodySupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: (n) => {
            n.tracked = true;

            let extractedActions = [];
            if (n.actions) {
                for (let i = 0; i < n.actions.length; i++) {
                    extractedActions.push({
                        "id": n.actions[i].identifier || "",
                        "text": n.actions[i].text || n.actions[i].name || "Action"
                    });
                }
            }

            root._popupCounter++;
            let currentUid = root._popupCounter;

            // Store the live object so the popup can interact with it.
            let live = root.liveNotifs;
            live[currentUid] = n;
            root.liveNotifs = live;

            let notifData = {
                "appName":     n.appName  !== "" ? n.appName  : "System",
                "summary":     n.summary  !== "" ? n.summary  : "No Title",
                "body":        n.body     !== "" ? n.body     : "",
                "iconPath":    n.appIcon  !== "" ? n.appIcon  : "",
                "actionsJson": JSON.stringify(extractedActions),
                "uid":         currentUid
            };

            // Always add to the history list.
            globalNotificationHistory.insert(0, notifData);

            // Only trigger the visual popup past the startup phase.
            if (!root.isStartup) {
                activePopupsModel.append(notifData);
                popups.storeNotif(currentUid, n);

                let cap = Notifications.maxVisible(Config.rawSettings.notifications);
                if (cap > 0) {
                    while (activePopupsModel.count > cap) activePopupsModel.remove(0);
                }
            }
        }
    }

    NotificationPopups {
        id: popups
        popupModel: activePopupsModel
        uiScale: root.uiScale
        onRemoveRequested: (uid) => root.removePopup(uid)
    }
}
