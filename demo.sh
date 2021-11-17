#!/bin/bash

DEMO_DIR="$(dirname "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd ${DEMO_DIR}/.. && pwd)"

. _demo-magic.sh

TYPE_SPEED=30
# PROMPT_AFTER=1
DEMO_PROMPT="☸ $ "
NO_WAIT=1

function comment() {
    printf "$GREEN>>> %s <<<$GREEN\n" "$1"
    wait
}

# comment "https://excalidraw.com/#json=uhI3fqeRHGiO5y91yiwlR,jwUQ5aBDQ0SJFzR8tjUSkg"

oidc_bucket="izhang-hypershift-demo"
bucket_region="us-east-1"
aws_cred_file="$HOME/.aws/credentials"

pull_secret="../notes/pull-secret.txt"
hostClusterNamespace="ian-clusters"
hostClusterName="izhang-hypershift-demo"
hyperConfig="./$hyperClusterName.kubeconfig"
ssh_pub_key_path="../notes/id_rsa.pub"

hostKubeconfig="./hostKubeconfig"
mgmt_kubeconfig="./mgmt-kubeconfig"

export DEMO_MC_NAME="hypershift-demo-managed-cluster"
hyershift_demo_MC="./managed-cluster.yaml"

auto_import_secret="./auto-import-secret.yaml"
auto_import_crd="./auto-import-crd.yaml"

HOST_OC="oc --kubeconfig $hostKubeconfig"

MGMT_OC="oc --kubeconfig $mgmt_kubeconfig"

addon_config="./addonconfig.yaml"

function checkSetup() {
    pe "which hypershift"
    pe "oc get po -n open-cluster-management"
    comment "Install hypershift operaotr to management cluster"
}

function installHypershiftOperator() {
    local KUBECONFIG=$mgmt_kubeconfig
    pe "hypershift install --oidc-storage-provider-s3-bucket-name=$oidc_bucket \
        --oidc-storage-provider-s3-region=$bucket_region \
        --oidc-storage-provider-s3-credentials=$aws_cred_file"

    pe "oc get po -n hypershift"
}

function renderHypershiftCreate() {
    local KUBECONFIG=$mgmt_kubeconfig
    pe "hypershift create cluster none \
        --pull-secret $pull_secret \
        --name $hostClusterName \
        --namespace $hostClusterNamespace \
        --node-pool-replicas 2 \
        --ssh-key $ssh_pub_key_path --render  > hypershift-create.yaml"
}

function createHostClusterOnAWS() {
    local KUBECONFIG=$mgmt_kubeconfig
    pe "hypershift create cluster aws \
        --pull-secret $pull_secret \
        --aws-creds $aws_cred_file \
        --name $hostClusterName \
        --namespace $hostClusterNamespace \
        --base-domain dev10.red-chesterfield.com \
        --instance-type m5.xlarge \
        --region $bucket_region \
        --node-pool-replicas 2 \
        --root-volume-size 30 \
        --root-volume-type gp2 \
        --ssh-key $ssh_pub_key_path"

    pe "$MGMT_OC wait --timeout=300s --for=condition=IgnitionEndpointAvailable hostedcluster -n $hostClusterNamespace $hostClusterName"

    pe "$MGMT_OC wait --timeout=300s --for=condition=KubeAPIServerAvailable hostedcontrolplane -n $hostClusterNamespace-$hostClusterName $hostClusterName"
    pe "$MGMT_OC get secret -n $hostClusterNamespace ${hostClusterName}-admin-kubeconfig -ogo-template='{{.data.kubeconfig | base64decode}}' > $hostKubeconfig"
}

function destroyHostClusterOnAWS() {
    local KUBECONFIG=$mgmt_kubeconfig
    pe "hypershift destroy cluster aws \
        --aws-creds $aws_cred_file \
        --name $hostClusterName \
        --namespace $hostClusterNamespace \
        --base-domain dev10.red-chesterfield.com \
        --cluster-grace-period 600s \
        --region $bucket_region"

    pe "$MGMT_OC get hostedcluster -A"
}

function waitFor() {
    local kind=$1
    local ns=$2
    local name=$3
    local kubeconfig=$4

    matched=$(oc get $kind $name -n $ns --kubeconfig $kubeconfig --no-headers --ignore-not-found=true)

    while [ -z "$matched" ]; do
        matched=$(oc get $kind $name -n $ns --kubeconfig $kubeconfig --no-headers --ignore-not-found=true)
        echo "Waiting for $kind ($ns/$name) to be created"
        sleep 10
    done
}

function waitforRouteStatus() {
    local ns="$1"
    local name="$2"
    local cfg="$3"

    valid=$(oc get route -n $ns $name --kubeconfig $cfg -ojsonpath="{.status.ingress[].host}")
    echo "valid: " $valid
    while [ -z "$valid" ]; do
        valid=$(oc get route -n $ns $name --kubeconfig $cfg -ojsonpath="{.status.ingress[].host}")
        sleep 10
    done
}

function showHostOCP() {
    #comment "Get ACM route"
    printf "ACM URL:\n{https://%s}\n" $($MGMT_OC get route -n open-cluster-management multicloud-console -ojsonpath='{.status.ingress[].host}')

    waitFor "route" openshift-console console $hostKubeconfig
    waitforRouteStatus openshift-console console $hostKubeconfig
    printf "Guest cluster OCP console URL:\n{https://%s}\n" $($HOST_OC get route -n openshift-console console -ojsonpath='{.status.ingress[].host}')

    waitFor "secret" $hostClusterNamespace-$hostClusterName kubeadmin-password $mgmt_kubeconfig
    printf "Guest cluster kubeadmin-password:\n{%s}\n" $($MGMT_OC get secret -n $hostClusterNamespace-$hostClusterName kubeadmin-password -ogo-template='{{.data.password | base64decode}}')
}

function importAsManagedCluster() {
    pe "$MGMT_OC get managedcluster -A"
    pe "envsubst < $hyershift_demo_MC | $MGMT_OC apply -f -"
    pe "$MGMT_OC get secret -n $DEMO_MC_NAME ${DEMO_MC_NAME}-import -o jsonpath={.data.crds\\\.yaml} | base64 -d  > $auto_import_crd"
    pe "$MGMT_OC get secret -n $DEMO_MC_NAME ${DEMO_MC_NAME}-import -o jsonpath={.data.import\\\.yaml} | base64 -d > $auto_import_secret"

    pe "$HOST_OC apply -f $auto_import_crd"
    pe "$HOST_OC apply -f $auto_import_secret"

    pe "envsubst < $addon_config | $MGMT_OC apply -f -"
}

function unimportAsManagedCluster() {
    pe "envsubst < $hyershift_demo_MC | $MGMT_OC delete -f -"
    pe "$MGMT_OC get managedcluster -A"
}

function cleanUpAll() {
    unimportAsManagedCluster
    destroyHostClusterOnAWS
}

function createHostAndImport() {
    createHostClusterOnAWS
    importAsManagedCluster
}

function _usage() {
    echo -e ""
    echo -e "Usage: $0 [options]"
    echo -e "\t$0 help you deploy a hosted cluster, then import the hosted cluster to your ACM hub,\n\tand provide helper functions to clean up and show some entry points"
    echo -e ""
    echo -e "\t-c\tcreate hosted cluster(on AWS) and imported it to ACM hub"
    echo -e "\t-d\tdetach the hosted cluster from ACM hub and destroy the hosted cluster"
    echo -e "\t-r\trender will output the hypershift CRs to YAML file for you to inspect"
    echo -e "\t-s\tshow routes to hosted cluster's OCP console and your ACM hub"
    echo -e ""
    echo -e "Note: this script assums, you put the kubeconfig to your ACM huh at ./mgmt-kubeconfig"

}

while getopts "cdrsh" opt; do
    case "${opt}" in
    c)
        createHostAndImport

        exit $?
        ;;
    d)
        cleanUpAll

        exit $?
        ;;
    r)
        renderHypershiftCreate

        exit $?
        ;;
    s)
        showHostOCP

        exit $?
        ;;
    h | ?)
        _usage

        exit 0
        ;;
    esac
done

_usage
