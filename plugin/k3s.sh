#!/bin/bash

# Public configuration (adjustable over CLI)
K3S_OPTIONS="
-K3S_K8S_NAME|-kcn|kyma
"

#
# Hook executed when the PLUGIN was loaded.
#
function _k3s_main {
  cmdExists docker false "'docker' not found in path.
Please install Docker and re-run this script
(see https://docs.docker.com/get-docker/)"

  cmdExists kubectl false "'kubectl' not found in path.
Please install Kubectl and re-run this script
(see https://kubernetes.io/docs/tasks/tools/install-kubectl/)"

  cmdExists k3d false "'k3d' not found in path.
Please install K3D and re-run this script
(see https://github.com/rancher/k3d#get)"
}

#
# Cleanup hook executed when the Kitbag script terminates.
#
function _k3s_cleanup {
  debug 'No cleanup action required for K3S'
}

#
# Create a new K3S cluster.
#
function k3s_create { # Create new k3s cluster (or restart existing cluster)
  k3d cluster list | grep $K3S_K8S_NAME
  if [ $? -eq 0 ]; then
    k3d cluster start $K3S_K8S_NAME
  else
    k3d cluster create $K3S_K8S_NAME
  fi
}

#
# Delete a K3S cluster.
#
function k3s_delete { # Delete k3s cluster
  debug "Delete K3S cluster '$K3S_K8S_NAME'"
  k3d cluster delete "$K3S_K8S_NAME"
}

#
# Re-create a K3S cluster.  
#
function k3s_rebuild { # Rebuild k3s cluster
  k3s_delete
  k3s_create
}

function k3s_config { # Get the kubeconfig file
  k3d kubeconfig get $K3S_K8S_NAME
}
