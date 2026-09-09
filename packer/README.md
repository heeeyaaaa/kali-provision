# Building a Kali VM on an Arch host with VMware

One command creates the VMware VM and provisions it. Packer clones Kali's
official VMware image, runs `../site.yml` against it over SSH, and leaves a
ready, standalone VM you open in VMware. Re-run whenever you need a fresh one --
every git repo, apt package, and pipx app is re-pulled at latest during the run.

## One-time host setup (Arch)

```
sudo pacman -S --needed packer ansible git-lfs
packer plugins install github.com/hashicorp/vmware
```

VMware Workstation must be installed and licensed (provides `vmrun`/`vmware-vmx`).
Download and install it from broadcom.com/products/vmware-workstation.

Download Kali's official **VMware** image from https://www.kali.org/get-kali/
(the "Virtual Machines" tab → VMware), extract it, and note the path to its
`.vmx` file.

## Build

```
cd packer
packer init .
packer build -var "source_vmx=/path/to/kali-...-vmware-amd64.vmx" .
```

Then once Packer clones the VM you will need to manually log into `kali` and
run `sudo systemctl enable --now ssh` to start the SSH service before Packer
can connect.

The finished VM lands in `packer/output/kali/`. Open the `.vmx` in VMware and
it's ready. Tunables: `-var cpus=6`, `-var memory=16384`, and
`-var 'ssh_password=...'` if your base image doesn't use the default `kali`/`kali`.

## Notes

- **`git lfs pull` first.** The Ansible run copies the payload tarballs
  (`artifacts/*.tar.zst`, ~167 MB) into the VM over SSH, so they must be real
  files locally, not LFS pointers.
- **Credentials:** defaults assume Kali's `kali`/`kali`. The build hardcodes
  root's password to `kali` too (Kali ships root locked, no password at all
  -- see `packer/scripts/setup.sh`) and Ansible escalates with
  `become_method: su` against it, supplied non-interactively via `-e
  ansible_become_password=kali` -- nothing gets written to sudoers, so the
  finished VM has no standing passwordless-escalation path.
- **Prefer clicking "New VM" yourself?** If you'd rather create the VM by hand in
  the VMware GUI, skip Packer entirely and provision it over SSH instead -- see the
  `bootstrap.yml` flow in the top-level README (`-e target=kali`). Same end result,
  no host tooling beyond Ansible.
- **From-ISO instead of from-image?** The `vmware-vmx` source can be swapped for
  `vmware-iso` with a `boot_command` + preseed if you'd rather build from the
  installer ISO. The `vmx` route is used here because it needs no preseed file.
