# Creates a fully-provisioned Kali VMware VM in one command.
#
# Source is Kali's official prebuilt VMware image (a .vmx) rather than an ISO +
# preseed — no unattended-install file to maintain. Packer clones it, boots it,
# runs ../site.yml against it over SSH, powers it down, and leaves a ready,
# standalone VM under output/. Open that .vmx in VMware and it's done.
#
#   packer build -var "source_vmx=/path/to/kali.vmx" .   (~15 min, run when needed)
#
# Run from the Arch HOST, not from inside a VM. Requires VMware Workstation,
# packer, the packer vmware plugin, and ansible.

packer {
  required_plugins {
    vmware = {
      source  = "github.com/hashicorp/vmware"
      version = ">= 1.0.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.0.0"
    }
  }
}

variable "source_vmx" {
  type        = string
  description = "Path to the base Kali .vmx (from Kali's official VMware image download, extracted)."
  # e.g. "/home/you/vms/kali-linux-2026.x-vmware-amd64/kali-linux-2026.x-vmware-amd64.vmx"
}

variable "ssh_username" {
  type    = string
  default = "kali"
}

variable "ssh_password" {
  type      = string
  default   = "kali"
  sensitive = true
}

variable "output_dir" {
  type    = string
  default = "output/kali"
}

variable "cpus" {
  type    = number
  default = 4
}

variable "memory" {
  type    = number
  default = 8192
}

source "vmware-vmx" "kali" {
  source_path      = var.source_vmx
  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_password
  ssh_timeout      = "10m"
  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
  output_directory = var.output_dir

  # Full clone: the output VM is self-contained and does not depend on the
  # source image staying in place.
  linked = false

  vmx_data = {
    "numvcpus"  = "${var.cpus}"
    "memsize"   = "${var.memory}"
    "cpuid.coresPerSocket" = "1"
  }

  # Discard the temporary build snapshot in the final image.
  skip_compaction = false
}

build {
  name    = "kali"
  sources = ["source.vmware-vmx.kali"]

  # Kali's official images ship root locked (no password). The script sets
  # one (kali/kali) so `become_method: su` (ansible.cfg) has something to
  # authenticate against -- nothing gets written to sudoers.
  #
  # scripts (not inline): execute_command wraps the whole file under one
  # `sudo -S`, so the script runs entirely as root.
  provisioner "shell" {
    scripts         = ["${path.root}/scripts/setup.sh"]
    execute_command = "echo '${var.ssh_password}' | sudo -S -E sh -eux '{{ .Path }}'"
  }

  provisioner "ansible" {
    playbook_file = "${path.root}/../site.yml"
    # Without this, the provisioner defaults to the OS user running packer
    # instead of the guest's SSH user.
    user = var.ssh_username
    # site.yml's play targets {{ target }}; "all" matches Packer's generated
    # host. ansible_python_interpreter is pinned since auto-discovery caches
    # a version-pinned path at Gathering Facts, and "Purge the stale apt
    # burpsuite" (autoremove: true) can orphan that interpreter mid-run.
    extra_arguments = [
      "-e", "target=all",
      "-e", "ansible_python_interpreter=/usr/bin/python3",
      # ansible.cfg sets become_method=su, needing root's password (set by
      # the shell provisioner above). Passed as -e extra-vars, the one
      # mechanism proven to reach this provisioner's subprocess.
      "-e", "ansible_become_method=su",
      "-e", "ansible_become_password=kali",
      "--scp-extra-args", "'-O'",
    ]
    # ansible.cfg's log_path isn't reliably picked up by this provisioner's
    # subprocess, so set it directly. Absolute path since this subprocess's
    # CWD isn't reliably the repo root.
    ansible_env_vars = [
      "ANSIBLE_LOG_PATH=${path.root}/../ansible.log",
    ]
    # The source only has ssh_password (no baked-in key). use_proxy=true
    # routes Ansible through Packer's local SSH-proxy adapter, bridging the
    # existing password-authenticated communicator session instead of
    # requiring a pre-authorized key on the guest.
    use_proxy = true
  }
}
