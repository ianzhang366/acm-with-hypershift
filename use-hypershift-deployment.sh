#!/bin/bash

DEMO_DIR="$(dirname "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd ${DEMO_DIR}/.. && pwd)"

. _demo-magic.sh

TYPE_SPEED=30
# PROMPT_AFTER=1
DEMO_PROMPT="☸ $ "
NO_WAIT=1

work_dirctory="/Users/ianzhang/golang/src/hypershift/josh-fork"

hypershiftDeploymentDir="/Users/ianzhang/golang/src/hypershift/hypershift-deployment-controller"
awsSecretDir="./aws-secret.yaml"

hypershiftDeployment="./sample-cluster-2.yaml"

management_cluster="$HOME/golang/src/cluster-keeper-clc/dependencies/lifeguard/clusterclaims/izhang-hd/kubeconfig"

MGMT_OC="oc --kubeconfig $management_cluster"

oidc_bucket="izhang-hyper-dev02"
bucket_region="us-east-1"
aws_cred_file="$HOME/.aws/credentials"

hostClusterNamespace="clusters"

hypershiftCmd="/Users/ianzhang/golang/src/hypershift/hypershift/bin/hypershift"
# hypershiftCmd="/Users/ianzhang/golang/src/hypershift/josh-fork/bin/hypershift"

#izhang-hyper-test-499
export hostClusterName="sample-2"
host_Kubeconfig="/tmp/host-kubeconfig"

function createBucket() {
    BUCKET_NAME="$oidc_bucket"
    aws s3api create-bucket --acl public-read --bucket $BUCKET_NAME --debug
}

function startUpOperator() {

    p "# set up the hypershift operator"
    p ""
    export KUBECONFIG="$management_cluster"
    # make build

    # install CRDs
    $hypershiftCmd install --oidc-storage-provider-s3-bucket-name="$oidc_bucket" \
        --oidc-storage-provider-s3-region="$bucket_region" \
        --oidc-storage-provider-s3-credentials="$aws_cred_file"

    # turn off the default in-cluster hypershift controllers
    # kubectl patch deploy operator -n hypershift -p '{"spec":{"replicas": 0}}' --type=merge

    pe "oc get deploy -n hypershift"

    # run operator in local env
    #    go run ./hypershift-operator run \
    #        --oidc-storage-provider-s3-bucket-name=$oidc_bucket \
    #        --oidc-storage-provider-s3-region=$bucket_region \
    #        --namespace=hypershift \
    #        --oidc-storage-provider-s3-credentials=$aws_cred_file

    # pe "kubectl set image deployment -n hypershift operator operator=$hypershift_operator_img"

    cd $hypershiftDeploymentDir

    oc project open-cluster-management

    oc apply -k config/rbac
    oc apply -k config/deployment
}

function createHostCluster() {
    export KUBECONFIG="$management_cluster"
    oc create ns clusters

    oc apply -f $awsSecretDir

    envsubst < $hypershiftDeployment | kubectl apply -f -

    pe "oc get hc -n clusters"
    pe "oc wait --timeout=300s --for=condition=ValidHostedControlPlaneConfiguration hostedcluster -n $hostClusterNamespace $hostClusterName"
}

function deleteHostedCluster() {
    export KUBECONFIG="$management_cluster"

    envsubst < $hypershiftDeployment | kubectl delete -f -
    # oc delete -f $awsSecretDir

    # oc delete ns clusters
}

function showHostOCP() {
    #comment "Get ACM route"
    printf "ACM URL:\n{https://%s}\n" $($MGMT_OC get route -n open-cluster-management multicloud-console -ojsonpath='{.status.ingress[].host}')

    pe "waitFor secret $hostClusterNamespace ${hostClusterName}-admin-kubeconfig $management_cluster"
    pe "$MGMT_OC get secret -n $hostClusterNamespace ${hostClusterName}-admin-kubeconfig -ogo-template='{{.data.kubeconfig | base64decode}}' > $host_Kubeconfig"

    waitFor "route" openshift-console console $host_Kubeconfig
    waitforRouteStatus openshift-console console $host_Kubeconfig

    printf "Guest cluster OCP console URL:\n{https://%s}\n" $(oc get route --kubeconfig $host_Kubeconfig -n openshift-console console -ojsonpath='{.status.ingress[].host}')

    waitFor "secret" $hostClusterNamespace-$hostClusterName kubeadmin-password $management_cluster
    printf "Guest cluster kubeadmin-password:\n{%s}\n" $($MGMT_OC get secret -n $hostClusterNamespace-$hostClusterName kubeadmin-password -ogo-template='{{.data.password | base64decode}}')
}

while getopts "c:d:ish" opt; do
    case "${opt}" in
    c)
        hostClusterName="$OPTARG"
        createHostCluster
        showHostOCP
        exit $?
        ;;
    d)
        hostClusterName="$OPTARG"
        deleteHostedCluster

        exit $?
        ;;
    i)
        # createBucket
        startUpOperator

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
