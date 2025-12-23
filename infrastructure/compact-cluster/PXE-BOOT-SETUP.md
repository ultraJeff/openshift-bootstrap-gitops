# PXE Boot Setup for OpenShift Agent-Based Installer

This document describes how to configure PXE boot on an OpenWrt router (GL.iNet GL-AXT1800) to network boot OpenShift nodes using the agent-based installer.

## Overview

Instead of using USB drives for each node, PXE boot allows all nodes to boot from the network using a single set of boot files hosted on the router.

```
┌─────────────────────────────────────────────────────────────┐
│  Node boots → DHCP → TFTP (iPXE) → HTTP (kernel/initrd/rootfs)  │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- OpenWrt router with:
  - dnsmasq (DHCP/TFTP server)
  - uhttpd (HTTP server)
  - Sufficient storage (~1.5GB for boot files)
- Generated PXE files from `openshift-install agent create pxe-files`

## Router Configuration

### 1. Directory Structure

```
/srv/tftp/                          # TFTP root
├── ipxe.efi                        # iPXE bootloader (UEFI)
├── agent.x86_64-vmlinuz            # Linux kernel
├── agent.x86_64-initrd.img         # Initial ramdisk
└── agent.x86_64-rootfs.img         # Root filesystem (1.1GB)

/www/pxe/                           # HTTP served directory
├── boot.ipxe                       # iPXE boot script
├── agent.x86_64-vmlinuz      → symlink to /srv/tftp/
├── agent.x86_64-initrd.img   → symlink to /srv/tftp/
└── agent.x86_64-rootfs.img   → symlink to /srv/tftp/
```

### 2. TFTP Configuration (dnsmasq)

Enable TFTP and set the root directory:

```bash
uci set dhcp.@dnsmasq[0].enable_tftp='1'
uci set dhcp.@dnsmasq[0].tftp_root='/srv/tftp'
uci commit dhcp
```

### 3. HTTP Configuration (uhttpd)

Add LAN listener for serving boot files:

```bash
uci add_list uhttpd.main.listen_http='192.168.8.1:8080'
uci commit uhttpd
/etc/init.d/uhttpd restart
```

Verify HTTP is accessible:
```bash
curl -I http://192.168.8.1:8080/pxe/agent.x86_64-rootfs.img
```

### 4. iPXE Chainloading Configuration

Create `/etc/dnsmasq.d/pxe.conf`:

```
# Tag iPXE clients (they send option 175)
dhcp-match=set:ipxe,175

# Serve boot.ipxe script to iPXE clients via HTTP
dhcp-boot=tag:ipxe,http://192.168.8.1:8080/pxe/boot.ipxe

# Serve ipxe.efi to regular PXE clients via TFTP
dhcp-boot=tag:!ipxe,ipxe.efi,,192.168.8.1
```

Enable the config directory:
```bash
uci set dhcp.@dnsmasq[0].confdir='/etc/dnsmasq.d'
uci commit dhcp
/etc/init.d/dnsmasq restart
```

### 5. iPXE Boot Script

Create `/srv/tftp/autoexec.ipxe` (suppresses "not found" warning):

```
#!ipxe
# Chain to the OpenShift boot script
chain http://192.168.8.1:8080/pxe/boot.ipxe
```

Create `/www/pxe/boot.ipxe`:

```
#!ipxe
echo Booting OpenShift Agent Installer...
kernel http://192.168.8.1:8080/pxe/agent.x86_64-vmlinuz coreos.live.rootfs_url=http://192.168.8.1:8080/pxe/agent.x86_64-rootfs.img ignition.firstboot ignition.platform.id=metal rw initrd=agent.x86_64-initrd.img
initrd http://192.168.8.1:8080/pxe/agent.x86_64-initrd.img
boot
```

## Boot Flow

1. **Node powers on** and requests DHCP
2. **dnsmasq** responds with IP and PXE boot file (`ipxe.efi`)
3. **Node downloads** `ipxe.efi` via TFTP
4. **iPXE starts** and requests DHCP again (with option 175)
5. **dnsmasq** recognizes iPXE and responds with script URL
6. **iPXE downloads** and executes `boot.ipxe` via HTTP
7. **Script loads** kernel and initrd via HTTP
8. **Kernel boots** and downloads rootfs via HTTP
9. **Agent installer** starts

## File Downloads

### iPXE Bootloader
```bash
wget -O /srv/tftp/ipxe.efi 'http://boot.ipxe.org/ipxe.efi'
```

### OpenShift PXE Files
```bash
# Generate on your workstation
openshift-install agent create pxe-files --dir .

# Copy to router (use -O for legacy scp)
scp -O boot-artifacts/* root@192.168.8.1:/srv/tftp/
```

## Troubleshooting

### Check DHCP/TFTP logs
```bash
logread | grep -iE '(tftp|dhcp|pxe)'
```

### Verify files are accessible
```bash
# TFTP
tftp 192.168.8.1 -c get ipxe.efi

# HTTP
curl -I http://192.168.8.1:8080/pxe/boot.ipxe
curl -I http://192.168.8.1:8080/pxe/agent.x86_64-rootfs.img
```

### Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| Node returns to boot menu | Secure Boot enabled | Disable Secure Boot in UEFI |
| TFTP timeout | Firewall blocking | Check router firewall rules |
| iPXE shell appears | Script not found | Verify `/www/pxe/boot.ipxe` exists |
| Kernel panic | Rootfs URL wrong | Check `coreos.live.rootfs_url` parameter |

## Updating the PXE Image

To update the boot files for a new installation or OpenShift version:

### 1. Regenerate PXE Files

On your workstation, create a fresh working directory with updated configs:

```bash
# Create new working directory
mkdir ~/ocp-install-new
cd ~/ocp-install-new

# Copy your config files
cp /path/to/install-config.yaml .
cp /path/to/agent-config.yaml .
cp -r /path/to/openshift .

# Download the desired openshift-install version
VERSION=4.20.8  # Update to target version
curl -LO https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${VERSION}/openshift-install-linux.tar.gz
tar xzf openshift-install-linux.tar.gz

# Generate new PXE files
./openshift-install agent create pxe-files --dir .
```

### 2. Update Files on Router

```bash
# SSH to router and remove old files
ssh root@192.168.8.1 "rm -f /srv/tftp/agent.x86_64-*"

# Copy new files (use -O for OpenWrt compatibility)
scp -O boot-artifacts/agent.x86_64-vmlinuz root@192.168.8.1:/srv/tftp/
scp -O boot-artifacts/agent.x86_64-initrd.img root@192.168.8.1:/srv/tftp/
scp -O boot-artifacts/agent.x86_64-rootfs.img root@192.168.8.1:/srv/tftp/

# Verify files are in place
ssh root@192.168.8.1 "ls -lh /srv/tftp/agent.*"
```

### 3. Verify HTTP Symlinks

The symlinks in `/www/pxe/` should still work since they point to `/srv/tftp/`:

```bash
ssh root@192.168.8.1 "ls -la /www/pxe/"
```

If symlinks are missing, recreate them:

```bash
ssh root@192.168.8.1 "
  ln -sf /srv/tftp/agent.x86_64-vmlinuz /www/pxe/
  ln -sf /srv/tftp/agent.x86_64-initrd.img /www/pxe/
  ln -sf /srv/tftp/agent.x86_64-rootfs.img /www/pxe/
"
```

### 4. Test HTTP Access

```bash
curl -I http://192.168.8.1:8080/pxe/agent.x86_64-rootfs.img
```

The boot script (`/www/pxe/boot.ipxe`) doesn't need to change unless you're modifying kernel parameters.

## Cleanup

To remove PXE boot configuration:

```bash
# Remove boot files
rm -rf /srv/tftp/agent.* /srv/tftp/ipxe.efi
rm -rf /www/pxe/

# Remove dnsmasq config
rm /etc/dnsmasq.d/pxe.conf
uci delete dhcp.@dnsmasq[0].confdir
uci commit dhcp
/etc/init.d/dnsmasq restart

# Remove HTTP listener (optional)
uci del_list uhttpd.main.listen_http='192.168.8.1:8080'
uci commit uhttpd
/etc/init.d/uhttpd restart
```

## References

- [iPXE Documentation](https://ipxe.org/docs)
- [OpenWrt dnsmasq PXE](https://openwrt.org/docs/guide-user/services/dhcp/dnsmasq-pxe)
- [OpenShift Agent-Based Installer - PXE](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/installing_an_on-premise_cluster_with_the_agent-based_installer/)
