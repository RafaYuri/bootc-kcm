#!/bin/bash
# ==============================================================================
# Script: bootc-desktop-notify.sh
# Descrição: Notificação gráfica de atualização staged do bootc no KDE Plasma.
#            Disparado automaticamente pelo systemd user via inotify
#            (PathExists=/run/reboot-required) sem nenhum daemon residente em RAM.
# ==============================================================================
set -euo pipefail

if [ ! -f /run/reboot-required ]; then
    exit 0
fi

if ! command -v notify-send >/dev/null 2>&1; then
    exit 0
fi

ACTION="$(notify-send \
    --app-name="bootc" \
    --icon="bootc" \
    --urgency=normal \
    --action="reboot=Reiniciar Agora" \
    --action="settings=Abrir Painel Bootc" \
    "🔄 Atualização do Sistema Pronta" \
    "Uma nova imagem do sistema foi preparada (staged) pelo bootc. Reinicie o computador para aplicar as alterações." || true)"

case "$ACTION" in
    reboot)
        qdbus6 org.kde.LogoutPrompt /LogoutPrompt promptReboot 2>/dev/null \
            || qdbus org.kde.LogoutPrompt /LogoutPrompt promptReboot 2>/dev/null \
            || systemctl reboot
        ;;
    settings)
        systemsettings kcm_bootc >/dev/null 2>&1 &
        ;;
esac
