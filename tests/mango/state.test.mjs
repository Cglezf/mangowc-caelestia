// Pruebas de la lógica pura de services/mango/state.js.
// Correr con: node --test tests/mango/
// Los fixtures son la salida real de `mmsg get all-monitors|all-clients`
// en la T14 (2026-10-06), con los títulos de ventana neutralizados.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");

// state.js es una librería de QML (`.pragma library`): se carga en un
// contexto aislado sin esa línea, que no es JavaScript.
function loadState() {
    const source = readFileSync(join(root, "services", "mango", "state.js"), "utf8")
        .replace(/^\.pragma library\s*$/m, "");
    const context = {};
    vm.runInNewContext(source, context);
    return context;
}

const S = loadState();
const monitors = readFileSync(join(here, "fixtures", "all-monitors.json"), "utf8");
const clients = readFileSync(join(here, "fixtures", "all-clients.json"), "utf8");

// vm devuelve objetos de otro contexto: se normalizan para deepEqual.
const plain = value => JSON.parse(JSON.stringify(value));
const calls = request => plain(S.dispatchCalls(request));

test("parseIpc descarta errores de mmsg y JSON inválido", () => {
    assert.equal(S.parseIpc('{"error":"unknown command"}'), null);
    assert.equal(S.parseIpc("not json"), null);
    assert.equal(S.parseIpc(monitors).monitors.length, 1);
});

test("el monitor activo da el tag activo y el número real de tags", () => {
    const mon = S.pickMonitor(S.parseIpc(monitors));
    assert.equal(mon.name, "eDP-1");
    assert.equal(S.activeTag(mon), 2);
    assert.equal(S.tagCount(mon), 9);
    assert.equal(S.activeTag(null), 1);
    assert.equal(S.tagCount(null), 1);
});

test("los scratchpads y las ventanas sin tag no cuentan como ventanas de un tag", () => {
    const list = S.parseIpc(clients).clients;
    const tagged = list.filter(c => S.isTagged(c)).map(c => c.id);
    assert.deepEqual(plain(tagged), [11]);
    assert.equal(S.clientTag(list[0]), 2);
});

test("la ventana proyectada lleva workspace y lastIpcObject completos", () => {
    const client = S.parseIpc(clients).clients[0];
    const top = plain(S.toToplevel(client, null));
    assert.deepEqual(top.workspace, { id: 2, name: "2" });
    assert.equal(top.address, "b");
    assert.equal(top.lastIpcObject.class, "kitty");
    assert.equal(top.lastIpcObject.toplevelId, "d825e817be1cfdbe9b5c4afc24e6daed");
    assert.deepEqual(top.lastIpcObject.at, [84, 30]);
    assert.deepEqual(top.lastIpcObject.size, [1806, 1020]);
    assert.equal(top.lastIpcObject.fullscreen, 0);
    assert.equal(S.ipcObject({ is_fullscreen: true }, 1).fullscreen, 2);
    assert.equal(S.ipcObject({ is_maximized: true }, 1).fullscreen, 1);
});

test("el monitor es un solo objeto con id 0 que sigue al estado vivo", () => {
    const source = { monitorState: null, focusedWorkspace: { id: 1 } };
    const mon = S.monitorView(source);
    assert.equal(mon.id, 0);
    assert.equal(mon.name, "");
    source.monitorState = S.pickMonitor(S.parseIpc(monitors));
    source.focusedWorkspace = { id: 2 };
    assert.equal(mon.name, "eDP-1");
    assert.equal(mon.width, 1920);
    assert.equal(mon.activeWorkspace.id, 2);
    assert.equal(mon.lastIpcObject.specialWorkspace.name, "");
});

// `mmsg watch all-monitors` capturado en la T14 (2026-10-06): una línea por
// emisión, y emite también cuando solo cambia el título de la ventana activa
// (el indicador giratorio de kitty, varias veces por segundo).
const watchLines = readFileSync(join(here, "fixtures", "watch-all-monitors.ndjson"), "utf8")
    .split("\n").filter(Boolean);

test("cada línea de mmsg watch es una instantánea completa", () => {
    assert.equal(watchLines.length, 2);
    for (const line of watchLines)
        assert.equal(S.activeTag(S.pickMonitor(S.parseIpc(line))), 2);
});

test("un cambio de título no cambia la clave del monitor; un cambio de tag sí", () => {
    const [a, b] = watchLines.map(line => S.pickMonitor(S.parseIpc(line)));
    assert.notEqual(a.active_client.title, b.active_client.title);
    assert.equal(S.monitorKey(a), S.monitorKey(b));
    const moved = { ...a, active_tags: [3] };
    assert.notEqual(S.monitorKey(a), S.monitorKey(moved));
});

// mmsg watch escribe en STDERR (mangowm de la T14, 2026-10-06). Un Process que
// solo lee stdout no recibe nada y la barra queda vacía sin ningún error.
test("cada flujo mmsg watch de Mango.qml lee también stderr", () => {
    const qml = readFileSync(join(root, "services", "Mango.qml"), "utf8");
    const streams = qml.match(/"mmsg", "watch"/g) ?? [];
    const stderrParsers = qml.match(/stderr: SplitParser/g) ?? [];
    assert.equal(streams.length, 2);
    assert.equal(stderrParsers.length, streams.length);
});

test("el nombre del tag es su número, para que Workspace.qml muestre el dígito", () => {
    const ws = plain(S.toWorkspace({ index: 4, client_count: 2 }, null, []));
    assert.equal(ws.id, 4);
    assert.equal(ws.name, "4");
    assert.equal(ws.lastIpcObject.windows, 2);
});

test("cambio de tag absoluto y relativo", () => {
    assert.deepEqual(calls("workspace 3"), [["view,3"]]);
    assert.deepEqual(calls("workspace r+1"), [["viewtoright"]]);
    assert.deepEqual(calls("workspace r-2"), [["viewtoleft"], ["viewtoleft"]]);
    assert.deepEqual(calls("workspace special"), []);
});

test("el selector address: apunta al cliente con un argumento client,<id> aparte", () => {
    assert.deepEqual(calls("movetoworkspace 4,address:0xb"), [["tag,4", "client,11"]]);
    assert.deepEqual(calls("killwindow address:0xb"), [["killclient", "client,11"]]);
    assert.deepEqual(calls("togglefloating address:0xb"), [["togglefloating", "client,11"]]);
    assert.deepEqual(calls("pin address:0xb"), [["toggleglobal", "client,11"]]);
});

test("la dirección expuesta vuelve al mismo cliente tal como la escribe Buttons.qml", () => {
    for (const id of [3, 10, 11, 375]) {
        const address = S.clientAddress({ id });
        assert.deepEqual(calls(`killwindow address:0x${address}`), [["killclient", `client,${id}`]]);
    }
});

test("sin selector, las órdenes actúan sobre la ventana enfocada", () => {
    assert.deepEqual(calls("togglefloating"), [["togglefloating"]]);
    assert.deepEqual(calls("fullscreen"), [["togglefullscreen"]]);
    assert.deepEqual(calls("cyclelayout"), [["switch_layout"]]);
    assert.deepEqual(calls("togglespecialworkspace special"), []);
    assert.deepEqual(calls("spawn kitty"), [["spawn,kitty"]]);
});

test("el grupo de indicadores no pasa del último tag real", () => {
    assert.deepEqual(plain(S.tagGroup(1, 5, 9)), { shown: 5, offset: 0 });
    assert.deepEqual(plain(S.tagGroup(7, 5, 9)), { shown: 5, offset: 4 });
    assert.deepEqual(plain(S.tagGroup(9, 5, 9)), { shown: 5, offset: 4 });
    assert.deepEqual(plain(S.tagGroup(3, 10, 9)), { shown: 9, offset: 0 });
    assert.deepEqual(plain(S.tagGroup(13, 10, 20)), { shown: 10, offset: 10 });
});

// ActiveIndicator y OccupiedBg ubican el tag en la casilla `tag - offset - 1`.
// Con el grupo limitado, el offset deja de ser múltiplo de `shown` y la
// fórmula vieja `(tag - 1) % shown` señalaba otra casilla (tag 7 -> tag 6).
test("el tag activo cae siempre dentro de las casillas visibles", () => {
    for (const count of [1, 3, 5, 9, 10]) {
        for (const shown of [1, 5, 10]) {
            for (let active = 1; active <= count; active++) {
                const { shown: visible, offset } = S.tagGroup(active, shown, count);
                const slot = active - offset - 1;
                assert.ok(slot >= 0 && slot < visible, `count=${count} shown=${shown} active=${active} slot=${slot}`);
            }
        }
    }
});
