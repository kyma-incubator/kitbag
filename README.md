# Kitbag Framework

Welcome to the Kitbag framework!

Features of this framework are:

* **written in Bash**<br/>
  Make it compatible to run any kind of logic which can be executed from bash (e.g. running commands in Docker
  containers or directly on your local machine).
* **plugin-based architecture**<br/>
  The Kitbag CLI is based on plugins which offer commands. Plugins can be nested (a plugin can have sub-plugins, which
  can have again sub-plugins and so fourth) and each sub-plugin can offer additional commands.
* **fluent interface**<br/>
  The plugin approach make it possible to implement the call of plugins a fluent-interface approach (
  e.g. `kitbag speak spain sayHello -SPEAK_BOLD_FONT true"`)
* **easy extendable**<br/>
  The framework is easy extendable by adding further plugins. Plugins are integrated following a
  convention-over-configuration approach.

## 1. Architecture

### 1.1 Components

In Kitbag, we can differentiate between five things

1. **The core framework**<br/>
   This contains the `kitbag` script itself inclusive the framework core- and utility-library.
2. **Plugins**<br/>
   Plugins are extensions for the core-framework. A plugin exposes commands which can be called by DevOps or developers
   via the CLI. Each plugin can use its own commands and also import other plugins and use their commands as well. <br/>
3. **Sub-Plugins**<br/>
   Sub-Plugins are very similar to normal plugins. Sub-Plugins belong to a parent plugin and can only be called over the
   CLI if the parent-plugin is also called. A sub-plugin inherits automatically all options from the parent-plugin and
   can reuse them.<br/>
   Sub-plugins are a good choice to:
    * bundle commands related to a specific sub-topic
    * make the usage of the Kitbag call more intuitive by not overloading a plugin with too many commands

4. **Options**<br/>
   Options are configuration parameter for particular plugins. Each plugin can define a set of options the user the
   define over the CLI to adjust the behavior of the exposed commands.

Lets investriage how these componetens are reflected in a Kitbag command. The general syntax of the Kitbag script is:

```
kitbag <plugin> [<sub-plugin> [sub-sub-plugin]...] <command> [-OPTION1 <option1Value> [-<OPTION2> <option2Value>]...]
```

Lets compare this syntax by using an example command:

```
         (1)    (2)     (3)           (4a)         (4b)
kitbag  speak  spain  sayHello  -SPEAK_BOLD_FONT  true

1)      call plugin "speak"
        
2)             call sub-plugin "spain"
              
3)                    call command (=public function) "speak_spain_sayHello" of sub-plugin "spain"
                    
4a+b)                           set option "SPEAK_BOLD_FONT" to "true"
              
```

### 1.2 Folder Structure

The framework follows a flat folder structure:

```
 /
  |
  + kitbag         # Kitbag script (entrypoint for any call)
  |
  +- /lib           # contains the core-library and utils-library of the Kitbag framework
  |  |
  |  + core.sh      # core functions of the framework (e.g. CLI parsing, dispatching etc.)
  |  |  
  |  + utils.sh     # utility functions available in all plugins
  |
  +- /plugin        # all plugins have to be stored in the plugins-directory
     |
     + eat.sh       # plugin with name "eat"
     |
     + speak.sh     # plugin with name "speak"
     |
     +- /speak      # a plugin can have a sub-directory for asset or sub-plugin files
        |
        +- /files   # directory for assets used by plugin "speak"
        |
        + spain.sh  # sub-plugin "spain"
        |
        + /spain    # sub-plugins can also have a sub-directory for assets / sub-plugin files
        | ...
```

## 2. Installation

The installation of Kitbag itself is quite simple:

1. Clone this repository
2. Execute the command `./kitbag self install`

This will install the Kitbag framework into your `$PATH`.

## 3. Extending the Framework

### 3.1 Convention Over Configuration

Kitbag is following a convention-over-configuration approach. Means, you don't have to configure anything in Kitbag to
extend it, but you have to follow some conventions/rules and Kitbag will recognize and integrate available extensions
automatically.

The following example extends Kitbag to enable it to "speak" in different languages. The example shows you a new
plugin (incl. sub-plugin) can be added to Kitbag. Additionally, the plugins will support some configuration options for
the user to make the output a bit more "readable".

**Basic conventions are**:

1. Public functions<br/>
   These functions become callable over the CLI. Naming pattern is:<br/>
   `<pluginName>_[subPluginName_]<functionName>`.<br/>
   Example:<br/>
   `speak_german`
2. Private functions<br/>
   Private function are intended to be used only by the plugin itself and won't become callable over the CLI. Private
   values start always with an `_` (underscore):<br/>
   `_<pluginName>_[subPluginName_]<functionName>`.<br/>
   Example:<br/>
   `_speak_formatBold`
3. Options<br/>
   Options are defined in a string variable which follows the pattern: `<PLUGINNAME>_OPTIONS=""` (uppercase letters are
   mandatory).<br/>
   An option definition consists of four parts which are separated by the `|` character (pipe):<br/>
   `-<PLUGINNAME>_<OPTIONNAME>|-<acronym>|defaultValue|Description of this option.`<br/>
   Each option is defined in a separate line.

### 3.2 Add a new plugin

A plugin offers new commands for the Kitbag user. Plugins are normally addressing one particular topic and offer the
necessary functionality for DevOps to deal with this topic in an convenient way (e.g. we have a plugin to manage the
local KIND cluster, a plugin to install/reset a Jenkins in a K8s etc.).

#### 3.2.1 The automated way

Kitbag includes a plugin to generate a new plugin from scratch. Just the plugin-name and the name of the first command
have to be provided as option:

```
kitbag genplugin create -GPLUGINNAME <nameOfTheNewPlugin> -GCMDNAME <nameOfTheExposedCommand>
```

This command will generate a plugin file with the given plugin-name in the directory `kitbag/plugin` which includes
already the mandatory main- and cleanup hooks and a public function to expose the given command-name.

#### 3.2.2 The manual way

1. Create the plugin-file `speak.sh` in the directory `kitbag/plugin`.
2. Per convention, each plugin has to implement two hooks:
    1. `_<pluginName>_main`<br/>
       Will be called when the plugin was loaded. This hook can be used for initializing things or verifying
       pre-conditions:
    1. `_<pluginName>_cleanup`<br/>
       Is called after the execution is finished. Here a plugin can execute any kind of cleanup or housekeeping actions.
3. Implement the commands the user can call as public functions: `<pluginName>_<commandName> {}`.<br/>
   For functions which should not be callable over the CLI, add an `_` (underscore) as prefix to mark them
   private: `_<pluginName>_<fctName> {}`
4. If the user of the plugin should be able to provide some configuration parameters to the plugin, you can specify a
   list options which can be set as parameter over the CLI. This is done by defining a variable which includes the
   supported options as string:<br/>
   `<PLUGINNAME>[_<SUBPLUGINNAME>]_OPTIONS="-<PLUGINNAME>[_<SUBPLUGINNAME>]_OPTIONNAME|-on|defaultValue|Some description text"`<br/>
   Multiple options are separated by a line break:

```
MYPLUGIN_OPTIONS="
MYPLUGIN_OPTION1|-op1|option1DefaultValue|Description of option 1
MYPLUGIN_OPTION2|-op2|option2DefaultValue|Description of option 2
MYPLUGIN_OPTION3|-op3|option3DefaultValue|Description of option 3
"
```

**Example:**

Create the plugin file inclusive all hooks:

```
$> echo '
# Main hook called after loading the plugin
function _speak_main {
  # using the info-function (part of the utils-library) to print info-msgs to the console
  info "Calling _speak_main hook"
}

# Clenaup hook called after the execution has finished
function _speak_cleanup {
  info "Calling _speak_cleanup hook"
}

# Exposed command of the plugin which can be called over the CLI
function speak_helloWorld {   # Say "Hello World"
  info "HELLO WORLD"
}

' > kitbag/plugin/speak.sh
```

Now your new plugin will be listed as plugin when calling the Kitbag framework (see last line of the output)

```
$> kitbag

kitbag
INFO: Load configuration file '/Users/t/.kitbag/config'
Usage:
kitbag <plugin> [plugin]* <command> [-optionKey optionValue]*

Available PLUGINs are:
vault cert self nfs aks jenkins camunda kind genplugin speak azurek8s git localdev cm
```

When calling the `speak` plugin, Kitbag will show the available commands (= public functions) of the plugin:

```
$> kitbag speak
INFO: Load configuration file '/Users/t/.kitbag/config'
INFO: Calling _speak_main hook
Usage:
kitbag speak help
kitbag speak <command> [-optionKey optionValue]*

Supported commands for 'speak' are:
  * helloWorld   		-) Say "Hello World"

INFO: Calling _speak_cleanup hook
```

Now the command "helloWorld" can be directly executed:

```
kitbag speak helloWorld
INFO: Load configuration file '/Users/t/.kitbag/config'
INFO: Calling _speak_main hook
INFO: HELLO WORLD
INFO: Calling _speak_cleanup hook
```

Finally, let's add another command which allows the user to configure the message:

```
echo '
SPEAK_OPTIONS="
-MESSAGE|-msg|HelloWorld|The message to speak
"

function speak_saySomething {
  info "$MESSAGE"
}

'  >> kitbag/plugin/speak.sh
```

And here the result:

```
$ kitbag speak saySomething -MESSAGE "GoodDay"

INFO: Load configuration file '/Users/t/.kitbag/config'
INFO: Calling _speak_main hook
INFO: GoodDay
INFO: Calling _speak_cleanup hook
```

#### 3.2.3 Add a sub-plugin

In the following example we add a sub-plugin `spain` to the previously created `speak` plugin.

1. The sub-plugin has to be located in a directory which has the same name as the parent
   plugin: `mkdir -p kitbag/plugin/speak`
2. The naming pattern of sub-plugins have to include the name of the parent-plugin:
    * Public functions: `<parentPlugin>_<subPlugin>_<commandName>`
    * Private functions: `_<parentPlugin>_<subPlugin>_<commandName>`
    * Options: `<PARENT_PLUGINNAME>_<SUBPLUGINNAME>_OPTIONS=""`

**Example:**

Create the plugin file inclusive all hooks:

```
$> mkdir -p kitbag/plugin/speak

$> echo '
SPEAK_SPAIN_OPTIONS="
-SPEAK_SPAIN_MESSAGE|-ssm|Hola_World|Message to say in Spanish
"

# Main hook called after loading the plugin
function _speak_spain_main {
  # using the info-function (part of the utils-library) to print info-msgs to the console
  info "Calling _speak_spain_main hook"
}

# Cleanup hook called after the execution has finished
function _speak_spain_cleanup {
  info "Calling _speak_spain_cleanup hook"
}

# Exposed command of the plugin which can be called over the CLI
function speak_spain_holaWorld {   # Say hola
  info "$SPEAK_SPAIN_MESSAGE"
}

' > kitbag/plugin/speak/spain.sh
```

We can verify that the sub-plugin was detected by calling the `speak` plugin and verify the list of available command (
see hint `(subPLUGIN)` in the commands list):

```
kitbag speak
INFO: Load configuration file '/Users/t/.kitbag/config'
INFO: Calling _speak_main hook
Usage:
kitbag speak help
kitbag speak <command> [-optionKey optionValue]*

Supported commands for 'speak' are:
  * sayHello   	    	I say hello to you
  * saySomething   		I say what you want
  * spain 		       (subPLUGIN)

Available options for 'speak' are [Name|Alias|DefaultValue|Description]:
  * -SPEAK_MESSAGE|-sm|Hello_WORLD|Tell me what I should say
  * -SPEAK_OPT2|-op2|blub|I'm also an option
```

Lets call the sub-plugin:

```
kitbag speak spain
INFO: Load configuration file '/Users/t/.kitbag/config'
INFO: Calling _speak_main hook
INFO: Calling _speak_spain_main hook
Usage:
kitbag speak spain help
kitbag speak spain <command> [-optionKey optionValue]*

Supported commands for 'speak spain' are:
  * holaWorld   		Say hola

Available options for 'speak' are [Name|Alias|DefaultValue|Description]:
  * -SPEAK_MESSAGE|-sm|Hello_WORLD|Tell me what I should say
  * -SPEAK_OPT2|-op2|blub|I'm also an option
  * -SPEAK_SPAIN_MESSAGE|-spo1|Hola_World|Message to say in Spanish

INFO: Calling _speak_spain_cleanup hook
INFO: Calling _speak_cleanup hook
```

As we see in the console output, the sub-plugin `spain` had inherited all options from the parent-plugin `speak`.

Finally, let's call the `holaWorld` command:

```
kitbag speak spain holaWorld
INFO: Load configuration file '/Users/t/.kitbag/config'
INFO: Calling _speak_main hook
INFO: Calling _speak_spain_main hook
INFO: Hola_World
INFO: Calling _speak_spain_cleanup hook
INFO: Calling _speak_cleanup hook
```
