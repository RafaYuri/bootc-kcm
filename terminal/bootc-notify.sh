#!/bin/sh
# ==============================================================================
# Script: bootc-notify
# Descrição: Notificação de atualização pendente do bootc para terminal (CLI).
#            Pode ser executado diretamente em /usr/bin/bootc-notify ou
#            carregado automaticamente via /etc/profile.d/bootc-notify.sh.
# ==============================================================================

REBOOT_MARKER="/run/reboot-required"

# Quando invocado como comando direto (com argumentos)
case "${1:-}" in
    -h|--help)
        echo "Uso: bootc-notify [OPÇÃO]"
        echo ""
        echo "Opções:"
        echo "  -c, --check         Retorna 0 se houver reboot pendente (/run/reboot-required), 1 caso contrário"
        echo "  -s, --status        Exibe mensagem detalhada informando se há reboot pendente ou se o sistema está atualizado"
        echo "  --sync-marker       (Root) Sincroniza /run/reboot-required inspecionando 'bootc status --format=json'"
        echo "  -h, --help          Exibe esta ajuda"
        return 0 2>/dev/null || exit 0
        ;;
    -c|--check)
        if [ -f "$REBOOT_MARKER" ]; then
            return 0 2>/dev/null || exit 0
        fi
        return 1 2>/dev/null || exit 1
        ;;
    -s|--status)
        if [ -f "$REBOOT_MARKER" ]; then
            printf '\033[1;36m🔄 Atualização pendente do sistema (bootc). Reinicie para aplicar as alterações.\033[0m\n'
            return 0 2>/dev/null || exit 0
        else
            printf '\033[1;32m✅ Sistema atualizado. Nenhuma reinicialização pendente.\033[0m\n'
            return 0 2>/dev/null || exit 0
        fi
        ;;
    --sync-marker)
        if command -v bootc >/dev/null 2>&1; then
            if bootc status --format=json 2>/dev/null | grep -Eq '"staged"|rollbackQueued":true'; then
                touch "$REBOOT_MARKER" 2>/dev/null || true
            fi
        fi
        return 0 2>/dev/null || exit 0
        ;;
esac

# Para carregamento interativo via /etc/profile.d/bootc-notify.sh:
# Garante que a saída é um terminal (TTY interativo) antes de imprimir,
# prevenindo problemas em sessões não-interativas como scp, sftp e rsync.
if [ -t 1 ] && [ -f "$REBOOT_MARKER" ]; then
    printf '\033[1;36m🔄 Atualização pendente do sistema (bootc). Reinicie para aplicar as alterações.\033[0m\n'
fi
