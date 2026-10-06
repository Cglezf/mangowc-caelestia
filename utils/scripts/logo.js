.pragma library

// Qué logo del sistema mostrar (barra, pantalla de bloqueo, panel). Pura, para
// probarla con node (tests/sysinfo/logo.test.mjs).
//
//   configured  general.logo de shell.json: "", "caelestia", o un icono o ruta
//   configIcon  lo que resolvió SysInfo.qml para `configured` (vacío si no aplica)
//   distroIcon  el icono del LOGO de /etc/os-release, YA comprobado: vacío si
//               ningún tema de iconos lo tiene
//   defaultUrl  el logo de caelestia
//
// Devuelve siempre la decisión completa. La versión anterior no tocaba nada
// cuando no había icono, y un cambio de configuración que caía al defecto
// dejaba isDefault con el valor de antes.
function chooseLogo(configured, configIcon, distroIcon, defaultUrl) {
    if (configured === "caelestia" || (!configured && !distroIcon))
        return { source: defaultUrl, isDefault: true };
    if (configured)
        return { source: configIcon, isDefault: false };
    return { source: distroIcon, isDefault: false };
}
