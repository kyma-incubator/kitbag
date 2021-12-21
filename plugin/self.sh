# Public configuration (adjustable over CLI)
SELF_OPTIONS="
"

# Internal configuration
self_kitbagShellRCOpts=()
self_shellRCPath=""

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
  # Populate self_kitbagShellRCOpts array
  _self_addKitbagPath
  # Install Kitbag options into user's shell config file
  _self_addShellRCBlock

  info "Kitbag installed in ${self_shellRCPath}"
  info "*** Please restart your shell to make the changes effective *** "
}

function self_uninstall { # Removes self home dir from OS PATH env var
  _self_removeShellRCBlock
  info "Kitbag removed from ${self_shellRCPath}"
}

function self_home {  #Go to Kitbag home directory
  dirname $(which kitbag)
}

function self_lint {  #Run linter for Kitbag sources
  files=$(find $KITBAG_HOME -name *.sh | xargs echo " ")
  docker run --rm -v "$KITBAG_HOME:$KITBAG_HOME" koalaman/shellcheck $files
}

##################
# Helper Functions
##################

function _self_getShellRCPath {
  self_shellRCPath="${HOME}/.$(basename $(echo $SHELL))rc"
}

function _self_addShellRCBlock {
  echo "#kitbag begin
$(printf "%s\n" "${self_kitbagShellRCOpts[@]}")
#kitbag end" >> ${self_shellRCPath}
}

function _self_removeShellRCBlock {
  local regexp="/#kitbag begin/,/#kitbag end/d"
  if [ $OS = 'Mac' ]; then
    sed -i '.bak' "$regexp" ${self_shellRCPath}
  else
    sed -i "$regexp" ${self_shellRCPath}
  fi
}

function _self_addKitbagPath {
  self_kitbagShellRCOpts+=( "export PATH=\$PATH:${KITBAG_HOME}" )
}

function _self_check {
  grep "#kitbag begin" ${self_shellRCPath} &> /dev/null
  if [ $? -eq 0 ]; then
    fail "Kitbag already installed in your shell. Inspect ${self_shellRCPath} or use 'kitbag self uninstall'" "true"
  fi
}
