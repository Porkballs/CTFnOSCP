nk3              : LNK file parsing, required by hashgrab.py
#   - ldap3               : pure-Python LDAP (used by bloodyAD, ldeep, etc.)
#   - pycryptodome        : crypto backend for ldapsearch-ad NTLM auth
#   - gssapi              : Python GSSAPI bindings — enables Kerberos auth
#                           via ldap3 and impacket (needs libkrb5-dev at build)

log "Installing Python libraries (python-ldap, pyasn1*, pylnk3, ldap3, pycryptodome, gssapi)..."
$SUDO pip install --break-system-packages \
    python-ldap \
    'pyasn1>=0.4.5' \
    'pyasn1-modules>=0.2.5' \
    pylnk3 \
    ldap3 \
    pycryptodome \
    gssapi

pipx ensurepath

# ---- Docker service ---------------------------------------------------------
# Enable so containers with --restart always survive reboots.
log "Enabling Docker service..."
$SUDO systemctl enable docker --now 2>/dev/null || warn "Could not enable Docker (non-systemd env?)"

# Add current user to the docker group so docker commands don't need sudo.
# Takes effect on next login — for this session use: newgrp docker
if ! groups "$USER" | grep -qw docker; then
    $SUDO usermod -aG docker "$USER"
    log "Added $USER to docker group (takes effect on next login)"
fi

# ---- Rockyou ----------------------------------------------------------------

log "Extracting rockyou.txt if needed..."
if [ -f /usr/share/wordlists/rockyou.txt.gz ]; then
    $SUDO gunzip /usr/share/wordlists/rockyou.txt.gz
elif [ -f /usr/share/wordlists/rockyou.txt ]; then
    echo "    Already extracted, skipping."
else
    warn "rockyou.txt(.gz) not found — is the wordlists package installed?"
fi

# ---- Powerline fonts --------------------------------------------------------

log "Installing Powerline fonts..."
mkdir -p ~/Scripts
cd ~/Scripts
if [ ! -d fonts ]; then
    git clone https://github.com/powerline/fonts
else
    git -C fonts pull --ff-only || true
fi
cd fonts
chmod +x install.sh
./install.sh
cd "$SCRIPT_DIR"

# ---- RustScan (latest release) ----------------------------------------------
# GitHub's /releases/latest/download/<asset> redirect always points at the most
# recent non-prerelease asset — no version pinning needed.

log "Installing latest RustScan from GitHub..."
RUSTSCAN_TMP=$(mktemp -d)
trap 'rm -rf "$RUSTSCAN_TMP"' EXIT

RUSTSCAN_URL="https://github.com/bee-san/RustScan/releases/latest/download/rustscan.deb.zip"

if wget -q --show-progress -O "$RUSTSCAN_TMP/rustscan.deb.zip" "$RUSTSCAN_URL"; then
    unzip -o "$RUSTSCAN_TMP/rustscan.deb.zip" -d "$RUSTSCAN_TMP/"

    # The zip ships multiple debs (amd64, arm64, etc.). Pick the one for this box.
    ARCH=$(dpkg --print-architecture)
    DEB=$(find "$RUSTSCAN_TMP" -name "rustscan_*_${ARCH}.deb" -print -quit)

    if [ -z "$DEB" ]; then
        warn "No rustscan .deb matched arch '$ARCH'. Available files:"
        find "$RUSTSCAN_TMP" -name "*.deb"
        # Fall back to first .deb so the user at least gets something installable
        DEB=$(find "$RUSTSCAN_TMP" -name "rustscan_*.deb" -print -quit)
    fi

    if [ -n "$DEB" ]; then
        echo "    Installing: $(basename "$DEB")"
        $SUDO dpkg -i "$DEB" || $SUDO apt-get install -f -y
    else
        warn "No .deb found inside the zip; skipping RustScan."
    fi
else
    warn "Could not download RustScan zip; skipping."
fi

# ---- Ligolo-ng (latest release) ---------------------------------------------
# Asset names embed the version (e.g. ligolo-ng_agent_0.8.3_linux_amd64.tar.gz),
# so resolve the latest tag via curl -I on the /releases/latest redirect.
# Stages all three binaries under /opt/ligolo-ng so the Win/Linux agents are
# ready to copy to targets, and symlinks the proxy onto $PATH.

log "Installing latest Ligolo-ng (linux proxy + linux/windows agents)..."
LIGOLO_TMP=$(mktemp -d)
trap 'rm -rf "$RUSTSCAN_TMP" "$LIGOLO_TMP"' EXIT

# Follow the /releases/latest redirect and pull the tag (e.g. v0.8.3) off the end
LIGOLO_TAG=$(curl -sLI -o /dev/null -w '%{url_effective}' \
    https://github.com/nicocha30/ligolo-ng/releases/latest \
    | sed -E 's|.*/tag/||; s|/$||')

if [ -z "$LIGOLO_TAG" ] || [ "${LIGOLO_TAG#v}" = "$LIGOLO_TAG" ]; then
    warn "Could not resolve Ligolo-ng latest tag (got '$LIGOLO_TAG'); skipping."
else
    LIGOLO_VER="${LIGOLO_TAG#v}"   # strip leading 'v'
    LIGOLO_BASE="https://github.com/nicocha30/ligolo-ng/releases/download/${LIGOLO_TAG}"

    LINUX_PROXY="ligolo-ng_proxy_${LIGOLO_VER}_linux_amd64.tar.gz"
    LINUX_AGENT="ligolo-ng_agent_${LIGOLO_VER}_linux_amd64.tar.gz"
    WIN_AGENT="ligolo-ng_agent_${LIGOLO_VER}_windows_amd64.zip"

    echo "    Latest tag: $LIGOLO_TAG"

    cd "$LIGOLO_TMP"
    for asset in "$LINUX_PROXY" "$LINUX_AGENT" "$WIN_AGENT"; do
        echo "    Fetching $asset"
        wget -q --show-progress -O "$asset" "${LIGOLO_BASE}/${asset}"
    done

    # Stage everything under /opt/ligolo-ng
    $SUDO mkdir -p /opt/ligolo-ng/agents/linux /opt/ligolo-ng/agents/windows

    # Linux proxy → /opt/ligolo-ng/proxy + symlink onto PATH
    tar -xzf "$LINUX_PROXY"
    $SUDO install -m 755 proxy /opt/ligolo-ng/proxy
    $SUDO ln -sf /opt/ligolo-ng/proxy /usr/local/bin/ligolo-proxy

    # Linux agent → /opt/ligolo-ng/agents/linux/agent
    rm -f agent
    tar -xzf "$LINUX_AGENT"
    $SUDO install -m 755 agent /opt/ligolo-ng/agents/linux/agent

    # Windows agent → /opt/ligolo-ng/agents/windows/agent.exe
    unzip -o "$WIN_AGENT" >/dev/null
    $SUDO install -m 755 agent.exe /opt/ligolo-ng/agents/windows/agent.exe

    cd "$SCRIPT_DIR"

    echo "    Installed:"
    echo "      Proxy:         /opt/ligolo-ng/proxy  (run as 'ligolo-proxy')"
    echo "      Linux agent:   /opt/ligolo-ng/agents/linux/agent"
    echo "      Windows agent: /opt/ligolo-ng/agents/windows/agent.exe"
fi

# ---- update-toolkit (update script + systemd timer) -------------------------
# Manages updates for tools that don't come from apt:
#   - CyberChef  : checks latest GitHub release, downloads only if newer
#   - HackTricks : git pull both repos, docker restart only if new commits landed
#
# Installed at /usr/local/bin/update-toolkit (run manually: sudo update-toolkit)
# Systemd timer runs it weekly and persists the last-run time across reboots.

log "Installing update-toolkit script and systemd timer..."

$SUDO tee /usr/local/bin/update-toolkit > /dev/null << 'UPDATE_SCRIPT'
#!/bin/bash
# update-toolkit — update all non-apt tools
# Run manually: sudo update-toolkit
# Run automatically: weekly systemd timer (update-toolkit.timer)
#
# Tools managed:
#   apt upgrade  : handles gedit, sublime, feroxbuster, netexec, sstimap,
#                  chisel, golang, docker, krb5, ntpdate, ruby, seclists, etc.
#   THIS SCRIPT  : everything else (see sections below)

set -euo pipefail

log()  { printf '\n[*] %s\n' "$*"; }
ok()   { printf '    [ok]      %s\n' "$*"; }
skip() { printf '    [skip]    %s\n' "$*"; }
upd()  { printf '    [update]  %s\n' "$*"; }
warn() { printf '\n[!] %s\n' "$*" >&2; }

# ---- Config / state ---------------------------------------------------------
CONFIG_FILE="/opt/.toolkit-config"
VERSIONS_FILE="/opt/.toolkit-versions"

if [ ! -f "$CONFIG_FILE" ]; then
    warn "$CONFIG_FILE not found — run setup.sh first."; exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

TOOLKIT_PATH="${TOOLKIT_PATH:-$HOME/Toolkit}"
WIN_AD="$TOOLKIT_PATH/Windows/AD"
WIN_EXES="$TOOLKIT_PATH/Windows/EXEs"
WIN_ROOT="$TOOLKIT_PATH/Windows"
LIN_TOOLS="$TOOLKIT_PATH/LinuxTools"

touch "$VERSIONS_FILE"

# ---- Helpers ----------------------------------------------------------------
gh_latest_tag() {
    curl -sLI -o /dev/null -w '%{url_effective}' \
        "https://github.com/$1/releases/latest" \
        | sed -E 's|.*/tag/||; s|/$||'
}

get_ver() { grep "^${1}=" "$VERSIONS_FILE" 2>/dev/null | cut -d= -f2 || echo "none"; }
set_ver() {
    if grep -q "^${1}=" "$VERSIONS_FILE" 2>/dev/null; then
        sed -i "s|^${1}=.*|${1}=${2}|" "$VERSIONS_FILE"
    else
        echo "${1}=${2}" >> "$VERSIONS_FILE"
    fi
}

# Returns 0 (update needed, LATEST_TAG+LATEST_VER set) or 1 (already current)
needs_update() {
    local key="$1" repo="$2"
    LATEST_TAG=$(gh_latest_tag "$repo")
    LATEST_VER="${LATEST_TAG#v}"
    local stored; stored=$(get_ver "$key")
    if [ "$LATEST_TAG" = "$stored" ]; then
        skip "$key $LATEST_TAG"; return 1
    fi
    upd "$key: $stored → $LATEST_TAG"; return 0
}

# Always download — for raw GitHub master-branch files (no versioning)
force_fetch() {
    local url="$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    if wget -q -O "${dest}.tmp" "$url"; then
        mv "${dest}.tmp" "$dest"
        ok "$(basename "$dest")"
    else
        rm -f "${dest}.tmp"
        warn "FAIL: $(basename "$dest")  ($url)"
    fi
}

# ---- 1. pipx tools ----------------------------------------------------------
log "Upgrading pipx tools..."
# upgrade-all handles PyPI-sourced packages (ldapsearchad, ldeep, bloodyAD)
pipx upgrade-all --quiet 2>/dev/null || true
# Git-sourced packages (wenum, gopherus) need reinstall to pick up new commits
for pkg in wenum gopherus; do
    pipx reinstall "$pkg" --quiet 2>/dev/null \
        && ok "$pkg (git reinstall)" \
        || warn "$pkg reinstall failed"
done

# ---- 2. Python system libraries ---------------------------------------------
log "Upgrading Python system libraries..."
pip install --break-system-packages --upgrade --quiet \
    python-ldap 'pyasn1>=0.4.5' 'pyasn1-modules>=0.2.5' \
    pylnk3 ldap3 pycryptodome gssapi \
    && ok "pip libraries"

# ---- 3. /opt git clones (XSStrike, XXEinjector) ----------------------------
log "Updating /opt git clones..."
for repo in XSStrike XXEinjector; do
    if [ -d "/opt/$repo" ]; then
        OUT=$(git -C "/opt/$repo" pull --ff-only --quiet 2>&1)
        echo "$OUT" | grep -q "Already up to date" && skip "$repo" || ok "$repo pulled"
    else
        warn "/opt/$repo not found — run setup.sh"
    fi
done
# Re-run XSStrike deps in case requirements.txt changed
[ -f /opt/XSStrike/requirements.txt ] && \
    pip install --break-system-packages --quiet -r /opt/XSStrike/requirements.txt

# ---- 4. GitHub release assets (version-checked) ----------------------------
log "Checking GitHub release assets..."

# RustScan
if needs_update "rustscan" "bee-san/RustScan"; then
    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' RETURN
    ARCH=$(dpkg --print-architecture)
    wget -q -O "$TMP/rustscan.deb.zip" \
        "https://github.com/bee-san/RustScan/releases/latest/download/rustscan.deb.zip"
    unzip -o "$TMP/rustscan.deb.zip" -d "$TMP/" >/dev/null
    DEB=$(find "$TMP" -name "rustscan_*_${ARCH}.deb" -print -quit)
    [ -z "$DEB" ] && DEB=$(find "$TMP" -name "rustscan_*.deb" -print -quit)
    if [ -n "$DEB" ]; then
        dpkg -i "$DEB" >/dev/null 2>&1 || apt-get install -f -y >/dev/null
        set_ver "rustscan" "$LATEST_TAG"
        ok "RustScan $LATEST_TAG"
    fi
    trap - RETURN; rm -rf "$TMP"
fi

# Ligolo-ng
if needs_update "ligolo-ng" "nicocha30/ligolo-ng"; then
    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' RETURN
    BASE="https://github.com/nicocha30/ligolo-ng/releases/download/${LATEST_TAG}"
    wget -q -O "$TMP/proxy.tar.gz"       "${BASE}/ligolo-ng_proxy_${LATEST_VER}_linux_amd64.tar.gz"
    wget -q -O "$TMP/agent_linux.tar.gz" "${BASE}/ligolo-ng_agent_${LATEST_VER}_linux_amd64.tar.gz"
    wget -q -O "$TMP/agent_win.zip"      "${BASE}/ligolo-ng_agent_${LATEST_VER}_windows_amd64.zip"
    cd "$TMP"
    tar -xzf proxy.tar.gz       && install -m 755 proxy     /opt/ligolo-ng/proxy
    rm -f agent
    tar -xzf agent_linux.tar.gz && install -m 755 agent     /opt/ligolo-ng/agents/linux/agent
    unzip -o agent_win.zip >/dev/null
    install -m 755 agent.exe /opt/ligolo-ng/agents/windows/agent.exe
    cp /opt/ligolo-ng/agents/windows/agent.exe "$WIN_AD/agent.exe"   2>/dev/null || true
    cp /opt/ligolo-ng/agents/windows/agent.exe "$WIN_EXES/agent.exe" 2>/dev/null || true
    cp /opt/ligolo-ng/proxy                    "$WIN_AD/proxy"        2>/dev/null || true
    cd - >/dev/null
    trap - RETURN; rm -rf "$TMP"
    set_ver "ligolo-ng" "$LATEST_TAG"
    ok "Ligolo-ng $LATEST_TAG"
fi

# peass-ng (winpeas + linpeas)
if needs_update "peass-ng" "peass-ng/PEASS-ng"; then
    BASE="https://github.com/peass-ng/PEASS-ng/releases/download/${LATEST_TAG}"
    force_fetch "$BASE/winPEASx64.exe" "$WIN_ROOT/winPEASx64.exe"
    force_fetch "$BASE/linpeas.sh"     "$LIN_TOOLS/linpeas.sh"
    chmod +x "$LIN_TOOLS/linpeas.sh" 2>/dev/null || true
    set_ver "peass-ng" "$LATEST_TAG"
fi

# kerbrute
if needs_update "kerbrute" "ropnop/kerbrute"; then
    BASE="https://github.com/ropnop/kerbrute/releases/download/${LATEST_TAG}"
    force_fetch "$BASE/kerbrute_linux_amd64"       "$WIN_AD/kerbrute_linux_amd64"
    force_fetch "$BASE/kerbrute_darwin_amd64"      "$WIN_AD/kerbrute_darwin_amd64"
    force_fetch "$BASE/kerbrute_windows_amd64.exe" "$WIN_AD/kerbrute_windows_amd64.exe"
    chmod +x "$WIN_AD/kerbrute_linux_amd64" "$WIN_AD/kerbrute_darwin_amd64" 2>/dev/null || true
    cp "$WIN_AD/kerbrute_linux_amd64"        "$WIN_ROOT/kerbrute"     2>/dev/null || true
    cp "$WIN_AD/kerbrute_windows_amd64.exe"  "$WIN_ROOT/kerbrute.exe" 2>/dev/null || true
    set_ver "kerbrute" "$LATEST_TAG"
fi

# windapsearch Go binaries
if needs_update "windapsearch" "ropnop/go-windapsearch"; then
    BASE="https://github.com/ropnop/go-windapsearch/releases/download/${LATEST_TAG}"
    force_fetch "$BASE/windapsearch-linux-amd64"       "$WIN_AD/windapsearch-linux-amd64"
    force_fetch "$BASE/windapsearch-darwin-amd64"      "$WIN_AD/windapsearch-darwin-amd64"
    force_fetch "$BASE/windapsearch-windows-amd64.exe" "$WIN_AD/windapsearch-windows-amd64.exe"
    chmod +x "$WIN_AD/windapsearch-linux-amd64" "$WIN_AD/windapsearch-darwin-amd64" 2>/dev/null || true
    set_ver "windapsearch" "$LATEST_TAG"
fi

# SharpHound
if needs_update "sharphound" "SpecterOps/SharpHound"; then
    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' RETURN
    wget -q -O "$TMP/sh.zip" \
        "https://github.com/SpecterOps/SharpHound/releases/download/${LATEST_TAG}/sharphound-${LATEST_TAG}.zip"
    unzip -o -j "$TMP/sh.zip" "SharpHound.exe" "SharpHound.ps1" -d "$WIN_AD/" >/dev/null 2>&1
    cp "$WIN_AD/SharpHound.exe" "$WIN_ROOT/SharpHound.exe" 2>/dev/null || true
    cp "$WIN_AD/SharpHound.ps1" "$WIN_ROOT/SharpHound.ps1" 2>/dev/null || true
    trap - RETURN; rm -rf "$TMP"
    set_ver "sharphound" "$LATEST_TAG"
fi

# Snaffler
if needs_update "snaffler" "SnaffCon/Snaffler"; then
    force_fetch \
        "https://github.com/SnaffCon/Snaffler/releases/download/${LATEST_TAG}/Snaffler.exe" \
        "$WIN_AD/Snaffler.exe"
    set_ver "snaffler" "$LATEST_TAG"
fi

# mimikatz
if needs_update "mimikatz" "gentilkiwi/mimikatz"; then
    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' RETURN
    wget -q -O "$TMP/mimi.zip" \
        "https://github.com/gentilkiwi/mimikatz/releases/download/${LATEST_TAG}/mimikatz_trunk.zip"
    unzip -o -j "$TMP/mimi.zip" "x64/mimikatz.exe" -d "$WIN_AD/" >/dev/null 2>&1
    trap - RETURN; rm -rf "$TMP"
    set_ver "mimikatz" "$LATEST_TAG"
fi

# pspy64
if needs_update "pspy" "DominicBreuker/pspy"; then
    force_fetch \
        "https://github.com/DominicBreuker/pspy/releases/download/${LATEST_TAG}/pspy64" \
        "$WIN_ROOT/pspy64"
    chmod +x "$WIN_ROOT/pspy64" 2>/dev/null || true
    set_ver "pspy" "$LATEST_TAG"
fi

# GodPotato
if needs_update "godpotato" "BeichenDream/GodPotato"; then
    for net in NET2 NET35 NET4; do
        force_fetch \
            "https://github.com/BeichenDream/GodPotato/releases/download/${LATEST_TAG}/GodPotato-${net}.exe" \
            "$WIN_EXES/GodPotato/GodPotato-${net}.exe"
    done
    set_ver "godpotato" "$LATEST_TAG"
fi

# PrintSpoofer
if needs_update "printspoofer" "itm4n/PrintSpoofer"; then
    BASE="https://github.com/itm4n/PrintSpoofer/releases/download/${LATEST_TAG}"
    force_fetch "$BASE/PrintSpoofer64.exe" "$WIN_EXES/PrintSpoofer64.exe"
    force_fetch "$BASE/PrintSpoofer32.exe" "$WIN_EXES/printspoofer32.exe"
    set_ver "printspoofer" "$LATEST_TAG"
fi

# JuicyPotato
if needs_update "juicypotato" "ohpe/juicy-potato"; then
    force_fetch \
        "https://github.com/ohpe/juicy-potato/releases/download/${LATEST_TAG}/JuicyPotato.exe" \
        "$WIN_EXES/JuicyPotato.exe"
    set_ver "juicypotato" "$LATEST_TAG"
fi

# aquatone
if needs_update "aquatone" "michenriksen/aquatone"; then
    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' RETURN
    wget -q -O "$TMP/aq.zip" \
        "https://github.com/michenriksen/aquatone/releases/download/${LATEST_TAG}/aquatone_linux_amd64_${LATEST_VER}.zip"
    unzip -o -j "$TMP/aq.zip" "aquatone" -d "$WIN_AD/" >/dev/null 2>&1
    chmod +x "$WIN_AD/aquatone" 2>/dev/null || true
    trap - RETURN; rm -rf "$TMP"
    set_ver "aquatone" "$LATEST_TAG"
fi

# azurehound
if needs_update "azurehound" "SpecterOps/AzureHound"; then
    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' RETURN
    wget -q -O "$TMP/az.zip" \
        "https://github.com/SpecterOps/AzureHound/releases/download/${LATEST_TAG}/AzureHound_${LATEST_TAG}_linux_amd64.zip"
    unzip -o -j "$TMP/az.zip" "azurehound" -d "$WIN_AD/" >/dev/null 2>&1
    chmod +x "$WIN_AD/azurehound" 2>/dev/null || true
    trap - RETURN; rm -rf "$TMP"
    set_ver "azurehound" "$LATEST_TAG"
fi

# KvcForensic — release tag is the literal string "latest" (no version to diff)
# Always re-download; 7z extract overwrites in place.
log "Refreshing KvcForensic (Linux)..."
TMP=$(mktemp -d)
if wget -q -O "$TMP/KvcForensic_Linux.7z" \
    "https://github.com/wesmar/KvcForensic/releases/download/latest/KvcForensic_Linux.7z"; then
    7z x -y -p"github.com" "$TMP/KvcForensic_Linux.7z" -o"$LIN_TOOLS/KvcForensic" >/dev/null 2>&1 \
        && chmod +x "$LIN_TOOLS/KvcForensic/KvcForensic" \
                    "$LIN_TOOLS/KvcForensic/KvcForensic_static" 2>/dev/null \
        && ok "KvcForensic refreshed" \
        || warn "KvcForensic extract failed"
fi
rm -rf "$TMP"

# ---- 5. Raw GitHub files (always re-fetch — tracks master/main branch) ------
log "Refreshing raw GitHub files..."

# PowerShell scripts (PowerSploit / Empire / standalone repos)
PS_BASE="https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master"
force_fetch "$PS_BASE/Recon/PowerView.ps1"  "$WIN_AD/PowerView.ps1"
force_fetch "$PS_BASE/Privesc/PowerUp.ps1"  "$WIN_AD/PowerUp.ps1"
cp "$WIN_AD/PowerUp.ps1" "$WIN_EXES/PowerUp.ps1" 2>/dev/null || true

force_fetch "https://raw.githubusercontent.com/EmpireProject/Empire/master/data/module_source/credentials/Invoke-Kerberoast.ps1" "$WIN_AD/Invoke-Kerberoast.ps1"
force_fetch "https://raw.githubusercontent.com/61106960/adPEAS/main/adPEAS.ps1"                              "$WIN_AD/adPEAS.ps1"
force_fetch "https://raw.githubusercontent.com/dafthack/DomainPasswordSpray/master/DomainPasswordSpray.ps1" "$WIN_AD/DomainPasswordSpray.ps1"
force_fetch "https://raw.githubusercontent.com/Kevin-Robertson/Powermad/master/Powermad.ps1"                "$WIN_AD/Powermad.ps1"
force_fetch "https://raw.githubusercontent.com/NetSPI/PowerUpSQL/master/PowerUpSQL.ps1"                     "$WIN_AD/PowerUpSQL.ps1"
force_fetch "https://raw.githubusercontent.com/antonioCoco/RunasCs/master/Invoke-RunasCs.ps1"               "$WIN_AD/Invoke-RunasCs.ps1"
force_fetch "https://raw.githubusercontent.com/ropnop/windapsearch/master/windapsearch.py"                  "$WIN_AD/windapsearch.py"
chmod +x "$WIN_AD/windapsearch.py" 2>/dev/null || true

# SharpCollection — raw master branch, always latest Flangvik build
SC="https://raw.githubusercontent.com/Flangvik/SharpCollection/master/NetFramework_4.7_x64"
for tool in Rubeus.exe Certify.exe SharpUp.exe SharpGPOAbuse.exe \
            SharpSCCM.exe SharpShares.exe KrbRelayUp.exe GMSAPasswordReader.exe; do
    force_fetch "$SC/$tool" "$WIN_AD/$tool"
done

# SpoolSample (jakobfriedl precompiled — master branch)
force_fetch \
    "https://github.com/jakobfriedl/precompiled-binaries/raw/main/LateralMovement/SpoolSample.exe" \
    "$WIN_AD/SpoolSample.exe"

# Linux enum scripts
force_fetch "https://raw.githubusercontent.com/diego-treitos/linux-smart-enumeration/master/lse.sh"       "$LIN_TOOLS/lse.sh"
force_fetch "https://raw.githubusercontent.com/pentestmonkey/unix-privesc-check/1_x/unix-privesc-check"  "$LIN_TOOLS/unix-privesc-check"
force_fetch "https://raw.githubusercontent.com/xct/hashgrab/main/hashgrab.py"                             "$LIN_TOOLS/hashgrab.py"
chmod +x "$LIN_TOOLS/lse.sh" "$LIN_TOOLS/unix-privesc-check" "$LIN_TOOLS/hashgrab.py" 2>/dev/null || true

# ---- 6. CyberChef -----------------------------------------------------------
log "Checking CyberChef..."
CC_LATEST=$(curl -sLI -o /dev/null -w '%{url_effective}' \
    https://github.com/gchq/CyberChef/releases/latest \
    | sed -E 's|.*/tag/||; s|/$||')
CC_LATEST_VER="${CC_LATEST#v}"

if [ -L /opt/CyberChef/CyberChef.html ]; then
    CC_INSTALLED=$(cat "$CC_VER_FILE" 2>/dev/null || echo "none")
else
    CC_INSTALLED="none"
fi

# ---- 6. CyberChef -----------------------------------------------------------
log "Checking CyberChef..."
CC_LATEST=$(curl -sLI -o /dev/null -w '%{url_effective}' \
    https://github.com/gchq/CyberChef/releases/latest \
    | sed -E 's|.*/tag/||; s|/$||')
CC_LATEST_VER="${CC_LATEST#v}"

# Version stored as the tag (e.g. v11.4.0) in a plain file
CC_VER_FILE="/opt/CyberChef/.installed_version"
CC_INSTALLED=$(cat "$CC_VER_FILE" 2>/dev/null || echo "none")

if [ "$CC_LATEST_VER" = "$CC_INSTALLED" ]; then
    ok "CyberChef v${CC_LATEST_VER}"
else
    upd "CyberChef ${CC_INSTALLED} → ${CC_LATEST_VER}"
    CC_ZIP="CyberChef_v${CC_LATEST_VER}.zip"
    TMP=$(mktemp -d)
    if wget -q -O "$TMP/${CC_ZIP}" \
        "https://github.com/gchq/CyberChef/releases/download/${CC_LATEST}/${CC_ZIP}"; then
        # Clear old content, extract full zip (v10+ ships multiple modules, not one .html)
        find /opt/CyberChef -mindepth 1 ! -name '.installed_version' -delete 2>/dev/null || true
        unzip -o "$TMP/${CC_ZIP}" -d /opt/CyberChef/ >/dev/null
        # Symlink entry point — works for both old single-file and new modular format
        CC_INDEX=$(find /opt/CyberChef -maxdepth 3 -name "*.html" -not -name 'index.html' -not -name '.installed_version' -print -quit)
        if [ -n "$CC_INDEX" ]; then
            ln -sf "$CC_INDEX" /opt/CyberChef/CyberChef.html
            echo "$CC_LATEST_VER" > "$CC_VER_FILE"
            # Refresh the index.html redirect for the web service
            CC_INDEX_REL="${CC_INDEX#/opt/CyberChef/}"
            echo "<meta http-equiv='refresh' content='0; url=${CC_INDEX_REL}'>" \
                > /opt/CyberChef/index.html
            systemctl restart cyberchef.service 2>/dev/null || true
            ok "CyberChef updated to v${CC_LATEST_VER}"
        else
            warn "CyberChef: no .html entry point found after extraction"
        fi
    else
        warn "CyberChef download failed"
    fi
    rm -rf "$TMP"
fi

# ---- 7. HackTricks (git pull + Docker restart if changed) -------------------
log "Updating HackTricks..."

update_hacktricks() {
    local repo="$1" container="$2" port="$3"
    if [ ! -d "$repo" ]; then
        warn "$repo not found — run setup.sh first"; return
    fi
    PULL=$(git -C "$repo" pull --ff-only 2>&1)
    if echo "$PULL" | grep -q "Already up to date"; then
        ok "$repo is current"
    else
        ok "$repo updated"
        if docker inspect "$container" >/dev/null 2>&1; then
            docker restart "$container" >/dev/null \
                && ok "$container restarted (http://localhost:${port})" \
                || warn "Failed to restart $container"
        else
            warn "$container container not found — run setup.sh to create it"
        fi
    fi
}

update_hacktricks /opt/hacktricks       hacktricks       3337
update_hacktricks /opt/hacktricks-cloud hacktricks-cloud 3338

log "update-toolkit complete."
UPDATE_SCRIPT

$SUDO chmod +x /usr/local/bin/update-toolkit

# Systemd service unit
$SUDO tee /etc/systemd/system/update-toolkit.service > /dev/null << 'SERVICE'
[Unit]
Description=Update CyberChef and HackTricks
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-toolkit
StandardOutput=journal
StandardError=journal
# Don't fail the timer if a transient network error occurs
SuccessExitStatus=0 1
SERVICE

# Systemd timer unit — runs weekly, Persistent=true means it catches up if the
# machine was off when the timer was due (e.g. VM not running on Sunday night)
$SUDO tee /etc/systemd/system/update-toolkit.timer > /dev/null << 'TIMER'
[Unit]
Description=Weekly update for CyberChef and HackTricks

[Timer]
OnCalendar=weekly
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
TIMER

# Enable and start the timer
$SUDO systemctl daemon-reload
$SUDO systemctl enable --now update-toolkit.timer 2>/dev/null \
    && log "update-toolkit timer enabled (weekly, persistent)" \
    || warn "Could not enable systemd timer (non-systemd env?)"

# CyberChef v10+ ships a zip of modules rather than a single .html file.
# Extract the full zip; find the HTML entry point dynamically.
log "Installing CyberChef (offline)..."
CC_TAG=$(gh_latest_tag "gchq/CyberChef")
if [ -n "$CC_TAG" ]; then
    CC_VER="${CC_TAG#v}"
    CC_ZIP="CyberChef_v${CC_VER}.zip"
    if [ ! -L /opt/CyberChef/CyberChef.html ]; then
        $SUDO mkdir -p /opt/CyberChef
        if wget -q --show-progress -O "/tmp/${CC_ZIP}" \
            "https://github.com/gchq/CyberChef/releases/download/${CC_TAG}/${CC_ZIP}"; then
            $SUDO unzip -o "/tmp/${CC_ZIP}" -d /opt/CyberChef/ >/dev/null \
                || warn "CyberChef unzip failed"
            # Find the HTML entry point (works for both old single-file and new modular format)
            CC_INDEX=$($SUDO find /opt/CyberChef -maxdepth 3 -name "*.html" -print -quit)
            if [ -n "$CC_INDEX" ]; then
                $SUDO ln -sf "$CC_INDEX" /opt/CyberChef/CyberChef.html
                echo "$CC_VER" | $SUDO tee /opt/CyberChef/.installed_version > /dev/null
                # index.html redirect → Python http.server serves it as default doc
                CC_INDEX_REL="${CC_INDEX#/opt/CyberChef/}"
                echo "<meta http-equiv='refresh' content='0; url=${CC_INDEX_REL}'>" \
                    | $SUDO tee /opt/CyberChef/index.html > /dev/null
                echo "    [ok] CyberChef v${CC_VER} → $CC_INDEX"
            else
                warn "CyberChef: no .html entry point found in zip"
            fi
            rm -f "/tmp/${CC_ZIP}"
        else
            warn "CyberChef download failed"
        fi
    else
        echo "    [skip] CyberChef already installed"
    fi
else
    warn "Could not resolve CyberChef latest tag; skipping."
fi

# ---- CyberChef persistent web service ---------------------------------------
# Serves /opt/CyberChef/ via Python http.server on port 3339.
# index.html at the root auto-redirects to the versioned entry point so
# http://localhost:3339 works as a stable URL regardless of version.
log "Setting up CyberChef web service (port 3339)..."
$SUDO tee /etc/systemd/system/cyberchef.service > /dev/null << 'CCSERVICE'
[Unit]
Description=CyberChef offline web server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 -m http.server 3339 --directory /opt/CyberChef
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
CCSERVICE

$SUDO systemctl daemon-reload
$SUDO systemctl enable --now cyberchef.service 2>/dev/null \
    && log "CyberChef service enabled → http://localhost:3339" \
    || warn "Could not enable cyberchef.service (non-systemd env?)"

# ---- Firefox bookmarks (enterprise policy) ----------------------------------
# Uses Firefox's built-in policy engine — no profile hacking needed.
# Bookmarks appear in the toolbar on next Firefox launch.
# Both policy paths are written for compatibility across Kali/Debian variants.
log "Adding Firefox bookmarks (HackTricks + CyberChef)..."

FF_POLICY='{
  "policies": {
    "Bookmarks": [
      {
        "Title": "HackTricks",
        "URL": "http://localhost:3337",
        "Placement": "toolbar"
      },
      {
        "Title": "HackTricks Cloud",
        "URL": "http://localhost:3338",
        "Placement": "toolbar"
      },
      {
        "Title": "CyberChef",
        "URL": "http://localhost:3339",
        "Placement": "toolbar"
      }
    ]
  }
}'

# Primary path: firefox-esr install dir (works on all Linux)
for FF_DIR in /usr/lib/firefox-esr /usr/lib/firefox; do
    if [ -d "$FF_DIR" ]; then
        $SUDO mkdir -p "$FF_DIR/distribution"
        echo "$FF_POLICY" | $SUDO tee "$FF_DIR/distribution/policies.json" > /dev/null \
            && echo "    [ok] $FF_DIR/distribution/policies.json"
    fi
done

# Fallback path: /etc/firefox/policies (supported since Firefox 78)
$SUDO mkdir -p /etc/firefox/policies
echo "$FF_POLICY" | $SUDO tee /etc/firefox/policies/policies.json > /dev/null \
    && echo "    [ok] /etc/firefox/policies/policies.json"
#
# Ports:
#   http://localhost:3337 — HackTricks (main)
#   http://localhost:3338 — HackTricks Cloud
#
# Re-running this script:
#   - git pull on both repos (picks up new content)
#   - docker restart on both containers (reloads updated volume content)
#
HT_IMAGE="ghcr.io/hacktricks-wiki/hacktricks-cloud/translator-image"

log "Setting up HackTricks (full build, persistent)..."

# Clone / update content repos
if [ ! -d /opt/hacktricks ]; then
    $SUDO git clone --depth 1 https://github.com/HackTricks-wiki/hacktricks /opt/hacktricks \
        || warn "HackTricks clone failed"
else
    $SUDO git -C /opt/hacktricks pull --ff-only >/dev/null 2>&1 \
        && echo "    [updated] /opt/hacktricks" \
        || warn "/opt/hacktricks pull failed (continuing)"
fi

if [ ! -d /opt/hacktricks-cloud ]; then
    $SUDO git clone --depth 1 https://github.com/HackTricks-wiki/hacktricks-cloud /opt/hacktricks-cloud \
        || warn "HackTricks Cloud clone failed"
else
    $SUDO git -C /opt/hacktricks-cloud pull --ff-only >/dev/null 2>&1 \
        && echo "    [updated] /opt/hacktricks-cloud" \
        || warn "/opt/hacktricks-cloud pull failed (continuing)"
fi

# Pull the Docker image once (translator-image includes mdbook + preprocessors)
log "Pulling HackTricks Docker image (first run takes a few minutes)..."
$SUDO docker pull "$HT_IMAGE" || warn "Docker image pull failed — containers may not start"

# Helper: launch or restart a HackTricks container
# Usage: hacktricks_container <name> <host_port> <volume_path>
hacktricks_container() {
    local name="$1" port="$2" vol="$3"
    if $SUDO docker inspect "$name" >/dev/null 2>&1; then
        # Container exists — restart so it picks up updated volume content
        $SUDO docker restart "$name" >/dev/null \
            && echo "    [restarted] $name at http://localhost:${port}" \
            || warn "  Failed to restart $name"
    else
        $SUDO docker run -d \
            --name "$name" \
            --restart unless-stopped \
            --platform linux/amd64 \
            -p "${port}:3000" \
            -v "${vol}:/app" \
            "$HT_IMAGE" \
            bash -c "cd /app \
                && git config --global --add safe.directory /app \
                && MDBOOK_PREPROCESSOR__HACKTRICKS__ENV=dev mdbook serve --hostname 0.0.0.0" \
            && echo "    [started]  $name at http://localhost:${port} (building — allow ~5 min)" \
            || warn "  Failed to start $name"
    fi
}

hacktricks_container hacktricks       3337 /opt/hacktricks
hacktricks_container hacktricks-cloud 3338 /opt/hacktricks-cloud

# ---- Toolkit (Windows + Linux pentest tools) --------------------------------
# Stages binaries/scripts under ~/Toolkit so they're ready to serve to targets
# (HTTP server, SMB share, whatever). Idempotent: existing files are skipped.
# A failed download warns but doesn't abort the whole script.

TOOLKIT="$HOME/Toolkit"
WIN_ROOT="$TOOLKIT/Windows"
WIN_AD="$TOOLKIT/Windows/AD"
WIN_EXES="$TOOLKIT/Windows/EXEs"
LIN_TOOLS="$TOOLKIT/LinuxTools"

mkdir -p "$WIN_AD" "$WIN_EXES/GodPotato" "$WIN_EXES/Procmon" "$LIN_TOOLS"

# Write config so update-toolkit can find the toolkit path when run as root
$SUDO tee /opt/.toolkit-config > /dev/null << TKCFG
TOOLKIT_PATH=$TOOLKIT
TKCFG

# Relax strict mode for this section — individual download failures are OK
set +e

fetch() {
    # fetch <url> <dest> — skip if dest already exists
    local url="$1" dest="$2"
    if [ -e "$dest" ]; then
        printf '    [skip] %s\n' "${dest#$TOOLKIT/}"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    if wget -q -O "$dest.tmp" "$url"; then
        mv "$dest.tmp" "$dest"
        printf '    [ok]   %s\n' "${dest#$TOOLKIT/}"
    else
        rm -f "$dest.tmp"
        printf '    [FAIL] %s  (%s)\n' "${dest#$TOOLKIT/}" "$url" >&2
    fi
}

log "Staging toolkit at $TOOLKIT ..."

# ---- PowerShell scripts (raw GitHub) ----------------------------------------
echo "  PowerShell scripts..."
PS_BASE="https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master"
fetch "$PS_BASE/Recon/PowerView.ps1"             "$WIN_AD/PowerView.ps1"
fetch "$PS_BASE/Privesc/PowerUp.ps1"             "$WIN_AD/PowerUp.ps1"
# Get-SPN.ps1 and Invoke-Kerberoast aren't standalone files in PowerSploit —
# they're functions inside PowerView.ps1. Empire still ships the standalone
# Invoke-Kerberoast.ps1, which is what most write-ups link to.
fetch "https://raw.githubusercontent.com/EmpireProject/Empire/master/data/module_source/credentials/Invoke-Kerberoast.ps1" "$WIN_AD/Invoke-Kerberoast.ps1"
fetch "https://raw.githubusercontent.com/61106960/adPEAS/main/adPEAS.ps1"                              "$WIN_AD/adPEAS.ps1"
fetch "https://raw.githubusercontent.com/dafthack/DomainPasswordSpray/master/DomainPasswordSpray.ps1"  "$WIN_AD/DomainPasswordSpray.ps1"
fetch "https://raw.githubusercontent.com/Kevin-Robertson/Powermad/master/Powermad.ps1"                 "$WIN_AD/Powermad.ps1"
fetch "https://raw.githubusercontent.com/NetSPI/PowerUpSQL/master/PowerUpSQL.ps1"                      "$WIN_AD/PowerUpSQL.ps1"

# ---- Pre-compiled .NET tools (Flangvik's SharpCollection) -------------------
echo "  SharpCollection (pre-compiled .NET)..."
SC="https://raw.githubusercontent.com/Flangvik/SharpCollection/master/NetFramework_4.7_x64"
# Ghostpack-CompiledBinaries is a defensive fallback for GhostPack-family tools
# (Rubeus, Certify, SharpUp, ...) in case Flangvik ever drops the build.
# Note: SeManageVolumeExploit.exe and SpoolSample.exe are NOT in either — they
# come from dedicated sources below.
GP="https://raw.githubusercontent.com/r3motecontrol/Ghostpack-CompiledBinaries/master"
for tool in Rubeus.exe Certify.exe SharpUp.exe SharpGPOAbuse.exe \
            SharpSCCM.exe SharpShares.exe \
            KrbRelayUp.exe GMSAPasswordReader.exe; do
    fetch "$SC/$tool" "$WIN_AD/$tool"
    # If SharpCollection didn't deliver a usable file, try Ghostpack as backup
    # (only for the GhostPack-family tools it actually carries).
    if [ ! -s "$WIN_AD/$tool" ]; then
        case "$tool" in
            Rubeus.exe|Certify.exe|SharpUp.exe|SharpDPAPI.exe|SharpDump.exe|SafetyKatz.exe|Seatbelt.exe)
                echo "    [fallback] trying Ghostpack-CompiledBinaries for $tool"
                fetch "$GP/$tool" "$WIN_AD/$tool"
                ;;
        esac
    fi
done

# ---- SpoolSample (not in SharpCollection — use jakobfriedl's prebuilds) -----
echo "  SpoolSample..."
fetch "https://github.com/jakobfriedl/precompiled-binaries/raw/main/LateralMovement/SpoolSample.exe" "$WIN_AD/SpoolSample.exe"

# ---- SeManageVolumeExploit (CsEnox's own release, tag 'public') -------------
echo "  SeManageVolumeExploit..."
fetch "https://github.com/CsEnox/SeManageVolumeExploit/releases/download/public/SeManageVolumeExploit.exe" "$WIN_AD/SeManageVolumeExploit.exe"

# ---- RunasCs ----------------------------------------------------------------
# Invoke-RunasCs.ps1 lives in the master branch, not in release assets.
echo "  RunasCs..."
fetch "https://raw.githubusercontent.com/antonioCoco/RunasCs/master/Invoke-RunasCs.ps1" "$WIN_AD/Invoke-RunasCs.ps1"

# ---- kerbrute (multi-platform) ----------------------------------------------
echo "  kerbrute..."
TAG=$(gh_latest_tag "ropnop/kerbrute")
if [ -n "$TAG" ]; then
    KB="https://github.com/ropnop/kerbrute/releases/download/${TAG}"
    fetch "$KB/kerbrute_linux_amd64"       "$WIN_AD/kerbrute_linux_amd64"
    fetch "$KB/kerbrute_darwin_amd64"      "$WIN_AD/kerbrute_darwin_amd64"
    fetch "$KB/kerbrute_windows_amd64.exe" "$WIN_AD/kerbrute_windows_amd64.exe"
    chmod +x "$WIN_AD/kerbrute_linux_amd64" "$WIN_AD/kerbrute_darwin_amd64" 2>/dev/null
fi

# ---- windapsearch (multi-platform + Python) ---------------------------------
echo "  windapsearch..."
TAG=$(gh_latest_tag "ropnop/go-windapsearch")
if [ -n "$TAG" ]; then
    WP="https://github.com/ropnop/go-windapsearch/releases/download/${TAG}"
    fetch "$WP/windapsearch-linux-amd64"       "$WIN_AD/windapsearch-linux-amd64"
    fetch "$WP/windapsearch-darwin-amd64"      "$WIN_AD/windapsearch-darwin-amd64"
    fetch "$WP/windapsearch-windows-amd64.exe" "$WIN_AD/windapsearch-windows-amd64.exe"
    chmod +x "$WIN_AD/windapsearch-linux-amd64" "$WIN_AD/windapsearch-darwin-amd64" 2>/dev/null
fi
# Original Python windapsearch (ropnop/windapsearch) — useful when Python is
# available but the static binary isn't the right fit. Deps installed above.
fetch "https://raw.githubusercontent.com/ropnop/windapsearch/master/windapsearch.py" "$WIN_AD/windapsearch.py"
chmod +x "$WIN_AD/windapsearch.py" 2>/dev/null

# ---- ldapsearch-ad (yaap7) --------------------------------------------------
# Similar to windapsearch but supports NTLM hash auth (-H :NTLM) which is
# very handy in OSCP-style workflows when you have a hash but no cleartext pw.
# Installed via pipx — exposes 'ldapsearch-ad.py' globally on PATH.
echo "  ldapsearch-ad..."
if ! command -v ldapsearch-ad.py >/dev/null 2>&1; then
    pipx install ldapsearchad || warn "pipx install ldapsearchad failed"
fi

# ---- ldeep (franc-pentest) --------------------------------------------------
# In-depth LDAP enumeration — more thorough than windapsearch/ldapsearch-ad
# (auth policies, bitlocker keys, silos, delegations, SCCM, LAPS, etc.).
# Builds a native Kerberos extension (needs libkrb5-dev, installed above).
echo "  ldeep..."
if ! command -v ldeep >/dev/null 2>&1; then
    pipx install ldeep || warn "pipx install ldeep failed"
fi

# ---- bloodyAD (CravateRouge) ------------------------------------------------
# AD write-side privilege abuse — WriteOwner, WriteDACL, GenericAll, GenericWrite,
# AddSelf, shadow credentials, RBCD, DCsync, password change, gMSA read.
# Complements ldeep (which is read-only enumeration).
echo "  bloodyAD..."
if ! command -v bloodyAD >/dev/null 2>&1; then
    pipx install bloodyAD || warn "pipx install bloodyAD failed"
fi

# ---- wenum (WebFuzzForge fork of wfuzz) -------------------------------------
# Actively-maintained wfuzz fork. No PyPI release — installed from git.
# Exposes 'wenum' globally on PATH via pipx.
echo "  wenum..."
if ! command -v wenum >/dev/null 2>&1; then
    pipx install git+https://github.com/WebFuzzForge/wenum || warn "pipx install wenum failed"
fi

# ---- Gopherus (Esonhugh/Gopherus3 — Python 3 fork of tarunkant/Gopherus) ----
# The original tarunkant/Gopherus is unmaintained (Python 2, PR#18 open since
# 2022). Esonhugh/Gopherus3 is the active Python 3 refactor with argparse CLI
# and adds SMTP/expanded memcache modules. Exposes 'gopherus' on PATH.
echo "  gopherus (Gopherus3)..."
if ! command -v gopherus >/dev/null 2>&1; then
    pipx install git+https://github.com/Esonhugh/Gopherus3.git || warn "pipx install Gopherus3 failed"
fi

# ---- XSStrike (XSS scanner) -------------------------------------------------
# Full repo (imports from core/, db/, plugins/ — not single-file). Not on PyPI,
# so pipx is unsuitable. Cloned to /opt/XSStrike with a wrapper on PATH.
echo "  XSStrike..."
if [ ! -d /opt/XSStrike ]; then
    $SUDO git clone --depth 1 https://github.com/s0md3v/XSStrike /opt/XSStrike \
        && $SUDO pip install --break-system-packages -r /opt/XSStrike/requirements.txt >/dev/null \
        || warn "  XSStrike clone/install failed"
else
    $SUDO git -C /opt/XSStrike pull --ff-only >/dev/null 2>&1 || true
fi
# /usr/local/bin/xsstrike wrapper — invokes python on the repo's entry point
if [ ! -f /usr/local/bin/xsstrike ]; then
    printf '#!/bin/bash\nexec python3 /opt/XSStrike/xsstrike.py "$@"\n' \
        | $SUDO tee /usr/local/bin/xsstrike >/dev/null
    $SUDO chmod +x /usr/local/bin/xsstrike
fi

# ---- XXEinjector (Ruby, XXE exploitation) -----------------------------------
# No maintained fork exists — every "fork" is a verbatim mirror of enjoiz's
# original (checked: micxu, MichaelWayneLIU, pekita1, CyberScions,
# The-Cracker-Technology). Kali doesn't package it. Single .rb file, needs
# only Ruby (installed above via apt).
echo "  XXEinjector..."
if [ ! -d /opt/XXEinjector ]; then
    $SUDO git clone --depth 1 https://github.com/enjoiz/XXEinjector /opt/XXEinjector \
        || warn "  XXEinjector clone failed"
else
    $SUDO git -C /opt/XXEinjector pull --ff-only >/dev/null 2>&1 || true
fi
# /usr/local/bin/xxeinjector wrapper
if [ ! -f /usr/local/bin/xxeinjector ]; then
    printf '#!/bin/bash\nexec ruby /opt/XXEinjector/XXEinjector.rb "$@"\n' \
        | $SUDO tee /usr/local/bin/xxeinjector >/dev/null
    $SUDO chmod +x /usr/local/bin/xxeinjector
fi

# ---- SharpHound (BloodHound collector) --------------------------------------
# Repo moved BloodHoundAD -> SpecterOps; asset name is LOWERCASE sharphound-*
echo "  SharpHound..."
TAG=$(gh_latest_tag "SpecterOps/SharpHound")
if [ -n "$TAG" ]; then
    fetch "https://github.com/SpecterOps/SharpHound/releases/download/${TAG}/sharphound-${TAG}.zip" "$WIN_AD/SharpHound.zip"
    if [ -f "$WIN_AD/SharpHound.zip" ] && [ ! -f "$WIN_AD/SharpHound.exe" ]; then
        unzip -o -j "$WIN_AD/SharpHound.zip" "SharpHound.exe" "SharpHound.ps1" -d "$WIN_AD/" >/dev/null 2>&1
    fi
fi

# ---- Snaffler ---------------------------------------------------------------
echo "  Snaffler..."
TAG=$(gh_latest_tag "SnaffCon/Snaffler")
[ -n "$TAG" ] && fetch "https://github.com/SnaffCon/Snaffler/releases/download/${TAG}/Snaffler.exe" "$WIN_AD/Snaffler.exe"

# ---- mimikatz ---------------------------------------------------------------
echo "  mimikatz..."
TAG=$(gh_latest_tag "gentilkiwi/mimikatz")
if [ -n "$TAG" ]; then
    fetch "https://github.com/gentilkiwi/mimikatz/releases/download/${TAG}/mimikatz_trunk.zip" "$WIN_AD/mimikatz_trunk.zip"
    if [ -f "$WIN_AD/mimikatz_trunk.zip" ] && [ ! -f "$WIN_AD/mimikatz.exe" ]; then
        unzip -o -j "$WIN_AD/mimikatz_trunk.zip" "x64/mimikatz.exe" -d "$WIN_AD/" >/dev/null 2>&1
    fi
fi

# ---- KvcForensic (modern lsass.dmp parser, replaces pypykatz on 24H2+) ------
# Password-protected 7z archive (password: github.com). The KvcForensic.json
# offset templates MUST live next to the binary, so we extract to a subdir.
# Linux-only — parse dumps locally on Kali instead of spinning up Windows.
echo "  KvcForensic (Linux)..."
fetch "https://github.com/wesmar/KvcForensic/releases/download/latest/KvcForensic_Linux.7z" "$LIN_TOOLS/KvcForensic_Linux.7z"
if [ -f "$LIN_TOOLS/KvcForensic_Linux.7z" ] && [ ! -f "$LIN_TOOLS/KvcForensic/KvcForensic_static" ]; then
    mkdir -p "$LIN_TOOLS/KvcForensic"
    7z x -y -p"github.com" "$LIN_TOOLS/KvcForensic_Linux.7z" -o"$LIN_TOOLS/KvcForensic" >/dev/null 2>&1 \
        && chmod +x "$LIN_TOOLS/KvcForensic/KvcForensic" "$LIN_TOOLS/KvcForensic/KvcForensic_static" 2>/dev/null \
        || warn "  7z extract of KvcForensic_Linux.7z failed"
fi

# ---- Sysinternals (PsExec, Procdump, ADExplorer, Procmon) -------------------
echo "  Sysinternals..."
fetch "https://download.sysinternals.com/files/PSTools.zip"        "$WIN_AD/PSTools.zip"
fetch "https://download.sysinternals.com/files/Procdump.zip"       "$WIN_AD/Procdump.zip"
fetch "https://download.sysinternals.com/files/AdExplorer.zip"     "$WIN_AD/AdExplorer.zip"
fetch "https://download.sysinternals.com/files/ProcessMonitor.zip" "$WIN_EXES/Procmon/ProcessMonitor.zip"

[ -f "$WIN_AD/PSTools.zip"    ] && [ ! -f "$WIN_AD/PsExec64.exe"    ] && unzip -o -j "$WIN_AD/PSTools.zip" "PsExec64.exe" -d "$WIN_AD/" >/dev/null 2>&1
[ -f "$WIN_AD/Procdump.zip"   ] && [ ! -f "$WIN_AD/procdump64.exe"  ] && unzip -o -j "$WIN_AD/Procdump.zip" "procdump64.exe" -d "$WIN_AD/" >/dev/null 2>&1
[ -f "$WIN_AD/AdExplorer.zip" ] && [ ! -f "$WIN_AD/ADExplorer64.exe" ] && unzip -o -j "$WIN_AD/AdExplorer.zip" "ADExplorer64.exe" -d "$WIN_AD/" >/dev/null 2>&1
[ -f "$WIN_EXES/Procmon/ProcessMonitor.zip" ] && [ ! -f "$WIN_EXES/Procmon/Procmon64.exe" ] && unzip -o "$WIN_EXES/Procmon/ProcessMonitor.zip" -d "$WIN_EXES/Procmon/" >/dev/null 2>&1

# ---- aquatone ---------------------------------------------------------------
echo "  aquatone..."
TAG=$(gh_latest_tag "michenriksen/aquatone")
if [ -n "$TAG" ]; then
    fetch "https://github.com/michenriksen/aquatone/releases/download/${TAG}/aquatone_linux_amd64_${TAG#v}.zip" "$WIN_AD/aquatone.zip"
    if [ -f "$WIN_AD/aquatone.zip" ] && [ ! -f "$WIN_AD/aquatone" ]; then
        unzip -o -j "$WIN_AD/aquatone.zip" "aquatone" -d "$WIN_AD/" >/dev/null 2>&1
        chmod +x "$WIN_AD/aquatone" 2>/dev/null
    fi
fi

# ---- azurehound -------------------------------------------------------------
echo "  azurehound..."
TAG=$(gh_latest_tag "SpecterOps/AzureHound")
if [ -n "$TAG" ]; then
    # Asset filename: AzureHound_vX.Y.Z_linux_amd64.zip (capital A, underscores)
    fetch "https://github.com/SpecterOps/AzureHound/releases/download/${TAG}/AzureHound_${TAG}_linux_amd64.zip" "$WIN_AD/azurehound.zip"
    if [ -f "$WIN_AD/azurehound.zip" ] && [ ! -f "$WIN_AD/azurehound" ]; then
        unzip -o -j "$WIN_AD/azurehound.zip" "azurehound" -d "$WIN_AD/" >/dev/null 2>&1
        chmod +x "$WIN_AD/azurehound" 2>/dev/null
    fi
fi

# ---- netcat for Windows -----------------------------------------------------
echo "  netcat (windows)..."
fetch "https://raw.githubusercontent.com/int0x33/nc.exe/master/nc64.exe" "$WIN_AD/nc64.exe"
fetch "https://raw.githubusercontent.com/int0x33/nc.exe/master/nc.exe"   "$WIN_EXES/nc.exe"
cp -n "$WIN_AD/nc64.exe" "$WIN_EXES/nc64.exe" 2>/dev/null

# ---- Ligolo binaries (cp from earlier install) ------------------------------
echo "  ligolo agent/proxy (copy from /opt/ligolo-ng)..."
if [ -f /opt/ligolo-ng/agents/windows/agent.exe ]; then
    cp -n /opt/ligolo-ng/agents/windows/agent.exe "$WIN_AD/agent.exe"
    cp -n /opt/ligolo-ng/agents/windows/agent.exe "$WIN_EXES/agent.exe"
fi
[ -f /opt/ligolo-ng/proxy ] && cp -n /opt/ligolo-ng/proxy "$WIN_AD/proxy"

# ---- EXEs folder ------------------------------------------------------------
echo "  chisel (linux + windows from chisel-common-binaries)..."
# Kali's chisel-common-binaries package ships prebuilt linux+windows binaries
# in /usr/share/chisel-common-binaries/. Cleaner than chasing GitHub assets.
CHISEL_DIR="/usr/share/chisel-common-binaries"
if [ -d "$CHISEL_DIR" ]; then
    # Pick highest version present (handles multiple versions cleanly)
    LIN_BIN=$(ls "$CHISEL_DIR"/chisel_*_linux_amd64 2>/dev/null | sort -V | tail -n1)
    WIN_BIN=$(ls "$CHISEL_DIR"/chisel_*_windows_amd64.exe 2>/dev/null | sort -V | tail -n1)
    [ -n "$LIN_BIN" ] && [ ! -f "$WIN_EXES/chisel" ]        && cp "$LIN_BIN" "$WIN_EXES/chisel"        && chmod +x "$WIN_EXES/chisel"
    [ -n "$WIN_BIN" ] && [ ! -f "$WIN_EXES/chiselx64.exe" ] && cp "$WIN_BIN" "$WIN_EXES/chiselx64.exe"
    echo "    [ok]   chisel from $(basename "${LIN_BIN:-?}")"
else
    warn "  $CHISEL_DIR not found — is chisel-common-binaries installed?"
fi

echo "  GodPotato..."
TAG=$(gh_latest_tag "BeichenDream/GodPotato")
if [ -n "$TAG" ]; then
    for net in NET2 NET35 NET4; do
        fetch "https://github.com/BeichenDream/GodPotato/releases/download/${TAG}/GodPotato-${net}.exe" "$WIN_EXES/GodPotato/GodPotato-${net}.exe"
    done
fi

echo "  JuicyPotato..."
TAG=$(gh_latest_tag "ohpe/juicy-potato")
[ -n "$TAG" ] && fetch "https://github.com/ohpe/juicy-potato/releases/download/${TAG}/JuicyPotato.exe" "$WIN_EXES/JuicyPotato.exe"

echo "  PrintSpoofer..."
TAG=$(gh_latest_tag "itm4n/PrintSpoofer")
if [ -n "$TAG" ]; then
    fetch "https://github.com/itm4n/PrintSpoofer/releases/download/${TAG}/PrintSpoofer64.exe" "$WIN_EXES/PrintSpoofer64.exe"
    fetch "https://github.com/itm4n/PrintSpoofer/releases/download/${TAG}/PrintSpoofer32.exe" "$WIN_EXES/printspoofer32.exe"
fi

echo "  plink (PuTTY)..."
fetch "https://the.earth.li/~sgtatham/putty/latest/w64/plink.exe" "$WIN_EXES/plink.exe"

# Copy PowerUp.ps1 to EXEs too (it appears in both folders in your tree)
cp -n "$WIN_AD/PowerUp.ps1" "$WIN_EXES/PowerUp.ps1" 2>/dev/null

# ---- Windows top-level ------------------------------------------------------
echo "  pspy64..."
TAG=$(gh_latest_tag "DominicBreuker/pspy")
if [ -n "$TAG" ]; then
    fetch "https://github.com/DominicBreuker/pspy/releases/download/${TAG}/pspy64" "$WIN_ROOT/pspy64"
    chmod +x "$WIN_ROOT/pspy64" 2>/dev/null
fi

echo "  winPEAS / linPEAS..."
TAG=$(gh_latest_tag "peass-ng/PEASS-ng")
if [ -n "$TAG" ]; then
    PEASS_BASE="https://github.com/peass-ng/PEASS-ng/releases/download/${TAG}"
    fetch "$PEASS_BASE/winPEASx64.exe" "$WIN_ROOT/winPEASx64.exe"
    fetch "$PEASS_BASE/linpeas.sh"     "$LIN_TOOLS/linpeas.sh"
    chmod +x "$LIN_TOOLS/linpeas.sh" 2>/dev/null
fi

# Top-level duplicates (SharpHound, kerbrute) — cp from AD/
cp -n "$WIN_AD/SharpHound.exe"              "$WIN_ROOT/SharpHound.exe"  2>/dev/null
cp -n "$WIN_AD/SharpHound.ps1"              "$WIN_ROOT/SharpHound.ps1"  2>/dev/null
cp -n "$WIN_AD/kerbrute_linux_amd64"        "$WIN_ROOT/kerbrute"        2>/dev/null
cp -n "$WIN_AD/kerbrute_windows_amd64.exe"  "$WIN_ROOT/kerbrute.exe"    2>/dev/null

# ---- Linux tools ------------------------------------------------------------
echo "  lse, unix-privesc-check, hashgrab..."
fetch "https://raw.githubusercontent.com/diego-treitos/linux-smart-enumeration/master/lse.sh"          "$LIN_TOOLS/lse.sh"
fetch "https://raw.githubusercontent.com/pentestmonkey/unix-privesc-check/1_x/unix-privesc-check"       "$LIN_TOOLS/unix-privesc-check"
fetch "https://raw.githubusercontent.com/xct/hashgrab/main/hashgrab.py"                                "$LIN_TOOLS/hashgrab.py"
chmod +x "$LIN_TOOLS/lse.sh" "$LIN_TOOLS/unix-privesc-check" "$LIN_TOOLS/hashgrab.py" 2>/dev/null

# chisel (linux binary, same as Windows/EXEs/chisel)
cp -n "$WIN_EXES/chisel" "$LIN_TOOLS/chisel" 2>/dev/null

# nc (system binary)
if command -v nc >/dev/null && [ ! -f "$LIN_TOOLS/nc" ]; then
    cp "$(command -v nc)" "$LIN_TOOLS/nc"
fi

# Items with no canonical online source — keep your existing copies
cat <<'TODO'

  [!] Not auto-fetched (no canonical source / custom / Windows-only artifact):
      Windows/AD:
        - ADenum.ps1                              (multiple forks; pick one)
        - chrome_online.paf.exe                   (PortableApps.com)
        - Get-SPN.ps1                             (not a standalone file — functionality
                                                   is inside PowerView.ps1's Get-DomainSPNTicket;
                                                   alt: nidem/kerberoast/GetUserSPNs.ps1)
        - ldapdomaindump.exe                      (python: pipx install ldapdomaindump)
        - Microsoft.ActiveDirectory.Management.dll (from RSAT on a Windows host)
        - vncpwd.exe                              (legacy — keep your copy)
        - watch_processes.ps1                     (your custom script)
      Windows/EXEs:
        - adduser.c / adduser.exe                 (your custom code)
        - base64.ps1                              (your custom script)
        - dirty_pipe_*.c                          (CVE-2022-0847 POCs — pick a fork)
        - Juicy.Potato.x86.exe                    (older juicy-potato variant)
        - socat / socatx64.exe                    (no official prebuilt — use 3ndG4me/socat)
      Windows top-level:
        - powershell_reverse_base64.ps1           (your custom script)

      Drop these into the relevant folders from your previous VM/backup.

TODO

# ---- Seed toolkit version state file ----------------------------------------
# Populate /opt/.toolkit-versions with current installed versions so
# update-toolkit doesn't re-download every GitHub release asset on its first run.
VERSIONS_FILE="/opt/.toolkit-versions"
$SUDO touch "$VERSIONS_FILE"

seed_ver() {
    # seed_ver <key> <owner/repo> — resolve latest tag and store it
    local key="$1" repo="$2" tag
    tag=$(gh_latest_tag "$repo")
    [ -z "$tag" ] && return
    if $SUDO grep -q "^${key}=" "$VERSIONS_FILE" 2>/dev/null; then
        $SUDO sed -i "s|^${key}=.*|${key}=${tag}|" "$VERSIONS_FILE"
    else
        echo "${key}=${tag}" | $SUDO tee -a "$VERSIONS_FILE" > /dev/null
    fi
}

log "Seeding toolkit version state (prevents re-downloads on first update run)..."
seed_ver "rustscan"     "bee-san/RustScan"
seed_ver "ligolo-ng"    "nicocha30/ligolo-ng"
seed_ver "peass-ng"     "peass-ng/PEASS-ng"
seed_ver "kerbrute"     "ropnop/kerbrute"
seed_ver "windapsearch" "ropnop/go-windapsearch"
seed_ver "sharphound"   "SpecterOps/SharpHound"
seed_ver "snaffler"     "SnaffCon/Snaffler"
seed_ver "mimikatz"     "gentilkiwi/mimikatz"
seed_ver "pspy"         "DominicBreuker/pspy"
seed_ver "godpotato"    "BeichenDream/GodPotato"
seed_ver "printspoofer" "itm4n/PrintSpoofer"
seed_ver "juicypotato"  "ohpe/juicy-potato"
seed_ver "aquatone"     "michenriksen/aquatone"
seed_ver "azurehound"   "SpecterOps/AzureHound"

# Re-enable strict mode for the rest of the script
set -e

# ---- Cleanup ----------------------------------------------------------------

log "Cleaning up apt..."
$SUDO apt-get autoremove -y
$SUDO apt-get autoclean -y

cat <<EOF

[+] Setup complete.

    Ligolo-ng staged at /opt/ligolo-ng:
      - Run the proxy with:   ligolo-proxy -selfcert -laddr 0.0.0.0:443
      - Linux agent:          /opt/ligolo-ng/agents/linux/agent
      - Windows agent:        /opt/ligolo-ng/agents/windows/agent.exe

    Ligolo binaries also copied into the toolkit for serving to targets:
      - $WIN_AD/agent.exe
      - $WIN_EXES/agent.exe
      - $WIN_AD/proxy

    CyberChef (persistent web service):
      - http://localhost:3339  (auto-starts on boot via cyberchef.service)
      - sudo systemctl status cyberchef.service

    Firefox bookmarks:
      - Added to toolbar via enterprise policy (restart Firefox to see them)
      - HackTricks, HackTricks Cloud, CyberChef
      - Policy files: /usr/lib/firefox-esr/distribution/policies.json
                      /etc/firefox/policies/policies.json

    HackTricks (persistent Docker):
      - Main book:  http://localhost:3337  (building ~5 min on first boot)
      - Cloud book: http://localhost:3338
      - Containers restart automatically on reboot (--restart unless-stopped)
      - To stop:    sudo docker stop hacktricks hacktricks-cloud
      - To check:   sudo docker ps | grep hacktricks

    Updates (CyberChef + HackTricks):
      - Auto:       weekly systemd timer (sudo systemctl status update-toolkit.timer)
      - Manual:     sudo update-toolkit
      - Next run:   sudo systemctl list-timers update-toolkit.timer

    Toolkit staged at $TOOLKIT:
      - Windows/{AD,EXEs}, top-level Windows, LinuxTools
      - Re-run the script anytime to refill missing tools (existing files are skipped)

EOF
