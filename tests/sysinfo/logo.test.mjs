// Pruebas de utils/scripts/logo.js y de cómo lo usa utils/SysInfo.qml.
// Correr con: node --test tests/
//
// Caso (2026-10-06, T14 con CachyOS): /etc/os-release declara LOGO=cachyos y
// ningún tema de iconos lo tiene. SysInfo.qml lo pedía con "image-missing" de
// respaldo, así que nunca recibía vacío y nunca caía al logo de caelestia.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");

function loadLogo() {
    const source = readFileSync(join(root, "utils", "scripts", "logo.js"), "utf8")
        .replace(/^\.pragma library\s*$/m, "");
    const context = {};
    vm.runInNewContext(source, context);
    return context;
}

const L = loadLogo();
const DEFAULT = "file:///etc/xdg/quickshell/caelestia/assets/logo.svg";
const plain = value => JSON.parse(JSON.stringify(value));
const choose = (...args) => plain(L.chooseLogo(...args));

test("sin configurar y sin icono de la distribución, el logo de caelestia", () => {
    assert.deepEqual(choose("", "", "", DEFAULT), { source: DEFAULT, isDefault: true });
});

test("sin configurar y con icono de la distribución, el de la distribución", () => {
    assert.deepEqual(choose("", "", "/usr/share/icons/x/cachyos.svg", DEFAULT),
        { source: "/usr/share/icons/x/cachyos.svg", isDefault: false });
});

test("\"caelestia\" gana aunque la distribución tenga icono", () => {
    assert.deepEqual(choose("caelestia", "", "/usr/share/icons/x/cachyos.svg", DEFAULT),
        { source: DEFAULT, isDefault: true });
});

test("un logo configurado gana sobre el de la distribución", () => {
    assert.deepEqual(choose("~/logo.svg", "file:///home/u/logo.svg", "/x/cachyos.svg", DEFAULT),
        { source: "file:///home/u/logo.svg", isDefault: false });
});

test("la decisión es completa: volver a vacío sin icono regresa al defecto", () => {
    // La versión anterior no tocaba nada en ese caso y dejaba isDefault en false.
    const first = choose("~/logo.svg", "file:///home/u/logo.svg", "", DEFAULT);
    const back = choose("", "", "", DEFAULT);
    assert.equal(first.isDefault, false);
    assert.deepEqual(back, { source: DEFAULT, isDefault: true });
});

// La guarda de la clase: un iconPath con respaldo nunca devuelve vacío, así que
// cualquier `|| algo` detrás no se ejecuta nunca.
test("SysInfo.qml pide los logos con check, sin respaldo \"image-missing\"", () => {
    const qml = readFileSync(join(root, "utils", "SysInfo.qml"), "utf8");
    assert.ok(!/iconPath\([^)]*"image-missing"\)/.test(qml), "ningún iconPath con image-missing de respaldo");
    assert.ok(qml.includes("Logo.chooseLogo("), "decide con chooseLogo");
    assert.equal((qml.match(/iconPath\([^)]*, true\)/g) ?? []).length, 2, "dos iconPath con check: distribución y configurado");
});
