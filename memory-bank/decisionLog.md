### 2025-06-20 15:35:22 (America/Toronto)

**Problem:**
Namespace creation failed during OpenShift deployment with error:
```
error: unable to process template
  namespaces "classquiz" not found
error: no objects passed to apply
```

**Root Cause:**
The `oc process` command was attempting to validate the template against the cluster before the namespace existed. The template includes a ResourceQuota object that requires the namespace to exist for validation.

**Solution:**
Added `--local` flag to the `oc process` command to skip server-side validation during template processing. This allows the template to be processed locally and then applied to create the namespace and other resources.

**Changes:**
- Modified `openshift/deploy.sh` at line 90:
  ```diff
  - oc process -f templates/namespace.yaml -p NAMESPACE=$NAMESPACE -p ENVIRONMENT=$ENVIRONMENT | oc apply -f - || error_exit "Failed to create namespace $NAMESPACE" $DEPLOYMENT_ERROR
  + oc process --local -f templates/namespace.yaml -p NAMESPACE=$NAMESPACE -p ENVIRONMENT=$ENVIRONMENT | oc apply -f - || error_exit "Failed to create namespace $NAMESPACE" $DEPLOYMENT_ERROR
  ```

**Verification:**
Ran `./openshift/deploy.sh` successfully after the change. The namespace was created and the deployment proceeded to subsequent steps without errors.

---
# Decision Log

This file records architectural and implementation decisions using a list format.
2025-06-20 12:39:18 - Log of updates made.

*

## Decision

*

## Rationale

*

## Implementation Details

*
[2025-06-20 14:14:52] - Updated frontend build config to use nodejs:20-ubi9 instead of nodejs:18
* Decision: Changed Node.js version from 18 to 20 in OpenShift build config
* Rationale: Original nodejs:18 ImageStreamTag was not available, and nodejs:20-ubi9 is the current stable version
* Implementation Details: Modified openshift/templates/frontend-buildconfig.yaml
[2025-06-20 15:58:35] - Removed resource quotas from namespace.yaml template to simplify namespace creation process. This change eliminates CPU/memory limits that were causing deployment issues.