#!/usr/bin/env bash
# Instalador de mangowc-caelestia: MangoWM + caelestia-shell + caelestia CLI
# (port de Ackerman-00) con sus dependencias, y la config de mango para que
# arranque el shell y cargue sus binds.
#
#   Arch y derivadas (CachyOS, EndeavourOS, Manjaro…): paru primero (de los
#     repositorios o del AUR), las dependencias del AUR con él y luego
#     packaging/arch/PKGBUILD.
#   Debian y derivadas (PikaOS, Debian sid…): apt para lo que hay en los
#     repositorios; libcava, app2unit, el CLI (venv) y las fuentes que faltan se
#     compilan o descargan; el shell se compila con CMake. Todo lo que instala
#     fuera de apt queda anotado en /usr/local/share/mangowc-caelestia para
#     poder quitarlo con --uninstall.
#
# Uso: ./install.sh [-y] [--no-config | --only-config | --uninstall]
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# mango ignora XDG_CONFIG_HOME: lee $HOME/.config/mango/config.conf y resuelve
# ahí los `source = ./...` (src/config/load.c de mango).
MANGO_DIR="$HOME/.config/mango"
STATE_DIR=/usr/local/share/mangowc-caelestia
CLI_VENV=/opt/mangowc-caelestia/cli
FONT_DIR=/usr/local/share/fonts/mangowc-caelestia

# Versiones fijadas de lo que se baja fuera de los gestores de paquetes.
LIBCAVA_VER=1.0.0
LIBCAVA_SHA=437df0a29e52e555357a06238f4c5cbe6d51b5dd4225700cb7adbb19d8bb9474
APP2UNIT_VER=1.4.4
APP2UNIT_SHA=03c1206097a1596c0e49dc48b82d0b602cc9f38cc498542fe27ef613a050d6fc
NERDFONTS_VER=3.4.0

YES=0
MODE=all

msg() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==> AVISO:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m==> ERROR:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
    cat <<EOF
Uso: $0 [opciones]

  -y, --yes        no preguntar al gestor de paquetes
  --no-config      instalar paquetes, sin tocar ~/.config/mango
  --only-config    solo la config de mango (caelestia.conf + source en config.conf)
  --uninstall      quitar lo instalado (la config de mango se deja)
  -h, --help       esta ayuda
EOF
}

while (($#)); do
    case $1 in
        -y | --yes) YES=1 ;;
        --no-config) MODE=packages ;;
        --only-config) MODE=config ;;
        --uninstall) MODE=uninstall ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

[[ $EUID -ne 0 ]] || die "ejecútalo como tu usuario; el script usa sudo cuando hace falta"

detect_family() {
    local id
    # shellcheck disable=SC1091
    . /etc/os-release
    for id in ${ID:-} ${ID_LIKE:-}; do
        case $id in
            arch) echo arch; return ;;
            debian | ubuntu) echo debian; return ;;
        esac
    done
    die "distro no soportada (${PRETTY_NAME:-desconocida}): solo familias Arch y Debian"
}

TMP=$(mktemp -d)
SUDO_PID=""
trap '[[ -z $SUDO_PID ]] || kill "$SUDO_PID" 2>/dev/null; rm -rf "$TMP"' EXIT

# Pide la contraseña una vez y mantiene vivo el sello de sudo mientras dura el
# script: paru y makepkg -si llaman a sudo por su cuenta y, sin esto, cada
# construcción larga lo volvía a pedir.
sudo_keepalive() {
    msg "Se necesita sudo (se pide una sola vez)"
    sudo -v || die "sin sudo no se puede instalar"
    while kill -0 $$ 2>/dev/null; do
        sudo -n -v 2>/dev/null
        sleep 50
    done &
    SUDO_PID=$!
}

fetch() { # fetch URL DESTINO [SHA256]
    curl -fL --retry 3 -o "$2" "$1"
    [[ -z ${3:-} ]] || echo "$3  $2" | sha256sum -c --quiet - || die "checksum incorrecto: $1"
}

# ---------------------------------------------------------------- Arch
AUR_PKGS=(libcava app2unit python-materialyoucolor ttf-material-symbols-variable ttf-rubik-vf)

arch_install() {
    local noconfirm=()
    ((YES)) && noconfirm=(--noconfirm)

    msg "Herramientas de construcción y terminales (kitty, alacritty)"
    sudo pacman -S --needed "${noconfirm[@]}" base-devel git kitty alacritty

    if have paru; then
        msg "paru ya está instalado"
    elif pacman -Si paru >/dev/null 2>&1; then
        # CachyOS, EndeavourOS… lo traen en sus repositorios.
        msg "Instalando paru desde los repositorios"
        sudo pacman -S --needed "${noconfirm[@]}" paru
    else
        msg "Instalando paru (paru-bin, del AUR)"
        git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$TMP/paru-bin"
        (cd "$TMP/paru-bin" && makepkg -si --needed "${noconfirm[@]}")
    fi

    msg "Dependencias del AUR: ${AUR_PKGS[*]}"
    paru -S --needed "${noconfirm[@]}" "${AUR_PKGS[@]}"

    if [[ -n $(git -C "$REPO" status --porcelain) ]]; then
        warn "hay cambios sin commitear: el PKGBUILD construye solo lo commiteado"
    fi

    msg "Construyendo mangowc-caelestia-shell y mangowc-caelestia-cli (PKGBUILD)"
    # BUILDDIR/PKGDEST fuera del repo para no dejar src/, pkg/ ni .pkg.tar.* en él.
    (cd "$REPO/packaging/arch" &&
        BUILDDIR="$TMP/build" PKGDEST="$TMP/pkg" SRCDEST="$TMP/srcdest" \
            makepkg -si "${noconfirm[@]}")
}

arch_uninstall() {
    sudo pacman -Rns mangowc-caelestia-shell mangowc-caelestia-cli
}

# ---------------------------------------------------------------- Debian
DEB_BUILD=(build-essential cmake ninja-build pkgconf git curl ca-certificates xz-utils meson
    qt6-base-dev qt6-declarative-dev qt6-wayland-dev qt6-shadertools-dev
    libqalculate-dev libpipewire-0.3-dev libaubio-dev libfftw3-dev libgl-dev libwayland-dev
    libiniparser-dev libpulse-dev libasound2-dev python3-venv fontconfig)
DEB_RUNTIME=(qt6-wayland libqt6sql6-sqlite qt6-svg-plugins qt6-image-formats-plugins
    qml6-module-qtquick qml6-module-qtquick-layouts qml6-module-qtquick-controls
    qml6-module-qtquick-templates qml6-module-qtquick-effects qml6-module-qtquick-shapes
    qml6-module-qtquick-window qml6-module-qtqml-workerscript qml6-module-qtqml-models
    pipewire wireplumber network-manager lm-sensors grim slurp swappy wl-clipboard cliphist
    fuzzel gpu-screen-recorder libnotify-bin libglib2.0-bin procps util-linux libxml2-utils
    xkb-data x11-xkb-utils polkitd iproute2 dconf-cli kitty alacritty)
# Sin nada del ecosistema Hyprland: en PikaOS hyprpicker arrastra un
# libhyprutils de Debian que pisa el de la distro.
DEB_OPTIONAL=(brightnessctl ddcutil ydotool fish)

deb_installed() { [[ $(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null) == installed ]]; }
apt_candidate() { apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}'; }

debian_install() {
    local apt_y=() mango="" qs_ver qmldir p optional=()
    ((YES)) && apt_y=(-y)

    msg "Actualizando índices de apt"
    sudo apt-get update

    for p in mangowm mangowc; do
        [[ $(apt_candidate $p) != "" && $(apt_candidate $p) != "(none)" ]] && { mango=$p; break; }
    done
    [[ -n $mango ]] || die "tu distro no empaqueta mango: https://mangowm.github.io/docs/installation"

    qs_ver=$(apt_candidate quickshell)
    [[ -n $qs_ver && $qs_ver != "(none)" ]] || die "tu distro no empaqueta quickshell (hace falta >= 0.3.1)"
    dpkg --compare-versions "$qs_ver" ge 0.3.1 || die "quickshell $qs_ver es demasiado viejo (hace falta >= 0.3.1)"

    for p in "${DEB_OPTIONAL[@]}"; do
        [[ $(apt_candidate "$p") =~ ^(|\(none\))$ ]] || optional+=("$p")
    done

    local pkgs=("$mango" quickshell "${DEB_BUILD[@]}" "${DEB_RUNTIME[@]}" "${optional[@]}")

    # Si otra cosa ya da wl-copy/wl-paste (otter-clip en PikaOS, que choca con
    # wl-clipboard), se usa esa: caelestia solo necesita --type y --watch.
    if ! deb_installed wl-clipboard && command -v wl-copy >/dev/null && command -v wl-paste >/dev/null; then
        msg "wl-copy/wl-paste ya los da $(dpkg -S "$(readlink -f "$(command -v wl-copy)")" 2>/dev/null | cut -d: -f1 || echo otro paquete); no instalo wl-clipboard"
        for p in "${!pkgs[@]}"; do [[ ${pkgs[p]} != wl-clipboard ]] || unset 'pkgs[p]'; done
    fi

    # El instalador no debe desmontar el escritorio que ya tienes: si apt
    # quiere quitar algo, se para y lo dice.
    local removed
    removed=$(apt-get -s install --no-install-recommends "${pkgs[@]}" 2>/dev/null | awk '/^Remv/ {print $2}')
    if [[ -n $removed ]]; then
        warn "apt quitaría estos paquetes por conflictos:"
        printf '      %s\n' $removed >&2
        ((YES)) && die "no sigo con -y; revisa los conflictos o ejecútalo sin -y para decidir"
        local reply
        read -rp "¿Quitarlos y seguir? [s/N] " reply
        [[ $reply =~ ^[sSyY]$ ]] || die "cancelado; no se instaló nada"
    fi

    msg "Paquetes de apt ($mango, quickshell $qs_ver y dependencias)"
    sudo apt-get install "${apt_y[@]}" --no-install-recommends "${pkgs[@]}"

    sudo install -d "$STATE_DIR"

    if pkg-config --exists libcava || pkg-config --exists cava; then
        msg "libcava ya está instalado"
    else
        msg "Compilando libcava $LIBCAVA_VER (LukashonakV/cava; el paquete cava no trae la biblioteca)"
        fetch "https://github.com/LukashonakV/cava/archive/$LIBCAVA_VER.tar.gz" "$TMP/cava.tar.gz" "$LIBCAVA_SHA"
        tar -xzf "$TMP/cava.tar.gz" -C "$TMP"
        (cd "$TMP/cava-$LIBCAVA_VER" &&
            meson setup build --prefix=/usr/local -Dcava_font=false -Dbuild_target=lib >/dev/null &&
            meson compile -C build &&
            sudo meson install -C build --quiet)
        sudo cp "$TMP/cava-$LIBCAVA_VER/build/meson-logs/install-log.txt" "$STATE_DIR/libcava.manifest"
        sudo ldconfig
    fi

    if have app2unit; then
        msg "app2unit ya está instalado"
    else
        msg "Instalando app2unit $APP2UNIT_VER"
        fetch "https://github.com/Vladimir-csp/app2unit/archive/refs/tags/v$APP2UNIT_VER.tar.gz" \
            "$TMP/app2unit.tar.gz" "$APP2UNIT_SHA"
        tar -xzf "$TMP/app2unit.tar.gz" -C "$TMP"
        sudo make -C "$TMP/app2unit-$APP2UNIT_VER" install-bin prefix=/usr/local >/dev/null
        printf '/usr/local/bin/%s\n' app2unit app2unit-open app2unit-open-scope app2unit-open-service \
            app2unit-term app2unit-term-scope app2unit-term-service | sudo tee "$STATE_DIR/app2unit.manifest" >/dev/null
    fi

    debian_fonts

    msg "CLI caelestia en un venv ($CLI_VENV)"
    sudo rm -rf "$CLI_VENV"
    sudo python3 -m venv "$CLI_VENV"
    sudo "$CLI_VENV/bin/pip" install --quiet --disable-pip-version-check "$REPO/cli"
    sudo ln -sfT "$CLI_VENV/bin/caelestia" /usr/local/bin/caelestia
    sudo install -Dm644 "$REPO/cli/completions/caelestia.fish" \
        /usr/local/share/fish/vendor_completions.d/caelestia.fish

    msg "Compilando el shell (CMake)"
    qmldir=$(/usr/lib/qt6/bin/qtpaths6 --query QT_INSTALL_QML 2>/dev/null ||
        echo "/usr/lib/$(gcc -dumpmachine)/qt6/qml")
    rm -rf "$REPO/build"
    cmake -S "$REPO" -B "$REPO/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=/ \
        -DVERSION="0.0.$(git -C "$REPO" rev-list --count HEAD)" \
        -DGIT_REVISION="$(git -C "$REPO" rev-parse --short=12 HEAD)" \
        -DDISTRIBUTOR="install.sh (Debian)" \
        -DENABLE_MODULES="extras;plugin;shell" \
        -DINSTALL_LIBDIR=usr/lib/caelestia \
        -DINSTALL_QMLDIR="${qmldir#/}" \
        -DINSTALL_QSCONFDIR=etc/xdg/quickshell/caelestia
    cmake --build "$REPO/build"
    sudo cmake --install "$REPO/build"
    sudo cp "$REPO/build/install_manifest.txt" "$STATE_DIR/shell.manifest"
    sudo chmod 755 /etc/xdg/quickshell/caelestia/assets/wrap_term_launch.sh

    # El mismo lanzador que packaging/arch/caelestia-shell.
    sudo tee /usr/local/bin/caelestia-shell >/dev/null <<'EOF'
#!/bin/sh
export CAELESTIA_LIB_DIR="${CAELESTIA_LIB_DIR:-/usr/lib/caelestia}"
exec qs -c caelestia "$@"
EOF
    sudo chmod 755 /usr/local/bin/caelestia-shell

    if ! have sass; then
        warn "sin dart-sass: 'caelestia scheme' no generará el tema de Discord (lo demás funciona)"
    fi
}

debian_fonts() {
    local need=()
    fc-list -q 'Material Symbols Rounded' || need+=(material)
    fc-list -q 'Rubik' || need+=(rubik)
    fc-list -q 'CaskaydiaCove NF' || need+=(caskaydia)
    ((${#need[@]})) || { msg "Fuentes ya instaladas"; return; }

    msg "Fuentes: ${need[*]} -> $FONT_DIR"
    sudo install -d "$FONT_DIR"
    if [[ " ${need[*]} " == *" material "* ]]; then
        fetch 'https://raw.githubusercontent.com/google/material-design-icons/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf' \
            "$TMP/MaterialSymbolsRounded.ttf"
        sudo install -m644 "$TMP/MaterialSymbolsRounded.ttf" "$FONT_DIR/"
    fi
    if [[ " ${need[*]} " == *" rubik "* ]]; then
        fetch 'https://raw.githubusercontent.com/google/fonts/main/ofl/rubik/Rubik%5Bwght%5D.ttf' "$TMP/Rubik.ttf"
        fetch 'https://raw.githubusercontent.com/google/fonts/main/ofl/rubik/Rubik-Italic%5Bwght%5D.ttf' "$TMP/Rubik-Italic.ttf"
        sudo install -m644 "$TMP/Rubik.ttf" "$TMP/Rubik-Italic.ttf" "$FONT_DIR/"
    fi
    if [[ " ${need[*]} " == *" caskaydia "* ]]; then
        fetch "https://github.com/ryanoasis/nerd-fonts/releases/download/v$NERDFONTS_VER/CascadiaCode.tar.xz" \
            "$TMP/CascadiaCode.tar.xz"
        mkdir -p "$TMP/caskaydia"
        tar -xJf "$TMP/CascadiaCode.tar.xz" -C "$TMP/caskaydia" --wildcards 'CaskaydiaCoveNerdFont-*.ttf'
        sudo install -m644 "$TMP"/caskaydia/*.ttf "$FONT_DIR/"
    fi
    sudo fc-cache -f "$FONT_DIR"
}

debian_uninstall() {
    local m
    for m in "$STATE_DIR"/*.manifest; do
        [[ -e $m ]] || continue
        msg "Quitando lo anotado en $(basename "$m")"
        xargs -r -d '\n' sudo rm -f <"$m"
    done
    sudo rm -rf /usr/lib/caelestia /etc/xdg/quickshell/caelestia "$CLI_VENV" "$FONT_DIR" "$STATE_DIR"
    sudo rm -f /usr/local/bin/caelestia /usr/local/bin/caelestia-shell \
        /usr/local/share/fish/vendor_completions.d/caelestia.fish
    sudo ldconfig
    sudo fc-cache -f
    msg "Los paquetes de apt (mango, quickshell, dependencias) se quedan: quítalos con apt si quieres"
}

# ---------------------------------------------------------------- Config de mango
setup_config() {
    local conf="$MANGO_DIR/config.conf" frag="$MANGO_DIR/caelestia.conf" stamp fresh=0
    stamp=$(date +%Y%m%d-%H%M%S)
    mkdir -p "$MANGO_DIR"

    if [[ ! -e $conf ]]; then
        msg "config.conf nuevo, a partir de /etc/mango/config.conf"
        fresh=1
    fi

    if [[ -e $frag ]] && ! cmp -s "$REPO/mango/caelestia.conf" "$frag"; then
        cp "$frag" "$frag.$stamp.bak"
        warn "caelestia.conf ya existía y era distinto: copia en $frag.$stamp.bak"
    fi
    install -m644 "$REPO/mango/caelestia.conf" "$frag"

    # Arriba del todo: en mango gana el PRIMER bind que coincide, y la config por
    # defecto ya usa teclas como SUPER+Left, SUPER+n o ALT+Tab.
    if grep -sqE '^\s*source(-optional)?\s*=\s*\S*caelestia\.conf' "$conf"; then
        msg "config.conf ya carga caelestia.conf"
    elif ((fresh)); then
        { printf '# mangowc-caelestia: shell, binds y reglas (ver caelestia.conf)\nsource-optional = ./caelestia.conf\n\n'
            cat /etc/mango/config.conf 2>/dev/null || true; } >"$conf"
    else
        cp "$conf" "$conf.$stamp.bak"
        { printf '# mangowc-caelestia: shell, binds y reglas (ver caelestia.conf)\nsource-optional = ./caelestia.conf\n\n'
            cat "$conf.$stamp.bak"; } >"$conf"
        msg "config.conf carga ahora caelestia.conf (copia previa: $conf.$stamp.bak)"
    fi

    mkdir -p "$HOME/Pictures/Wallpapers"
}

# ---------------------------------------------------------------- Principal
FAMILY=$(detect_family)
msg "Familia de distro: $FAMILY"

[[ $MODE == config ]] || sudo_keepalive

case $MODE in
    uninstall)
        "${FAMILY}_uninstall"
        exit 0
        ;;
    config) ;;
    *) "${FAMILY}_install" ;;
esac

[[ $MODE == packages ]] || setup_config

cat <<EOF

Listo. Cierra la sesión y entra en "Mango" desde tu gestor de inicio de sesión
(o ejecuta 'mango' desde una TTY). El shell arranca solo (exec-once en caelestia.conf).

  Lanzador: Super+A o Super+Espacio · Terminal: Super+T · Cerrar ventana: Super+Q
  Fondos: pon imágenes en ~/Pictures/Wallpapers y pulsa Super+W
  Todos los binds: $MANGO_DIR/caelestia.conf
EOF
