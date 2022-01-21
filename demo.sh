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

oidc_bucket="izhang-hyper-v1"
bucket_region="us-east-1"
aws_cred_file="$HOME/.aws/credentials"

pull_secret="../notes/pull-secret.txt"
hostClusterNamespace="clusters"
hostClusterName="mce-auto-import"

ssh_pub_key_path="../notes/id_rsa.pub"
infraID="izhang-hypershift-demo-zqjpd"
hypershiftDestroyCMD="/Users/ianzhang/golang/src/hypershift/hypershift/bin/hypershift "

hostKubeconfig="/tmp/hostKubeconfig"
mgmt_kubeconfig="$HOME/golang/src/cluster-keeper-clc/dependencies/lifeguard/clusterclaims/izhang-hub/kubeconfig"

export DEMO_MC_NAME="hypershift-demo-managed-cluster"
hyershift_demo_MC="./managed-cluster.yaml"

auto_import_secret="./auto-import-secret.yaml"
auto_import_crd="./auto-import-crd.yaml"

HOST_OC="oc --kubeconfig $hostKubeconfig"

MGMT_OC="oc --kubeconfig $mgmt_kubeconfig"

addon_config="./addonconfig.yaml"

BASE_DOMAIN="dev02.red-chesterfield.com"

function checkSetup() {
    pe "which hypershift"
    if [ -z "$(which hypershift)" ]; then
        echo "hypershift binary dones't exist, please install it follow: https://github.com/openshift/hypershift"
        exit 1
    fi

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

function hypershiftCreate() {
    local KUBECONFIG=$mgmt_kubeconfig
    local render="$1"
    pe "hypershift create cluster aws \
        --pull-secret $pull_secret \
        --aws-creds $aws_cred_file \
        --name $hostClusterName \
        --namespace $hostClusterNamespace \
        --base-domain $BASE_DOMAIN \
        --infra-id $infraID \
        --instance-type m5.xlarge \
        --region $bucket_region \
        --node-pool-replicas 2 \
        --root-volume-size 30 \
        --root-volume-type gp2 \
        --ssh-key $ssh_pub_key_path $render"
}

function createHostClusterOnAWS() {
    local KUBECONFIG=$mgmt_kubeconfig

    hypershiftCreate

    pe "$MGMT_OC wait --timeout=300s --for=condition=IgnitionEndpointAvailable hostedcluster -n $hostClusterNamespace $hostClusterName"

    pe "$MGMT_OC wait --timeout=300s --for=condition=KubeAPIServerAvailable hostedcontrolplane -n $hostClusterNamespace-$hostClusterName $hostClusterName"
    pe "$MGMT_OC get secret -n $hostClusterNamespace ${hostClusterName}-admin-kubeconfig -ogo-template='{{.data.kubeconfig | base64decode}}' > $hostKubeconfig"
}

function destroyHostClusterOnAWS() {
    local KUBECONFIG=$mgmt_kubeconfig
    pe "$hypershiftDestroyCMD destroy cluster aws \
        --aws-creds $aws_cred_file \
        --name $hostClusterName \
        --namespace $hostClusterNamespace \
        --base-domain $BASE_DOMAIN \
        --infra-id $infraID \
        --region $bucket_region"

    pe "$MGMT_OC get hostedcluster -A"
}

function showHostOCP() {
    #comment "Get ACM route"
    printf "ACM URL:\n{https://%s}\n" $($MGMT_OC get route -n open-cluster-management multicloud-console -ojsonpath='{.status.ingress[].host}')

    pe "$MGMT_OC get secret -n $hostClusterNamespace ${hostClusterName}-admin-kubeconfig -ogo-template='{{.data.kubeconfig | base64decode}}' > $hostKubeconfig"
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
    # unimportAsManagedCluster
    destroyHostClusterOnAWS
}

function createHostAndImport() {
    createHostClusterOnAWS
    # importAsManagedCluster
}

function _usage() {
    echo -e ""
    echo -e "Usage: $0 [options]"
    echo -e "\t$0 help you deploy a hosted cluster, then import the hosted cluster to your ACM hub,\n\tand provide helper functions to clean up and show some entry points.\n\tYou should run $0 -i at least once before running other operator."
    echo -e ""
    echo -e "\t-c\tcreate hosted cluster(on AWS) and imported it to ACM hub"
    echo -e "\t-d\tdetach the hosted cluster from ACM hub and destroy the hosted cluster"
    echo -e "\t-f\tforce reimport the hosted cluster to ACM"
    echo -e "\t-i\tinstall hypershift operator to your management clouster(aka, the ACM hub's OCP)"
    echo -e "\t-r\trender will output the hypershift CRs to YAML file for you to inspect"
    echo -e "\t-s\tshow routes to hosted cluster's OCP console and your ACM hub"
    echo -e ""
    echo -e "Note: this script assums, you put the kubeconfig to your ACM huh at ./mgmt-kubeconfig"

}

while getopts "cdfirsh" opt; do
    case "${opt}" in
    c)
        createHostAndImport

        exit $?
        ;;
    d)
        cleanUpAll

        exit $?
        ;;
    f)
        unimportAsManagedCluster
        importAsManagedCluster

        exit $?
        ;;
    i)
        # checkSetup
        installHypershiftOperator

        exit $?
        ;;

    r)
        hypershiftCreate "--render  > hypershift-create.yaml"

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
