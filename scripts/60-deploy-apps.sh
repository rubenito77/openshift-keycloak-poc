#!/usr/bin/env bash
set -euo pipefail

APPS_NAMESPACE="${APPS_NAMESPACE:-keycloak-poc-apps}"
APPS_DOMAIN="${APPS_DOMAIN:-$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')}"
KEYCLOAK_HOST="${KEYCLOAK_HOST:-keycloak.${APPS_DOMAIN}}"
PUBLIC_HOST="${PUBLIC_HOST:-app-public.${APPS_DOMAIN}}"
PROTECTED_HOST="${PROTECTED_HOST:-app-protected.${APPS_DOMAIN}}"

export APPS_NAMESPACE APPS_DOMAIN KEYCLOAK_HOST PUBLIC_HOST PROTECTED_HOST

oc create namespace "${APPS_NAMESPACE}" \
  --dry-run=client -o yaml |
oc apply -f -

oc create configmap keycloak-poc-backend \
  -n "${APPS_NAMESPACE}" \
  --from-file=app.py=apps/backend/app.py \
  --dry-run=client -o yaml |
oc apply -f -

envsubst < apps/manifests/apps.yaml.tpl |
oc apply -f -

oc rollout status deployment/app-public \
  -n "${APPS_NAMESPACE}" \
  --timeout=300s
oc rollout status deployment/app-protected \
  -n "${APPS_NAMESPACE}" \
  --timeout=300s

oc get deployment,pods,service,route -n "${APPS_NAMESPACE}"

