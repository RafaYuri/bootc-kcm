# ==============================================================================
# Script: bootc-notify.fish
# Descrição: Notificação de atualização pendente do bootc para o shell Fish.
#            Instalado em /usr/share/fish/vendor_conf.d/bootc-notify.fish.
# ==============================================================================

if status is-interactive; and test -f /run/reboot-required
    echo -e "\e[1;36m🔄 Atualização pendente do sistema (bootc). Reinicie para aplicar as alterações.\e[0m"
end
