#!/bin/bash

DEMO_DIR="$(dirname "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd ${DEMO_DIR}/.. && pwd)"

. _demo-magic.sh

TYPE_SPEED=30
# PROMPT_AFTER=1
DEMO_PROMPT="☸ $ "
NO_WAIT=1

p "# this is a WIP image, please disable the local-cluster when you setting this up"
p "# you can bring local-cluster back, after this override is done"

auto_import_hypershift_img="quay.io/ianzhang366/managedcluster-import-controller:with-klusterlet-v1"

# note the hypershift crd should be installed prior to the auto-import pod, otherwise, the following error will show up

#2022-01-12T15:52:30.024Z	ERROR	controller-runtime.source	if kind is a CRD, it should be installed before calling Start	{"kind": "HostedCluster.hypershift.openshift.io", "error": "no matches for kind \"HostedCluster\" in version \"hypershift.openshift.io/v1alpha1\""}

pe "kubectl apply -f https://raw.githubusercontent.com/stolostron/registration-operator/main/deploy/klusterlet/config/crds/0000_00_operator.open-cluster-management.io_klusterlets.crd.yaml"

p "# pause the multiclusterhub operator to make sure the auto-import image can be override"

pe "kubectl annotate mch -n open-cluster-management multiclusterhub mch-pause=true"

pe "kubectl apply -f ./import-hypershift-rbac.yaml"

pe "kubectl set image deployment -n open-cluster-management managedcluster-import-controller-v2 managedcluster-import-controller=$auto_import_hypershift_img"

kubectl patch deploy managedcluster-import-controller-v2 -n open-cluster-management -p '{"spec":{"replicas": 1}}' --type=merge
