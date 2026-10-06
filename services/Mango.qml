pragma Singleton

import qs.components.misc
import Quickshell
import Quickshell.Io
import Quickshell.Wayland._ToplevelManagement
import QtQuick
import "mango/state.js" as MangoState

// Backend de MangoWC con la forma de Hyprland que espera el shell (Hypr.qml
// lo reexporta). El estado sale SOLO de dos flujos `mmsg watch`; nada se
// actualiza de forma optimista, así que la barra no puede mostrar un tag
// distinto del real. La lógica pura vive en mango/state.js, con su prueba.
Singleton {
    id: root

    // Último JSON de `mmsg watch all-monitors` (monitor activo) y de `all-clients`.
    property var monitorState: null
    property var clientState: []

    readonly property int activeTagNumber: MangoState.activeTag(monitorState)
    readonly property int activeWsId: activeTagNumber
    readonly property int tagCount: MangoState.tagCount(monitorState)
    readonly property string focusedOutput: monitorState?.name ?? ""
    readonly property string currentLayout: monitorState?.layout_symbol ?? ""
    readonly property var availableLayouts: []

    // Ventanas con tag; los scratchpads (`tags: []`) quedan fuera.
    readonly property var toplevelList: (clientState ?? []).filter(c => MangoState.isTagged(c)).map(c => MangoState.toToplevel(c, root.focusedMonitor))
    readonly property var toplevels: ({
            values: toplevelList
        })

    readonly property var parsedTags: (monitorState?.tags ?? []).map(tag => MangoState.toWorkspace(tag, root.focusedMonitor, root.toplevelsOnTag(tag.index)))
    readonly property var workspaces: ({
            values: parsedTags
        })

    readonly property var outputsList: monitorState ? [focusedMonitor] : []
    readonly property var monitors: ({
            values: outputsList
        })

    // La ventana enfocada puede ser un scratchpad visible: se busca entre todas.
    readonly property var focusedClientData: (clientState ?? []).find(c => c.is_focused) ?? null
    readonly property var activeToplevel: focusedClient

    readonly property QtObject focusedClient: QtObject {
        readonly property var wayland: ToplevelManager.activeToplevel
        readonly property string title: root.focusedClientData?.title ?? ""
        readonly property string appId: root.focusedClientData?.appid ?? ""
        readonly property string address: MangoState.clientAddress(root.focusedClientData)
        readonly property var workspace: root.focusedWorkspace
        readonly property var monitor: root.focusedMonitor
        readonly property var lastIpcObject: MangoState.ipcObject(root.focusedClientData, MangoState.clientTag(root.focusedClientData) || root.activeTagNumber)
    }

    // Se crea una vez y no depende de nada: misma identidad en cada lectura
    // (Visibilities, monitorFor). Sus getters leen el estado vivo de root.
    readonly property var focusedMonitor: MangoState.monitorView(root)

    readonly property var focusedWorkspace: MangoState.toWorkspace({
        index: activeTagNumber,
        client_count: (monitorState?.tags ?? []).find(t => t.index === activeTagNumber)?.client_count ?? 0
    }, focusedMonitor, toplevelsOnTag(activeTagNumber))

    // Teclado: mango solo da el nombre largo de la distribución; se mantiene
    // el stub para no cambiar la barra ni la pantalla de bloqueo.
    readonly property var keyboard: null
    readonly property bool capsLock: false
    readonly property bool numLock: false
    readonly property string defaultKbLayout: ""
    readonly property string kbLayoutFull: ""
    readonly property string kbLayout: ""
    readonly property bool hadKeyboard: false
    readonly property var kbMap: new Map()

    // Extras placeholder (removed for MangoWC)
    readonly property var extras: ({
            devices: {
                keyboards: []
            },
            options: {},
            message: function () {},
            batchMessage: function () {},
            applyOptions: function () {},
            refreshOptions: function () {},
            refreshDevices: function () {}
        })

    readonly property var options: ({})
    readonly property var devices: extras.devices

    signal configReloaded

    function toplevelsOnTag(tag: int): var {
        return toplevelList.filter(t => t.workspace.id === tag);
    }

    function tagGroup(active: int, shown: int, count: int): var {
        return MangoState.tagGroup(active, shown, count);
    }

    function dispatch(request: string): void {
        const calls = MangoState.dispatchCalls(request);
        if (calls.length === 0)
            console.warn("MangoWC: no equivalent for", request);
        for (const args of calls)
            Quickshell.execDetached(["mmsg", "dispatch", ...args]);
    }

    function monitorFor(screen): var {
        // Un solo monitor: se devuelve el mismo objeto que focusedMonitor.
        return focusedMonitor;
    }

    function reloadDynamicConfs(): void {
        // MangoWC doesn't have dynamic config reloading via IPC
        console.log("MangoWC: Dynamic config reload not supported");
    }

    // Toggle compositor blur by editing mango_core.conf and hot-reloading.
    // Mango blur is GLOBAL: `blur` frosts windows AND is the master toggle that
    // `blur_layer` (layer surfaces = bars/drawers) piggybacks on. So enabling
    // compositor blur here turns on BOTH (blur_layer does nothing without blur).
    // Disabling sets both off, leaving crisp apps + QML-transparent panels.
    function setCompositorBlur(enabled: bool): void {
        // Mango blur (mangowm.github.io/docs/visuals/effects):
        //   blur=1            master toggle (frosts windows)
        //   blur_layer=1      layer surfaces (bars/drawers/panels) — needs blur=1
        //   blur_optimized=0  standard setup — composite against real content
        //                     (blur_optimized=1 caches wallpaper as blur bg, cheaper)
        // Disabling sets all off, leaving crisp apps + QML-transparent panels.
        const value = enabled ? "1" : "0";
        const optimized = enabled ? "0" : "1";
        const conf = `${Quickshell.env("HOME")}/.config/mango/mango_core.conf`;
        const script = `f="${conf}"; ` +
            `for kv in "blur=${value}" "blur_layer=${value}" "blur_optimized=${optimized}"; do ` +
            `k="\${kv%%=*}"; v="\${kv#*=}"; ` +
            `if grep -q "^$k=" "$f"; then ` +
            `sed -i -E "s/^$k=[0-9]+/$k=$v/" "$f"; ` +
            `else printf "$k=%s\\n" "$v" >> "$f"; fi; ` +
            `done; ` +
            `mmsg dispatch reload_config`;
        Quickshell.execDetached(["sh", "-c", script]);
        console.log(`MangoWC: Compositor blur ${enabled ? "enabled" : "disabled"}`);
    }

    // `mmsg watch` emite una instantánea JSON por línea en cada cambio.
    Process {
        id: monitorStream

        command: ["mmsg", "watch", "all-monitors"]
        running: true

        stdout: SplitParser {
            onRead: data => {
                const monitor = MangoState.pickMonitor(MangoState.parseIpc(data));
                if (monitor)
                    root.monitorState = monitor;
            }
        }
    }

    Process {
        id: clientStream

        command: ["mmsg", "watch", "all-clients"]
        running: true

        stdout: SplitParser {
            onRead: data => {
                const parsed = MangoState.parseIpc(data);
                if (parsed?.clients)
                    root.clientState = parsed.clients;
            }
        }
    }

    // Los flujos mueren con el compositor y no tienen latido: se relanzan.
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            if (!monitorStream.running)
                monitorStream.running = true;
            if (!clientStream.running)
                clientStream.running = true;
        }
    }

    IpcHandler {
        target: "mango"

        function refreshDevices(): void {
            // No-op for MangoWC
        }
    }

    CustomShortcut {
        name: "refreshDevices"
        description: "Reload devices"
        onPressed: {} // No-op for MangoWC
        onReleased: {} // No-op for MangoWC
    }
}
