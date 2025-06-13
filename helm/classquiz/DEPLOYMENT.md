# ClassQuiz OpenShift Deployment Guide

This guide provides step-by-step instructions for deploying ClassQuiz to OpenShift using Helm.

## Prerequisites

- OpenShift cluster access
- `oc` CLI tool installed
- `helm` CLI tool installed (v3.x)
- Git repository cloned locally
- Access to OpenShift's internal registry
- Podman (for local image building)
- Project admin privileges in your OpenShift project

## 1. Prepare OpenShift Environment

### 1.1 Login to OpenShift

```bash
# Login to your OpenShift cluster
oc login <your-cluster-url>

# Verify login
oc whoami
```

### 1.2 Create Project

```bash
# Create a new project (if it doesn't exist)
oc new-project classquiz

# Verify project creation
oc project classquiz
```

## 2. Build and Push Container Images

### 2.1 Clean Up Existing Resources (Optional)

If you need to start fresh or are encountering build issues, you can clean up existing resources:

```bash
# Delete all related image stream tags that might cause conflicts
oc delete istag frontend:latest api:latest -n classquiz 2>/dev/null || true
oc delete istag classquiz/frontend:latest classquiz/api:latest -n classquiz 2>/dev/null || true

# Delete all related build configurations and image streams
oc delete bc,is frontend classquiz-frontend classquiz-api -n classquiz 2>/dev/null || true

# Verify cleanup
echo "Checking remaining resources..."
oc get bc,is,istag -n classquiz
```

### 2.2 Frontend Image

```bash
# Ensure we're in the right project
oc project classquiz

# Remove the specific image stream tag if it exists
echo "Checking for existing image stream tags..."
for tag in frontend:latest classquiz/frontend:latest; do
    if oc get istag $tag -n classquiz &>/dev/null; then
        echo "Removing existing image stream tag $tag..."
        oc delete istag $tag -n classquiz
        # Wait for the tag to be fully removed
        while oc get istag $tag -n classquiz &>/dev/null; do
            echo "Waiting for image stream tag to be removed..."
            sleep 2
        done
    fi
done

# Create the build configuration
echo "Creating build configuration..."
oc new-build --name=classquiz-frontend \
  --strategy=docker \
  --binary=true \
  --to=classquiz/frontend:latest

# Verify build config was created
if ! oc get bc classquiz-frontend -n classquiz &>/dev/null; then
    echo "Error: Failed to create build configuration"
    exit 1
fi

# Start the build from the frontend directory
echo "Starting build..."
oc start-build classquiz-frontend \
  --from-dir=./frontend \
  --follow

# Verify the image was created
echo "Verifying image..."
oc get is classquiz-frontend -n classquiz
```

### 2.3 API Image

```bash
# Remove the specific image stream tag if it exists
echo "Checking for existing image stream tags..."
for tag in api:latest classquiz/api:latest; do
    if oc get istag $tag -n classquiz &>/dev/null; then
        echo "Removing existing image stream tag $tag..."
        oc delete istag $tag -n classquiz
        # Wait for the tag to be fully removed
        while oc get istag $tag -n classquiz &>/dev/null; do
            echo "Waiting for image stream tag to be removed..."
            sleep 2
        done
    fi
done

# Create the build configuration
echo "Creating build configuration..."
oc new-build --name=classquiz-api \
  --strategy=docker \
  --binary=true \
  --to=classquiz/api:latest

# Verify build config was created
if ! oc get bc classquiz-api -n classquiz &>/dev/null; then
    echo "Error: Failed to create build configuration"
    exit 1
fi

# Start the build from the root directory
echo "Starting build..."
oc start-build classquiz-api \
  --from-dir=. \
  --follow

# Verify the image was created
echo "Verifying image..."
oc get is classquiz-api -n classquiz
```

### 2.4 Troubleshooting Build Issues

If you encounter build issues:

```bash
# Check build status
oc get builds -n classquiz

# View build logs
oc logs -f build/classquiz-frontend-<build-number> -n classquiz
oc logs -f build/classquiz-api-<build-number> -n classquiz

# Check build configuration
oc describe bc classquiz-frontend -n classquiz
oc describe bc classquiz-api -n classquiz

# Check image stream status
oc describe is classquiz-frontend -n classquiz
oc describe is classquiz-api -n classquiz
```

Common build issues and solutions:

1. **"Image stream tag already exists" error**:
   ```bash
   # Remove all related image stream tags
   for tag in frontend:latest classquiz/frontend:latest api:latest classquiz/api:latest; do
       oc delete istag $tag -n classquiz 2>/dev/null || true
   done

   # Wait for tags to be fully removed
   for tag in frontend:latest classquiz/frontend:latest api:latest classquiz/api:latest; do
       while oc get istag $tag -n classquiz &>/dev/null; do
           echo "Waiting for $tag to be removed..."
           sleep 2
       done
   done

   # Then retry the build steps
   ```

2. **Build timeout**:
   ```bash
   # Increase build timeout and resources
   oc patch bc classquiz-frontend -n classquiz -p '{"spec":{"resources":{"limits":{"cpu":"2","memory":"4Gi"}}}}'
   oc patch bc classquiz-api -n classquiz -p '{"spec":{"resources":{"limits":{"cpu":"2","memory":"4Gi"}}}}'
   ```

3. **Build stuck in pending state**:
   ```bash
   # Check build pod status
   oc get pods -n classquiz | grep build

   # Delete stuck build
   oc delete build classquiz-frontend-<build-number> -n classquiz
   oc delete build classquiz-api-<build-number> -n classquiz

   # Retry build
   oc start-build classquiz-frontend --from-dir=./frontend --follow
   oc start-build classquiz-api --from-dir=. --follow
   ```

4. **Image stream tag not found after build**:
   ```bash
   # Check if the image stream exists
   oc get is -n classquiz

   # If needed, create the image stream manually
   oc create is classquiz-frontend -n classquiz
   oc create is classquiz-api -n classquiz

   # Retry the build
   oc start-build classquiz-frontend --from-dir=./frontend --follow
   oc start-build classquiz-api --from-dir=. --follow
   ```

## 3. Prepare Helm Deployment

### 3.1 Create Custom Values File

Create a file named `my-values.yaml` with your environment-specific configuration:

```yaml
global:
  imageRegistry: "image-registry.openshift-image-registry.svc:5000"
  storageClass: "standard"  # Change to your OpenShift storage class

frontend:
  image:
    repository: classquiz/frontend
    tag: latest
  route:
    host: your-domain.com
    tls:
      enabled: true
      termination: edge

api:
  image:
    repository: classquiz/api
    tag: latest
  route:
    host: api.your-domain.com
    tls:
      enabled: true
      termination: edge
  config:
    rootAddress: "https://your-domain.com"
    secretKey: "your-secret-key"  # Change this!
    maxWorkers: "1"
    accessTokenExpireMinutes: 30
    skipEmailVerification: "True"
    storageBackend: "local"
    storagePath: "/app/data"

postgresql:
  password: "your-db-password"  # Change this!
  persistence:
    size: 10Gi

meilisearch:
  persistence:
    size: 10Gi

storage:
  uploads:
    enabled: true
    size: 20Gi
    accessMode: ReadWriteMany
```

### 3.2 Package Helm Chart

```bash
# Navigate to the helm directory
cd helm

# Package the chart
helm package classquiz

# Verify the package was created
ls -l classquiz-*.tgz
```

## 4. Deploy the Application

### 4.1 Install Helm Chart

```bash
# Install the chart with your custom values
helm install classquiz ./classquiz-0.1.0.tgz \
  -f my-values.yaml \
  --namespace classquiz

# Verify the release
helm list -n classquiz
```

### 4.2 Verify Deployment

```bash
# Check all pods are running
oc get pods -n classquiz

# Check services
oc get services -n classquiz

# Check routes
oc get routes -n classquiz

# Check persistent volume claims
oc get pvc -n classquiz
```

## 5. Access the Application

After deployment, you can access the application at:
- Frontend: `https://your-domain.com`
- API: `https://api.your-domain.com`

## 6. Monitoring and Maintenance

### 6.1 View Logs

```bash
# Frontend logs
oc logs -f deployment/classquiz-frontend -n classquiz

# API logs
oc logs -f deployment/classquiz-api -n classquiz

# Worker logs
oc logs -f deployment/classquiz-worker -n classquiz

# Database logs
oc logs -f statefulset/classquiz-postgresql -n classquiz

# Redis logs
oc logs -f statefulset/classquiz-redis -n classquiz

# Meilisearch logs
oc logs -f statefulset/classquiz-meilisearch -n classquiz
```

### 6.2 Scale Components

```bash
# Scale frontend
oc scale deployment classquiz-frontend --replicas=2 -n classquiz

# Scale API
oc scale deployment classquiz-api --replicas=2 -n classquiz

# Scale worker
oc scale deployment classquiz-worker --replicas=2 -n classquiz
```

## 7. Backup and Restore

### 7.1 Backup PostgreSQL

```bash
# Create a backup
oc exec -it $(oc get pod -l app.kubernetes.io/component=postgresql -o jsonpath='{.items[0].metadata.name}') -n classquiz -- \
  pg_dump -U postgres classquiz > classquiz_backup.sql
```

### 7.2 Backup Uploads

```bash
# Create a backup of uploads
oc rsync $(oc get pod -l app.kubernetes.io/component=api -o jsonpath='{.items[0].metadata.name}'):/app/data ./uploads_backup -n classquiz
```

## 8. Troubleshooting

### 8.1 Common Issues

1. **Pods not starting**:
   ```bash
   # Check pod events
   oc describe pod <pod-name> -n classquiz

   # Check pod logs
   oc logs <pod-name> -n classquiz
   ```

2. **Database connection issues**:
   ```bash
   # Check PostgreSQL logs
   oc logs -f statefulset/classquiz-postgresql -n classquiz

   # Test database connection
   oc exec -it $(oc get pod -l app.kubernetes.io/component=postgresql -o jsonpath='{.items[0].metadata.name}') -n classquiz -- \
     psql -U postgres -d classquiz -c "\l"
   ```

3. **Storage issues**:
   ```bash
   # Check PVC status
   oc get pvc -n classquiz

   # Check PV status
   oc get pv
   ```

## 9. Uninstallation

### 9.1 Remove the Application

```bash
# Uninstall the Helm release
helm uninstall classquiz -n classquiz

# Delete PVCs (optional)
oc delete pvc --selector=app.kubernetes.io/instance=classquiz -n classquiz

# Delete the project (optional)
oc delete project classquiz
```

## 10. Upgrading

### 10.1 Upgrade the Application

```bash
# Update the chart
helm upgrade classquiz ./classquiz-0.1.0.tgz \
  -f my-values.yaml \
  --namespace classquiz

# Verify the upgrade
helm list -n classquiz
```

## Security Notes

1. Change all default passwords in `my-values.yaml`
2. Use proper TLS certificates for production
3. Consider using OpenShift secrets for sensitive data
4. Regularly update container images
5. Monitor resource usage and adjust limits as needed

## Additional Resources

- [ClassQuiz GitHub Repository](https://github.com/erwangranger/ClassQuiz)
- [OpenShift Documentation](https://docs.openshift.com)
- [Helm Documentation](https://helm.sh/docs)
- [PostgreSQL Documentation](https://www.postgresql.org/docs)
- [Redis Documentation](https://redis.io/documentation)
- [Meilisearch Documentation](https://docs.meilisearch.com)

## 1. Local Image Building (Optional)

If you want to build images locally before pushing to OpenShift:

### Using Podman on macOS

```bash
# Build the frontend image
cd frontend
podman build -t classquiz/frontend:latest .

# Build the API image
cd ..
podman build -t classquiz/api:latest .

# List built images
podman images | grep classquiz
```

Note: If you're using Podman Desktop on macOS, you can also build images through the GUI interface.