#!/usr/bin/env bash
# Install, update or remove the Neon KDE Widgets for the current user.
# Run ./install.sh --help for usage.

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

WIDGETS=(clock monitor atmos player)
declare -A DESC=(
    [clock]="Neon Clock: digital clock and date"
    [monitor]="Neon Monitor: CPU, RAM, temperatures, GPU, network, storage"
    [atmos]="Neon Atmos: weather and forecast"
    [player]="Neon Player: now playing and media controls"
)

if [ -t 1 ]; then
    B=$'\e[1m' DIM=$'\e[2m' C=$'\e[36m' G=$'\e[32m' Y=$'\e[33m' RD=$'\e[31m' R=$'\e[0m'
else
    B="" DIM="" C="" G="" Y="" RD="" R=""
fi

usage() {
    cat <<EOF
${B}Neon KDE Widgets installer${R}

Usage: ./install.sh [options] [widget...]

Widgets: ${WIDGETS[*]} (or "all")
With no widget names, you'll be asked which ones to use.

Options:
  -r, --remove     Uninstall the given widgets instead of installing them
  -l, --list       Show the widgets and whether they're installed
  -s, --restart    Restart the Plasma desktop afterwards without asking
  -h, --help       Show this help

Examples:
  ./install.sh                 Pick from a menu
  ./install.sh all             Install or update all widgets
  ./install.sh clock player    Install or update only these two
  ./install.sh -r atmos        Uninstall Neon Atmos

Widgets are installed for your user only. Installing a widget that's
already installed updates it.
EOF
}

die() { printf '%sError:%s %s\n' "$RD" "$R" "$1" >&2; exit 1; }

plugin_id() {
    sed -n 's/.*"Id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "neon-$1/metadata.json" | head -n1
}

is_installed() {
    kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qxF "$1"
}

list() {
    for w in "${WIDGETS[@]}"; do
        if is_installed "$(plugin_id "$w")"; then state="${G}installed${R}"; else state="${DIM}not installed${R}"; fi
        printf '  %-8s %-62s %s\n' "$w" "${DESC[$w]}" "$state"
    done
}

# ---- parse arguments ----
mode=install restart=ask picked=()
while [ $# -gt 0 ]; do
    case "$1" in
        -r|--remove)  mode=remove ;;
        -l|--list)    mode=list ;;
        -s|--restart) restart=yes ;;
        -h|--help)    usage; exit 0 ;;
        all)          picked=("${WIDGETS[@]}") ;;
        -*)           die "unknown option '$1'. Run ./install.sh --help" ;;
        *)
            name=${1%/}           # tab completion adds a trailing slash
            name=${name#neon-}
            [ -n "${DESC[$name]+x}" ] || die "unknown widget '$1'. Choose from: ${WIDGETS[*]}, all"
            picked+=("$name") ;;
    esac
    shift
done

command -v kpackagetool6 >/dev/null 2>&1 \
    || die "kpackagetool6 not found. These widgets need KDE Plasma 6."

if [ "$mode" = list ]; then
    list
    exit 0
fi

# ---- no widgets given: ask ----
if [ ${#picked[@]} -eq 0 ]; then
    [ -t 0 ] || die "no widgets given. Run ./install.sh --help"
    verb=$([ "$mode" = remove ] && echo "uninstall" || echo "install or update")
    printf '%sNeon KDE Widgets%s\n\n' "$B" "$R"
    i=1
    for w in "${WIDGETS[@]}"; do
        if is_installed "$(plugin_id "$w")"; then state=" ${G}(installed)${R}"; else state=""; fi
        printf '  %s%d%s) %s%s\n' "$C" "$i" "$R" "${DESC[$w]}" "$state"
        i=$((i + 1))
    done
    printf '  %sa%s) All of them\n\n' "$C" "$R"
    read -r -p "Which widgets do you want to $verb? (e.g. 1 3, or a): " answer
    # Accept commas as separators; split into words without expanding * or ?
    read -r -a answers <<< "${answer//,/ }"
    for a in "${answers[@]}"; do
        case "$a" in
            a|A|all) picked=("${WIDGETS[@]}") ;;
            [1-9])
                [ "$a" -le ${#WIDGETS[@]} ] || die "no widget number $a"
                picked+=("${WIDGETS[$((a - 1))]}") ;;
            *) die "didn't understand '$a'" ;;
        esac
    done
    [ ${#picked[@]} -gt 0 ] || { echo "Nothing selected."; exit 0; }
    echo
fi

# Drop duplicates, keep order
declare -A seen=()
todo=()
for w in "${picked[@]}"; do
    [ -n "${seen[$w]+x}" ] || { seen[$w]=1; todo+=("$w"); }
done

# ---- do it ----
failed=0 changed=0
for w in "${todo[@]}"; do
    id=$(plugin_id "$w")
    name=${DESC[$w]%%:*}
    if [ "$mode" = remove ]; then
        if ! is_installed "$id"; then
            printf '  %s%s%s is not installed\n' "$DIM" "$name" "$R"
            continue
        fi
        action="Uninstalled" args=(-r "$id")
    elif is_installed "$id"; then
        action="Updated" args=(-u "./neon-$w")
    else
        action="Installed" args=(-i "./neon-$w")
    fi
    if out=$(kpackagetool6 -t Plasma/Applet "${args[@]}" 2>&1); then
        printf '  %s✓%s %s %s\n' "$G" "$R" "$action" "$name"
        changed=$((changed + 1))
    else
        printf '  %s✗%s %s failed:\n%s\n' "$RD" "$R" "$name" "$out" >&2
        failed=$((failed + 1))
    fi
done

[ "$changed" -gt 0 ] || exit "$failed"

# ---- restart Plasma so the changes load ----
echo
if [ "$mode" = remove ]; then
    echo "Uninstalled widgets still on your desktop or panel will show an error box;"
    echo "right-click it and choose Remove."
else
    echo "Add widgets by right-clicking the desktop and choosing Add Widgets…"
fi
echo "Plasma needs to restart to load the changes. Your open apps are not affected."

if [ "$restart" = ask ] && [ -t 0 ]; then
    read -r -p "Restart the Plasma desktop now? [y/N] " yn
    case "$yn" in [yY]*) restart=yes ;; esac
fi
if [ "$restart" = yes ]; then
    # Plasma usually runs as a systemd user service. Without systemd (or if the
    # session wasn't started through it), restart the plasmashell process directly.
    if systemctl --user restart plasma-plasmashell 2>/dev/null; then
        printf '%sPlasma restarted.%s\n' "$G" "$R"
    elif command -v kquitapp6 >/dev/null 2>&1 && command -v kstart >/dev/null 2>&1; then
        kquitapp6 plasmashell >/dev/null 2>&1 || true
        kstart plasmashell >/dev/null 2>&1 \
            && printf '%sPlasma restarted.%s\n' "$G" "$R" \
            || { printf '%sCouldn'\''t restart Plasma.%s Log out and back in to load the changes.\n' "$Y" "$R"; exit 1; }
    else
        printf '%sCouldn'\''t restart Plasma.%s Log out and back in to load the changes.\n' "$Y" "$R"
        exit 1
    fi
else
    printf 'Restart it later with: %ssystemctl --user restart plasma-plasmashell%s\n' "$Y" "$R"
fi

exit "$failed"
