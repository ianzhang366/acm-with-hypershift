#!/bin/bash

DEMO_DIR="$(dirname "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd ${DEMO_DIR}/.. && pwd)"

. _demo-magic.sh

TYPE_SPEED=30
# PROMPT_AFTER=1
DEMO_PROMPT="☸ $ "
NO_WAIT=1

export managedClusterOperatorImg="quay.io/ianzhang366/managedcluster-import-controller:with-klusterlet-v1"
export registrationOperatorImg="quay.io/open-cluster-management/registration-operator:latest"
export registrationImg="quay.io/open-cluster-management/registration:latest"
export workImg="quay.io/open-cluster-management/work:latest"

p "# this is a WIP image, please disable the local-cluster when you setting this up"
p "# you can bring local-cluster back, after this override is done"
p ""

# note the hypershift crd should be installed prior to the auto-import pod, otherwise, the following error will show up

# #2022-01-12T15:52:30.024Z	ERROR	controller-runtime.source	if kind is a CRD, it should be installed before calling Start	{"kind": "HostedCluster.hypershift.openshift.io", "error": "no matches for kind \"HostedCluster\" in version \"hypershift.openshift.io/v1alpha1\""}

pe "kubectl apply -f https://raw.githubusercontent.com/stolostron/registration-operator/main/deploy/klusterlet/config/crds/0000_00_operator.open-cluster-management.io_klusterlets.crd.yaml"

p "# pause the multiclusterhub operator to make sure the auto-import image can be override"

pe "kubectl annotate mch -n open-cluster-management multiclusterhub mch-pause=true"

pe "kubectl apply -f ./import-hypershift-rbac.yaml"

pe "envsubst < managedclsuter-deployment.yaml | oc apply -f -"

p "# in order to import your hosted cluster to hub, please patch your hostedcluster with following command"
p "# assuming your hostedcluster CR is at $(clusters) namespace"

p "# kubectl get hc -n clusters --no-headers | awk '{print $1}'| xargs -L1 kubectl patch hc -n clusters -p '{"metadata":{"annotations":{"hypershift-auto-import":"true"}}}' --type=merge"

p "# if you want import your hostedcluster with detached mode, please run command:"
p "# kubectl get hc -n clusters --no-headers | awk '{print $1}'| xargs -L1 kubectl patch hc -n clusters -p '{"metadata":{"annotations":{"hypershift-auto-import":"true","hypershift-on-management":"true"}}}' --type=merge"
