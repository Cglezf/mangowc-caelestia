pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.utils
import "scripts/logo.js" as Logo

Singleton {
    id: root

    property string osName
    property string osPrettyName
    property string osId
    property list<string> osIdLike
    property string osLogo: Qt.resolvedUrl(`${Quickshell.shellDir}/assets/logo.svg`)
    property bool isDefaultLogo: true

    property string uptime
    readonly property string user: Quickshell.env("USER")
    readonly property string wm: Quickshell.env("XDG_CURRENT_DESKTOP") || Quickshell.env("XDG_SESSION_DESKTOP")
    readonly property string shell: Quickshell.env("SHELL").split("/").pop()

    FileView {
        id: osRelease

        path: "/etc/os-release"
        onLoaded: {
            const lines = text().split("\n");

            const fd = key => lines.find(l => l.startsWith(`${key}=`))?.split("=")[1].replace(/"/g, "") ?? "";

            root.osName = fd("NAME");
            root.osPrettyName = fd("PRETTY_NAME");
            root.osId = fd("ID");
            root.osIdLike = fd("ID_LIKE").split(" ");

            // iconPath con check = true da vacío si ningún tema tiene el icono.
            // Con "image-missing" de respaldo nunca daba vacío: un LOGO que no
            // existe (cachyos, 2026-10-06) no caía nunca al logo de caelestia, y
            // el `|| "file://" + ...` de un logo configurado por ruta no corría.
            const distroLogo = fd("LOGO");
            const distroIcon = distroLogo ? Quickshell.iconPath(distroLogo, true) : "";
            const configured = Config.general.logo;
            const configIcon = configured && configured !== "caelestia" ? (Quickshell.iconPath(configured, true) || "file://" + Paths.absolutePath(configured)) : "";
            const logo = Logo.chooseLogo(configured, configIcon, distroIcon, Qt.resolvedUrl(`${Quickshell.shellDir}/assets/logo.svg`));
            root.osLogo = logo.source;
            root.isDefaultLogo = logo.isDefault;
        }
    }

    Connections {
        function onLogoChanged(): void {
            osRelease.reload();
        }

        target: Config.general
    }

    Timer {
        running: true
        repeat: true
        interval: 15000
        onTriggered: fileUptime.reload()
    }

    FileView {
        id: fileUptime

        path: "/proc/uptime"
        onLoaded: {
            const up = parseInt(text().split(" ")[0] ?? 0);

            const days = Math.floor(up / 86400);
            const hours = Math.floor((up % 86400) / 3600);
            const minutes = Math.floor((up % 3600) / 60);

            let str = "";
            if (days > 0)
                str += `${days} day${days === 1 ? "" : "s"}`;
            if (hours > 0)
                str += `${str ? ", " : ""}${hours} hour${hours === 1 ? "" : "s"}`;
            if (minutes > 0 || !str)
                str += `${str ? ", " : ""}${minutes} minute${minutes === 1 ? "" : "s"}`;
            root.uptime = str;
        }
    }
}
