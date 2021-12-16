#!/bin/bash

# Public configuration (adjustable over CLI)
SELF_PLUGIN_OPTIONS="
-SELF_PLUGIN_NAME|-gpn||The plugin name
-SELF_PLUGIN_CMD|-gcn|firstcmd|Name of the command
"

#
# Hook executed when the plugin was loaded.
#
function _self_plugin_main {
  debug "Main hook of 'self_plugin' called"
}

#
# Cleanup hook executed when the Kitbag script terminates.
#
function _self_plugin_cleanup {
  debug "Cleanup hook of 'self_plugin' called"
}

#
# Command implementation. Command will be shown in the help message of this PLUGIN.
#
function self_plugin_create { # Create a new plugin
  varNotEmpty 'SELF_PLUGIN_NAME' true
  fileNotExists "${PLUGIN_DIR}/${SELF_PLUGIN_NAME}.sh" true

  _self_plugin_checkKitbag
  _self_plugin_loadtpl
  _self_plugin_customizeTemplate
  _self_plugin_deployTemplate
}


#################################################
# Helper functions
#################################################

# Load template to variable

function _self_plugin_loadtpl {
  read -rd '' SELF_PLUGIN_TPL << "EOF"
#!/bin/bash

# Public configuration (adjustable over CLI)
<PLUGIN>_OPTIONS="
-OPTIONNAME|-ACRONYM|defaultValue|Description
"

#
# Main hook executed when the plugin gets loaded.
#
function _<plugin>_main {
  debug "Main hook of '<plugin>' called"

  # load further plugins
  #loadPlugin plugin
}

#
# Cleanup hook executed when the plugin terminates.
#
function _<plugin>_cleanup {
  debug "Cleanup hook of '<plugin>' called"
}


function <plugin>_<command> { # Description of <plugin>_<command>
  info "You are in plugin '<plugin>': executing '<plugin>_<command>'"
}

EOF
}

function _self_plugin_customizeTemplate {
  # Inject PLUGIN name
  SELF_PLUGIN_TPL=$(sed "s/<plugin>/${SELF_PLUGIN_NAME}/g" <(echo "${SELF_PLUGIN_TPL}"))
  # Inject first command name
  SELF_PLUGIN_TPL=$(sed "s/<command>/${SELF_PLUGIN_CMD}/g" <(echo "${SELF_PLUGIN_TPL}"))
  # Inject upper case PLUGIN namve for PLUGIN_OPTIONS 
  SELF_PLUGIN_NAME_UPPER="$(echo ${SELF_PLUGIN_NAME} | tr 'a-z' 'A-Z')"
  SELF_PLUGIN_TPL=$(sed "s/<PLUGIN>/${SELF_PLUGIN_NAME_UPPER}/g" <(echo "${SELF_PLUGIN_TPL}"))
}

function _self_plugin_deployTemplate {
  # Creates file with content of the SELF_PLUGIN_TPL variable
  echo "${SELF_PLUGIN_TPL}" > "${PLUGIN_DIR}/${SELF_PLUGIN_NAME}.sh"
  if [ $? -eq 0 ]; then
    info "PLUGIN '${SELF_PLUGIN_NAME}' successfully created. Have fun!"
  else
    fail "Something went wrong. Sorry!"
  fi
}

function _self_plugin_checkKitbag {
  if [ ${SELF_PLUGIN_NAME} == "kitbag" ]; then
    fail "Kitbag name is reserved for main script. Choose different name!" "true"
  fi
}
