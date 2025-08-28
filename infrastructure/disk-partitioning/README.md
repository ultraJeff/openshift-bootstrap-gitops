# Single Node OpenShift (SNO) Disk Partitioning

This directory contains configurations for partitioning disks during OpenShift installation to separate the root filesystem from storage that will be used for containers and VMs.

## ⚠️ IMPORTANT: Installation-Time Only

**These configurations MUST be applied during OpenShift installation.** You cannot partition the disk after CoreOS has expanded its rootfs to consume all available space.

## Use Cases

- **Single Node OpenShift (SNO)** with separate storage partition
- **3-node compact clusters** where masters need dedicated storage
- **Preventing root filesystem exhaustion** from container storage
- **LVM-based dynamic storage provisioning**

## Files Overview

### Installation-Time Configurations
- `create-partition-for-lvmstorage.bu` - Butane template (source)
- `98-create-a-partition-for-lvmstorage.yaml` - Ready-to-use MachineConfig

### Post-Installation Storage Setup
- `../cluster-configs/storage/lvmstorage-operator.yaml` - LVMStorage Operator installation
- `../cluster-configs/storage/lvmcluster.yaml` - LVMCluster configuration

## Configuration Details

### Disk Layout
```
/dev/nvme0n1
├── /dev/nvme0n1p1 - EFI System (existing)
├── /dev/nvme0n1p2 - Boot (existing)  
├── /dev/nvme0n1p3 - Root filesystem (limited to 150GB)
└── /dev/nvme0n1p4 - LVM Storage (rest of disk)
```

### Default Settings
- **Root partition size**: 150GB (150,000 MiB)
- **Storage partition**: Uses remaining disk space
- **Device**: `/dev/nvme0n1` (adjust for your hardware)
- **Partition label**: `lvmstorage` (accessible as `/dev/disk/by-partlabel/lvmstorage`)

## Customization Required

Before using these configurations, you MUST update:

1. **Device path** (`device: /dev/nvme0n1`):
   - NVMe: `/dev/nvme0n1`, `/dev/nvme1n1`
   - SATA/SCSI: `/dev/sda`, `/dev/sdb`
   - Virtual: `/dev/vda`, `/dev/vdb`

2. **Root partition size** (`start_mib: 150000`):
   - Minimum: 25GB (25,000 MiB)
   - Recommended: 120GB+ (120,000 MiB)
   - For production: 150GB+ (150,000 MiB)

3. **Storage partition size** (`size_mib: 0`):
   - `0` = use all remaining space
   - Specific size in MiB if you want to limit

## Installation Methods

### Method 1: OpenShift Assisted Installer (Recommended)
1. Go to [console.redhat.com](https://console.redhat.com/openshift/assisted-installer/clusters/~new)
2. Configure your cluster details
3. In **Host discovery** section, click **Add hosts**
4. Under **Advanced networking**, upload the `98-create-a-partition-for-lvmstorage.yaml` file
5. Complete the installation

### Method 2: Agent-based Installer
1. Include the MachineConfig in your `agent-config.yaml`:
   ```yaml
   apiVersion: v1beta1
   kind: AgentConfig
   metadata:
     name: sno-cluster
   additionalNTPSources:
   - pool.ntp.org
   ```
2. Place the MachineConfig in the manifests directory
3. Run the agent-based installer

### Method 3: IPI/UPI with Custom Manifests
1. During `openshift-install create manifests`
2. Copy the MachineConfig to the `manifests/` directory
3. Continue with `openshift-install create cluster`

## Converting Butane to MachineConfig

If you modify the Butane template, regenerate the YAML:

```bash
# Install butane if not already installed
curl -L https://github.com/coreos/butane/releases/latest/download/butane-x86_64-unknown-linux-gnu -o butane
chmod +x butane && sudo mv butane /usr/local/bin/

# Convert Butane to MachineConfig
butane create-partition-for-lvmstorage.bu -o 98-create-a-partition-for-lvmstorage.yaml
```

## Post-Installation: Setting Up LVM Storage

After OpenShift installation completes:

1. **Install LVMStorage Operator**:
   ```bash
   oc apply -f ../cluster-configs/storage/lvmstorage-operator.yaml
   ```

2. **Wait for operator to be ready**:
   ```bash
   oc get csv -n openshift-storage
   ```

3. **Create LVMCluster**:
   ```bash
   oc apply -f ../cluster-configs/storage/lvmcluster.yaml
   ```

4. **Verify storage class**:
   ```bash
   oc get storageclass
   oc get pv
   ```

## Verification Commands

### Check Disk Layout
```bash
# List all disks and partitions
lsblk

# Check partition labels
ls -la /dev/disk/by-partlabel/

# Verify partition sizes
df -h
```

### Check LVM Status
```bash
# List volume groups
sudo vgs

# List logical volumes
sudo lvs

# Check LVM cluster status
oc get lvmcluster -n openshift-storage
```

## Troubleshooting

### Common Issues

1. **Partition not created**:
   - Verify device path matches your hardware
   - Check MachineConfig was applied during installation
   - Review ignition logs: `journalctl -u ignition-firstboot`

2. **LVMCluster not finding disk**:
   - Verify partition exists: `ls /dev/disk/by-partlabel/lvmstorage`
   - Check node labels and selectors in LVMCluster spec
   - Review operator logs: `oc logs -n openshift-storage -l app=lvms-operator`

3. **Storage class not working**:
   - Verify LVMCluster is ready: `oc get lvmcluster`
   - Check for volume group: `sudo vgs`
   - Review CSI driver logs: `oc logs -n openshift-storage -l app=topolvm-controller`

### Emergency Recovery

If you need to reclaim space from the storage partition:
```bash
# WARNING: This will destroy all LVM data
sudo vgremove vg1  # Replace with actual VG name
sudo wipefs -a /dev/disk/by-partlabel/lvmstorage
```

## References

- [Original blog post](https://hackmd.io/@johnsimcall/S1_fuwzyA)
- [OpenShift LVM Storage documentation](https://docs.openshift.com/container-platform/latest/storage/persistent_storage/persistent-storage-lvm.html)
- [Assisted Installer custom manifests](https://access.redhat.com/documentation/en-us/assisted_installer_for_openshift_container_platform/2024/html-single/installing_openshift_container_platform_with_the_assisted_installer/index#setting-the-cluster-details_installing-with-ui)
- [Butane configuration specification](https://coreos.github.io/butane/config-openshift-v4_14/)
