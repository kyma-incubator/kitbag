#!/bin/bash


source $KITBAG_HOME/plugin/k3s.sh

# Public configuration (adjustable over CLI)
MOTHERSHIP_OPTIONS="
MOTHERSHIP_CORRELATION_ID|corelation_id|
MOTHERSHIP_RUNTIME_ID|runtime_id|
MOTHERSHIP_SCHEDULING_ID|scheduling_id|
MOTHERSHIP_SHOOT|shoot|
MOTHERSHIP_EXCLUDE|exclude|
MOTHERSHIP_KUBECONFIG|kubeconfig|
MOTHERSHIP_K8S_NAME|kcn|msrec
"

#
# Hook executed when the PLUGIN was loaded.
#
function _mothership_main {
  cmdExists docker
  cmdExists k3d
  cmdExists istioctl
  cmdExists msrec
  cmdExists kcp
  cmdExists jq
  cmdExists tr

  varNotEmpty MOTHERSHIP_KUBECONFIG true
  fileExists ${MOTHERSHIP_KUBECONFIG} true
  
  MOTHERSHIP_KCP_OPTION=$(_mothership_validate_exclusive_args \
	  ${!MOTHERSHIP_CORRELATION_ID@} \
	  ${!MOTHERSHIP_RUNTIME_ID@} \
	  ${!MOTHERSHIP_SCHEDULING_ID@} \
	  ${!MOTHERSHIP_SHOOT@})

  varNotEmpty ISTIOCTL_PATH true
  varNotEmpty KCPCONFIG true

  MOTHERSHIP_LOCAL_JQ_FILTER=$(_mothership_parse_excluded)
  
  # create a temp mothership reconciler configuration file
  MOTHERSHIP_TEMP_MSRECONFIG=$(mktemp /tmp/msreconfig-XXXXX)
}

function _mothership_parse_excluded {
  local excluded=( $(echo "${MOTHERSHIP_EXCLUDE}" | tr "," "\n") )

  if [[ "${#excluded[@]}" > 0 ]]; then
    local jq_select_body=$(_mothership_build_exclude_filter "${excluded[@]}")
    echo "del(.configuration.components[] | select(${jq_select_body}))"
  fi
}

function _mothership_match_option {
  local arg=$1
  
  case $arg in
    ${!MOTHERSHIP_CORRELATION_ID@})
      echo "--correlation-id=${MOTHERSHIP_CORRELATION_ID}"
      ;;

    ${!MOTHERSHIP_RUNTIME_ID@})
      echo "--runtime-id=${MOTHERSHIP_RUNTIME_ID}"
      ;;

    ${!MOTHERSHIP_SCHEDULING_ID@})
      echo "--scheduling-id=${MOTHERSHIP_SCHEDULING_ID}"
      ;;

    ${!MOTHERSHIP_SHOOT@})
      echo "--shoot=${MOTHERSHIP_SHOOT}"
      ;;

    *)
      fail "Unsupported argument ${arg}" true
  esac
}

function _mothership_build_exclude_filter {
  local filter
  local args=( "$@" )

  for i in "${!args[@]}"; do
    filter="${filter} .component == \"${args[i]}\""

    if [ "${#args[@]}" == $(( i + 1 )) ]; then
      break
    fi
    
    filter="${filter} or"
  done

  echo ${filter}
}

# validate exclusive arguments
function _mothership_validate_exclusive_args {
  local args=( "$@" )
  local is_found=false
  local result

  for arg in "${args[@]}"; do
    # continue if variable with a given name is not set
    if [ -z "${!arg}" ]; then 
      debug "empty argument skipped: ${arg}"
      continue
    fi

    # fail if argument was already found
    if [ "$is_found" = true ]; then
      fail "Exclusive arguments found: ${arg}, ${result}" true
    fi

    # valid argument was found
    debug "argument found: ${arg}:${!arg}"
    is_found=true
    result=${arg}
  done

  # none argument was found
  if [ false = "$is_found" ]; then
    fail "invalid argument: mandatory argument is missing" true
  fi
  
  # assign result value to the variable
  local var=${args[1]} 
  echo $(_mothership_match_option ${result})
}

#
# Cleanup hook executed when the Kitbag script terminates.
#
function _mothership_cleanup {
  # set trap to prevent cleanup interrupts
  trap "" SIGINT

  rm -f "$MOTHERSHIP_TEMP_MSRECONFIG"

  # remove cleanup interrupt trap
  trap - SIGINT
}

#
# Creates a new cluster and start mothership reconciler.
#
function mothership_local {
  # fetch cluster configuration from the mothership
  kcp rc s ${MOTHERSHIP_KCP_OPTION} -o json > "${MOTHERSHIP_TEMP_MSRECONFIG}"

  # fail with error message if error code is not 0
  if [ "$?" -ne 0 ]; then
    fail "cluster state fetching failed" true
  fi

  # transform cluster configuration - filter components
  jq "${MOTHERSHIP_LOCAL_JQ_FILTER}" "${MOTHERSHIP_TEMP_MSRECONFIG}" \
  > "${MOTHERSHIP_TEMP_MSRECONFIG}"
  
  # fail with error message if error code is not 0
  if [ "$?" -ne 0 ]; then
    fail "component filtering failed" true
  fi
  
  # run mothership local command
  cat ${MOTHERSHIP_TEMP_MSRECONFIG} \
  | msrec local --kubeconfig=${MOTHERSHIP_KUBECONFIG} -

  # fail with error message if error code is not 0
  if [ "$?" -ne 0 ]; then
    fail "local reconciliation failed" true
  fi
}

