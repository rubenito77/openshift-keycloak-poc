#!/usr/bin/env bash
set -euo pipefail

oc apply -f manifests/00-keycloak-operator.yaml

echo
echo "La Subscription usa aprobación manual."
echo "Revise y apruebe el InstallPlan antes de continuar:"
echo
echo 'oc get installplan.operators.coreos.com -n keycloak'

