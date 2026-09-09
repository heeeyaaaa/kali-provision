# kali-provision

Reproduce a fully-tooled Kali workstation from scratch -- either build a brand new
VM with Packer, or provision an existing Kali box directly with Ansible.

## How it works

Two ways to run this, same underlying playbook:

- **Packer** clones Kali's official `.vmx`, boots it, and runs the full Ansible
  playbook against it unattended -- hands you back a finished, standalone VM.
- **Ansible directly** provisions any Kali box you already have (a VM, a fresh
  install, or the machine you're running the command on).

Everything nothing-can-re-derive (loose binaries, `.ps1` tooling, PSTools) is
carried as zstd-compressed tarballs tracked with git-lfs (`artifacts/*.tar.zst`,
see `.gitattributes`). Everything else -- apt packages, pipx tools, git clones,
cargo/go packages, vendor SDKs -- is re-fetched fresh from upstream on every run.

## What it covers

| Role | What it does |
|---|---|
| `apt_repos` | github-cli, microsoft-prod, nodesource repos + signing keys |
| `base_packages` | ~110 apt packages -- see the [package table](#apt-packages) below |
| `python_tools` | ~33 pipx applications, 3 installed from git source instead of PyPI, plus a shared `~/venv` -- see [pipx tools](#pipx-tools) |
| `lang_tools` | cargo crates (evtx_dump, rusthound-ce, …) and go packages |
| `git_tools` | ~46 tool repos cloned into `~/tools` (+ 4 outside it), always upstream HEAD; each repo's `requirements.txt` installs into the shared `~/venv` (volatility3 gets its own dedicated venv) |
| `binary_tools` | gcloud SDK, Azure CLI, hashcat (built from source), BloodHound CE via `bloodhound-cli`, a Volatility 2 Docker container, Burp Suite (optional) |
| `artifacts_sync` | restores `~/Downloads`, `~/Downloads/windows`, wordlists, and a handful of loose system binaries that have no apt package |
| `claude` | installs Claude Code (native installer) |
| `dotfiles` | shell config, PATH, and XFCE power/screensaver tweaks |
| `system_tweaks` | manual clock-sync tooling for Kerberos time-skew, disables `systemd-timesyncd` |

## Directory reference

A few directories this repo populates that aren't obvious from the role names above:

- **`~/tools/`** -- every `git_tools` repo, cloned at upstream HEAD. Not copied --
  this directory doesn't exist in the repo at all, it's rebuilt by cloning on
  every run. Repos shipping a `requirements.txt` get it installed into the
  shared `~/venv` (see below); `volatility3` is the one exception, with its own
  dedicated venv at `~/tools/volatility3/volvenv` (built with `pip install -e
  ".[full]"`, which needs its own venv regardless).
- **`~/venv/`** -- one shared Python virtualenv for libraries meant to be
  `import`ed directly in your own ad-hoc scripts (`source ~/venv/bin/activate`).
  Distinct from pipx: a pipx tool gets its own isolated venv purely to expose a
  CLI entry point on PATH, so you can't `import impacket` from a script without
  activating that one tool's specific venv. This shared venv is the "general AD
  /DFIR toolkit" instead -- some names deliberately overlap with pipx tools
  (`impacket`, `minidump`) for exactly that reason.
- **`~/Downloads/`** -- general loot and standalone tools with no apt/pip/git
  home: wordlists, standalone binaries, scripts you'd otherwise hunt down by
  hand each time.
- **`~/Downloads/windows/`** -- Windows-specific post-exploitation binaries and
  `.ps1` tooling (Mimikatz, PowerView, Inveigh, PsTools, and similar) meant to
  be dropped onto a target, not run locally.

## Custom tools on PATH

A few tools aren't apt/pipx packages and don't show up in the tables below --
here's where they come from and how to use them:

- **`vol2`** -- Volatility 2 wrapper. Volatility 2 needs Python 2, unavailable
  on modern Kali, so this runs it in Docker instead
  (`blacktop/volatility:latest`, pulled during provisioning rather than built
  locally). Bind-mounts your current directory into the container, so run it
  from wherever your memory image lives: `sudo vol2 -f memory.dmp
  --profile=Win10x64_19041 pslist`. Needs `sudo` -- `kali` is deliberately
  not in the `docker` group (that's root-equivalent with no password at all,
  see Design notes). The wrapper itself is
  `roles/binary_tools/files/volatility2/vol2` if you want to see exactly what
  it does.
- **`vol`** (Volatility 3) -- installed into its own venv at
  `~/tools/volatility3/volvenv` rather than exposed on PATH directly (it needs
  `pip install -e ".[full]"`, kept separate from the shared `~/venv`).
  Activate it first: `source ~/tools/volatility3/volvenv/bin/activate && vol
  -f memory.dmp windows.pslist`.
- **`bloodhound-cli`** -- symlinked from `~/tools/bloodhound/bloodhound-cli`
  (downloaded from SpecterOps' releases). Deploys/manages the BloodHound CE
  Docker stack: `sudo bloodhound-cli install`, `sudo bloodhound-cli up` --
  needs `sudo` for the same reason `vol2` does. Collection is a separate
  step, via the pipx-installed `bloodhound-python` / `bloodhound-ce-python`
  (no Docker involved, so no sudo needed there).
- **`BurpSuite`** -- symlinked from `/opt/BurpSuite/BurpSuite<Edition>` (the
  current PortSwigger installer, not the stale apt package, which gets
  purged first).
- **`gdre_tools.x86_64`, `pycdc`, `utmdump`, `kerbrute`** -- standalone
  prebuilt binaries with no apt/pip/git home, restored straight to `/usr/bin`
  or `/usr/local/bin` from `artifacts/system-bins.tar.zst`: Godot RE Tools,
  a Python bytecode decompiler, a macOS UTMP-format parser, and a Kerberos
  username/password brute-forcer, respectively.

## Apt packages

Everything below is a *non-default* package -- installed on top of a stock Kali
image (`base_packages` diffs `apt-mark showmanual` against a fresh-Kali baseline,
so anything Kali already ships by default isn't re-listed here).

**Active Directory / domain**
| Package | What it's for |
|---|---|
| `krb5-user`, `krb5-config`, `krb5-pkinit` | Kerberos client + PKINIT (certificate-based Kerberos auth) |
| `samba-ad-dc`, `samba-ad-provision`, `samba-dsdb-modules` | stand up a Samba Active Directory Domain Controller (test labs) |
| `winbind` | resolve Windows/AD identities from Samba |
| `ldeep` | LDAP-based Active Directory enumeration |
| `mitm6` | IPv6 DNS takeover for AD relay attacks |
| `dnsmasq` | lightweight DNS/DHCP for lab networks |

**Cloud**
| Package | What it's for |
|---|---|
| `awscli` | AWS CLI |
| `azure-cli` | Azure CLI (also the supported install path for `az`, via the microsoft-prod repo) |
| `azurehound` | BloodHound-style enumeration for Azure AD / Entra ID |

**Forensics / DFIR**
| Package | What it's for |
|---|---|
| `plaso`, `python3-plaso` | super-timeline forensic analysis (`log2timeline`) |
| `regripper` | Windows registry forensic analysis plugins |
| `reglookup` | Windows registry hive parsing/reporting |
| `ewf-tools` | Expert Witness Format (EnCase `.E01`) disk image handling |
| `libesedb-dev` | headers for parsing ESE databases (Windows Search, WebCache) |
| `libplist-utils` | Apple property list (`.plist`) tools |
| `libguestfs-tools` | mount and inspect VM disk images (`virt-*`) |
| `extundelete` | recover deleted files from ext3/ext4 |
| `aeskeyfind` | recover AES keys from memory images |
| `crash` | Linux kernel crash dump analysis |
| `python3-msoffcrypto-tool` | decrypt password-protected Office documents |
| `python3-pdfminer`, `poppler-utils` | PDF text/metadata extraction |
| `tesseract-ocr` | OCR engine |

**Reverse engineering / binary analysis**
| Package | What it's for |
|---|---|
| `ghidra` | NSA's SRE suite -- disassembler/decompiler |
| `jadx` | Android DEX-to-Java decompiler |
| `apktool` | decompile/rebuild Android APKs |
| `gdb`, `gdb-multiarch` | debugger, incl. cross-architecture |
| `ltrace`, `strace` | library-call / syscall tracers |
| `pyinstxtractor` | extract PyInstaller-packed Python executables |
| `mono-devel` | run/inspect .NET (Mono) binaries |
| `qemu-system-common`, `qemu-system-riscv`, `qemu-user`, `qemu-utils` | emulation for firmware and cross-architecture analysis |
| `binutils-riscv64-linux-gnu` | RISC-V binutils |
| `android-sdk-libsparse-utils` | convert Android sparse (`.img`) images |
| `libfuse3-dev`, `fuse` | userspace filesystems (some forensic tools mount images via FUSE) |
| `wimtools` | Windows Imaging Format (`.wim`) tools |

**Web / recon**
| Package | What it's for |
|---|---|
| `dirsearch` | web path/directory brute-forcer |
| `gitleaks` | scan git repos for committed secrets |
| `seclists` | SecLists wordlist collection |

**Credentials / crypto**
| Package | What it's for |
|---|---|
| `keepass2`, `kpcli` | interact with / crack KeePass password databases |
| `phpggc` | PHP deserialization gadget chain generator |
| `minisign` | lightweight signing tool |
| `faketime` | override a process's perceived system time (time-bound exploit testing) |
| `sshpass` | non-interactive SSH password auth |

**Build toolchains** (compiling tools from source, cargo crates, Go packages, .NET, Node)
| Package | What it's for |
|---|---|
| `autoconf`, `automake`, `autopoint`, `cmake`, `libtool`, `pkg-config` | standard C/C++ build toolchain |
| `cargo` | Rust package manager / build tool |
| `golang` | Go toolchain |
| `llvm` | LLVM compiler infrastructure |
| `mingw-w64` | cross-compile Windows binaries from Linux |
| `gradle`, `maven`, `default-jdk` | Java build tooling + JDK |
| `nodejs`, `node-ws`, `npm` | Node.js runtime + package manager |
| `libssl-dev`, `libjpeg-dev`, `libldap2-dev`, `libsasl2-dev`, `libsasl2-modules-gssapi-mit`, `liburing-dev`, `libxslt1-dev`, `libfdt-dev`, `libguava-java` | headers needed to build various Python/Java packages from source (Pillow, python-ldap, lxml, Ghidra's Guava dep, etc.) |

**Docker**
| Package | What it's for |
|---|---|
| `docker.io`, `docker-compose`, `docker-buildx` | container runtime -- BloodHound CE and the Volatility 2 container both run on this |

**Communications** (chat/messaging clients, sometimes useful for OSINT/recon)
| Package | What it's for |
|---|---|
| `gajim`, `pidgin`, `profanity` | XMPP/multi-protocol chat clients |
| `mosquitto-clients` | MQTT pub/sub CLI tools (IoT testing) |
| `lftp` | advanced FTP/SFTP client |

**System / misc**
| Package | What it's for |
|---|---|
| `ansible-core` | Ansible itself -- this box can re-run its own playbook |
| `gh` | GitHub CLI |
| `jq` | JSON processor |
| `cabextract` | extract Microsoft CAB archives |
| `evince` | PDF viewer |
| `fd-find` | fast `find` alternative |
| `ncdu` | interactive disk usage analyzer |
| `putty-tools` | PuTTY's CLI tools (e.g. `puttygen` for key conversion) |
| `rlwrap` | adds readline history/editing to CLIs that lack it |
| `nfs4-acl-tools` | NFSv4 ACL manipulation |
| `open-iscsi` | iSCSI initiator |
| `libreoffice` | office suite (document conversion/inspection) |
| `libmemcached-tools` | memcached CLI tools |
| `ntpsec-ntpdate` | manual clock sync -- match a target DC's clock before Kerberos auth |
| `terraform` | infrastructure as code (spin up cloud attack ranges/labs) |
| `apt-transport-https`, `software-properties-common` | apt plumbing |

## Pipx tools

Each gets its own isolated venv (see [`~/venv`](#directory-reference) above for
why this is different from the shared venv). Most install straight from PyPI;
`donpapi`, `sccmhunter`, and `netexec` install from their GitHub repos instead
(no working PyPI package, or Kali's apt version lags upstream too far).

| Package | What it's for |
|---|---|
| `impacket` | the core Python library/toolset for SMB, Kerberos, and DCE/RPC protocol attacks |
| `netexec` | (git source) network protocol swiss-army-knife -- successor to CrackMapExec |
| `bloodhound`, `bloodhound-ce` | BloodHound collectors (legacy + Community Edition) |
| `bloodyAD` | Active Directory privilege escalation via LDAP |
| `pywhisker` | manipulate `msDS-KeyCredentialLink` (Shadow Credentials attack) |
| `coercer` | trigger authentication coercion (PetitPotam-family) against Windows hosts |
| `donpapi` | (git source) dump DPAPI secrets remotely |
| `sccmhunter` | (git source) enumerate and attack Microsoft SCCM/ConfigMgr |
| `evil-winrm-py` | WinRM shell client |
| `regipy` | Windows registry hive parsing (Python library + CLI) |
| `oletools` | analyze OLE/Office documents for malicious macros |
| `pyrdp-mitm` | RDP man-in-the-middle proxy (broken on Python 3.14 upstream -- excluded, see `exclude_tools`) |
| `minidump` | parse Windows minidump/LSASS dump files |
| `mailaccess` | mailbox access / enumeration |
| `man-spider` | crawl SMB shares harvesting credentials from files |
| `git-dumper` | dump a `.git` directory exposed on a web server |
| `h8mail`, `holehe`, `ghunt` | email/account OSINT (breach data, service enumeration, Google account recon) |
| `pacu` | AWS exploitation framework |
| `roadtools` | Azure AD / Entra ID recon framework |
| `user-scanner` | enumerate valid usernames against a target |
| `hermes-dec` | decompile Hermes bytecode back to JS -- React Native Android APKs ship their JS source pre-compiled to Hermes bytecode instead of plaintext, so this is the way to recover it |
| `rat-king-parser` | malware/RAT config decoder |
| `snaffler-ng` | crawl file shares for sensitive files/credentials |
| `uploadserver` | quick HTTP server with file upload support (exfil staging) |
| `ippserver` | IPP (network printer protocol) server emulation |
| `sqlmap-websocket-proxy` | route `sqlmap` traffic through a WebSocket |
| `nfs_security_tooling`, `vipermonkey`, `wsuks` | additional AD/malware-analysis tooling (confirmed unavailable on a fresh provision at last check -- see `exclude_tools`) |

## Usage

### Option A -- build a fresh VM with Packer

```
sudo apt update && sudo apt install -y ansible git git-lfs packer
git clone <your-remote> kali-provision && cd kali-provision
git lfs pull
ansible-galaxy collection install -r requirements.yml
cd packer && packer init .
packer build -var "source_vmx=/path/to/kali-linux-*-vmware-amd64.vmx" .
```

Produces a finished, standalone VM under `packer/output/`. Downloads Kali's
official prebuilt image first if you don't already have one -- see
`packer/README.md`.

### Option B -- provision an existing Kali box directly

Escalation uses `su` (`ansible.cfg`), not `sudo` -- it needs root's own
password, and Kali ships root locked with no password set at all. Give it
one, once, using the `kali` user's own already-working `sudo` access:

```
sudo passwd root
```

Then:

```
sudo apt update && sudo apt install -y ansible git git-lfs
git clone <your-remote> kali-provision && cd kali-provision
git lfs pull
ansible-galaxy collection install -r requirements.yml
ansible-playbook site.yml -K
```

To target a *different* machine over SSH instead of the one you're running
on: run `bootstrap.yml` once first (it does the `passwd root` step above
remotely, plus installs your SSH key so later runs don't need `-k`), fill in
the `[kali]` group in `inventory.ini` with its IP, then

```
ansible-playbook -i inventory.ini bootstrap.yml -l kali -k -K   # once
ansible-playbook site.yml -i inventory.ini -e target=kali -K
```

(`-k` prompts for the SSH password, `-K` for the become password -- `su`
means that's root's password now, not `kali`'s own.)

### Useful invocations

```
ansible-playbook site.yml -K --tags git,tools       # just re-pull ~/tools
ansible-playbook site.yml -K --tags apt              # just packages
ansible-playbook site.yml -K -e skip_artifacts=true  # no payload tarballs
ansible-playbook site.yml -K --check                 # dry run
```

### On the source machine, to capture current state

```
./scripts/snapshot.sh && git add -A && git lfs status && git commit -m "snapshot $(date -I)"
```

Regenerates `base_packages`, `python_tools` (pipx list), `git_tools`, and the
`artifacts/*.tar.zst` payloads from whatever's actually on the box right now.
Check `git lfs status` before committing -- see the note in Design notes below.

## Design notes

**Git repos track HEAD, not pinned SHAs.** `git_tools/vars/main.yml` records
only name and URL; every run pulls current upstream. Re-running the playbook
is how you update your toolset.

**Nothing re-derivable is stored.** `~/tools` is several GB on disk but a few
dozen lines of YAML here -- the repos are cloned, not copied. The gcloud SDK,
Azure CLI, and Volatility 2's Python 2 environment are all fetched/built fresh
on every run rather than carried in the repo.

**Failures are non-fatal, but reported and asserted where it matters.**
apt/pipx/cargo/go/git steps use `failed_when: false` and print what didn't
install, so one dead upstream doesn't abort a run touching a hundred-plus
packages. A handful of outcomes that turned out to matter in practice
(per-repo venvs actually working, `az` being usable, local `.deb`
packages landing installed rather than half-configured) are backed by a real
`ansible.builtin.assert` instead of just a debug message -- a silent skip in
any of those specifically broke real usage before, so they now fail the play
loudly if they regress.

**`exclude_tools` (in `group_vars/all/main.yml`) is the denylist.** Anything
listed there is skipped by `git_tools`, `python_tools` (pipx), and
`lang_tools` (cargo/go) -- confirmed-broken or not-a-priority tools live here
rather than being silently retried every run. The excluded tool can stay
installed on your own source box; it just won't be provisioned onto a new one.

**No standing root access, anywhere.** Escalation is `su` (`ansible.cfg`),
not `sudo` with a `NOPASSWD` grant -- it needs root's own password every
time, which `bootstrap.yml`/`packer/scripts/setup.sh` set once (Kali ships
root locked, no password at all) rather than handing the provisioning user a
free path to root. `kali` is deliberately kept out of the `docker` group for
the same reason: group membership is root-equivalent with *no* password
needed (`docker run -v /:/host --rm -it alpine chroot /host` is an instant
root shell), which would undo the whole point. `docker`, `vol2`, and
`bloodhound-cli` all need an explicit `sudo` as a result -- which surfaced a
Kali-specific gotcha: its stock `secure_path` omits `/usr/local/{bin,sbin}`
entirely (unlike vanilla Debian), so `sudo vol2` reported "command not
found" even though `vol2` worked fine without `sudo` and via its full path.
`binary_tools` restores the standard Debian `secure_path` via a sudoers
drop-in -- no new capability, just fixing where `sudo` looks.

**Volatility 2 runs in a container, not natively.** It needs Python 2, which
doesn't exist on current Kali at all. `binary_tools` pulls the maintained
`blacktop/volatility` image rather than building one (`roles/binary_tools/files/volatility2/`)
and installs a `vol2` wrapper script that bind-mounts your current directory
in, so `sudo vol2 -f memory.dmp --profile=... pslist` works the way a native
`vol.py` call would.

**Burp Suite** installs from PortSwigger's current release via silent
install4j by default (`burpsuite_install: true` in `group_vars/all/main.yml`),
replacing Kali's apt `burpsuite` package, which lags upstream. Set
`burpsuite_edition: pro` if you have a Pro licence to activate.

## Secrets

This repo contains no credentials. VPN profiles, `~/.aws`, `~/.azure`,
`~/.roadtools_auth`, and Burp settings are deliberately out of scope -- keep
them in a separate `ansible-vault`-encrypted store if you want them
provisioned too. Claude Code installs at its defaults with no bundled
skills/settings -- run `claude` once to authenticate and configure it
however you like.

## License

Licensed under the [MIT License](LICENSE).
