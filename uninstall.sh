#!/bin/bash
# ==============================================================================
# Script: uninstall.sh
# Projeto: Bootc KCM (Generic KDE Plasma 6 Module for Bootc Distributions)
# Descrição: Remove todos os componentes do módulo Bootc KCM instalados no sistema.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr}"
MANIFEST_FILE="${SCRIPT_DIR}/.installed_files.manifest"

run_priv() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

echo "🗑️  [Bootc KCM] Desinstalando módulo Bootc KCM..."

# Desabilita as unidades systemd user
if [[ $EUID -ne 0 ]] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now bootc-reboot-notify.path 2>/dev/null || true
    systemctl --user stop bootc-reboot-notify.service 2>/dev/null || true
fi
run_priv systemctl --global disable bootc-reboot-notify.path 2>/dev/null || true

FILES_TO_REMOVE=(
    "${PREFIX}/lib64/qt6/plugins/plasma/kcms/systemsettings/kcm_bootc.so"
    "${PREFIX}/lib/qt6/plugins/plasma/kcms/systemsettings/kcm_bootc.so"
    "${PREFIX}/libexec/kf6/kauth/kcm_bootc_authhelper"
    "${PREFIX}/lib/kf6/kauth/kcm_bootc_authhelper"
    "${PREFIX}/share/polkit-1/actions/org.containers.bootc.policy"
    "${PREFIX}/share/polkit-1/rules.d/90-bootc-kcm.rules"
    "${PREFIX}/share/dbus-1/system.d/org.containers.bootc.conf"
    "${PREFIX}/share/dbus-1/system-services/org.containers.bootc.service"
    "${PREFIX}/share/applications/kcm_bootc.desktop"
    "${PREFIX}/bin/bootc-desktop-notify.sh"
    "${PREFIX}/bin/bootc-notify"
    "/etc/profile.d/bootc-notify.sh"
    "${PREFIX}/share/fish/vendor_conf.d/bootc-notify.fish"
    "${PREFIX}/lib/systemd/user/bootc-reboot-notify.path"
    "${PREFIX}/lib/systemd/user/bootc-reboot-notify.service"
    "${PREFIX}/lib/systemd/system/bootc-fetch-apply-updates.service.d/10-stage-only.conf"
)

# Adiciona arquivos do manifesto se existir
if [[ -f "$MANIFEST_FILE" ]]; then
    while IFS= read -r file; do
        [[ -n "$file" ]] && FILES_TO_REMOVE+=("$file")
    done < "$MANIFEST_FILE"
fi

# Adiciona ícones
for size in 16 24 32 48 64 128 256 512; do
    FILES_TO_REMOVE+=(
        "${PREFIX}/share/icons/hicolor/${size}x${size}/apps/bootc.png"
        "${PREFIX}/share/icons/hicolor/${size}x${size}/apps/kcm_bootc.png"
    )
done

for f in "${FILES_TO_REMOVE[@]}"; do
    if [[ -e "$f" || -L "$f" ]]; then
        echo "   Removendo: $f"
        run_priv rm -f "$f"
    fi
done

# Remove diretório do drop-in do systemd se ficou vazio
if [[ -d "${PREFIX}/lib/systemd/system/bootc-fetch-apply-updates.service.d" ]]; then
    run_priv rmdir "${PREFIX}/lib/systemd/system/bootc-fetch-apply-updates.service.d" 2>/dev/null || true
fi

rm -f "$MANIFEST_FILE"

echo "🔄 [Bootc KCM] Recarregando D-Bus, Polkit e Systemd..."
run_priv systemctl daemon-reload 2>/dev/null || true
run_priv systemctl reload dbus-broker.service 2>/dev/null || run_priv systemctl reload dbus.service 2>/dev/null || true
run_priv systemctl restart polkit.service 2>/dev/null || true

if [[ $EUID -ne 0 ]] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload 2>/dev/null || true
fi

if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    run_priv gtk-update-icon-cache -f -t "${PREFIX}/share/icons/hicolor" 2>/dev/null || true
fi

echo "✅ [Bootc KCM] Desinstalação concluída com sucesso."
