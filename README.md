# OpenShift Bootstrap GitOps Repository

This repository contains standardized configurations for bootstrapping new OpenShift clusters with common operational settings.

## Structure

```
├── cluster-configs/          # Cluster-level configurations
│   ├── logging/             # Log management and retention
│   ├── storage/             # Storage classes and persistent volumes
│   ├── monitoring/          # Monitoring and alerting setup
│   ├── networking/          # Network policies and ingress
│   └── security/            # Security policies and RBAC
├── applications/            # Application deployments
└── infrastructure/          # Infrastructure components
    └── disk-partitioning/   # SNO disk partitioning (install-time only)
```

## Quick Start

### 1. Apply Log Retention (Recommended First)
```bash
# Container log rotation (immediate effect)
oc apply -f cluster-configs/logging/kubelet-log-rotation.yaml

# System journal retention (requires node reboot)
oc apply -f cluster-configs/logging/journald-retention.yaml
```

### 2. Monitor Application
```bash
# Check KubeletConfig status
oc get kubeletconfig
oc describe kubeletconfig container-log-rotation

# Check MachineConfig status
oc get machineconfig | grep retention
oc get machineconfigpool
```

## Logging Configuration Details

### Container Logs (`kubelet-log-rotation.yaml`)
- **Max log file size**: 50Mi per container
- **Max log files**: 5 rotated files kept
- **Total per container**: ~250Mi maximum
- **Effect**: Immediate (no reboot required)

### System Logs (`journald-retention.yaml`)
- **Max journal usage**: 2GB total
- **Retention period**: 30 days
- **Rotation**: Daily
- **Effect**: Requires node reboot via MachineConfig

## Current Cluster Analysis
Based on cluster analysis from 2025-08-28:
- **Disk usage**: 29% (276G/953G)
- **Journal logs**: 3.5G
- **API server logs**: 2.1G
- **Pod logs**: 1.6G
- **Status**: Manageable but growing

## Single Node OpenShift (SNO) Disk Partitioning

⚠️ **CRITICAL: Must be done during installation only!**

For SNO clusters, separate your root filesystem from container storage:

1. **Before installation**: Customize `infrastructure/disk-partitioning/98-create-a-partition-for-lvmstorage.yaml`
2. **During installation**: Upload the MachineConfig via Assisted Installer
3. **After installation**: Apply storage configs for LVM-based dynamic provisioning

```bash
# Post-installation: Set up LVM storage
oc apply -f cluster-configs/storage/lvmstorage-operator.yaml
oc apply -f cluster-configs/storage/lvmcluster.yaml
```

See `infrastructure/disk-partitioning/README.md` for detailed instructions.

## Adding to New Clusters

1. **For SNO clusters**: Use disk partitioning configs during installation
2. **For new cluster bootstrap**: Apply all configs in `cluster-configs/`
3. **For existing clusters**: Apply selectively based on needs
4. **With ArgoCD/GitOps**: Point to this repo for automated application

## Configuration Customization

### Adjust Log Retention
Edit the values in the YAML files:
- `containerLogMaxSize`: Increase for verbose applications
- `MaxRetentionSec`: Adjust based on compliance requirements
- `SystemMaxUse`: Scale based on disk size

### Add Additional Configs
- Place new configurations in appropriate subdirectories
- Follow the same naming convention: `component-purpose.yaml`
- Add documentation to this README

## Troubleshooting

### Check Log Rotation Status
```bash
# Container logs
oc logs -n kube-system -l app=node-exporter | grep -i log

# Journal status
oc debug node/NODE_NAME -- chroot /host journalctl --disk-usage
```

### Force Immediate Cleanup
```bash
# Clean old container logs (if needed)
oc debug node/NODE_NAME -- chroot /host find /var/log/pods -name "*.log.*" -mtime +7 -delete

# Vacuum journal logs
oc debug node/NODE_NAME -- chroot /host journalctl --vacuum-time=7d
```
