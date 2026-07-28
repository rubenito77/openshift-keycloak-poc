#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-keycloak}"
APPS_DOMAIN="${APPS_DOMAIN:-$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')}"
KEYCLOAK_HOST="${KEYCLOAK_HOST:-keycloak.${APPS_DOMAIN}}"

echo "== Keycloak =="
oc get keycloak keycloak -n "${NAMESPACE}" \
  -o go-template='{{range .status.conditions}}{{printf "%-16s %-6s %s\n" .type .status .message}}{{end}}'

echo
echo "== PostgreSQL =="
POSTGRES_POD="$(oc get pods -n "${NAMESPACE}" -l name=keycloak-postgresql -o jsonpath='{.items[0].metadata.name}')"
oc exec -n "${NAMESPACE}" "${POSTGRES_POD}" -- pg_isready -U keycloak -d keycloak

echo
echo "== Route =="
oc get route -n "${NAMESPACE}" \
  -o custom-columns='NAME:.metadata.name,HOST:.spec.host,TERMINATION:.spec.tls.termination,SERVICE:.spec.to.name'

echo
echo "== OIDC master =="
curl -fsS "https://${KEYCLOAK_HOST}/realms/master/.well-known/openid-configuration" |
  jq -r '.issuer'

echo
echo "== OIDC platform =="
curl -fsS "https://${KEYCLOAK_HOST}/realms/platform/.well-known/openid-configuration" |
  jq -r '.issuer'

