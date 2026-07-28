#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-keycloak}"

oc apply -n "${NAMESPACE}" -f manifests/30-platform-realm.yaml
oc wait \
  --for=condition=Done \
  keycloakrealmimport/platform-realm \
  -n "${NAMESPACE}" \
  --timeout=300s

oc get keycloakrealmimport platform-realm \
  -n "${NAMESPACE}" \
  -o go-template='{{range .status.conditions}}{{printf "%-12s %-6s %s\n" .type .status .message}}{{end}}'

