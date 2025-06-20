#!/bin/bash

# ClassQuiz OpenShift Deployment Script
# This script performs all OpenShift deployment steps for ClassQuiz

# Configuration variables
# NAMESPACE: Kubernetes namespace to deploy to (default: "classquiz")
# Can be overridden by setting NAMESPACE environment variable
# SKIP_BUILD: Skip build steps if set to true (default: false)
NAMESPACE=${NAMESPACE:-"classquiz"}
ENVIRONMENT="prod"
SKIP_BUILD=${SKIP_BUILD:-"false"}
TIMESTAMP=$(date +"%Y-%m-%d %T")

# Exit codes
SUCCESS=0
PREREQ_FAILED=1
TEMPLATE_ERROR=2
DEPLOYMENT_ERROR=3
READINESS_ERROR=4
BUILD_ERROR=5

# Logging function with timestamp
log() {
    echo "[$TIMESTAMP] $1"
}

# Error handling function
error_exit() {
    log "ERROR: $1"
    exit $2
}

# Verify prerequisites
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Check oc command availability
    if ! command -v oc &> /dev/null; then
        error_exit "OpenShift CLI (oc) is not installed or not in PATH" $PREREQ_FAILED
    fi

    # Check if logged in to OpenShift
    if ! oc whoami &> /dev/null; then
        error_exit "Not logged in to OpenShift cluster. Run 'oc login' first." $PREREQ_FAILED
    fi

    # Verify template files exist
    local required_templates=(
        "templates/namespace.yaml"
        "templates/postgresql-statefulset.yaml"
        "templates/postgresql-service.yaml"
        "templates/postgresql-networkpolicy.yaml"
        "templates/postgresql-pvc.yaml"
        "templates/redis-deployment.yaml"
        "templates/redis-service.yaml"
        "templates/redis-networkpolicy.yaml"
        "templates/redis-pvc.yaml"
        "templates/meilisearch-serviceaccount.yaml"
        "templates/meilisearch-role.yaml"
        "templates/meilisearch-rolebinding.yaml"
        "templates/meilisearch-scc.yaml"
        "templates/meilisearch-statefulset.yaml"
        "templates/meilisearch-service.yaml"
        "templates/meilisearch-networkpolicy.yaml"
        "templates/meilisearch-pvc.yaml"
        "templates/backend-buildconfig.yaml"
        "templates/backend-deployment.yaml"
        "templates/backend-service.yaml"
        "templates/frontend-buildconfig.yaml"
        "templates/frontend-deployment.yaml"
        "templates/frontend-service.yaml"
        "templates/frontend-route.yaml"
    )

    for template in "${required_templates[@]}"; do
        if [[ ! -f "$template" ]]; then
            error_exit "Required template file not found: $template" $PREREQ_FAILED
        fi
    done

    log "All prerequisites verified successfully"
}

# Verify prerequisites before starting
verify_prerequisites

# Step 1: Namespace creation
log "Starting namespace creation..."
oc process --local -f templates/namespace.yaml -p NAMESPACE=$NAMESPACE -p ENVIRONMENT=$ENVIRONMENT | oc apply -f - || error_exit "Failed to create namespace $NAMESPACE" $DEPLOYMENT_ERROR

# Verify namespace was created
if ! oc get namespace $NAMESPACE &> /dev/null; then
    error_exit "Namespace $NAMESPACE creation verification failed" $DEPLOYMENT_ERROR
fi
log "Namespace $NAMESPACE created and verified successfully"

# Create ImageStreams for builds
log "Creating ImageStreams..."
oc apply -f templates/backend-imagestream.yaml -n $NAMESPACE || error_exit "Failed to create backend ImageStream" $DEPLOYMENT_ERROR
oc apply -f templates/frontend-imagestream.yaml -n $NAMESPACE || error_exit "Failed to create frontend ImageStream" $DEPLOYMENT_ERROR

log "Verifying ImageStreams..."
if ! oc get imagestream classquiz-backend -n $NAMESPACE &> /dev/null; then
    error_exit "Backend ImageStream not found after creation" $DEPLOYMENT_ERROR
fi
if ! oc get imagestream classquiz-frontend -n $NAMESPACE &> /dev/null; then
    error_exit "Frontend ImageStream not found after creation" $DEPLOYMENT_ERROR
fi

# Build applications if not skipped
if [[ "$SKIP_BUILD" != "true" ]]; then
    log "Starting application builds..."

    # Build backend
    log "Building backend application..."
    oc apply -f templates/backend-buildconfig.yaml -n $NAMESPACE || error_exit "Failed to create backend BuildConfig" $BUILD_ERROR
    oc start-build classquiz-backend -n $NAMESPACE --follow || error_exit "Backend build failed" $BUILD_ERROR

    # Verify backend build
    if ! oc get imagestreamtag classquiz-backend:latest -n $NAMESPACE &> /dev/null; then
        error_exit "Backend image not found after build" $BUILD_ERROR
    fi
    log "Backend built successfully"

    # Build frontend
    log "Building frontend application..."
    oc apply -f templates/frontend-buildconfig.yaml -n $NAMESPACE || error_exit "Failed to create frontend BuildConfig" $BUILD_ERROR
    oc start-build classquiz-frontend -n $NAMESPACE --follow || error_exit "Frontend build failed" $BUILD_ERROR

    # Verify frontend build
    if ! oc get imagestreamtag classquiz-frontend:latest -n $NAMESPACE &> /dev/null; then
        error_exit "Frontend image not found after build" $BUILD_ERROR
    fi
    log "Frontend built successfully"
fi

# Step 2: Database services deployment
log "Starting database services deployment..."

# PostgreSQL deployment
log "Deploying PostgreSQL components..."
oc process -f templates/postgresql-statefulset.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to deploy PostgreSQL StatefulSet" $DEPLOYMENT_ERROR
oc process -f templates/postgresql-service.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to create PostgreSQL Service" $DEPLOYMENT_ERROR
oc process -f templates/postgresql-networkpolicy.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to create PostgreSQL NetworkPolicy" $DEPLOYMENT_ERROR
oc process -f templates/postgresql-pvc.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to create PostgreSQL PVC" $DEPLOYMENT_ERROR

log "Verifying PostgreSQL resources..."
if ! oc get statefulset postgresql -n $NAMESPACE &> /dev/null; then
    error_exit "PostgreSQL StatefulSet not found after deployment" $DEPLOYMENT_ERROR
fi
if ! oc get svc postgresql -n $NAMESPACE &> /dev/null; then
    error_exit "PostgreSQL Service not found after deployment" $DEPLOYMENT_ERROR
fi
if ! oc get pvc postgresql-pvc -n $NAMESPACE &> /dev/null; then
    error_exit "PostgreSQL PVC not found after deployment" $DEPLOYMENT_ERROR
fi

log "PostgreSQL deployed and verified successfully"

# Redis deployment
log "Deploying Redis components..."
oc process -f templates/redis-deployment.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to deploy Redis Deployment" $DEPLOYMENT_ERROR
oc process -f templates/redis-service.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to create Redis Service" $DEPLOYMENT_ERROR
oc process -f templates/redis-networkpolicy.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to create Redis NetworkPolicy" $DEPLOYMENT_ERROR
oc process -f templates/redis-pvc.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to create Redis PVC" $DEPLOYMENT_ERROR

log "Verifying Redis resources..."
if ! oc get deployment redis -n $NAMESPACE &> /dev/null; then
    error_exit "Redis Deployment not found after deployment" $DEPLOYMENT_ERROR
fi
if ! oc get svc redis -n $NAMESPACE &> /dev/null; then
    error_exit "Redis Service not found after deployment" $DEPLOYMENT_ERROR
fi
if ! oc get pvc redis-pvc -n $NAMESPACE &> /dev/null; then
    error_exit "Redis PVC not found after deployment" $DEPLOYMENT_ERROR
fi

log "Redis deployed and verified successfully"

# Meilisearch deployment
log "Deploying Meilisearch RBAC components..."
oc process -f templates/meilisearch-serviceaccount.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to create Meilisearch ServiceAccount" $DEPLOYMENT_ERROR
oc process -f templates/meilisearch-role.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to create Meilisearch Role" $DEPLOYMENT_ERROR
oc process -f templates/meilisearch-rolebinding.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to create Meilisearch RoleBinding" $DEPLOYMENT_ERROR
oc process -f templates/meilisearch-scc.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to create Meilisearch SecurityContextConstraints" $DEPLOYMENT_ERROR

log "Verifying Meilisearch RBAC components..."
if ! oc get serviceaccount meilisearch -n $NAMESPACE &> /dev/null; then
    error_exit "Meilisearch ServiceAccount not found after deployment" $DEPLOYMENT_ERROR
fi
if ! oc get role meilisearch -n $NAMESPACE &> /dev/null; then
    error_exit "Meilisearch Role not found after deployment" $DEPLOYMENT_ERROR
fi
if ! oc get rolebinding meilisearch -n $NAMESPACE &> /dev/null; then
    error_exit "Meilisearch RoleBinding not found after deployment" $DEPLOYMENT_ERROR
fi
if ! oc get scc meilisearch-scc -n $NAMESPACE &> /dev/null; then
    error_exit "Meilisearch SecurityContextConstraints not found after deployment" $DEPLOYMENT_ERROR
fi

log "Deploying Meilisearch resources..."
oc process -f templates/meilisearch-statefulset.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to deploy Meilisearch StatefulSet" $DEPLOYMENT_ERROR
oc process -f templates/meilisearch-service.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to create Meilisearch Service" $DEPLOYMENT_ERROR
oc process -f templates/meilisearch-networkpolicy.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to create Meilisearch NetworkPolicy" $DEPLOYMENT_ERROR
oc process -f templates/meilisearch-pvc.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to create Meilisearch PVC" $DEPLOYMENT_ERROR

log "Verifying Meilisearch resources..."
if ! oc get statefulset meilisearch -n $NAMESPACE &> /dev/null; then
    error_exit "Meilisearch StatefulSet not found after deployment" $DEPLOYMENT_ERROR
fi
if ! oc get svc meilisearch -n $NAMESPACE &> /dev/null; then
    error_exit "Meilisearch Service not found after deployment" $DEPLOYMENT_ERROR
fi
if ! oc get pvc meilisearch-pvc -n $NAMESPACE &> /dev/null; then
    error_exit "Meilisearch PVC not found after deployment" $DEPLOYMENT_ERROR
fi

log "Meilisearch deployed and verified successfully"

# Step 3: Backend deployment
log "Deploying backend components..."
oc process -f templates/backend-deployment.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to deploy Backend Deployment" $DEPLOYMENT_ERROR
oc process -f templates/backend-service.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to create Backend Service" $DEPLOYMENT_ERROR

log "Verifying backend resources..."
if ! oc get deployment backend -n $NAMESPACE &> /dev/null; then
    error_exit "Backend Deployment not found after deployment" $DEPLOYMENT_ERROR
fi
if ! oc get svc backend -n $NAMESPACE &> /dev/null; then
    error_exit "Backend Service not found after deployment" $DEPLOYMENT_ERROR
fi

log "Backend deployed and verified successfully"

# Step 4: Frontend deployment
log "Deploying frontend components..."
oc process -f templates/frontend-deployment.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to deploy Frontend Deployment" $DEPLOYMENT_ERROR
oc process -f templates/frontend-service.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to create Frontend Service" $DEPLOYMENT_ERROR
oc process -f templates/frontend-route.yaml | oc apply -n $NAMESPACE -f - || error_exit "Failed to create Frontend Route" $DEPLOYMENT_ERROR

log "Verifying frontend resources..."
if ! oc get deployment frontend -n $NAMESPACE &> /dev/null; then
    error_exit "Frontend Deployment not found after deployment" $DEPLOYMENT_ERROR
fi
if ! oc get svc frontend -n $NAMESPACE &> /dev/null; then
    error_exit "Frontend Service not found after deployment" $DEPLOYMENT_ERROR
fi
if ! oc get route frontend -n $NAMESPACE &> /dev/null; then
    error_exit "Frontend Route not found after deployment" $DEPLOYMENT_ERROR
fi

log "Frontend deployed and verified successfully"

# Step 5: Verification
log "Starting comprehensive verification steps..."
log "Checking pod status..."
oc get pods -n $NAMESPACE || error_exit "Failed to get pod status" $READINESS_ERROR

log "Checking service status..."
oc get svc -n $NAMESPACE || error_exit "Failed to get service status" $READINESS_ERROR

log "Checking route status..."
oc get route -n $NAMESPACE || error_exit "Failed to get route status" $READINESS_ERROR

log "Verifying Meilisearch readiness..."
oc rollout status statefulset/meilisearch -n $NAMESPACE --timeout=300s || error_exit "Meilisearch failed to become ready within timeout" $READINESS_ERROR

log "Verifying PostgreSQL readiness..."
oc rollout status statefulset/postgresql -n $NAMESPACE --timeout=300s || error_exit "PostgreSQL failed to become ready within timeout" $READINESS_ERROR

log "Verifying Redis readiness..."
oc rollout status deployment/redis -n $NAMESPACE --timeout=300s || error_exit "Redis failed to become ready within timeout" $READINESS_ERROR

log "Verifying backend readiness..."
oc rollout status deployment/backend -n $NAMESPACE --timeout=300s || error_exit "Backend failed to become ready within timeout" $READINESS_ERROR

log "Verifying frontend readiness..."
oc rollout status deployment/frontend -n $NAMESPACE --timeout=300s || error_exit "Frontend failed to become ready within timeout" $READINESS_ERROR

log "All deployment steps completed successfully with verification!"
log ""
log "Usage notes:"
log "- To skip builds on subsequent deployments, run with SKIP_BUILD=true"
log "- Example: SKIP_BUILD=true ./deploy.sh"
log "- Builds can also be triggered independently via OpenShift web console"
exit $SUCCESS