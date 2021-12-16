#!/bin/bash
#
# [y] hybris Platform
#
# Copyright (c) 2020 SAP SE or an SAP affiliate company. All rights reserved.
#
# This software is the confidential and proprietary information of SAP
# ("Confidential Information"). You shall not disclose such Confidential
# Information and shall use it only in accordance with the terms of the
# license agreement you entered into with SAP.
#

#
# Log a debug message to stdout.
# @param The debug message.
#
function debug {
  local msg=$1
  if [ $DEBUG -eq 1 ]; then
    echo "DEBUG: ${msg}"
  fi
}

#
# Log a info message to stdout.
# @param The info message.
#
function info {
  local msg=$1
  echo "INFO: ${msg}"
}

#
# Log a warn message to stderr.
# @param The info message.
#
function warn {
  local msg=$1
  echo >&2 "WARN: ${msg}"
}

#
# Set a failure marker for the dispatcher.
# @param The error message.
#
function fail {
  local msg=$1
  local failFast=$2

  ERROR+=( "$msg" )

  _failFast $failFast
}

#
# Check whether a file exists on the local disk. Otherwise exit the script with an error message.
# @param The file path.
# @param OPTIONAL: Fail fast flag (stop further processing immediatelly otherwise finalize current dispatch loop).
#
function fileNotExists {
  local file=$1
  local failFast=$2

  if [ -f $file ]; then
    fail "The file '$file' already exists"
    _failFast $failFast
    return 1
  fi
}

#
# Check whether a file not exists on the local disk. Otherwise exit the script with an error message.
# @param The file path.
# @param OPTIONAL: Fail fast flag (stop further processing immediatelly otherwise finalize current dispatch loop).
#
function fileExists {
  local file=$1
  local failFast=$2
  local msg=$3
 
  if [ ! -f $file ]; then
    if [ -z "${msg}" ]; then
      fail "The file '$file' does not exist"
    else
      fail "$msg"
    fi
    _failFast $failFast
    return 1
  fi
}

#
# Check whether a directory exists on the local disk. Otherwise exit the script with an error message.
# @param The directory path.
# @param OPTIONAL: Fail fast flag (stop further processing immediatelly otherwise finalize current dispatch loop).
function dirExists {
  local dir=$1
  local failFast=$2

  if [ ! -d $dir ]; then
    fail "The directory '$dir' does not exist"
    _failFast $failFast
    return 1
  fi
}

#
# Check whether a command is availble on the shell. Otherwise exit the script with an error message.
# @param The command.
# @param Custom error message.
# @param OPTIONAL: Fail fast flag (stop further processing immediatelly otherwise finalize current dispatch loop).
#
function cmdExists {
  local cmd=$1
  local failFast=$2
  local msg=$3

  which $cmd > /dev/null
  if [ $? -ne 0 ]; then
    if [ -z "${msg}" ]; then
      fail "Command '${cmd}' not found in path"
    else
      fail "$msg"
    fi
    _failFast $failFast
    return 1
  fi
}

#
# Check whether a varialbe is defined and not empty.
# @param Variable name.
# @param OPTIONAL: Fail fast flag (stop further processing immediatelly otherwise finalize current dispatch loop).
#
function varNotEmpty {
  local var=$1
  local failFast=$2

  if [ -z "${!var}" ]; then
    fail "The variable '$var' was not defined or is empty"
    _failFast $failFast
    return 1
  fi
}

function _failFast {
  local failFast=$1

  if [ "$failFast" = "true" ]; then
    _showHelp
  fi
}

#
# Wait until a provided command is returning '0'(success) as return code or a timeout occurrs.
# @param Name of the command (shown in the wait message).
# @param The command which will be executd in a loop until it returns 0.
# @param Seconds to wait until the command will be executed again.
# @param Timeout in seconds.
#
function waitFor {
  local name=$1
  local command=$2
  local sleep=$3
  local timeout=$4
  local justWarn=$5

  echo -n "Waiting for ${name} to be ready "

  local loopCount=0
  until $(eval "$command"); do
    if [ "$loopCount" -ge $timeout ]; then
      echo ""
      echo -n "Timeout for ${name} exceeded: "
      if [ "$justWarn" = '1' -o "$justWarn" = 'true' -o "$justWarn" = 'yes' ]; then
        echo "CONTINUING"
        return 1
      else
        echo "ABORTING"
        exit 1
      fi
    fi
    printf '.'
    sleep $sleep
    let loopCount=loopCount+$sleep
  done
  echo ""
  return 0
}

#
# Join the elements of an array into a string.
# @param Concatination string.
# @param Array to join.
#
function joinArray {
  local IFS="$1"
  shift
  echo "$*"
}

#
# Render a template file (replace placeholders with current parameters).
# @param Path to the template file.
#
function renderTemplate {
  template=$1

  eval "echo \"$(< $template)\""
}

#
# Lookup for a configuration file in following locations: $PWD, $WORK_DIR, $HOME)
# Several file names can be passed as argument. First match wins.
# @param List of file names to search for.
#
function lookupConfigFile {
  local configFileFound=''
  local searchDir=''
  for configFile in "$@"; do
    for searchDir in ${PWD} ${WORK_DIR} "${HOME}/.kitbag" ${HOME}; do
      if [ -d "${searchDir}/${configFile}" ]; then
        configFileFound="${searchDir}/${configFile}"
        break
      fi
      if [ -f "${searchDir}/${configFile}" ]; then
        configFileFound="${searchDir}/${configFile}"
        break
      fi
    done
  done
  echo "$configFileFound"
}

#
# Install a container registry credential.
# @param secretName Name of the generate pull secret in Kubernetes.
# @param secretNamespace OPTIONAL: the namespace in which the secet should be deployed (default is 'default').
#
function deployK8sGcrCredentials {
  local secretName=$1
  local secretNamespace=$2
  local registryServer='eu.gcr.io'
  local registryUsername='_json_key'
  local registrySaFile=$(lookupConfigFile 'ccv2-devops-gcr.json')

  # Sanity checks
  if [ -z "$secretNamespace" ]; then
    secretNamespace='default'
  fi
  fileExists "$registrySaFile" true

  # Deploy the secret (if it doesn't exist already)
  kubectl -n $secretNamespace get secret $secretName > /dev/null
  if [ $? -eq 0 ]; then
    debug "Container registry secret '${secretNamespace}/${secretName}' already exists"
    return 0
  fi

  debug "Deploy new container registry credential '${secretName}'"
  kubectl -n $secretNamespace create secret docker-registry $secretName \
    --namespace="${secretNamespace}" \
    --docker-server="${registryServer}" \
    --docker-username="${registryUsername}" \
    --docker-password="$(cat ${registrySaFile})" \
    --docker-email=DL_5DA8771955A2D7205C1EE7CA@global.corp.sap

  if [ $? -ne 0 ]; then
    fail "Could not create container registry secret '${secretName}'" true
  fi
}

#
# Encrypt a file and lock it with a password (encrypted file will be stored with .enc extension).
# @param inputFile The file to encrypt.
# @paran password The password used to protect the file.
#
function encrypt {
  local inputFile=$1
  local password=$2
  local outputFile="$1.enc"

  openssl aes-256-cbc -md sha512 -pbkdf2 -iter 100000 -a -salt \
    -in "$inputFile" -out "$outputFile" -base64 \
    -pass pass:"$password"
}

#
# Decrypt a protected file. Decrypted file will be stored beside the encrypted file but without the .enc extension.
# @param inputfile The encrypted file.
# @param password The password to unlock the decrypted file.
#
function decrypt {
  local inputFile=$1
  local password=$2
  
  filename=$(basename -- "$inputFile")
  openssl enc -aes-256-cbc -md sha512 -pbkdf2 -iter 100000 -d \
    -in "$inputFile" -out "$(dirname $inputFile)/${filename%.*}" -base64 \
    -pass pass:"$password"
}
