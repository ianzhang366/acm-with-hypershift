#!/bin/bash

target_ns="clusters-my-demo"

kubectl patch platformconfiguration -n clusters my-demo -p '{"metadata":{"finalizers":null}}' --type=merge

kubectl get cluster.cluster.x-k8s.io -n $target_ns --no-headers | awk '{print $1}' | xargs -L1 kubectl patch cluster.cluster.x-k8s.io -n $target_ns -p '{"metadata":{"finalizers":null}}' --type=merge

kubectl patch hostedcontrolplanes -n $target_ns my-demo -p '{"metadata":{"finalizers":null}}' --type=merge

kubectl get awsmachine -n $target_ns --no-headers | awk '{print $1}' | xargs -L1 kubectl patch awsmachine -n $target_ns -p '{"metadata":{"finalizers":null}}' --type=merge

kubectl get machine -n $target_ns --no-headers | awk '{print $1}' | xargs -L1 kubectl patch machine -n $target_ns -p '{"metadata":{"finalizers":null}}' --type=merge

sleep 5s
kubectl get ns $target_ns
