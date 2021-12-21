#!/bin/bash

# INTERNAL CONFIGURATION
DEBUG=$KITBAG_DEBUG
DEFAULT_IFS=$IFS
WORK_DIR=$KITBAG_HOME
PLUGIN_DIR=$KITBAG_HOME/plugin
PLUGINS=$(find $PLUGIN_DIR -maxdepth 1 -name '*.sh' -execdir basename -s '.sh' {} +)  #Available plugins for kitbag tool

# CLI ARGS (managed by parseargs function)
PLUGIN='kitbag'    #PLUGIN the user asked for
CLI_COMMANDS=()  #Commands entered by the user
CLI_OPTIONS=()   #Options the user has provided

# DISPATCHING (managed by dispatch function)
SUB_PLUGINS=()     #List of called sub-plugins (used if dispatch-function is called more than one time)
LOADED_PLUGINS=()  # List of all loaded plugins
PLUGIN_COMMANDS=() #Supported commands of the plugin
PLUGIN_OPTIONS=()  #Supported options of the plugin
ERROR=()           #Fail method error array
SHOW_HELP=0
#################################

#
# Load the kitbag configuration file.
#
function loadConfigFile {
  local configFile=$(lookupConfigFile 'config') #support multiple config file locations
  if [ -f "$configFile" ]; then
    debug  "Load configuration file '$configFile'"
    chmod 600 "$configFile"
    source "$configFile"
  elif [ -d "$configFile" ]; then
    info  "Adjust file permissions of directory '$configFile' to 0700"
    chmod 700 "$configFile"
  else
    debug "No configuration file found"
    return 1
  fi
}

#
# Parse command line arguments. The function groups them into three different kinds and stores them in global variables.
#
# $PLUGIN: contains the plugin the user has entered.
# $CLI_COMMANDS: array containing the requested commands.
# $CLI_OPTIONS: array containing the provided user options.
#
# @param CLI arguments. ($@)
#
function parseArgs {
  # group provided CLI arguments
  debug "Start parsing provided CLI arguments"
  local loopCount=0
  while [ $# -gt 0 ]; do
    if [[ "$1" == "-"* ]]; then
      # CLI argument is an OPTION
      debug "Checking if CLI parameter '$1' is an supported option"
      if [[ "$1" == "-help" ]]; then
        SHOW_HELP=1
        shift 1
      fi
      for pluginOption in $pluginOptions[@]; do
        debug "CLI parameter '$1' is an option"
        #internal delimiter for CLI_OPTIONS is set to § to avoid parsing errors if a more common symbol was used instead
        CLI_OPTIONS+=( "$(echo $1 | tr -d '-')§${2}" )
        shift 2
      done
    else
      # CLI argument is the PLUGIN or a COMMAND
      if [ $loopCount -eq 0 ]; then #first non-option is always treated as the requested plugin
        debug "CLI parameter '$1' is the plugin"
        PLUGIN=$1
      else
        debug "CLI parameter '$1' is a command"
        CLI_COMMANDS+=( $1 )
      fi
      shift 1
      let loopCount=loopCount+1
    fi
  done
  debug "Parsing CLI arguments finished: PLUGIN=${PLUGIN} / CLI_COMMANDS=${CLI_COMMANDS[*]} / CLI_OPTIONS=${CLI_OPTIONS[*]} / SHOW_HELP=${SHOW_HELP}"
}

#
# Dispatch the requested plugin. The dispatch function recognizes whether a main-plugin has to be dispatched or
# a sub-plugin of it.
# The dispatching will load the requested (sub-)plugin and call the (sub-)plugin specific hooks.
# An help message will be shown if the dispatching was not possible.
#
# @param The plugin to dispatch.
#
function dispatch {
  debug "Dispatch main plugin '$PLUGIN'"
  _dispatchPlugin $PLUGIN
  for callee in ${CLI_COMMANDS[@]}; do
    debug "Try to call command '$callee'"
    for pluginCommand in ${PLUGIN_COMMANDS[@]}; do
      if [ "$pluginCommand" = "$callee" ]; then
        _callPluginCommand $callee
        return
      fi
    done

    debug "Try to dispatch to sub-plugin '${PLUGIN_DIR}/$(joinArray '/' ${SUB_PLUGINS[@]})/${callee}.sh'"
    if [ -f "${PLUGIN_DIR}/$(joinArray '/' ${SUB_PLUGINS[@]})/${callee}.sh" ]; then
      _dispatchSubPlugin $callee
    fi

    # stop further dispatching if an error occurred
    if [ ${#ERROR[@]} -gt 0 ]; then
      _showHelp
    fi
  done
  _showHelp
}

function _dispatchPlugin {
  local dispatchPlugin=$1
  local pluginPath=${PLUGIN_DIR}/${dispatchPlugin}.sh

  debug "Dispatching plugin '${dispatchPlugin}'"

  if [ -f "$pluginPath" ]; then
    loadPlugin "$dispatchPlugin"
    # Remember the loaded plugin for later dispatch calls
    SUB_PLUGINS+=( $dispatchPlugin )
  else
    debug "Plugin '${dispatchPlugin}' not found on filesystem ($pluginPath), use 'kitbag' as fallback plugin"
    PLUGIN='kitbag'
    _showHelp
  fi

  debug "Resolve supported commands of plugin '${dispatchPlugin}'"
  PLUGIN_COMMANDS=( $(grep -o "function *${dispatchPlugin}_.*[^{ ]" $pluginPath | awk -F "{" '{print $1}' | awk -F "_" '{print $2}') )
  debug "Found commands in plugin: ${PLUGIN_COMMANDS[*]}"
}

function _dispatchSubPlugin {
  local dispatchPlugin=$1
  local pluginPath="${PLUGIN_DIR}/$(joinArray '/' ${SUB_PLUGINS[@]})/${dispatchPlugin}.sh"

  debug "Dispatching sub-plugin '$(joinArray '_' ${SUB_PLUGINS[@]})_${dispatchPlugin}'"

  if [ -f "$pluginPath" ]; then
    _loadSubPlugin "$dispatchPlugin"
    # Remember the loaded PLUGIN for later dispatch calls
    SUB_PLUGINS+=( $dispatchPlugin )
  else
    debug "Plugin '${dispatchPlugin}' not found on filesystem ($pluginPath), use '${PLUGIN}' as fallback plugin"
    _showHelp
  fi

  debug "Resolve supported commands of sub-plugin '$(joinArray '_' ${SUB_PLUGINS[@]})'"
  PLUGIN_COMMANDS=( $(grep -o "function *$(joinArray '_' ${SUB_PLUGINS[@]})_.*[^{ ]" $pluginPath | awk -F "{" '{print $1}' | awk -F_ '{print $NF}') )
  debug "Found commands in sub-plugin: ${PLUGIN_COMMANDS[*]}"
}

#
# Call a command of the current plugin.
# @param The command.
#
function _callPluginCommand {
  local command=$1

  local validCmd=0
  for pluginCommand in ${PLUGIN_COMMANDS[@]}; do
    if [ "$pluginCommand" = "$command" ]; then
      if [ $SHOW_HELP -eq 1 ]; then
        validCmd=0 #mark command as invalid to trigger help view
        break
      else
        validCmd=1
      fi
      debug "Execute command method '$(joinArray '_' ${SUB_PLUGINS[@]})_$command'"
      if $(joinArray '_' ${SUB_PLUGINS[@]})_$command; then
        # check whether the command fired an error
        if [ ${#ERROR[@]} -gt 0 ]; then
          _showHelp
        fi
      else
        fail "Corrupted plugin file or invalid command call! Failing when executing function '${PLUGIN}_${command}'"
      fi
      break
    fi
  done

  if [ $validCmd -eq 0 ]; then
    debug "Could not find command '$command' in plugin '$PLUGIN' (available commands are: ${PLUGIN_COMMANDS[*]})"
    _showHelp
  fi
}

#
# Load an plugin file and populate the public options of the plugin.
# @param The plugin name (sub-plugins are supported by defining them with their full name e.g. <parentPlugin>_<subPlugin>).
#
function loadPlugin {
  local plugin=$1

  # generate the plugin path
  IFS=$'_'
  local pluginPathTokens=( ${plugin} )
  IFS=$DEFAULT_IFS
  local pluginPath="${PLUGIN_DIR}/$(joinArray '/' ${pluginPathTokens[@]}).sh"

  debug "Loading plugin '${pluginPath}'"
  fileExists $pluginPath
  source $pluginPath
  LOADED_PLUGINS+=( $plugin )

  debug "Resolve supported options of plugin '${plugin}'"
  local pluginOptionsVarPrefix="$(echo $plugin | tr a-z A-Z)"  #parse the variable-prefix
  _parsePluginOptions $pluginOptionsVarPrefix

  debug "Call main function of plugin: _${plugin}_main"
  if ! _${plugin}_main; then
    fail "Corrupted plugin file or defective main method! Failing when executing '_${plugin}_main'"
  fi
}


#
# Load a sub-plugin file and populate the public options of the sub-plugin.
# @param The sub-plugin name.
#
function _loadSubPlugin {
  local plugin=$1

  debug "Loading sub-plugin '${PLUGIN_DIR}/$(joinArray '/' ${SUB_PLUGINS[@]})/${plugin}.sh'"
  source "${PLUGIN_DIR}/$(joinArray '/' ${SUB_PLUGINS[@]})/${plugin}.sh"

  debug "Resolve supported options of sub-plugin '${plugin}'"
  local pluginOptionsVarPrefix="$(echo $(joinArray '_' ${SUB_PLUGINS[@]})_$plugin | tr a-z A-Z)" #parse the variable prefix
  _parsePluginOptions $pluginOptionsVarPrefix

  local fctName="_$(joinArray '_', ${SUB_PLUGINS[@]})_${plugin}_main"
  debug "Call main function of sub-plugin: ${fctName}"
  if ! $fctName; then
    fail "Corrupted sub-plugin file or defective main method! Failing when executing '${fctName}'"
  fi
}

#
# Parse the plugin options and populate them as variables.
# @param The plugin option variable name (follows the pattern <PLUGIN>_OPTIONS).
#
function _parsePluginOptions {
  local pluginOptionsVarPrefix=$1
  local pluginOptionsVarName="${pluginOptionsVarPrefix}_OPTIONS"

  #read the PLUGIN option
  IFS=$'\n'
  local pluginOptions=( ${!pluginOptionsVarName} )
  IFS=$DEFAULT_IFS

  #merge old and new PLUGIN options
  PLUGIN_OPTIONS=("${PLUGIN_OPTIONS[@]}" "${pluginOptions[@]}")
  debug "Found options (taken from variable '${pluginOptionsVarName}'): ${pluginOptions[*]}"

  _populateOptions "$pluginOptionsVarPrefix"
}

#
# Populate the public options of the plugin.
# If the user has provided the option over the CLI it will set the value given by the user, otherwise the configured
# default value will bet set.
#
function _populateOptions {
  local pluginOptionsVarPrefix=$1

  for pluginOption in "${PLUGIN_OPTIONS[@]}"; do
    debug "Parse pluginOption string '${pluginOption}'"

    # split plugin-option string into its tokens ([0]=full key name | [1]=acronym key name | [2]=default value | [4]=description)
    IFS='|'
    local pluginOptionTokens=( $pluginOption )
    IFS=$DEFAULT_IFS

    debug "Extracted these tokens from plugin option '${pluginOption}':"
    for pluginOptionToken in "${pluginOptionTokens[@]}"; do
      debug "   '${pluginOptionToken}'"
    done

    # ensure option name following naming convention
    if [[ "${pluginOptionTokens[0]}" != ${pluginOptionsVarPrefix}_* ]]; then
      fail "Plugin option '${pluginOptionTokens[0]} is invalid: option name has to start with '${pluginOptionsVarPrefix}_'"
    fi

    _populateOption "${pluginOptionTokens[0]}" "${pluginOptionTokens[1]}"
    _populateDefaultOption "${pluginOptionTokens[0]}" "${pluginOptionTokens[2]}"
  done
}

#
# Populate one plugin option.
# @param Name of the option how it will be vislbe for the plugin (e.g. 'OPTION_NAME')
# @param Full name of the option on CLI (e.g. '-OPTION_NAME')
# @param Short name (acronym) of the option on CLI (e.g. '-on')
#
function _populateOption {
  local cliOptionName=$1
  local cliOptionAcronym=$2

  # Populate provided user options 
  for cliOption in "${CLI_OPTIONS[@]}"; do
    # Split the CLI option key-value pair into separate tokens
    IFS='§'
    local cliOptionTokens=( $cliOption )
    IFS=$DEFAULT_IFS

    debug "Extracted these tokens from CLI option '${cliOption}':"
    for cliOptionToken in "${cliOptionTokens[@]}"; do
      debug "   '${cliOptionToken}'"
    done


    # Check if the user option is supported by the plugin (compare it with full key name and acronym key name)
    if [[ "${cliOptionTokens[0]}" == "${cliOptionName}" || "${cliOptionTokens[0]}" == "${cliOptionAcronym}" ]]; then
      export "${cliOptionName}"="${cliOptionTokens[1]}"
      debug "Populate provided CLI option '${cliOption}': ${cliOptionName}=${cliOptionTokens[1]}"
    fi
  done
}

#
# Populate one plugin option using its default value. Default value will only be set if the options wasn't set yet.
# @param Name of the option how it will be vislbe for the plugin (without leading '-', e.g. 'OPTION_NAME')
# @param The default value.
#
function _populateDefaultOption {
  local pluginOptionName=$1
  local defaultValue=$2

  if [ -z "${!pluginOptionName}" ]; then
    debug "No value for option '$pluginOptionName' set yet. Populate default value: ${pluginOptionName}=${defaultValue}"
    export "${pluginOptionName}"="${defaultValue}"
  else
    debug "Found option '$pluginOptionName=${!pluginOptionName}'. Default value will not be used."
  fi
}

#
# Show the help message for the current plugin.
#
function _showHelp {
  _showErrors
  echo 'Usage:'
  if [ $PLUGIN = "kitbag" ]; then
    echo 'kitbag <plugin> [plugin]* <command> [-optionKey optionValue]*'
    echo ''
    echo 'Available plugins are:'
    for plugin in ${PLUGINS[@]}; do
      echo "  * ${plugin}"
    done
  else
    local plugin=$(joinArray ' ' ${SUB_PLUGINS[@]})
    local pluginpath="$(joinArray '/' ${SUB_PLUGINS[@]}).sh"
    local plugincmdiprefix="$(joinArray '_' ${SUB_PLUGINS[@]})"

    echo "kitbag ${plugin} <command> [-optionKey optionValue]*"
    echo ''

    echo "Supported commands for '${plugin}' are:"
    for pluginCommand in ${PLUGIN_COMMANDS[@]}; do
      local cmdHelp=$(grep "function *${plugincmdiprefix}_${pluginCommand}" ${PLUGIN_DIR}/${pluginpath}| awk -F '#' '{print $2}')
      printf "  * %-15s %-25s\n" "${pluginCommand}" "${cmdHelp}"
    done

    local pluginDir=$PLUGIN_DIR/$(joinArray '/' ${SUB_PLUGINS[@]})
    if [ -d $pluginDir ]; then
      debug  "Checking for sub-plugin files in '${pluginDir}'"
      local plugins=( $(find $pluginDir -maxdepth 1 -name '*.sh' -execdir basename -s '.sh' {} +) )
      for plugin in ${plugins[@]}; do
        printf "  * %-15s %-25s\n" "${plugin}" "(sub-plugin)"
      done
    fi

    if [ ${#PLUGIN_OPTIONS[@]} -gt 0  ]; then
      echo ''
      echo "Available options for '${PLUGIN}' are [Name|Alias|DefaultValue|Description]:"
      for pluginOption in "${PLUGIN_OPTIONS[@]}"; do
        echo "  * ${pluginOption}"
      done
      echo "  * -help"
    fi
    echo ''

  fi
  exit 1
}

#
# Show error messages.
#
function _showErrors {
  if [ ${#ERROR[@]} -eq 0 ]; then
    # No errors to show
    return
  fi
  echo -e '\n\033[0;31mERROR:'
  for error in "${ERROR[@]}"; do
    >&2 echo "    * ${error}"
  done
  echo -e '\033[0m\n'
}

#
# Trigger of the plugin cleanup hooks.
#
function _cleanup {
  # Cleanup all loaded plugins (does not include sub-plugins)
  _cleanup_loadedPlugins
  # Call cleanup of sub-plugins
  debug "Call cleanup functions of plugin-call stack '${SUB_PLUGINS[*]}'"
  while [ ${#SUB_PLUGINS[@]} -gt 0 ]; do
    debug "Call cleanup function '_$(joinArray '_' ${SUB_PLUGINS[@]})_cleanup'"
    if ! _$(joinArray '_' ${SUB_PLUGINS[@]})_cleanup 2>/dev/null; then
        fail "Corrupted or invalid sub-plugin! Could not find cleanup method '_${PLUGIN}_${subPlugin}_cleanup'"
    fi
    unset 'SUB_PLUGINS[${#SUB_PLUGINS[@]}-1]'
  done
}

function _cleanup_loadedPlugins {
  # remove duplicates
  LOADED_PLUGINS=($(echo "${LOADED_PLUGINS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
  # remove plugins which are tracked as sub-plugins from $LOADED_PLUGINS
  for subPlugin in ${SUB_PLUGINS[@]}; do
    LOADED_PLUGINS=( "${LOADED_PLUGINS[@]/$subPlugin}" )
  done
  # remove null elements (can occure caused by previous filtering)
  for i in "${!LOADED_PLUGINS[@]}"; do
    [ -n "${LOADED_PLUGINS[$i]}" ] || unset "LOADED_PLUGINS[$i]"
  done
  debug "Call cleanup of loaded plugins '${LOADED_PLUGINS[*]}'"
  for plugin in "${LOADED_PLUGINS[@]}"; do
    if [ -z "$plugin" ]; then
      continue
    fi
    debug "Call cleanup function '_${plugin}_cleanup'"
    if ! _${plugin}_cleanup; then
      fail "Corrupted or invalid plugin! Could not find cleanup method '_${plugin}_cleanup'"
    fi
  done
}

# Register the cleanup trigger function.
trap _cleanup EXIT
