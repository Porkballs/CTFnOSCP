List of tools for OSCP.
# No Auto EXPLOITS
### Script will update and download repos/tools that is useful for OSCP 
### Files will be downloaded and sorted onto /home/kali/Toolkit/
# Create snapshot on VM incase system updates break KALI

chmod +x KaliSetUpforOSCP.sh

./KaliSetUpforOSCP.sh
# Kali Setup — Apps & Programs Inventory

Everything the `setup.sh` script installs, staged, or configures on a fresh Kali VM.

---

## 1. System Repositories & apt Packages

### Repositories added
- **Sublime Text** — `download.sublimetext.com/apt/stable` (signed-by keyring at `/etc/apt/keyrings/sublimehq-archive.gpg`)

### Packages installed via `apt-get`

| Package | Purpose |
|---|---|
| `gedit` | GUI text editor |
| `sublime-text` | Primary code / notes editor |
| `seclists` | Wordlist collection |
| `gobuster` | Directory / DNS / vhost fuzzer |
| `feroxbuster` | Recursive content discovery (Rust) |
| `netexec` | Modern replacement for CrackMapExec |
| 'sstimap` | Automatic SSTI (Server-Side Template Injection) detection & exploitation |
| `chisel-common-binaries` | Prebuilt chisel binaries (linux + windows) |
| `golang-go` | Go toolchain |
| `pipx` | Isolated Python app installer |
| `unzip`, `p7zip-full` | Archive extraction (zip + password-protected 7z) |
| `wget`, `curl` | HTTP downloaders |
| `git` | Version control (used for cloning tools) |
| `build-essential`, `python3-dev` | Compilation deps for `python-ldap` |
| `libsasl2-dev`, `libldap2-dev`, `libssl-dev` | LDAP / SASL / TLS libs for `python-ldap` |

---

## 2. Python Libraries (system pip, `--break-system-packages`)

| Library | Used by |
|---|---|
| `python-ldap` | PowerView-py, general AD LDAP tooling |
| `pyasn1`, `pyasn1-modules` | `windapsearch.py` |
| `pylnk3` | `hashgrab.py` |
| `ldap3`, `pycryptodome` | (kept for other ad-hoc LDAP scripting) |

Also installed to system Python via `pip -r requirements.txt`:

| From | Libraries |
|---|---|
| `XSStrike` | `python-Levenshtein`, `prettytable`, `requests`, `tld`, `fuzzywuzzy` |

---

## 3. Python Tools (pipx — global CLI commands)

| Command | Package / Source | Notes |
|---|---|---|
| `ldapsearch-ad.py` | `ldapsearchad` (PyPI) | AD LDAP enum with NTLM-hash auth support |
| `wenum` | `git+WebFuzzForge/wenum` | Actively-maintained wfuzz fork |
| `gopherus` | `git+Esonhugh/Gopherus3` | Python 3 SSRF payload generator |

---

## 4. Standalone Applications

### Installed under `/opt/`

| Path | What |
|---|---|
| `/opt/ligolo-ng/proxy` | Linux proxy binary (symlinked to `/usr/local/bin/ligolo-proxy`) |
| `/opt/ligolo-ng/agents/linux/agent` | Ligolo Linux agent (for Linux targets) |
| `/opt/ligolo-ng/agents/windows/agent.exe` | Ligolo Windows agent (for Windows targets) |
| `/opt/XSStrike/` | Full XSStrike repo clone |

### Wrappers on `/usr/local/bin/`

| Command | Wraps |
|---|---|
| `ligolo-proxy` | Symlink → `/opt/ligolo-ng/proxy` |
| `xsstrike` | Shim → `python3 /opt/XSStrike/xsstrike.py` |

### Other

| Item | Location | Notes |
|---|---|---|
| RustScan | apt (from GitHub `.deb`) | Latest release, arch auto-detected |
| Powerline fonts | User-level install | Via `~/Scripts/fonts/install.sh` |
| `rockyou.txt` (extracted) | `/usr/share/wordlists/rockyou.txt` | Gunzipped from `.gz` if needed |

---

## 5. Windows Toolkit — `~/Toolkit/Windows/`

### `Windows/AD/` — Active Directory tooling

**PowerShell scripts**

| File | Source |
|---|---|
| `PowerView.ps1` | PowerSploit/Recon |
| `PowerUp.ps1` | PowerSploit/Privesc |
| `Invoke-Kerberoast.ps1` | EmpireProject (standalone) |
| `adPEAS.ps1` | 61106960/adPEAS |
| `DomainPasswordSpray.ps1` | dafthack |
| `Powermad.ps1` | Kevin-Robertson |
| `PowerUpSQL.ps1` | NetSPI |
| `Invoke-RunasCs.ps1` | antonioCoco/RunasCs (master branch) |

**Pre-compiled .NET binaries** (Flangvik/SharpCollection, with Ghostpack fallback)

| Binary | Purpose |
|---|---|
| `Rubeus.exe` | Kerberos abuse (ASREPRoast, Kerberoast, S4U) |
| `Certify.exe` | AD CS enumeration & abuse |
| `SharpUp.exe` | Local privesc checks |
| `SharpGPOAbuse.exe` | GPO abuse |
| `SharpSCCM.exe` | SCCM attacks |
| `SharpShares.exe` | Share enumeration |
| `KrbRelayUp.exe` | Kerberos relay privesc |
| `GMSAPasswordReader.exe` | Read gMSA passwords |

**Additional binaries**

| Binary | Source |
|---|---|
| `SpoolSample.exe` | jakobfriedl/precompiled-binaries |
| `SeManageVolumeExploit.exe` | CsEnox releases |
| `SharpHound.exe`, `SharpHound.ps1` | SpecterOps/SharpHound (extracted from zip) |
| `Snaffler.exe` | SnaffCon/Snaffler |
| `mimikatz.exe` | gentilkiwi (extracted from zip) |
| `kerbrute_linux_amd64` | ropnop/kerbrute |
| `kerbrute_darwin_amd64` | ropnop/kerbrute |
| `kerbrute_windows_amd64.exe` | ropnop/kerbrute |
| `windapsearch-linux-amd64` | ropnop/go-windapsearch |
| `windapsearch-darwin-amd64` | ropnop/go-windapsearch |
| `windapsearch-windows-amd64.exe` | ropnop/go-windapsearch |
| `windapsearch.py` | ropnop/windapsearch (Python version) |
| `PsExec64.exe` | Sysinternals |
| `procdump64.exe` | Sysinternals |
| `ADExplorer64.exe` | Sysinternals |
| `aquatone` | michenriksen (Linux binary) |
| `azurehound` | SpecterOps/AzureHound |
| `nc64.exe` | int0x33/nc.exe |
| `agent.exe`, `proxy` | copied from `/opt/ligolo-ng/` |

### `Windows/EXEs/` — General exploitation binaries

| Binary | Source |
|---|---|
| `chisel`, `chiselx64.exe` | apt `chisel-common-binaries` (copied from `/usr/share/`) |
| `GodPotato/GodPotato-NET2.exe` | BeichenDream/GodPotato |
| `GodPotato/GodPotato-NET35.exe` | BeichenDream/GodPotato |
| `GodPotato/GodPotato-NET4.exe` | BeichenDream/GodPotato |
| `JuicyPotato.exe` | ohpe/juicy-potato |
| `PrintSpoofer64.exe` | itm4n/PrintSpoofer |
| `printspoofer32.exe` | itm4n/PrintSpoofer |
| `plink.exe` | PuTTY (the.earth.li) |
| `nc.exe`, `nc64.exe` | int0x33/nc.exe |
| `Procmon/ProcessMonitor.zip` (unzipped) | Sysinternals |
| `PowerUp.ps1` | copy of `../AD/PowerUp.ps1` |
| `agent.exe` | copy of `/opt/ligolo-ng/agents/windows/agent.exe` |

### `Windows/` (top-level)

| File | Source |
|---|---|
| `pspy64` | DominicBreuker/pspy |
| `winPEASx64.exe` | peass-ng/PEASS-ng |
| `SharpHound.exe`, `SharpHound.ps1` | copy of `AD/SharpHound.*` |
| `kerbrute`, `kerbrute.exe` | copies of `AD/kerbrute_*` |

---

## 6. Linux Toolkit — `~/Toolkit/LinuxTools/`

| File | Source |
|---|---|
| `linpeas.sh` | peass-ng/PEASS-ng |
| `lse.sh` | diego-treitos/linux-smart-enumeration |
| `unix-privesc-check` | pentestmonkey (branch `1_x`) |
| `hashgrab.py` | xct/hashgrab |
| `chisel` | copy of `../Windows/EXEs/chisel` |
| `nc` | copy of system `nc` binary |
| `KvcForensic/KvcForensic` | wesmar/KvcForensic (dynamic build) |
| `KvcForensic/KvcForensic_static` | wesmar/KvcForensic (static build) |
| `KvcForensic/KvcForensic.json` | Required offset templates |

---

## 7. Manual Follow-up (Not Auto-Fetched)

Files with no canonical online source — copy from previous VM or backup.

### `Windows/AD/`
- `ADenum.ps1` — pick a fork
- `chrome_online.paf.exe` — PortableApps.com
- `Get-SPN.ps1` — not standalone; use `PowerView.ps1`'s `Get-DomainSPNTicket` or `nidem/kerberoast/GetUserSPNs.ps1`
- `ldapdomaindump.exe` — install via `pipx install ldapdomaindump`
- `Microsoft.ActiveDirectory.Management.dll` — extract from RSAT on a Windows host
- `vncpwd.exe` — legacy, keep your copy
- `watch_processes.ps1` — custom script

### `Windows/EXEs/`
- `adduser.c` / `adduser.exe` — custom code
- `base64.ps1` — custom script
- `dirty_pipe_*.c` — CVE-2022-0847 POCs
- `Juicy.Potato.x86.exe` — older variant
- `socat` / `socatx64.exe` — no official prebuilt; try `3ndG4me/socat`

### `Windows/` (top-level)
- `powershell_reverse_base64.ps1` — custom script

---

## 8. Quick-Reference Command Map

Commands available on PATH after setup completes:

| Command | Provided by |
|---|---|
| `subl` | Sublime Text (apt) |
| `feroxbuster`, `gobuster` | apt |
| `netexec` (`nxc`) | apt |
| `rustscan` | GitHub release (installed as .deb) |
| `ligolo-proxy` | `/opt/ligolo-ng/proxy` (symlink) |
| `ldapsearch-ad.py` | pipx |
| `wenum` | pipx |
| `gopherus` | pipx |
| `xsstrike` | `/opt/XSStrike/xsstrike.py` (wrapper) |
| `7z` | apt (`p7zip-full`) |

---

*Regenerate after modifying `setup.sh` — this file mirrors what the script installs.*

# fixZSHHistory.sh fixes a corrupt .zsh_history file
chmod +x fixZSHHistory.sh


./fixZSHHistory.sh


# Bloodhound_Cyphers.md
A list of commonly used cyphers to run for Bloodhound

# NetExec (NXC) Cheatsheet.md
Quick reference cheatsheet for using NXC
