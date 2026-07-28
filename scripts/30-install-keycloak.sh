#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-keycloak}"
APPS_DOMAIN="${APPS_DOMAIN:-$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')}"
KEYCLOAK_HOST="${KEYCLOAK_HOST:-keycloak.${APPS_DOMAIN}}"

export NAMESPACE APPS_DOMAIN KEYCLOAK_HOST
envsubst < manifests/20-keycloak.yaml.tpl | oc apply -f -

oc wait \
  --for=condition=Ready \
  keycloak/keycloak \
  -n "${NAMESPACE}" \
  --timeout=600s

