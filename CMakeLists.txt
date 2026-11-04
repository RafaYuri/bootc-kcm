cmake_minimum_required(VERSION 3.22)

project(kcm-bootc VERSION 1.0.0 LANGUAGES CXX)

set(QT_MIN_VERSION "6.6.0")
set(KF6_MIN_VERSION "6.0.0")

find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(FeatureSummary)

remove_definitions(-DQT_NO_CAST_FROM_ASCII)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    DBus
)

find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS
    CoreAddons
    I18n
    KCMUtils
    Auth
)

add_subdirectory(src)

# 1. Regra Polkit para o módulo bootc (leitura sem senha, upgrade sem senha para administradores)
install(
    FILES polkit/90-bootc-kcm.rules
    DESTINATION ${KDE_INSTALL_DATADIR}/polkit-1/rules.d
)

# 2. Notificação gráfica desktop (daemonless via systemd user inotify)
install(
    PROGRAMS desktop/bootc-desktop-notify.sh
    DESTINATION ${KDE_INSTALL_BINDIR}
)

install(
    FILES
        systemd/user/bootc-reboot-notify.path
        systemd/user/bootc-reboot-notify.service
    DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/systemd/user
)

# 3. Override systemd do serviço de auto-atualização do bootc (evita reboot forçado e mantém em staged)
install(
    FILES systemd/system/bootc-fetch-apply-updates.service.d/10-stage-only.conf
    DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/systemd/system/bootc-fetch-apply-updates.service.d
)

# 4. Notificação de terminal (CLI) para sessões interativas (profile.d, fish e binário independente)
install(
    PROGRAMS terminal/bootc-notify.sh
    DESTINATION ${KDE_INSTALL_BINDIR}
    RENAME bootc-notify
)

install(
    FILES terminal/bootc-notify.sh
    DESTINATION /etc/profile.d
    RENAME bootc-notify.sh
)

install(
    FILES terminal/bootc-notify.fish
    DESTINATION ${KDE_INSTALL_DATADIR}/fish/vendor_conf.d
)

# 5. Ícones em múltiplos tamanhos padrão da especificação hicolor
set(BOOTC_ICON_SIZES 16 24 32 48 64 128 256 512)
foreach(size ${BOOTC_ICON_SIZES})
    install(
        FILES icons/hicolor/${size}x${size}/apps/bootc.png
        DESTINATION ${KDE_INSTALL_DATADIR}/icons/hicolor/${size}x${size}/apps
    )
    # Alias kcm_bootc.png para compatibilidade retroativa
    install(
        FILES icons/hicolor/${size}x${size}/apps/bootc.png
        DESTINATION ${KDE_INSTALL_DATADIR}/icons/hicolor/${size}x${size}/apps
        RENAME kcm_bootc.png
    )
endforeach()

feature_summary(WHAT ALL INCLUDE_QUIET_PACKAGES FATAL_ON_MISSING_REQUIRED_PACKAGES)
