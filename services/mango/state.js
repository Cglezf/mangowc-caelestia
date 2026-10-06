.pragma library

// Lógica pura del backend de MangoWC: proyecta el JSON de `mmsg` a la forma
// de Hyprland que espera el resto del shell, y traduce las órdenes de
// Hyprland a funciones de `mmsg dispatch`. Sin tipos de QML, para poder
// probarla con node (tests/mango/state.test.mjs).

// Órdenes de Hyprland que son una sola función de mango, sin argumentos.
const SIMPLE_FUNCS = {
    killwindow: "killclient",
    closewindow: "killclient",
    killclient: "killclient",
    togglefloating: "togglefloating",
    togglefullscreen: "togglefullscreen",
    fullscreen: "togglefullscreen",
    pin: "toggleglobal",
    cyclelayout: "switch_layout"
};

// Sin equivalente en mango: no se despachan.
const UNSUPPORTED = ["togglespecialworkspace"];

const SELECTOR = /address:0x([0-9a-fA-F]+)/;
const RELATIVE_TAG = /^r([+-])(\d+)$/;

function parseIpc(payload) {
    try {
        const data = JSON.parse(payload);
        return data && !data.error ? data : null;
    } catch (e) {
        return null;
    }
}

function pickMonitor(data) {
    const monitors = data?.monitors ?? [];
    return monitors.find(m => m.active) ?? monitors[0] ?? null;
}

// Lo que importa del monitor, sin `active_client`: `mmsg watch all-monitors`
// emite también cuando solo cambia el título de la ventana activa, y eso no
// toca nada de lo que se proyecta desde el monitor.
function monitorKey(monitor) {
    if (!monitor)
        return "";
    return JSON.stringify(monitor, (key, value) => key === "active_client" ? undefined : value);
}

function activeTag(monitor) {
    return monitor?.active_tags?.[0] ?? 1;
}

function tagCount(monitor) {
    return Math.max(1, monitor?.tags?.length ?? 0);
}

// Un scratchpad tiene `tags: []` y no pertenece a ningún tag.
function isTagged(client) {
    return !client?.is_scratchpad && (client?.tags?.length ?? 0) > 0;
}

function clientTag(client) {
    return client?.tags?.[0] ?? 0;
}

// Como en Hyprland: hexadecimal sin prefijo. Quien la usa antepone `0x`
// (Buttons.qml, Details.qml), y SELECTOR la lee de vuelta en base 16.
function clientAddress(client) {
    return (client?.id ?? 0).toString(16);
}

function ipcObject(client, tag) {
    const obj = {
        address: "0x" + clientAddress(client),
        title: client?.title ?? "",
        initialTitle: client?.title ?? "",
        initialClass: client?.appid ?? "",
        // Hyprland: 0 en mosaico, 1 maximizada, 2 pantalla completa.
        fullscreen: client?.is_fullscreen ? 2 : client?.is_maximized ? 1 : 0,
        floating: !!client?.is_floating,
        pinned: !!client?.is_global,
        xwayland: !!client?.is_xwayland,
        pid: client?.pid ?? -1,
        at: [client?.x ?? 0, client?.y ?? 0],
        size: [client?.width ?? 0, client?.height ?? 0],
        workspace: { id: tag, name: String(tag) },
        // Lo usa `grim -T` para capturar la ventana (popouts/ActiveWindow.qml).
        toplevelId: client?.foreign_toplevel_id ?? ""
    };
    obj["class"] = client?.appid ?? "";
    return obj;
}

function toToplevel(client, monitor) {
    const tag = clientTag(client);
    return {
        address: clientAddress(client),
        title: client?.title ?? "",
        appId: client?.appid ?? "",
        wayland: null,
        monitor: monitor,
        workspace: { id: tag, name: String(tag) },
        lastIpcObject: ipcObject(client, tag)
    };
}

// El nombre es el número: Workspace.qml muestra `ws.name[0]` si no coincide
// con el índice, y con «tag N» mostraba una «t».
function toWorkspace(tag, monitor, toplevels) {
    return {
        id: tag.index,
        name: String(tag.index),
        monitor: monitor,
        lastIpcObject: {
            windows: tag.client_count ?? 0,
            specialWorkspace: { name: "" }
        },
        toplevels: { values: toplevels }
    };
}

// El monitor enfocado: un objeto que se crea UNA vez, porque Visibilities y
// monitorFor() lo comparan por identidad, y que lee el estado vivo de <source>
// (el singleton Mango) con getters. No es un QtObject porque `id` es palabra
// reservada en QML y Brightness.qml lee `monitorFor(...).id`.
function monitorView(source) {
    return {
        id: 0,
        focused: true,
        lastIpcObject: { specialWorkspace: { name: "" } },
        get name() { return source.monitorState?.name ?? ""; },
        get x() { return source.monitorState?.x ?? 0; },
        get y() { return source.monitorState?.y ?? 0; },
        get width() { return source.monitorState?.width ?? 0; },
        get height() { return source.monitorState?.height ?? 0; },
        get activeWorkspace() { return source.focusedWorkspace; }
    };
}

// Cuántos indicadores mostrar y desde qué tag, sin pasar del último real.
function tagGroup(active, shown, count) {
    const total = Math.max(1, count);
    const visible = Math.min(Math.max(1, shown), total);
    const page = Math.floor((Math.max(1, active) - 1) / visible) * visible;
    return { shown: visible, offset: Math.min(page, total - visible) };
}

function viewCalls(arg) {
    const rel = RELATIVE_TAG.exec(arg ?? "");
    if (rel) {
        const func = rel[1] === "+" ? "viewtoright" : "viewtoleft";
        return Array.from({ length: Math.max(1, parseInt(rel[2], 10)) }, () => [func]);
    }
    const tag = parseInt(arg, 10);
    return Number.isNaN(tag) ? [] : [["view," + tag]];
}

// Devuelve los argumentos de cada `mmsg dispatch`. El cliente va como
// argumento aparte (`client,<id>` decimal), según la referencia de IPC de mango.
function dispatchCalls(request) {
    const tokens = request.trim().split(/\s+/);
    const command = tokens[0] ?? "";
    const selector = SELECTOR.exec(request);
    const target = selector ? ["client," + parseInt(selector[1], 16)] : [];
    const args = tokens.slice(1).join(",").split(",").filter(a => a && !a.startsWith("address:"));

    if (!command || UNSUPPORTED.includes(command))
        return [];
    if (SIMPLE_FUNCS[command])
        return [[SIMPLE_FUNCS[command], ...target]];
    if (command === "workspace" || command === "tag" || command === "view")
        return viewCalls(args[0]);
    if (command === "movetoworkspace") {
        const tag = parseInt(args[0], 10);
        return Number.isNaN(tag) ? [] : [["tag," + tag, ...target]];
    }
    if (command === "focusdir")
        return [["focusdir," + (args[0] ?? "")]];
    if (command.startsWith("resize"))
        return [[["resizewin", ...args].join(","), ...target]];
    if (command.startsWith("move"))
        return [[["movewin", ...args].join(","), ...target]];
    return [[[command, ...args].join(","), ...target]];
}
