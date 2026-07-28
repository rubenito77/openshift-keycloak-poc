#!/usr/bin/env bash
set -euo pipefail

KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
APPS_NAMESPACE="${APPS_NAMESPACE:-keycloak-poc-apps}"
APPS_DOMAIN="${APPS_DOMAIN:-$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')}"
KEYCLOAK_HOST="${KEYCLOAK_HOST:-keycloak.${APPS_DOMAIN}}"
PROTECTED_HOST="${PROTECTED_HOST:-app-protected.${APPS_DOMAIN}}"
CLIENT_ID="${CLIENT_ID:-app-protected}"
KC_CONFIG="/tmp/kcadm-poc.config"

KEYCLOAK_POD="$(
  oc get pod -n "${KEYCLOAK_NAMESPACE}" \
    -l app=keycloak \
    -o jsonpath='{.items[0].metadata.name}'
)"

ADMIN_USER="$(
  oc get secret keycloak-initial-admin \
    -n "${KEYCLOAK_NAMESPACE}" \
    -o jsonpath='{.data.username}' |
  base64 -d
)"
ADMIN_PASSWORD="$(
  oc get secret keycloak-initial-admin \
    -n "${KEYCLOAK_NAMESPACE}" \
    -o jsonpath='{.data.password}' |
  base64 -d
)"

kc() {
  oc exec -n "${KEYCLOAK_NAMESPACE}" "${KEYCLOAK_POD}" -- \
    /opt/keycloak/bin/kcadm.sh --config "${KC_CONFIG}" "$@"
}

oc exec -n "${KEYCLOAK_NAMESPACE}" "${KEYCLOAK_POD}" -- \
  /opt/keycloak/bin/kcadm.sh \
  --config "${KC_CONFIG}" \
  config credentials \
  --server http://127.0.0.1:8080 \
  --realm master \
  --user "${ADMIN_USER}" \
  --password "${ADMIN_PASSWORD}" >/dev/null

oc apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${APPS_NAMESPACE}
  labels:
    app.kubernetes.io/part-of: keycloak-poc
EOF

CLIENT_SECRET="$(openssl rand -hex 24)"
COOKIE_SECRET="$(openssl rand -base64 32 | tr -- '+/' '-_' | tr -d '\n')"
AUTHORIZED_PASSWORD="$(openssl rand -hex 12)"
DENIED_PASSWORD="$(openssl rand -hex 12)"

CLIENT_UUID="$(
  kc get clients -r platform -q "clientId=${CLIENT_ID}" |
  jq -r '.[0].id // empty'
)"

if [[ -z "${CLIENT_UUID}" ]]; then
  kc create clients -r platform \
    -s "clientId=${CLIENT_ID}" \
    -s enabled=true \
    -s publicClient=false \
    -s clientAuthenticatorType=client-secret \
    -s "secret=${CLIENT_SECRET}" \
    -s standardFlowEnabled=true \
    -s directAccessGrantsEnabled=true \
    -s fullScopeAllowed=true \
    -s "rootUrl=https://${PROTECTED_HOST}" \
    -s 'redirectUris=["https://'"${PROTECTED_HOST}"'/oauth2/callback"]' \
    -s 'webOrigins=["https://'"${PROTECTED_HOST}"'"]' >/dev/null
  CLIENT_UUID="$(
    kc get clients -r platform -q "clientId=${CLIENT_ID}" |
    jq -r '.[0].id'
  )"
else
  kc update "clients/${CLIENT_UUID}" -r platform \
    -s enabled=true \
    -s publicClient=false \
    -s clientAuthenticatorType=client-secret \
    -s "secret=${CLIENT_SECRET}" \
    -s standardFlowEnabled=true \
    -s directAccessGrantsEnabled=true \
    -s fullScopeAllowed=true \
    -s "rootUrl=https://${PROTECTED_HOST}" \
    -s 'redirectUris=["https://'"${PROTECTED_HOST}"'/oauth2/callback"]' \
    -s 'webOrigins=["https://'"${PROTECTED_HOST}"'"]' >/dev/null
fi

MAPPER_ID="$(
  kc get "clients/${CLIENT_UUID}/protocol-mappers/models" -r platform |
  jq -r '.[] | select(.name == "audience-app-protected") | .id' |
  head -1
)"

if [[ -z "${MAPPER_ID}" ]]; then
  kc create "clients/${CLIENT_UUID}/protocol-mappers/models" -r platform \
    -s name=audience-app-protected \
    -s protocol=openid-connect \
    -s protocolMapper=oidc-audience-mapper \
    -s 'config."included.client.audience"=app-protected' \
    -s 'config."id.token.claim"=true' \
    -s 'config."access.token.claim"=true' >/dev/null
fi

ensure_user() {
  local username="$1"
  local email="$2"
  local password="$3"
  local user_id

  user_id="$(
    kc get users -r platform -q "username=${username}" |
    jq -r '.[0].id // empty'
  )"

  if [[ -z "${user_id}" ]]; then
    kc create users -r platform \
      -s "username=${username}" \
      -s enabled=true \
      -s "email=${email}" \
      -s emailVerified=true >/dev/null
  fi

  kc set-password -r platform \
    --username "${username}" \
    --new-password "${password}" \
    --temporary=false >/dev/null
}

ensure_user poc-authorized poc-authorized@example.com "${AUTHORIZED_PASSWORD}"
ensure_user poc-denied poc-denied@example.com "${DENIED_PASSWORD}"

kc add-roles -r platform \
  --uusername poc-authorized \
  --rolename platform-user >/dev/null

oc create secret generic app-protected-oidc \
  -n "${APPS_NAMESPACE}" \
  --from-literal=client-id="${CLIENT_ID}" \
  --from-literal=client-secret="${CLIENT_SECRET}" \
  --from-literal=cookie-secret="${COOKIE_SECRET}" \
  --dry-run=client -o yaml |
oc apply -f -

oc create secret generic poc-test-users \
  -n "${APPS_NAMESPACE}" \
  --from-literal=authorized-username=poc-authorized \
  --from-literal=authorized-password="${AUTHORIZED_PASSWORD}" \
  --from-literal=denied-username=poc-denied \
  --from-literal=denied-password="${DENIED_PASSWORD}" \
  --dry-run=client -o yaml |
oc apply -f -

oc exec -n "${KEYCLOAK_NAMESPACE}" "${KEYCLOAK_POD}" -- \
  rm -f "${KC_CONFIG}" || true

unset ADMIN_PASSWORD CLIENT_SECRET COOKIE_SECRET
unset AUTHORIZED_PASSWORD DENIED_PASSWORD

echo "Cliente OIDC, usuarios y Secrets de la POC configurados."
echo "Direct Access Grants está habilitado sólo para automatizar esta POC."

