#!/bin/bash
# ==============================================================================
# Script: install.sh
# Projeto: Bootc KCM (Generic KDE Plasma 6 Module for Bootc Distributions)
# Descrição: Compila e instala o módulo KCM do bootc:
#            - Plugin do KDE System Settings (Kirigami + Qt6/KF6)
#            - Helper KAuth com ativação D-Bus sob demanda
#            - Regras Polkit administrativas
#            - Drop-in systemd para evitar reboot automático do timer bootc
#            - Notificação gráfica desktop daemonless (systemd user inotify)
#            - Notificação CLI para terminal (profile.d, fish e comando bootc-notify)
#            - Ícones hicolor da logo oficial do bootc
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
STAGING_DIR="${BUILD_DIR}/staging"
PREFIX="${PREFIX:-/usr}"
DESTDIR="${DESTDIR:-}"
ENABLE_USR_OVERLAY=0
FORCE_CONTAINER_BUILD=0

BUILD_DEPS=(
    cmake
    extra-cmake-modules
    gcc-c++
    ninja-build
    gettext
    qt6-qtbase-devel
    qt6-qtdeclarative-devel
    kf6-kcoreaddons-devel
    kf6-ki18n-devel
    kf6-kcmutils-devel
    kf6-kauth-devel
)

usage() {
    cat <<EOF
Uso: ./install.sh [OPÇÕES]

Opções:
  --usr-overlay       Ativa 'bootc usr-overlay' automaticamente se /usr for somente-leitura
  --container-build   Compila dentro de um container Podman efêmero (ideal para host imutável)
  --prefix <DIR>      Define o prefixo de instalação (padrão: /usr)
  --destdir <DIR>     Define o diretório de destino para staging (ex.: empacotamento ou Containerfile)
  -h, --help          Exibe esta mensagem de ajuda
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --usr-overlay)
            ENABLE_USR_OVERLAY=1
            shift
            ;;
        --container-build)
            FORCE_CONTAINER_BUILD=1
            shift
            ;;
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        --destdir)
            DESTDIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "❌ Opção desconhecida: $1" >&2
            usage
            exit 1
            ;;
    esac
done

run_priv() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

check_usr_writable() {
    local target_check="${DESTDIR}${PREFIX}"
    if [[ -w "$target_check" ]]; then
        return 0
    fi
    if run_priv test -w "$target_check" 2>/dev/null; then
        return 0
    fi
    return 1
}

has_native_build_deps() {
    command -v cmake >/dev/null 2>&1 || return 1
    command -v g++ >/dev/null 2>&1 || return 1
    [[ -d /usr/share/ECM/cmake ]] || return 1
    [[ -d /usr/lib64/cmake/KF6KCMUtils || -d /usr/lib/cmake/KF6KCMUtils ]] || return 1
    [[ -d /usr/lib64/cmake/KF6Auth || -d /usr/lib/cmake/KF6Auth ]] || return 1
    return 0
}

build_native() {
    echo "🔨 [Bootc KCM] Compilando nativamente com CMake..."
    if ! has_native_build_deps; then
        if command -v dnf >/dev/null 2>&1; then
            echo "📦 [Bootc KCM] Instalando dependências de compilação via DNF..."
            run_priv dnf install --setopt=tsflags=nodocs -y "${BUILD_DEPS[@]}"
        else
            echo "⚠️  Dependências de desenvolvimento KF6/Qt6 não encontradas. Recomenda-se usar --container-build." >&2
        fi
    fi

    rm -rf "$BUILD_DIR"
    cmake -B "$BUILD_DIR" -S "$SCRIPT_DIR" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF

    cmake --build "$BUILD_DIR" --parallel "$(nproc)"
    mkdir -p "$STAGING_DIR"
    DESTDIR="$STAGING_DIR" cmake --install "$BUILD_DIR"
}

build_in_podman() {
    if ! command -v podman >/dev/null 2>&1; then
        echo "❌ Erro: 'podman' não encontrado e os pacotes de desenvolvimento não estão no host." >&2
        exit 1
    fi

    local builder_img="quay.io/fedora/fedora:latest"

    echo "🐳 [Bootc KCM] Compilando em container Podman efêmero (${builder_img})..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR" "$STAGING_DIR"

    podman run --rm \
        --security-opt label=disable \
        -v bootc-kcm-dnf-cache:/var/cache/libdnf5:Z \
        -v "${SCRIPT_DIR}:/src:Z" \
        -w /src \
        "$builder_img" \
        bash -exc "
            dnf install --setopt=keepcache=True --setopt=tsflags=nodocs -y ${BUILD_DEPS[*]} &&
            cmake -B /src/build -S /src \
                -DCMAKE_INSTALL_PREFIX=${PREFIX} \
                -DCMAKE_BUILD_TYPE=Release \
                -DBUILD_TESTING=OFF &&
            cmake --build /src/build --parallel \$(nproc) &&
            DESTDIR=/src/build/staging cmake --install /src/build
        "
}

echo "🚀 [Bootc KCM] Iniciando compilação do módulo genérico Bootc KCM..."

if [[ $FORCE_CONTAINER_BUILD -eq 1 ]]; then
    build_in_podman
elif has_native_build_deps || [[ ! -f /run/ostree-booted ]]; then
    build_native
else
    echo "ℹ️  Sistema imutável (bootc/ostree) detectado sem pacotes '-devel' locais."
    echo "   Utilizando Podman para compilar sem modificar a imagem base..."
    build_in_podman
fi

# Verifica se o destino (/usr) é gravável; caso seja um host bootc em execução, oferece usr-overlay
if [[ -z "$DESTDIR" ]] && ! check_usr_writable; then
    if [[ $ENABLE_USR_OVERLAY -eq 1 ]]; then
        echo "🔓 [Bootc KCM] Ativando overlayfs transiente em /usr ('bootc usr-overlay')..."
        run_priv bootc usr-overlay
    else
        echo "⚠️  O diretório ${PREFIX} está montado como somente-leitura (comportamento imutável do bootc)."
        read -r -p "Deseja ativar 'sudo bootc usr-overlay' para instalar e testar agora? [s/N] " resp
        if [[ "$resp" =~ ^[sS](im)?$ || "$resp" =~ ^[yY](es)?$ ]]; then
            run_priv bootc usr-overlay
        else
            echo "ℹ️  Arquivos compilados com sucesso em: ${STAGING_DIR}"
            echo "   Execute './install.sh --usr-overlay' para instalá-los temporariamente no host."
            exit 0
        fi
    fi
fi

TARGET_ROOT="${DESTDIR:-/}"
echo "📂 [Bootc KCM] Instalando arquivos em ${TARGET_ROOT}..."
run_priv cp -rv "${STAGING_DIR}/"* "$TARGET_ROOT"

# Garante que os arquivos .bashrc (em /etc/skel e do usuário atual, se aplicável)
# carreguem /etc/bashrc (e consequentemente /etc/profile.d/bootc-notify.sh)
# e remove referências legadas a /usr/local/bin/bootc-notify.sh
ensure_bashrc_sources_etc() {
    local bashrc_file="$1"
    local use_priv="${2:-0}"
    [[ -f "$bashrc_file" ]] || return 0

    # Remove chamada legada acoplada (/usr/local/bin/bootc-notify.sh)
    if grep -q '/usr/local/bin/bootc-notify.sh' "$bashrc_file" 2>/dev/null; then
        if [[ "$use_priv" -eq 1 ]]; then
            run_priv sed -i '/# Notificação de atualização pendente do bootc/d' "$bashrc_file"
            run_priv sed -i '\|/usr/local/bin/bootc-notify\.sh|d' "$bashrc_file"
        else
            sed -i '/# Notificação de atualização pendente do bootc/d' "$bashrc_file"
            sed -i '\|/usr/local/bin/bootc-notify\.sh|d' "$bashrc_file"
        fi
    fi

    # Injeta carregamento de /etc/bashrc no topo caso não exista (ex.: templates do Oh My Bash)
    if ! grep -Eq '(\.|source)[[:space:]]+/etc/bashrc' "$bashrc_file" 2>/dev/null; then
        local tmp_rc
        tmp_rc="$(mktemp)"
        cat <<'EOF' > "$tmp_rc"
# Source global definitions (carrega /etc/bashrc e /etc/profile.d/*.sh, incluindo bootc-notify)
if [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi

EOF
        cat "$bashrc_file" >> "$tmp_rc"
        if [[ "$use_priv" -eq 1 ]]; then
            run_priv cp "$tmp_rc" "$bashrc_file"
            run_priv chmod 0644 "$bashrc_file"
        else
            cp "$tmp_rc" "$bashrc_file"
        fi
        rm -f "$tmp_rc"
    fi
}

ensure_bashrc_sources_etc "${TARGET_ROOT%/}/etc/skel/.bashrc" 1
if [[ -z "$DESTDIR" && -n "${HOME:-}" && -f "${HOME}/.bashrc" ]]; then
    ensure_bashrc_sources_etc "${HOME}/.bashrc" 0
fi

# Salva manifesto de arquivos instalados para desinstalação limpa
MANIFEST_FILE="${SCRIPT_DIR}/.installed_files.manifest"
(cd "$STAGING_DIR" && find . -type f -o -type l | sed 's|^\./|/|') > "$MANIFEST_FILE"

if [[ -z "$DESTDIR" ]]; then
    echo "🔄 [Bootc KCM] Recarregando serviços D-Bus, Polkit e Systemd..."
    run_priv systemctl daemon-reload 2>/dev/null || true
    run_priv systemctl reload dbus-broker.service 2>/dev/null || run_priv systemctl reload dbus.service 2>/dev/null || true
    run_priv systemctl restart polkit.service 2>/dev/null || true
    run_priv systemctl --global enable bootc-reboot-notify.path 2>/dev/null || true

    # Habilita o path imediatamente na sessão de usuário atual, se aplicável
    if [[ $EUID -ne 0 ]] && command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable --now bootc-reboot-notify.path 2>/dev/null || true
    fi

    if command -v kbuildsycoca6 >/dev/null 2>&1; then
        kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    fi

    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        run_priv gtk-update-icon-cache -f -t "${PREFIX}/share/icons/hicolor" 2>/dev/null || true
    fi
fi

echo "✅ [Bootc KCM] Módulo Bootc KCM instalado com sucesso!"
echo "   - Para abrir o módulo gráfico: systemsettings kcm_bootc"
echo "   - Para testar a notificação no terminal: bootc-notify --status"
