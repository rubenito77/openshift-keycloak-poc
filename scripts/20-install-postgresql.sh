#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-keycloak}"
POSTGRESQL_VERSION="${POSTGRESQL_VERSION:-15-el9}"
POSTGRESQL_STORAGE="${POSTGRESQL_STORAGE:-5Gi}"

oc process postgresql-persistent \
  -n openshift \
  -p DATABASE_SERVICE_NAME=keycloak-postgresql \
  -p POSTGRESQL_USER=keycloak \
  -p POSTGRESQL_DATABASE=keycloak \
  -p POSTGRESQL_VERSION="${POSTGRESQL_VERSION}" \
  -p VOLUME_CAPACITY="${POSTGRESQL_STORAGE}" \
  -p MEMORY_LIMIT=512Mi |
oc apply -n "${NAMESPACE}" -f -

oc rollout status dc/keycloak-postgresql \
  -n "${NAMESPACE}" \
  --timeout=300s

