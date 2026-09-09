#!/bin/sh
# Runs as root already (execute_command in kali.pkr.hcl wraps the whole
# script under one `sudo`), so nothing in here needs its own sudo.
set -eux

# Kali's official images ship root locked (no password). Sets it to
# kali/kali so `become_method: su` (ansible.cfg) has something to
# authenticate against.
echo "root:kali" | chpasswd

# Kali's default http.kali.org redirector load-balances to mirrors that
# intermittently 403 on individual .deb files. Pin the Cloudflare CDN.
# Works for both the classic sources.list and the newer deb822 kali.sources.
grep -rlE 'https?://[a-z0-9.-]*kali[.]org/kali' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null | xargs -r sed -i -E 's#https?://[a-z0-9.-]*kali[.]org/kali#http://kali.download/kali#g'

apt-get update -y

# Only what Ansible needs on the target: python3-apt for the apt module and
# zstd for the payload unarchive.
apt-get install -y --no-install-recommends python3-apt zstd
