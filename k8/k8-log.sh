#!/bin/bash

kubelog() {

  [[ -z "${1}" ]] && echo "Must provide pod filter." && return 1

  LIST="$(kubectl get pods -o custom-columns=NAME:.metadata.name,CONTAINERS:.spec.containers[*].name)"

  [[ -z "${LIST}" ]] && echo "No pods in cluster." && return 0

  PODS=($(echo "${LIST}" | awk '{print $1}' | grep ${1}))

  [[ ${#PODS[@]} < 1 ]] && echo "No pods found matching (${1}). Exiting." return exit 1

  [[ ${#PODS[@]} > 1 ]] && echo "To many pods to choose from (${#PODS[@]}) for filter (${1}). Exiting." && return 1

  if [[ -z "${2}" ]]; then
    kubectl logs -f ${PODS[0]}
  else

    CONTAINERS=($(echo "${LIST}" | grep "${PODS[0]}" | awk '{print $2}' | tr , '\n' | grep "${2}"))

    [[ ${#CONTAINERS[@]} < 1 ]] && echo "No containers found that match (${2}). Exiting." && return 1

    [[ ${#CONTAINERS[@]} > 1 ]] && echo "More than one container found that matched (${2}). Exiting." && return 1

    kubectl logs -f ${PODS[0]} ${CONTAINERS[0]}

  fi

}