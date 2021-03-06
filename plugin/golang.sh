#!/bin/bash

# Public configuration (adjustable over CLI)
GOLANG_OPTIONS="
"

# Internal configuration
golang_red='\033[0;31m'
golang_green='\033[0;32m'
golang_nc='\033[0m' # No Color

#
# Hook executed when the PLUGIN was loaded.
#
function _golang_main {
  debug 'No main hook required for golang plugin'
}

#
# Cleanup hook executed when the Kitbag script terminates.
#
function _golang_cleanup {
  debug 'No cleanup hook required for golang plugin'
}

function golang_test { # Merge branch into current branch
  go test -race -coverprofile=cover.out ./...
}

function golang_lint { # Kyma 
  local LINTS=(
    # default golangci-lint lints
    deadcode errcheck gosimple govet ineffassign staticcheck \
    structcheck typecheck unused varcheck \
    # additional lints
    golint gofmt misspell gochecknoinits unparam scopelint gosec
  )
  local ENABLE=$(sed 's/ /,/g' <<< "${LINTS[@]}")

  echo "Checks: ${LINTS[*]}"
  golangci-lint --disable-all --enable="${ENABLE}" --timeout=10m run $(pwd)/...

  echo -e "${golang_green}√ run golangci-lint${golang_nc}"
}

