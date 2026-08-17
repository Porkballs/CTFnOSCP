# Kali Setup — Apps & Programs Inventory

Everything the `setup.sh` script installs, stages, or configures on a fresh Kali VM.

---

## ⚠️ OSCP+ Compliance Legend

Tools are marked per **OffSec's OSCP+ Exam Guide** (not my own judgement). OffSec's own official allowed list is included at the bottom of this section; anything not on that list is judged against their stated rule: *"no automatic exploitation tools like SQLmap, SQLninja, db_autopwn, browser_autopwn — or any tool that performs a similar function"*.

| Marker | Meaning |
|---|---|
| ✅ | **OSCP+ ALLOWED** — either on OffSec's explicit allowed list, or functionally equivalent to allowed tools (enumeration, single-purpose exploits, payload generators, tunneling, etc.) |
| ⚠️ | **OSCP+ RESTRICTED** — allowed only with conditions (e.g. Responder analyze-only, Metasploit one-target-only) |
| 🚫 | **OSCP+ PROHIBITED** — SQLmap-class auto-exploit tool. Using this in the exam is a violation |

**OffSec's official OSCP+ allowed tools list** (from the OSCP+ Exam FAQ): BloodHound (Legacy & CE), SharpHound, PowerShell Empire, Covenant, PowerView, Rubeus, evil-winrm, Responder *(poisoning/spoofing not allowed)*, CrackMapExec/NetExec, Mimikatz, Impacket, PrintSpoofer.

**⚠️ SQLmap is Kali default but is PROHIBITED on OSCP+.** Same for the three prohibited tools this script installs — they are intentionally included because this toolkit isn't OSCP-exam-only; it's your working red-team box. Just don't run them during the exam.

---

## 1. System Repositories & apt Packages

### Repositories added
- **Sublime Text** — `download.sublimetext.com/apt/stable` (signed-by keyring)

### Packages installed via `apt-get`

| Package | OSCP+ | Purpose |
|---|---|---|
| `gedit` | ✅ | GUI text editor |
| `sublime-text` | ✅ | Code / notes editor |
| `seclists` | ✅ | Wordlists |
| `gobuster` | ✅ | Directory / DNS / vhost fuzzer |
| `feroxbuster` | ✅ | Recursive content discovery (Rust) |
| `netexec` | ✅ | **On OffSec allowed list** (as CrackMapExec/NetExec) |
| `sstimap` | 🚫 | **PROHIBITED** — SQLmap-class auto-exploit for SSTI |
| `chisel-common-binaries` | ✅ | Prebuilt chisel binaries |
| `golang-go` | ✅ | Go toolchain |
| `pipx` | ✅ | Isolated Python app installer |
| `unzip`, `p7zip-full` | ✅ | Archive extraction |
| `wget`, `curl` | ✅ | HTTP downloaders |
| `git` | ✅ | Version control |
| `ruby` | ✅ | Ruby interpreter (for XXEinjector) |
| `build-essential`, `python3-dev` | ✅ | Build deps |
| `libsasl2-dev`, `libldap2-dev`, `libssl-dev` | ✅ | Build deps for `python-ldap` |

---

## 2. Python Libraries (system pip, `--break-system-packages`)

All libraries — utility only, no OSCP+ classification needed.

| Library | Used by |
|---|---|
| `python-ldap` | PowerView-py, general AD tooling |
| `pyasn1`, `pyasn1-modules` | `windapsearch.py` |
| `pylnk3` | `hashgrab.py` |
| `ldap3`, `pycryptodome` | Ad-hoc LDAP scripting |

Also from `XSStrike/requirements.txt`: `python-Levenshtein`, `prettytable`, `requests`, `tld`, `fuzzywuzzy`.

---

## 3. Python Tools (pipx — global CLI commands)

| Command | OSCP+ | Purpose |
|---|---|---|
| `ldapsearch-ad.py` | ✅ | LDAP enum (equivalent to allowed PowerView/windapsearch) |
| `wenum` | ✅ | Fuzzer (equivalent to allowed DirBuster/gobuster) |
| `gopherus` | ✅ | Generates SSRF **payloads** — operator manually delivers them |

Note on `gopherus`: it doesn't auto-exploit — it generates payload strings you paste into your own request. Analogous to using `revshells.com` to build a reverse shell. Not a SQLmap-class tool.

---

## 4. Standalone Applications

### Installed under `/opt/`

| Path | OSCP+ | What |
|---|---|---|
| `/opt/ligolo-ng/proxy` | ✅ | Tunneling proxy (symlinked to `/usr/local/bin/ligolo-proxy`) |
| `/opt/ligolo-ng/agents/linux/agent` | ✅ | Ligolo Linux agent |
| `/opt/ligolo-ng/agents/windows/agent.exe` | ✅ | Ligolo Windows agent |
| `/opt/XSStrike/` | 🚫 | **PROHIBITED** — SQLmap-class auto-exploit for XSS |
| `/opt/XXEinjector/` | 🚫 | **PROHIBITED** — SQLmap-class auto-exploit for XXE |

### Wrappers on `/usr/local/bin/`

| Command | OSCP+ | Wraps |
|---|---|---|
| `ligolo-proxy` | ✅ | Symlink → `/opt/ligolo-ng/proxy` |
| `xsstrike` | 🚫 | Shim → `python3 /opt/XSStrike/xsstrike.py` |
| `xxeinjector` | 🚫 | Shim → `ruby /opt/XXEinjector/XXEinjector.rb` |

### Other

| Item | OSCP+ | Location |
|---|---|---|
| RustScan | ✅ | apt (from GitHub `.deb`) — port scanner |
| Powerline fonts | ✅ | User-level install |
| `rockyou.txt` extracted | ✅ | `/usr/share/wordlists/rockyou.txt` |

---

## 5. Windows Toolkit — `~/Toolkit/Windows/`

### `Windows/AD/` — Active Directory tooling

**PowerShell scripts** — all ✅ (single-purpose scripts, not auto-exploit frameworks)

| File | OSCP+ | Purpose |
|---|---|---|
| `PowerView.ps1` | ✅ | **On OffSec allowed list** |
| `PowerUp.ps1` | ✅ | Local privesc audit (PowerSploit) |
| `Invoke-Kerberoast.ps1` | ✅ | Auto-request Kerberoast hashes (Kerberoasting is a manual technique) |
| `adPEAS.ps1` | ✅ | AD enum aggregator |
| `DomainPasswordSpray.ps1` | ✅ | Password spray |
| `Powermad.ps1` | ✅ | `ms-DS-MachineAccountQuota` abuse |
| `PowerUpSQL.ps1` | ✅ | SQL Server enum + specific attacks |
| `Invoke-RunasCs.ps1` | ✅ | Execute-as-user helper |

**Pre-compiled .NET binaries** (Flangvik/SharpCollection)

| Binary | OSCP+ | Purpose |
|---|---|---|
| `Rubeus.exe` | ✅ | **On OffSec allowed list** — Kerberos attacks |
| `Certify.exe` | ✅ | AD CS template enumeration |
| `SharpUp.exe` | ✅ | Local privesc audit |
| `SharpGPOAbuse.exe` | ✅ | GPO abuse (specific single attack) |
| `SharpSCCM.exe` | ✅ | SCCM attacks (specific tool) |
| `SharpShares.exe` | ✅ | Share enumeration |
| `KrbRelayUp.exe` | ✅ | Kerberos relay privesc (specific attack chain) |
| `GMSAPasswordReader.exe` | ✅ | gMSA password reader (single-purpose) |

**Additional binaries**

| Binary | OSCP+ | Purpose |
|---|---|---|
| `SpoolSample.exe` | ✅ | PrinterBug trigger (single-purpose) |
| `SeManageVolumeExploit.exe` | ✅ | Specific privesc (analogous to PrintSpoofer) |
| `SharpHound.exe`, `SharpHound.ps1` | ✅ | **On OffSec allowed list** — BloodHound collector |
| `Snaffler.exe` | ✅ | Share credential loot (analogous to Impacket workflow) |
| `mimikatz.exe` | ✅ | **On OffSec allowed list** |
| `kerbrute_{linux,darwin,windows}_amd64[.exe]` | ✅ | User enum + password spray |
| `windapsearch-{linux,darwin,windows}-amd64[.exe]` | ✅ | LDAP enum |
| `windapsearch.py` | ✅ | LDAP enum (Python) |
| `PsExec64.exe` | ✅ | Remote exec (Sysinternals) |
| `procdump64.exe` | ✅ | Process dump (Sysinternals) |
| `ADExplorer64.exe` | ✅ | AD inspection (Sysinternals) |
| `aquatone` | ✅ | Visual recon |
| `azurehound` | ✅ | Azure attack-path collector (analogous to BloodHound) |
| `nc64.exe` | ✅ | Netcat |
| `agent.exe`, `proxy` | ✅ | Ligolo binaries |

### `Windows/EXEs/` — General exploitation binaries

| Binary | OSCP+ | Purpose |
|---|---|---|
| `chisel`, `chiselx64.exe` | ✅ | Tunneling |
| `GodPotato/GodPotato-NET{2,35,4}.exe` | ✅ | `SeImpersonate` → SYSTEM (single-purpose) |
| `JuicyPotato.exe` | ✅ | Legacy `SeImpersonate` → SYSTEM |
| `PrintSpoofer{64,32}.exe` | ✅ | **On OffSec allowed list** |
| `plink.exe` | ✅ | SSH tunneling |
| `nc.exe`, `nc64.exe` | ✅ | Netcat |
| `Procmon/...` | ✅ | Process monitor (Sysinternals) |
| `PowerUp.ps1` | ✅ | Copy of `../AD/PowerUp.ps1` |
| `agent.exe` | ✅ | Ligolo agent |

### `Windows/` (top-level)

| File | OSCP+ | Purpose |
|---|---|---|
| `pspy64` | ✅ | Linux process snooping (misplaced — actually a Linux tool) |
| `winPEASx64.exe` | ✅ | Windows privesc enum |
| `SharpHound.exe`, `SharpHound.ps1` | ✅ | Copy of `AD/SharpHound.*` |
| `kerbrute`, `kerbrute.exe` | ✅ | Copies of `AD/kerbrute_*` |

---

## 6. Linux Toolkit — `~/Toolkit/LinuxTools/`

| File | OSCP+ | Purpose |
|---|---|---|
| `linpeas.sh` | ✅ | Linux privesc enum |
| `lse.sh` | ✅ | Linux Smart Enumeration |
| `unix-privesc-check` | ✅ | Privesc audit |
| `hashgrab.py` | ✅ | Payload generator (like `revshells.com`) |
| `chisel` | ✅ | Tunneling |
| `nc` | ✅ | Netcat |
| `KvcForensic/KvcForensic{,_static}` | ✅ | Offline `lsass.dmp` parsing (analogous to mimikatz) |
| `KvcForensic/KvcForensic.json` | ✅ | Offset templates |

---

## 7. Manual Follow-up (Not Auto-Fetched)

All ✅ for OSCP+ (utility scripts, editors, legacy tools).

### `Windows/AD/`
- `ADenum.ps1` — pick a fork
- `chrome_online.paf.exe` — PortableApps.com
- `Get-SPN.ps1` — not standalone; use PowerView's `Get-DomainSPNTicket`
- `ldapdomaindump.exe` — `pipx install ldapdomaindump`
- `Microsoft.ActiveDirectory.Management.dll` — extract from RSAT
- `vncpwd.exe` — legacy
- `watch_processes.ps1` — custom script

### `Windows/EXEs/`
- `adduser.c` / `adduser.exe` — custom code
- `base64.ps1` — custom script
- `dirty_pipe_*.c` — CVE-2022-0847 POCs
- `Juicy.Potato.x86.exe` — older variant
- `socat` / `socatx64.exe` — try `3ndG4me/socat`

### `Windows/` (top-level)
- `powershell_reverse_base64.ps1` — custom script

---

## 8. OSCP+ Exam Checklist

**Before the exam, remember these are 🚫 PROHIBITED — do NOT run them:**

- `sstimap` — even if you find SSTI, do it manually with Tplmap-style payload testing or by hand
- `xsstrike` — XSS must be exploited manually (Burp Repeater + custom payloads)
- `xxeinjector` — XXE payloads must be constructed manually
- **`sqlmap`** *(Kali default)* — SQLi must be exploited manually. Use manual UNION/blind/time-based techniques
- `nessus`, `openvas`, `nexpose` — no mass vuln scanners

**Also remember these OSCP+ RESTRICTIONS:**

- ⚠️ **Metasploit** — allowed against ONE target only (Auxiliary, Exploit, Post modules or Meterpreter)
- ⚠️ **Responder** — allowed in analyze-only mode (`-A`). **Poisoning/spoofing is prohibited**
- ⚠️ **No spoofing** — IP, ARP, DNS, NBNS, etc.

**All the ⚡ tools I originally flagged are actually ✅ ALLOWED on OSCP+:**
mimikatz, Rubeus, kerbrute, netexec, all Sharp* tools, all Potato exploits, PrintSpoofer, SpoolSample, Snaffler, gopherus (payload gen only), hashgrab, KvcForensic, DomainPasswordSpray, Invoke-Kerberoast, etc.

The OSCP+ line isn't "does it automate anything?" — it's "does it automate the vulnerability discovery → exploitation chain like SQLmap does?" Almost none of the AD/privesc tools do that. They're targeted single-purpose exploits or enumeration, both of which OffSec explicitly permits.

---

## 9. Quick-Reference Command Map

| Command | OSCP+ | Attack surface | Provided by |
|---|---|---|---|
| `subl` | ✅ | (editor) | Sublime Text (apt) |
| `feroxbuster`, `gobuster` | ✅ | Content discovery | apt |
| `wenum` | ✅ | Parameter fuzzing | pipx |
| `netexec` (`nxc`) | ✅ | SMB/WinRM/LDAP/MSSQL | apt |
| `sstimap` | 🚫 | SSTI → RCE | apt |
| `xsstrike` | 🚫 | XSS | wrapper |
| `xxeinjector` | 🚫 | XXE | wrapper |
| `gopherus` | ✅ | SSRF payloads | pipx |
| `ldapsearch-ad.py` | ✅ | AD LDAP enum | pipx |
| `rustscan` | ✅ | Fast port scanning | GitHub `.deb` |
| `ligolo-proxy` | ✅ | Reverse tunneling | `/opt/ligolo-ng/` |
| `7z` | ✅ | Archive extraction | apt |

---

*Classifications derived from the OSCP+ Exam Guide (help.offsec.com) and OSCP+ Exam FAQ. Regenerate this file after modifying `setup.sh`.*
