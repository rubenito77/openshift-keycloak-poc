#!/usr/bin/env bash
set -euo pipefail

APPS_NAMESPACE="${APPS_NAMESPACE:-keycloak-poc-apps}"
APPS_DOMAIN="${APPS_DOMAIN:-$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')}"
KEYCLOAK_HOST="${KEYCLOAK_HOST:-keycloak.${APPS_DOMAIN}}"
PUBLIC_HOST="${PUBLIC_HOST:-app-public.${APPS_DOMAIN}}"
PROTECTED_HOST="${PROTECTED_HOST:-app-protected.${APPS_DOMAIN}}"
TOKEN_URL="https://${KEYCLOAK_HOST}/realms/platform/protocol/openid-connect/token"

decode_secret() {
  oc get secret "$1" -n "${APPS_NAMESPACE}" \
    -o "jsonpath={.data.$2}" |
  base64 -d
}

CLIENT_ID="$(decode_secret app-protected-oidc client-id)"
CLIENT_SECRET="$(decode_secret app-protected-oidc client-secret)"
AUTHORIZED_USER="$(decode_secret poc-test-users authorized-username)"
AUTHORIZED_PASSWORD="$(decode_secret poc-test-users authorized-password)"
DENIED_USER="$(decode_secret poc-test-users denied-username)"
DENIED_PASSWORD="$(decode_secret poc-test-users denied-password)"

pass=0
fail=0

check_code() {
  local id="$1"
  local expected="$2"
  local actual="$3"
  if [[ "${actual}" == "${expected}" ]]; then
    printf 'PASS %-8s HTTP %s\n' "${id}" "${actual}"
    pass=$((pass + 1))
  else
    printf 'FAIL %-8s esperado=%s obtenido=%s\n' "${id}" "${expected}" "${actual}"
    fail=$((fail + 1))
  fi
}

PUBLIC_CODE="$(
  curl -sS -o /dev/null -w '%{http_code}' "https://${PUBLIC_HOST}/"
)"
check_code PUB-01 200 "${PUBLIC_CODE}"

PROTECTED_ANON_CODE="$(
  curl -sS -o /dev/null -w '%{http_code}' "https://${PROTECTED_HOST}/"
)"
check_code PRO-01 302 "${PROTECTED_ANON_CODE}"

INVALID_CODE="$(
  curl -sS -o /dev/null -w '%{http_code}' \
    -u "${CLIENT_ID}:${CLIENT_SECRET}" \
    -d grant_type=password \
    -d "username=${AUTHORIZED_USER}" \
    -d password=incorrecta \
    -d scope=openid \
    "${TOKEN_URL}"
)"
check_code PRO-03 401 "${INVALID_CODE}"

AUTHORIZED_TOKEN="$(
  curl -fsS \
    -u "${CLIENT_ID}:${CLIENT_SECRET}" \
    -d grant_type=password \
    -d "username=${AUTHORIZED_USER}" \
    -d "password=${AUTHORIZED_PASSWORD}" \
    -d scope=openid \
    "${TOKEN_URL}" |
  jq -r '.access_token'
)"

AUTHORIZED_CODE="$(
  curl -sS -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${AUTHORIZED_TOKEN}" \
    "https://${PROTECTED_HOST}/"
)"
check_code PRO-05 200 "${AUTHORIZED_CODE}"

DENIED_TOKEN="$(
  curl -fsS \
    -u "${CLIENT_ID}:${CLIENT_SECRET}" \
    -d grant_type=password \
    -d "username=${DENIED_USER}" \
    -d "password=${DENIED_PASSWORD}" \
    -d scope=openid \
    "${TOKEN_URL}" |
  jq -r '.access_token'
)"

DENIED_CODE="$(
  curl -sS -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${DENIED_TOKEN}" \
    "https://${PROTECTED_HOST}/"
)"
check_code PRO-04 403 "${DENIED_CODE}"

ISSUER="$(
  curl -fsS \
    "https://${KEYCLOAK_HOST}/realms/platform/.well-known/openid-configuration" |
  jq -r '.issuer'
)"
EXPECTED_ISSUER="https://${KEYCLOAK_HOST}/realms/platform"
if [[ "${ISSUER}" == "${EXPECTED_ISSUER}" ]]; then
  printf 'PASS %-8s issuer correcto\n' TOK-01
  pass=$((pass + 1))
else
  printf 'FAIL %-8s issuer=%s\n' TOK-01 "${ISSUER}"
  fail=$((fail + 1))
fi

unset CLIENT_SECRET AUTHORIZED_PASSWORD DENIED_PASSWORD
unset AUTHORIZED_TOKEN DENIED_TOKEN

printf '\nResultado: %s PASS / %s FAIL\n' "${pass}" "${fail}"
[[ "${fail}" -eq 0 ]]

