# Public configuration (adjustable over CLI)
SELF_OPTIONS="
"

# Internal configuration
KITBAG_SHELLRCOPTS=()

#
# Hook executed when the PLUGIN was loaded.
#
function _self_main {
  _self_getShellRCPath
}

#
# Cleanup hook executed when the self script terminates.
#
function _self_cleanup {
  debug 'not implemented'
}

#
# Kitbag install function
#
function self_install { # Adds self home dir to OS PATH env var
  _self_check
  # Populate KITBAG_SHELLRCOPTS array 
  _self_addKitbagPath
  # Install Kitbag options into user's shell config file
  _self_addShellRCBlock

  info "Kitbag installed in ${SHELLRC_PATH}"
  info "*** Please restart your shell to make the changes effective *** "
}

function self_uninstall { # Removes self home dir from OS PATH env var
  _self_removeShellRCBlock
  info "Kitbag removed from ${SHELLRC_PATH}"
}

##################
# Helper Functions
##################

function _self_getShellRCPath {
  SHELLRC_PATH="${HOME}/.$(basename $(echo $SHELL))rc"
}

function _self_addShellRCBlock {
  echo "#kitbag begin
$(printf "%s\n" "${KITBAG_SHELLRCOPTS[@]}")
#kitbag end" >> ${SHELLRC_PATH}
}

function _self_removeShellRCBlock {
  local regexp="/#kitbag begin/,/#kitbag end/d"
  if [ $OS = 'Mac' ]; then
    sed -i '.bak' "$regexp" ${SHELLRC_PATH}
  else
    sed -i "$regexp" ${SHELLRC_PATH}
  fi
}

function _self_addKitbagPath {
  KITBAG_SHELLRCOPTS+=( "export PATH=\$PATH:${KITBAG_HOME}" )
}

function _self_check {
  grep "#kitbag begin" ${SHELLRC_PATH} &> /dev/null
  if [ $? -eq 0 ]; then
    fail "Kitbag already installed in your shell. Inspect ${SHELLRC_PATH} or use 'kitbag self uninstall'" "true"
  fi
}

function self_home {  #Go to Kitbag home directory
  dirname $(which kitbag)
}
