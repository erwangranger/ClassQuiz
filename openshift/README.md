# ClassQuiz OpenShift Deployment Guide

## Prerequisites
1. OpenShift CLI (`oc`) installed and configured
2. Cluster admin access to an OpenShift 4.17+ cluster
3. GitHub repository access (for build triggers)
4. Sufficient cluster resources (CPU, memory, storage)

## Deployment Steps

### 0. Create Namespace (Idempotent)
```bash
# Create namespace with optional quotas (can be run multiple times)
oc process -f openshift/templates/namespace.yaml \
  -p NAMESPACE=classquiz \
  -p ENVIRONMENT=dev | oc apply -f -
```

### 1. Create Build Configurations
```bash
# Frontend build
oc apply -f openshift/templates/frontend-buildconfig.yaml

# Backend build
oc apply -f openshift/templates/backend-buildconfig.yaml
```

### 2. Deploy Redis
```bash
# Persistent storage for Redis
oc apply -f openshift/templates/redis-pvc.yaml

# Redis deployment
oc apply -f openshift/templates/redis-deployment.yaml

# Redis service
oc apply -f openshift/templates/redis-service.yaml
```

### 3. Deploy Backend
```bash
# Backend deployment
oc apply -f openshift/templates/backend-deployment.yaml

# Backend service
oc apply -f openshift/templates/backend-service.yaml
```

### 4. Deploy Frontend
```bash
# Frontend deployment
oc apply -f openshift/templates/frontend-deployment.yaml

# Frontend service
oc apply -f openshift/templates/frontend-service.yaml

# Frontend route (update hostname as needed)
oc apply -f openshift/templates/frontend-route.yaml
```

## Verification

1. Check build status:
```bash
oc get builds
```

2. Verify pods are running:
```bash
oc get pods
```

3. Check services:
```bash
oc get svc
```

4. Test frontend route:
```bash
oc get route classquiz-frontend
curl -I http://$(oc get route classquiz-frontend -o jsonpath='{.spec.host}')
```

## Post-Deployment Configuration

1. Update frontend route hostname in `openshift/templates/frontend-route.yaml` if needed
2. Configure environment variables for backend if required
3. Set up monitoring and logging as needed

## Troubleshooting

### Common Issues

1. **Builds failing**:
   - Check build logs: `oc logs build/classquiz-frontend-1`
   - Verify GitHub webhook configuration

2. **Pods not starting**:
   - Check pod logs: `oc logs pod/classquiz-frontend-12345`
   - Verify resource quotas

3. **Redis connection issues**:
   - Check Redis logs: `oc logs pod/redis-12345`
   - Verify persistent volume claims

4. **Route not accessible**:
   - Check route configuration: `oc describe route classquiz-frontend`
   - Verify network policies

## Maintenance

1. To trigger a new build and follow the logs (recommended for debugging):
```bash
# Frontend build with log streaming
oc start-build classquiz-frontend --follow

# Backend build with log streaming
oc start-build classquiz-backend --follow
```

2. To trigger a new build without following logs:
```bash
oc start-build classquiz-frontend
oc start-build classquiz-backend
```

3. To scale deployments:
```bash
oc scale deployment/classquiz-frontend --replicas=3
oc scale deployment/classquiz-backend --replicas=3
```

## Idempotency Guarantees

This deployment is designed to be idempotent - it can be safely run multiple times without side effects:

1. Namespace creation:
   - Will create if not exists
   - Will update labels/annotations if changed
   - Will preserve existing resources

2. Resource deployments:
   - Will update configurations if changed
   - Will maintain existing pods and services
   - Will preserve persistent data

3. Build configurations:
   - Will trigger new builds only if source changes

## Best Practices

1. Use ConfigMaps for environment variables
2. Implement proper resource limits and requests
3. Set up monitoring and alerting
4. Regularly update base images
5. Implement proper backup strategy for Redis data