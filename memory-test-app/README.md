# Memory Test Application

A simple Python application that consumes exactly 2GB of memory for testing OpenShift resource limits and constraints. This application is designed to help validate memory resource management, monitoring, and alerting in OpenShift environments.

## Features

- **Controlled Memory Allocation**: Allocates exactly 2GB of memory on startup
- **Health Endpoints**: Provides `/health` and `/ready` endpoints for Kubernetes probes
- **Memory Statistics**: Real-time memory usage reporting via `/memory` endpoint  
- **Dynamic Control**: Endpoints to allocate (`/allocate`) and release (`/release`) memory
- **OpenShift Ready**: Follows OpenShift security best practices and constraints

## Application Endpoints

- `/` - Application info and current memory stats
- `/health` - Health check endpoint (for liveness probes)
- `/ready` - Readiness check endpoint (for readiness probes)
- `/memory` - Detailed memory statistics
- `/allocate` - Trigger memory allocation (allocates 2GB)
- `/release` - Release allocated memory

## Quick Start

### Prerequisites

- OpenShift CLI (`oc`) installed and authenticated
- Access to an OpenShift cluster with cluster-admin or sufficient permissions
- Your OpenShift server: `https://api.cluster-k252r.k252r.sandbox1112.opentlc.com:6443`

### Option 1: Build and Deploy in OpenShift (Recommended)

1. **Create the project and build resources:**
   ```bash
   # Create namespace and build configuration
   oc apply -f buildconfig.yaml
   ```

2. **Build the application:**
   ```bash
   # Start a binary build from the current directory
   oc start-build memory-test-app-build --from-dir=. --follow
   ```

3. **Deploy the application:**
   ```bash
   # Deploy with resource limits
   oc apply -f deployment.yaml
   ```

4. **Verify deployment:**
   ```bash
   # Check pod status
   oc get pods -n memory-test
   
   # Check resource allocation
   oc describe pod -l app=memory-test-app -n memory-test
   
   # Get the application URL
   oc get route memory-test-app-route -n memory-test
   ```

### Option 2: Build Locally and Push

1. **Build the container image locally:**
   ```bash
   # Build the image
   podman build -t memory-test-app:latest .
   
   # Tag for your registry
   podman tag memory-test-app:latest <your-registry>/memory-test-app:latest
   
   # Push to registry
   podman push <your-registry>/memory-test-app:latest
   ```

2. **Update deployment.yaml:**
   ```bash
   # Edit deployment.yaml to use your image
   sed -i 's|memory-test-app:latest|<your-registry>/memory-test-app:latest|' deployment.yaml
   ```

3. **Deploy to OpenShift:**
   ```bash
   oc apply -f deployment.yaml
   ```

## Resource Configuration

The application is configured with the following resource limits in `deployment.yaml`:

```yaml
resources:
  limits:
    memory: "2Gi"     # Hard limit - pod killed if exceeded
    cpu: "1"          # 1 CPU core limit
  requests:
    memory: "2Gi"     # Guaranteed allocation
    cpu: "500m"       # 0.5 CPU core request
```

### Resource Testing Scenarios

1. **Normal Operation**: App allocates 2GB and should run normally
2. **Memory Pressure**: Monitor behavior when node memory is constrained
3. **Limit Testing**: App should be killed if it tries to exceed 2GB limit
4. **Request Validation**: Pod should only be scheduled on nodes with 2GB+ available

## Monitoring and Testing

### Basic Health Checks

```bash
# Get the route URL
ROUTE_URL=$(oc get route memory-test-app-route -n memory-test -o jsonpath='{.spec.host}')

# Check application status
curl https://$ROUTE_URL/

# Check memory statistics
curl https://$ROUTE_URL/memory

# Check health endpoints
curl https://$ROUTE_URL/health
curl https://$ROUTE_URL/ready
```

### Memory Management Testing

```bash
# Force memory allocation (if not already allocated)
curl https://$ROUTE_URL/allocate

# Release memory
curl https://$ROUTE_URL/release

# Re-allocate memory
curl https://$ROUTE_URL/allocate
```

### Resource Monitoring

```bash
# Watch pod resource usage
oc adm top pods -n memory-test

# Get detailed pod resource information
oc describe pod -l app=memory-test-app -n memory-test

# Check pod events for resource-related issues
oc get events -n memory-test --field-selector involvedObject.kind=Pod

# Monitor pod logs
oc logs -f -l app=memory-test-app -n memory-test
```

## Troubleshooting

### Common Issues

1. **Pod OOMKilled**: 
   - The application exceeded the 2GB memory limit
   - Check events: `oc get events -n memory-test`
   - Increase limit if needed or investigate memory leaks

2. **Pod Pending**: 
   - Not enough memory available on nodes to satisfy 2GB request
   - Check node resources: `oc describe nodes`
   - Consider lowering memory request for testing

3. **Build Failures**:
   - Check build logs: `oc logs -f bc/memory-test-app-build -n memory-test`
   - Ensure Dockerfile and dependencies are correct

4. **Route Not Accessible**:
   - Verify route exists: `oc get route -n memory-test`
   - Check service endpoints: `oc get endpoints -n memory-test`

### Debug Commands

```bash
# Get detailed pod information
oc describe pod -l app=memory-test-app -n memory-test

# Check resource quotas
oc describe quota -n memory-test

# Debug networking
oc get svc,route -n memory-test

# Check pod logs
oc logs -l app=memory-test-app -n memory-test

# Execute commands in the pod
oc exec -it deployment/memory-test-app -n memory-test -- /bin/bash
```

## Cleanup

To remove the application and all resources:

```bash
# Delete all resources
oc delete namespace memory-test

# Or delete individual components
oc delete -f deployment.yaml
oc delete -f buildconfig.yaml
```

## File Structure

```
memory-test-app/
├── app.py              # Main Python application
├── requirements.txt    # Python dependencies
├── Dockerfile         # Container build instructions
├── buildconfig.yaml   # OpenShift build configuration
├── deployment.yaml    # OpenShift deployment with resource limits
└── README.md          # This file
```

## Development

### Local Testing

```bash
# Install dependencies
pip install -r requirements.txt

# Run locally
python app.py

# Test endpoints
curl http://localhost:8080/
curl http://localhost:8080/memory
curl http://localhost:8080/allocate
```

### Memory Allocation Details

- Target: 2GB (2,147,483,648 bytes)
- Allocation method: 10MB chunks filled with test data
- Memory is held in a global list to prevent garbage collection
- Uses `psutil` for accurate memory reporting
- Includes RSS (Resident Set Size) and VMS (Virtual Memory Size) metrics

## Security

The application follows OpenShift security best practices:

- Runs as non-root user (UID 1001)
- No privileged escalation
- Minimal capabilities
- Security context profiles applied
- Uses Red Hat UBI base images

This application is perfect for testing OpenShift resource management, monitoring systems, and validating memory-based horizontal pod autoscaling configurations.