#!/usr/bin/env bash

# Dependencies
#  - kind >=0.11
#  - k8s >= 1.19

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

METALLB_VERSION=v0.13.5
INGRESS_VERSION=controller-v1.2.1

# Fingers crossed this is at least a /24 range
METALLB_IP_PREFIX_RANGE=$(docker network inspect kind --format '{{(index .IPAM.Config 0).Subnet}}' | sed -r 's/(.*).\/.*/\1/')
METALLB_IP_ADDRESS_RANGE=$(echo "${METALLB_IP_PREFIX_RANGE}200-${METALLB_IP_PREFIX_RANGE}250" | sed "s/\./\\\./g")

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s

# Disable webhooks due to timeout issues
# https://github.com/metallb/metallb/issues/1597
# https://github.com/metallb/metallb/issues/1540
kubectl patch validatingwebhookconfigurations.admissionregistration.k8s.io metallb-webhook-configuration --patch-file ${SCRIPT_DIR}/metallb-webhook-patch.yaml

sed "s/METALLB_IP_ADDRESS_RANGE/${METALLB_IP_ADDRESS_RANGE}/" "${SCRIPT_DIR}/metallb-config.yaml" | kubectl apply -f -

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_VERSION}/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s

# Patch the ingress class to make it defaul
kubectl patch ingressclass nginx -p '{"metadata": {"annotations":{"ingressclass.kubernetes.io/is-default-class": "true"}}}'
