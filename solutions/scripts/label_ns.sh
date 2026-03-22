#!/bin/bash

USER_PREFIX="user"
USER_COUNT=100


echo "Generating ${USER_COUNT} namespace..."


for i in $(seq 1 ${USER_COUNT}); do
    USER_NAME="${USER_PREFIX}${i}"
    USER_NAMESPACE="${USER_PREFIX}${i}-dev"
    USER_NAMESPACE_SIT="${USER_PREFIX}${i}-sit"
    oc create ns ${USER_NAMESPACE} 
    oc label ns ${USER_NAMESPACE} "app.kubernetes.io/part-of=che.eclipse.org"
    oc label ns ${USER_NAMESPACE} "app.kubernetes.io/component=workspaces-namespace"
    oc label ns ${USER_NAMESPACE} "openshift.io/cluster-monitoring=true"
    oc annotate ns ${USER_NAMESPACE} "che.eclipse.org/username=${USER_NAME}"
    oc create user ${USER_NAME}
    oc adm policy add-role-to-user admin ${USER_NAME} -n ${USER_NAMESPACE}
    
    USER_NAMESPACE_SIT="${USER_PREFIX}${i}-sit"
    oc create ns ${USER_NAMESPACE_SIT} 
    oc adm policy add-role-to-user admin ${USER_NAME} -n ${USER_NAMESPACE_SIT}
    oc label ns ${USER_NAMESPACE_SIT} "openshift.io/cluster-monitoring=true"
    
    echo "Done. namespace created."
done
