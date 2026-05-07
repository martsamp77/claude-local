---
name: linux-packages
description: "[linux] Install, remove, upgrade, search, list, and pin packages on Linux. Detects the distro family from /etc/os-release and dispatches to apt (Debian/Ubuntu), dnf (Fedora/RHEL), or pacman (Arch)."
---

# linux-packages

Use this skill for any package operation on Linux. The right tool depends on the distro family — detect first, then dispatch.

## Detect the package manager

```bash
. /etc/os-release
case "${ID_LIKE:-$ID}" in
    *debian*|*ubuntu*) PM=apt ;;
    *fedora*|*rhel*|*centos*) PM=dnf ;;
    *arch*)            PM=pacman ;;
    *suse*)            PM=zypper ;;
    *)                 echo "Unknown distro family: $ID / ${ID_LIKE:-}" >&2 ;;
esac
```

Most desktops Marty would install on are Debian/Ubuntu (`apt`), Fedora/RHEL (`dnf`), or Arch (`pacman`). The rest of this skill covers those three. SUSE/zypper exists but is rare for personal use; if it comes up, the patterns below port over directly.

## Cheat sheet

| Operation | apt (Debian/Ubuntu) | dnf (Fedora/RHEL) | pacman (Arch) |
|---|---|---|---|
| Update package index | `sudo apt update` | (auto each command) | `sudo pacman -Sy` |
| Search | `apt search <query>` | `dnf search <query>` | `pacman -Ss <query>` |
| Show info | `apt show <pkg>` | `dnf info <pkg>` | `pacman -Si <pkg>` |
| Install | `sudo apt install <pkg>` | `sudo dnf install <pkg>` | `sudo pacman -S <pkg>` |
| Remove | `sudo apt remove <pkg>` | `sudo dnf remove <pkg>` | `sudo pacman -R <pkg>` |
| Remove + configs | `sudo apt purge <pkg>` | `sudo dnf remove <pkg>` (same) | `sudo pacman -Rns <pkg>` |
| Upgrade everything | `sudo apt update && sudo apt upgrade` | `sudo dnf upgrade` | `sudo pacman -Syu` |
| List installed | `apt list --installed` | `dnf list installed` | `pacman -Q` |
| List explicitly installed | `apt-mark showmanual` | `dnf repoquery --userinstalled` | `pacman -Qe` |
| Hold / pin | `sudo apt-mark hold <pkg>` | `sudo dnf versionlock add <pkg>` (needs `dnf-plugins-core`) | edit `/etc/pacman.conf` `IgnorePkg = <pkg>` |
| Unhold | `sudo apt-mark unhold <pkg>` | `sudo dnf versionlock delete <pkg>` | remove from `IgnorePkg` |
| Which package owns a file | `dpkg -S /path/to/file` | `dnf provides /path/to/file` | `pacman -Qo /path/to/file` |
| Clean caches | `sudo apt autoremove && sudo apt clean` | `sudo dnf autoremove && sudo dnf clean all` | `sudo pacman -Rns $(pacman -Qtdq)` (orphans) + `sudo paccache -r` |

## Cross-distro install patterns

### Flatpak (cross-distro, GUI apps)

```bash
flatpak search <query>
flatpak install flathub <app-id>
flatpak update
flatpak uninstall <app-id>
flatpak list --app
```

Flathub apps run sandboxed; safer for unfamiliar apps. Default to flatpak for most desktop GUI apps unless the distro repo version is well-maintained.

### Snap (Ubuntu primarily)

```bash
snap find <query>
sudo snap install <app>
sudo snap refresh
sudo snap remove <app>
snap list
sudo snap refresh --hold=72h     # defer auto-refresh
```

Snap is mandatory for some Ubuntu packages (Firefox on 22.04+). Check whether the deb version is also available — many users prefer apt installs from a PPA over snap.

### AUR (Arch)

```bash
# After installing an AUR helper like yay or paru:
yay -Ss <query>
yay -S <pkg>
yay -Syu --aur
```

Don't `curl | sh` AUR packages; use a helper that audits PKGBUILDs. Read PKGBUILD before building anything from an obscure AUR submitter.

## Safety

- **System-wide installs require explicit confirmation.** `apt install`, `dnf install`, `pacman -S` modify the system. Per CLAUDE.md, get a clear yes from Marty before each install/remove on Linux.
- **Don't `apt full-upgrade` or `pacman -Syu` casually on Arch** — major upgrades can require manual intervention. Read release notes first.
- **`apt remove` keeps configs; `apt purge` removes them.** Choose deliberately. Default to `remove` unless reinstall would otherwise pick up old broken config.
- **Never disable repository signature checks** (`--allow-unauthenticated`, `--nogpgcheck`, `SigLevel = Never`) without an explicit instruction.
- **Backup `/etc/apt/sources.list*`, `/etc/yum.repos.d/`, or `/etc/pacman.conf` before editing** — copy to `backups/linux/etc/<ts>/` per CLAUDE.md.

## Common patterns

**Install a fresh dev tool across distros:**

```bash
# Detect once, then:
case "$PM" in
    apt)    sudo apt update && sudo apt install -y ripgrep ;;
    dnf)    sudo dnf install -y ripgrep ;;
    pacman) sudo pacman -S --needed --noconfirm ripgrep ;;
esac
```

**Find what's grown your disk:**

```bash
# Debian/Ubuntu: largest installed packages
dpkg-query -W -f='${Installed-Size}\t${Package}\n' | sort -rn | head -20

# Fedora/RHEL
rpm -qa --queryformat '%{SIZE} %{NAME}\n' | sort -rn | head -20

# Arch
pacman -Qi | awk '/^Name/{n=$3} /^Installed Size/{print $4$5, n}' | sort -rh | head -20
```

**Reinstall a package whose files got corrupted:**

```bash
sudo apt install --reinstall <pkg>
sudo dnf reinstall <pkg>
sudo pacman -S <pkg>            # re-installs even if up to date
```

**See what would change** before running an upgrade:

```bash
apt list --upgradable
dnf check-update
pacman -Qu
```
