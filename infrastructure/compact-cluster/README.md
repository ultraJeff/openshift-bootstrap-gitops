# Compact 3-Node Cluster Installation

Agent-based installer configuration for a compact 3-node OpenShift cluster with LVM storage partitioning.

## Cluster Topology

| Node | Role | IP | MAC |
|------|------|-----|-----|
| master-0 | master (rendezvous) | 192.168.1.101 | AA:BB:CC:DD:EE:01 |
| master-1 | master | 192.168.1.102 | AA:BB:CC:DD:EE:02 |
| master-2 | master | 192.168.1.103 | AA:BB:CC:DD:EE:03 |

All nodes are masters in a compact cluster (etcd runs on all 3).

## Prerequisites

1. **DNS records** configured:
   - `api.<cluster>.<domain>` → 192.168.1.101 (or load balancer VIP)
   - `*.apps.<cluster>.<domain>` → 192.168.1.101 (or load balancer VIP)

2. **Pull secret** from [console.redhat.com/openshift/install/pull-secret](https://console.redhat.com/openshift/install/pull-secret)

3. **SSH public key** for node access

4. **openshift-install** binary matching your target version

## Directory Structure

```
compact-cluster/
├── install-config.yaml              # Your actual config (gitignored, has secrets)
├── install-config.yaml.example      # Template for reference
├── agent-config.yaml                # Your host configs (gitignored, has real MACs/IPs)
├── agent-config.yaml.example        # Template for reference
├── openshift/
│   ├── 98-master-partition-for-lvmstorage.yaml   # LVM partition (masters)
│   ├── 98-worker-partition-for-lvmstorage.yaml   # LVM partition (workers)
│   ├── 99-master-journald-retention.yaml         # Journal limits (masters)
│   └── 99-worker-journald-retention.yaml         # Journal limits (workers)
├── PXE-BOOT-SETUP.md                # PXE boot configuration guide
└── README.md
```

## Setup

### 1. Copy Example Files

```bash
cd infrastructure/compact-cluster
cp install-config.yaml.example install-config.yaml
cp agent-config.yaml.example agent-config.yaml
```

### 2. Update Configuration Files

**install-config.yaml:**
- Set `metadata.name` to your cluster name
- Set `baseDomain` to your domain
- Set `machineNetwork.cidr` to your network
- Add your pull secret (single-line JSON)
- Add your SSH public key

**agent-config.yaml:**
- Update `rendezvousIP` to your first node's IP
- For each host:
  - Set `hostname`
  - Set `macAddress` (appears twice per host)
  - Set `ip` address
  - Set `dns-resolver` and `routes` for your network

### 3. Download openshift-install

```bash
# Get the latest stable release
VERSION=4.20.8  # Change as needed
curl -LO https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${VERSION}/openshift-install-linux.tar.gz
tar xzf openshift-install-linux.tar.gz
chmod +x openshift-install
sudo mv openshift-install /usr/local/bin/
```

## Installation Steps

### 1. Create a working directory (installer consumes config files)

```bash
# The installer modifies files, so work from a copy
mkdir ~/ocp-install
cp install-config.yaml agent-config.yaml ~/ocp-install/
cp -r openshift ~/ocp-install/
cd ~/ocp-install
```

### 2. Generate the Agent ISO

```bash
openshift-install agent create image --dir .
```

This creates `agent.x86_64.iso` with:
- All node configurations embedded
- Disk partitioning manifest included
- Static network settings baked in

### 3. Boot All Nodes

1. Copy `agent.x86_64.iso` to a USB drive or mount via IPMI/BMC
2. Boot **all 3 nodes** from the ISO (order doesn't matter)
3. Nodes will self-discover and begin installation

### 4. Monitor Installation

```bash
# From your workstation (where you ran openshift-install)
openshift-install agent wait-for bootstrap-complete --dir . --log-level=info

# Then wait for full install
openshift-install agent wait-for install-complete --dir . --log-level=info
```

### 5. Access the Cluster

After installation completes:

```bash
export KUBECONFIG=~/ocp-install/auth/kubeconfig
oc get nodes
oc get co
```

The `auth/` directory contains:
- `kubeconfig` - cluster admin credentials
- `kubeadmin-password` - web console password

## Post-Installation

### Verify Disk Partitioning

```bash
# Check that all nodes have the lvmstorage partition
for node in master-0 master-1 master-2; do
  echo "=== $node ==="
  oc debug node/$node -- chroot /host lsblk /dev/nvme0n1
done
```

Expected output shows partition 5 with label `lvmstorage`.

### Install LVM Storage Operator

Apply the storage configurations from this repo:

```bash
oc apply -k cluster-configs/storage/
```

### Apply Other Cluster Configs

```bash
oc apply -k cluster-configs/
```

## Disk Layout

Each node will have:

```
/dev/nvme0n1
├── nvme0n1p1 - EFI System Partition
├── nvme0n1p2 - Boot partition
├── nvme0n1p3 - Boot backup
├── nvme0n1p4 - Root filesystem (150GB)
└── nvme0n1p5 - LVM Storage (remaining space, labeled "lvmstorage")
```

## Troubleshooting

### Nodes not discovering each other

- Verify all MACs match physical interfaces
- Check network connectivity between nodes
- Ensure DNS resolves correctly

### Installation stuck

```bash
# SSH to rendezvous host
ssh core@<rendezvous-ip>

# Check agent logs
journalctl -u agent.service -f
```

### Gather debug info

```bash
openshift-install agent gather-logs --dir .
```

## References

- [Agent-based Installer documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/installing_an_on-premise_cluster_with_the_agent-based_installer/)
- [Disk partitioning with Agent-based Installer](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/installing_an_on-premise_cluster_with_the_agent-based_installer/installing-with-agent-based-installer#installing-ocp-agent-inputs_installing-with-agent-based-installer)
