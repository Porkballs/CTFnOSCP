#!/bin/bash
#
# Pentest box setup script
#

set -euo pipefail

# ---- Setup ------------------------------------------------------------------

# Resolve the script's own directory so relative file lookups don't depend on CWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use sudo only if not already root
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

log() { printf '\n[*] %s\n' "$*"; }
warn() { printf '\n[!] %s\n' "$*" >&2; }

# ---- System update + core packages ------------------------------------------

# Add the official Sublime Text repository (modern signed-by approach;
# apt-key is deprecated). Skips if any sublime-text source already exists,
# regardless of keyring filename, to avoid Signed-By conflicts.
if grep -rq 'download\.sublimetext\.com' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
    log "Sublime Text repository already configured, skipping."
elif [ ! -f /etc/apt/keyrings/sublimehq-archive.gpg ]; then
    log "Adding Sublime Text repository..."
    $SUDO install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://download.sublimetext.com/sublimehq-pub.gpg \
        | $SUDO gpg --dearmor -o /etc/apt/keyrings/sublimehq-archive.gpg
    echo "deb [signed-by=/etc/apt/keyrings/sublimehq-archive.gpg] https://download.sublimetext.com/ apt/stable/" \
        | $SUDO tee /etc/apt/sources.list.d/sublime-text.list >/dev/null
fi

log "Updating package lists and upgrading..."
$SUDO apt-get update -y
$SUDO apt-get upgrade -y

log "Installing core tools..."
$SUDO apt-get install -y \
    gedit \
    sublime-text \
    seclists \
    gobuster \
    feroxbuster \
    netexec \
    golang-go \
    pipx \
    unzip \
    p7zip-full \
    wget \
    curl \
    git \
    build-essential \
    python3-dev \
    libsasl2-dev \
    libldap2-dev \
    libssl-dev

# ---- Python deps ------------------------------------------------------------
# Libraries (not applications), so pipx is the wrong tool. Install with pip
# into the system Python (Kali enforces PEP 668, hence --break-system-packages).
#   - python-ldap         : LDAP bindings (PowerView-py, windapsearch, etc.)
#   - pyasn1 / -modules   : ASN.1 support, required by windapsearch.py
#   - pylnk3              : LNK file parsing, required by hashgrab.py
#   - ldap3 / pycryptodome: required by ldapsearch-ad.py (pycryptodome enables
#                           NTLM hash auth instead of cleartext password)

log "Installing Python libraries (python-ldap, pyasn1*, pylnk3, ldap3, pycryptodome)..."
$SUDO pip install --break-system-packages \
    python-ldap \
    'pyasn1>=0.4.5' \
    'pyasn1-modules>=0.2.5' \
    pylnk3 \
    ldap3 \
    pycryptodome

pipx ensurepath

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

gh_latest_tag() {
    # Resolve "owner/repo" -> latest release tag (e.g. v1.2.3)
    curl -sLI -o /dev/null -w '%{url_effective}' \
        "https://github.com/$1/releases/latest" \
        | sed -E 's|.*/tag/||; s|/$||'
}

log "Staging toolkit at $TOOLKIT ..."

# ---- PowerShell scripts (raw GitHub) ----------------------------------------
echo "  PowerShell scripts..."
PS_BASE="https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master"
fetch "$PS_BASE/Recon/PowerView.ps1"             "$WIN_AD/PowerView.ps1"
fetch "$PS_BASE/Privesc/PowerUp.ps1"             "$WIN_AD/PowerUp.ps1"
fetch "$PS_BASE/Recon/Get-SPN.ps1"               "$WIN_AD/Get-SPN.ps1"
fetch "$PS_BASE/Recon/Invoke-Kerberoast.ps1"     "$WIN_AD/Invoke-Kerberoast.ps1"
fetch "https://raw.githubusercontent.com/61106960/adPEAS/main/adPEAS.ps1"                              "$WIN_AD/adPEAS.ps1"
fetch "https://raw.githubusercontent.com/dafthack/DomainPasswordSpray/master/DomainPasswordSpray.ps1"  "$WIN_AD/DomainPasswordSpray.ps1"
fetch "https://raw.githubusercontent.com/Kevin-Robertson/Powermad/master/Powermad.ps1"                 "$WIN_AD/Powermad.ps1"
fetch "https://raw.githubusercontent.com/NetSPI/PowerUpSQL/master/PowerUpSQL.ps1"                      "$WIN_AD/PowerUpSQL.ps1"

# ---- Pre-compiled .NET tools (Flangvik's SharpCollection) -------------------
echo "  SharpCollection (pre-compiled .NET)..."
SC="https://raw.githubusercontent.com/Flangvik/SharpCollection/master/NetFramework_4.7_x64"
for tool in Rubeus.exe Certify.exe SharpUp.exe SharpGPOAbuse.exe \
            SharpSCCM.exe SharpShares.exe SeManageVolumeExploit.exe \
            KrbRelayUp.exe GMSAPasswordReader.exe SpoolSample.exe; do
    fetch "$SC/$tool" "$WIN_AD/$tool"
done

# ---- RunasCs ----------------------------------------------------------------
echo "  RunasCs..."
TAG=$(gh_latest_tag "antonioCoco/RunasCs")
[ -n "$TAG" ] && fetch "https://github.com/antonioCoco/RunasCs/releases/download/${TAG}/Invoke-RunasCs.ps1" "$WIN_AD/Invoke-RunasCs.ps1"

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

# ---- SharpHound (BloodHound collector) --------------------------------------
echo "  SharpHound..."
TAG=$(gh_latest_tag "BloodHoundAD/SharpHound")
if [ -n "$TAG" ]; then
    fetch "https://github.com/BloodHoundAD/SharpHound/releases/download/${TAG}/SharpHound-${TAG}.zip" "$WIN_AD/SharpHound.zip"
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
    fetch "https://github.com/SpecterOps/AzureHound/releases/download/${TAG}/azurehound-linux-amd64.zip" "$WIN_AD/azurehound.zip"
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
echo "  chisel (linux + windows)..."
TAG=$(gh_latest_tag "jpillora/chisel")
if [ -n "$TAG" ]; then
    CV="${TAG#v}"
    fetch "https://github.com/jpillora/chisel/releases/download/${TAG}/chisel_${CV}_linux_amd64.gz"   "$WIN_EXES/chisel.gz"
    fetch "https://github.com/jpillora/chisel/releases/download/${TAG}/chisel_${CV}_windows_amd64.gz" "$WIN_EXES/chiselx64.exe.gz"
    [ -f "$WIN_EXES/chisel.gz" ]        && [ ! -f "$WIN_EXES/chisel" ]        && gunzip "$WIN_EXES/chisel.gz" && chmod +x "$WIN_EXES/chisel"
    [ -f "$WIN_EXES/chiselx64.exe.gz" ] && [ ! -f "$WIN_EXES/chiselx64.exe" ] && gunzip "$WIN_EXES/chiselx64.exe.gz"
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
fetch "https://raw.githubusercontent.com/pentestmonkey/unix-privesc-check/master/unix-privesc-check"   "$LIN_TOOLS/unix-privesc-check"
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

    Toolkit staged at $TOOLKIT:
      - Windows/{AD,EXEs}, top-level Windows, LinuxTools
      - Re-run the script anytime to refill missing tools (existing files are skipped)

EOF
