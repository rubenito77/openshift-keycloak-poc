#!/usr/bin/env bash
set -euo pipefail

oc whoami
oc version
oc get clusterversion
oc get ingress.config.openshift.io cluster \
  -o jsonpath='{.spec.domain}{"\n"}'
oc get storageclass
oc auth can-i create namespaces
oc auth can-i create subscriptions.operators.coreos.com -A
oc get packagemanifest keycloak-operator \
  -n openshift-marketplace \
  -o jsonpath='Package: {.metadata.name}{"\n"}Catalog: {.status.catalogSource}{"\n"}Default channel: {.status.defaultChannel}{"\n"}'

