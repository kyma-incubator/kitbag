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

  fileExists ${MOTHERSHIP_KUBECONFIG} true

  _mothership_validateArgs \
	  MOTHERSHIP_KCP_OPTION \
	  ${!MOTHERSHIP_CORRELATION_ID@} \
	  ${!MOTHERSHIP_RUNTIME_ID@} \
	  ${!MOTHERSHIP_SCHEDULING_ID@} \
	  ${!MOTHERSHIP_SHOOT@}

  varNotEmpty ISTIOCTL_PATH true
  varNotEmpty KCPCONFIG true

  MOTHERSHIP_LOCAL_JQ_FILTER=$(_mothership_parse_excluded)
  
  # create a temp kubeconfig file
  MOTHERSHIP_TEMP_KUBECONFIG=$(mktemp /tmp/kubeconfig-XXXXX)
  MOTHERSHIP_TEMP_MSRECONFIG=$(mktemp /tmp/msreconfig-XXXXX)

  MOTHERSHIP_LOCAL_TEMP_STD_ERR=$(cat /dev/urandom | env LC_CTYPE=C tr -cd 'a-f0-9' | head -c 32)
  MOTHERSHIP_LOCAL_FD=3
}

function _mothership_parse_excluded {
  local excluded=( $(echo "${MOTHERSHIP_EXCLUDE}" | tr "," "\n") )

  if [[ "${#excluded[@]}" > 0 ]]; then
    local jq_select_body=$(_mothership_build_exclude_filter "${excluded[@]}")
    echo "del(.configuration.components[] | select(${jq_select_body}))"
  fi
}

function _mothership_match_option {
  local var=$1 
  local arg=$2
  
  case $arg in
    ${!MOTHERSHIP_CORRELATION_ID@})
      eval "${var}=--correlation-id=${MOTHERSHIP_CORRELATION_ID}"
      ;;

    ${!MOTHERSHIP_RUNTIME_ID@})
      eval "${var}=--runtime-id=${MOTHERSHIP_RUNTIME_ID}"
      ;;

    ${!MOTHERSHIP_SCHEDULING_ID@})
      eval "${var}=--scheduling-id=${MOTHERSHIP_SCHEDULING_ID}"
      ;;

    ${!MOTHERSHIP_SHOOT@})
      eval "${var}=--shoot=${MOTHERSHIP_SHOOT}"
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

# validate exclusive arguments (change to parse)
function _mothership_validateArgs {
  local args=( "$@" )
  local is_found=false
  local result

  for arg in "${args[@]:1}"; do
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
  _mothership_match_option ${args[0]} ${result}
}

#
# Cleanup hook executed when the Kitbag script terminates.
#
function _mothership_cleanup {
  # set trap to prevent cleanup interrupts
  trap "" SIGINT

  # close file descriptor
  eval "exec $MOTHERSHIP_LOCAL_FD<&-"

  rm -f "$MOTHERSHIP_TEMP_KUBECONFIG" "$MOTHERSHIP_TEMP_MSRECONFIG" "$MOTHERSHIP_LOCAL_TEMP_STD_ERR"

  # remove cleanup interrupt trap
  trap - SIGINT
}

function _mothership_fetch_cluster_state {
  local command=$1

  mkfifo "$MOTHERSHIP_LOCAL_TEMP_STD_ERR"

  # redirect error output, async call is blocked with error pipe
  $command > "$MOTHERSHIP_TEMP_MSRECONFIG" 2>"$MOTHERSHIP_LOCAL_TEMP_STD_ERR" &
  local pid=$!

  # unblock command call
  eval "exec $MOTHERSHIP_LOCAL_FD<$MOTHERSHIP_LOCAL_TEMP_STD_ERR"
  wait $pid

  local exitcode=$?

  # fail with error message if error code is not 0
  [ "$exitcode" -gt 0 ] && fail "$(cat <&3)" true
}

#
# Creates a new cluster and start mothership reconciler.
#
function mothership_local {
  _mothership_fetch_cluster_state "kcp rc s ${MOTHERSHIP_KCP_OPTION} -o json"

  cat ${MOTHERSHIP_TEMP_MSRECONFIG} \
  | jq "${MOTHERSHIP_LOCAL_JQ_FILTER}" \
  | tee /tmp/test.cluster.config.json \
  | msrec local --kubeconfig=${MOTHERSHIP_KUBECONFIG} -
}

