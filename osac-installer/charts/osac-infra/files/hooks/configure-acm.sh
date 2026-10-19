#!/usr/bin/env bash
set -euo pipefail

ACM_NAMESPACE=open-cluster-management
ACM_NAME=multiclusterhub

echo "Waiting for the ACM operator CSV..."
until oc get csv -n "${ACM_NAMESPACE}" -o name | grep -q advanced-cluster-management; do
  sleep 5
done

ACM_CSV=$(oc get csv -n "${ACM_NAMESPACE}" -o name | grep advanced-cluster-management | tail -1)
echo "Waiting for ${ACM_CSV} to succeed..."
until [[ "$(oc get "${ACM_CSV}" -n "${ACM_NAMESPACE}" -o jsonpath='{.status.phase}')" == "Succeeded" ]]; do
  sleep 5
done

until oc api-resources --api-group=operator.open-cluster-management.io >/dev/null 2>&1; do
  sleep 5
done

oc apply -f - <<EOF
apiVersion: operator.open-cluster-management.io/v1
kind: MultiClusterHub
metadata:
  name: ${ACM_NAME}
  namespace: ${ACM_NAMESPACE}
  annotations:
    osac.openshift.io/tenant: platform
    osac.openshift.io/owner-reference: Subscription/acm-operator-subscription
spec: {}
EOF

echo "Waiting for MultiClusterHub/${ACM_NAME}..."
oc wait --for=jsonpath='{.status.phase}'=Running \
  "multiclusterhub/${ACM_NAME}" -n "${ACM_NAMESPACE}" --timeout=30m

echo "Waiting for ACM-managed MCE..."
until [[ "$(oc get multiclusterengine multiclusterengine -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null)" == "Available" ]]; do
  sleep 10
done

echo "Applying Assisted Service configuration..."
until oc apply -n multicluster-engine -f /config/config.yaml; do
  echo "Retrying AgentServiceConfig apply (webhooks may not be ready)..."
  sleep 5
done

oc wait --for=condition=Available deploy/assisted-service \
  -n multicluster-engine --timeout=600s
