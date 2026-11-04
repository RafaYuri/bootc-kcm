# 🦭 Bootc KCM (KDE Plasma 6)

Módulo de Configuração nativo do **KDE Plasma 6** (*KControlModule*) para gerenciamento visual, transacional e atômico de sistemas operacionais baseados em [bootc](https://github.com/containers/bootc).

Projetado para ser **100% genérico e agnóstico de distribuição**, funcionando perfeitamente em qualquer sistema operacional imutável/transacional derivado de bootc que adote o KDE Plasma como ambiente de desktop (ex.: Fedora Bootc, CentOS Stream Bootc, RHEL Image Mode, openSUSE MicroOS/Kalpa adaptados para bootc, ou distribuições customizadas).

---

## 🎯 Destaques e Funcionalidades

1. **Gestão Transacional Completa da Imagem:**
   * **Imagem Ativa (`Booted`):** Exibe a referência OCI em execução, arquitetura, digest SHA256 truncado/completo, transporte de registro, data de compilação da camada e hash OSTree.
   * **Imagem Preparada (`Staged`):** Identifica atualizações baixadas aguardando reinicialização, com botão direto para reiniciar a máquina pelo diálogo nativo `org.kde.LogoutPrompt` do Plasma 6.
   * **Reversão Atômica (`Rollback`):** Detecta a versão anterior preservada pelo bootc no disco e permite agendar o boot direto nela em caso de regressões.
   * **Verificação Remota (`bootc upgrade --check`):** Consulta registros OCI remotos por novas camadas sem baixá-las antecipadamente.
   * **Atualização em Segundo Plano:** Alternância visual para ativar/desativar o timer do sistema (`bootc-fetch-apply-updates.timer`).
   * **Logs de Execução Integrados:** Visualização recolhível da saída em tempo real dos comandos do `bootc`.

2. **Arquitetura 100% Daemonless (Zero Consumo de RAM em Repouso):**
   * **Sem daemons residentes:** O módulo não executa daemons nem serviços pesados em background.
   * **Helper KAuth Efêmero:** O binário `kcm_bootc_authhelper` é acionado sob demanda via D-Bus System Activation sob o domínio `org.containers.bootc` e encerra sua execução imediatamente após o processamento.
   * **Regras Polkit:** Leitura de status e verificação remota liberadas para sessões ativas locais; operações de download/stage liberadas sem senha para administradores (grupos `wheel` ou `sudo`), alinhado ao padrão do KDE Discover.

3. **Prevenção de Reboots Forçados (Retenção em Staged):**
   * Inclui o drop-in systemd `/usr/lib/systemd/system/bootc-fetch-apply-updates.service.d/10-stage-only.conf` que anula a flag `--apply` padrão de upstream do bootc.
   * As atualizações automáticas são baixadas e preparadas atômica e silenciosamente (*staged*), mantendo a integridade da sessão do usuário até que ele escolha o momento ideal para reiniciar.

4. **Notificação Dupla de Reboot Pendente (`/run/reboot-required`):**
   * **Gráfica no Plasma:** A unidade `systemd --user` `bootc-reboot-notify.path` monitora `/run/reboot-required` via `inotify` do kernel. No momento exato em que uma atualização entra em staged, dispara `bootc-desktop-notify.sh` exibindo notificação do KDE com botões *"Reiniciar Agora"* e *"Abrir Painel Bootc"*.
   * **No Terminal (CLI):** Integração automática via `/etc/profile.d/bootc-notify.sh` (POSIX/Bash/Zsh), `/usr/share/fish/vendor_conf.d/bootc-notify.fish` e o comando independente `bootc-notify`, informando atualizações pendentes sempre que o usuário abre um terminal.

5. **Identidade Visual Bootc:**
   * Utiliza a logo oficial do projeto Bootc compilada em múltiplos tamanhos padrão da especificação FreeDesktop Hicolor (16x16 até 512x512).

---

## 📂 Estrutura do Projeto

```text
Bootc KCM/
├── CMakeLists.txt                                  # Definição CMake (KDE ECM + Qt6 + KF6)
├── README.md                                       # Documentação completa
├── install.sh                                      # Script de compilação e instalação universal
├── uninstall.sh                                    # Script de remoção limpa
├── bootc-logo-full-vert.png                        # Logo original em alta resolução
├── icons/
│   └── hicolor/
│       ├── 16x16/apps/bootc.png                    # Ícones em todos os tamanhos padrão
│       ├── 24x24/apps/bootc.png
│       ├── 32x32/apps/bootc.png
│       ├── 48x48/apps/bootc.png
│       ├── 64x64/apps/bootc.png
│       ├── 128x128/apps/bootc.png
│       ├── 256x256/apps/bootc.png
│       └── 512x512/apps/bootc.png
├── desktop/
│   ├── kcm_bootc.desktop                           # Atalho de integração do Plasma
│   └── bootc-desktop-notify.sh                     # Script da notificação gráfica
├── terminal/
│   ├── bootc-notify.sh                             # Notificação CLI (/etc/profile.d/ e /usr/bin/)
│   └── bootc-notify.fish                           # Integração nativa para Fish Shell
├── systemd/
│   ├── user/
│   │   ├── bootc-reboot-notify.path                # Gatilho daemonless inotify (/run/reboot-required)
│   │   └── bootc-reboot-notify.service             # Disparo oneshot da notificação gráfica
│   └── system/
│       └── bootc-fetch-apply-updates.service.d/
│           └── 10-stage-only.conf                  # Remove --apply do timer nativo do bootc
├── polkit/
│   └── 90-bootc-kcm.rules                          # Regras de autorização Polkit (wheel/sudo)
└── src/
    ├── CMakeLists.txt                              # Compilação do plugin KCM e do AuthHelper
    ├── kcm_bootc.json                              # Metadados do plugin KDE Plasma 6
    ├── kcm_bootc.h                                 # Header C++ da classe KQuickManagedConfigModule
    ├── kcm_bootc.cpp                               # Lógica e comunicação D-Bus/KAuth
    ├── ui/
    │   └── main.qml                                # Interface gráfica Kirigami moderna
    └── helper/
        ├── bootchelper.h                           # Header do KAuth Helper privilegiado
        ├── bootchelper.cpp                         # Execução segura dos comandos bootc
        └── org.containers.bootc.actions            # Definição das ações KAuth
```

---

## 🛠️ Como Compilar e Instalar

### 1. Testando localmente em um host bootc imutável

Em sistemas operacionais imutáveis com `bootc`/`ostree`, `/usr` é montado como somente-leitura. O `install.sh` oferece suporte a compilação via Podman (sem poluir o sistema) e montagem em overlayfs temporário:

```bash
# Compila dentro de um container efêmero e instala usando bootc usr-overlay:
./install.sh --container-build --usr-overlay
```

Para abrir o módulo imediatamente no KDE Plasma:
```bash
systemsettings kcm_bootc
```

---

### 2. Integrando na construção de imagem (`Containerfile` / `Dockerfile`)

Para incluir o **Bootc KCM** em qualquer distribuição baseada em `bootc` com KDE Plasma, adicione um estágio multi-stage no seu `Containerfile`:

```dockerfile
# ====================================================================
# ESTÁGIO DE COMPILAÇÃO DO BOOTC KCM
# ====================================================================
FROM quay.io/fedora/fedora:latest AS kcm-builder

RUN dnf install --setopt=tsflags=nodocs -y \
        cmake extra-cmake-modules gcc-c++ ninja-build gettext \
        qt6-qtbase-devel qt6-qtdeclarative-devel \
        kf6-kcoreaddons-devel kf6-ki18n-devel kf6-kcmutils-devel kf6-kauth-devel

COPY ["Bootc KCM/", "/tmp/bootc-kcm/"]

RUN cmake -B /tmp/bootc-kcm/build -S /tmp/bootc-kcm \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF && \
    cmake --build /tmp/bootc-kcm/build --parallel "$(nproc)" && \
    DESTDIR=/tmp/kcm-install cmake --install /tmp/bootc-kcm/build

# ====================================================================
# IMAGEM FINAL (SUA DISTRIBUIÇÃO BASEADA EM BOOTC COM KDE PLASMA)
# ====================================================================
FROM sua-imagem-bootc:latest

# Copia todos os artefatos compilados (KCM, helper, polkit, systemd, terminal, ícones)
COPY --from=kcm-builder /tmp/kcm-install/usr/ /usr/
COPY --from=kcm-builder /tmp/kcm-install/etc/ /etc/

# Habilita o monitoramento daemonless de atualizações para as sessões de usuários
RUN systemctl --global enable bootc-reboot-notify.path
```

---

### 3. Compilação Nativa (Para Empacotadores / Desenvolvedores)

Se você estiver em um ambiente de desenvolvimento tradicional com pacotes `-devel` instalados:

```bash
cmake -B build -S . \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_BUILD_TYPE=Release

cmake --build build --parallel "$(nproc)"
sudo cmake --install build
```

---

## 🧪 Como Testar as Notificações

### 1. Testando a notificação no terminal (CLI)
Você pode simular que uma atualização foi baixada e está *staged* criando o arquivo de controle:
```bash
sudo touch /run/reboot-required
```
Abra uma nova aba do terminal ou execute:
```bash
bootc-notify --status
```
Você verá:
```text
🔄 Atualização pendente do sistema (bootc). Reinicie para aplicar as alterações.
```

### 2. Testando a notificação gráfica no KDE Plasma
Ao criar `/run/reboot-required`, o systemd da sessão do usuário disparará a notificação gráfica nativa do KDE Plasma com os botões interativos **"Reiniciar Agora"** e **"Abrir Painel Bootc"**.

Para limpar o teste:
```bash
sudo rm -f /run/reboot-required
```

---

## 🗑️ Desinstalação

Para remover completamente todos os arquivos, regras Polkit, unidades systemd e ícones instalados:

```bash
sudo ./uninstall.sh
```

---

## 📄 Licença

Distribuído sob a licença **GPL-2.0-or-later** / **LGPL-2.1-or-later**, em consonância com as diretrizes do KDE Frameworks e upstream do bootc.
