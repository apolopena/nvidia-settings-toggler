#!/usr/bin/env bash

# Allow optional parameters for functions without having to pass "$@"
# shellcheck disable=SC2120

# SUPER QUICK AND DIRTY FOR NOW, but here is the general gist of things...
#
# The idea here is to use this script to toggle on and off the proper settings for the proper monitors
# at the proper time in order to avoid screen teearing in Desktop applications AND to avoid breaking
# G-Sync/Adapative sync when Steam games are rnning using gamemoderun. 
#
# We need ForceFullCompositionPipeline = On to avoid screen tearing in Desktop applications
# We need ForceFullCompositionPipeline = Off when running Steam games with G-Sync/Adaptive Sync
# otherwise we get 1fps hangups that require opening and closing a TTY just to keep the system
# from locking up and needing a cold boot
#
# It is a very annoying Catch-22 nvidia/linux bug indeed but this script should be able to address it
# For now This script should work for any number of connected screens
#
# We will use the script at startup time when the .desktop files in ~/.config/autostart are executed
# to set ForceFullCompositionPipeline = On
# We will then use the script another time in ~/.config/gamemode.ini so that when gamemode starts
# (a steam game launches) we can set ForceFullCompositionPipeline = Off
# Finally we will set ForceFullCompositionPipeline = On when gamemode ends (a steam game exits)
#
# I have no idea if a steam game crashing will trigger the gamemode end command, it will have to
# be tested

# TODO add in AllowGSYNCCompatible=On for DP-4 (controlled by a an option?) and only set AllowGSYNCCompatible=On for that display if it set to Off or not set

# TODO only toggle composition pipeline settings on or off if they are not already in that state, allthough it doesnt seem to matter but it must right? it must.
# If we want to check the state of the CurrentMeta mode nvidia uses Aliases to the display names, I cant find a mapping of this anywhere
# Hence to check the state of the composition pipeline for a particular display we will need to generate our own alias maps based off of a combination
# of the resolution and offset. To clarify we will need to get the CurrentMetaMode with the command: nvidia-settings --query CurrentMetaMode --terse
# The map can be generated using this command: nvidia-settings --query dpys | grep 'connected, enabled'

# Globals
declare -A DISPLAYS
DISPLAY_TOTAL=
e_prefix="tearing_fix.sh error:"


# Generates a multidimensional array (matrix) of connected monitor information
# Data will be stored as follows:
#       Each row pertains to a connected monitor
#       Each column in a row pertains to specific information for that connected monitor
#               col 0: Display Name
#               col 1: Display Resolution
#               col 2: Display Width
#               col 2: Display Refresh Rate
#               col 3: Will contain the string 'primary' if the monitor is the primary display, the string will be blank if not
# Note: Do not call this function without ensuring that DISPLAYS is empty
_Set_display_data() {
    local num_columns=7 # Amount of data points for the DISPLAY map
    local num_rows # Number of connected displays
    local raw_data # xrandr output used to generate the data points for all connected displays

    # Data points, the number of these must match the value of $num_columns
    local primary_display   # Name of the primary display
    local display_names=()  # Names of connected displays
    local resolutions=()    # Resolutions of connected displays
    local display_widths=() # Widths of connected displays
    local display_offsets=()        # Diplay offsets show the positioning of a display within the virtual screen space          
    local refresh_rates=()  # Refresh rates of connected displays
    local display_states=() # Enabled or Disabled state of connected displays

    # Raw data for all connected displays
    raw_data="$(xrandr | grep -A 1 --no-group-separator ' connected ')"
    #echo "raw=$raw_data"

    # Total number of connected displays so we can retrieve the data later
    DISPLAY_TOTAL="$(( $(echo "$raw_data" | wc -l) / 2 ))"

    # Name of the primary display, there will only be one
    primary_display="$( echo "$raw_data" | grep " primary " | awk '{print $1;}' )"

    # Build the data point arrays that will be used to populate the DISPLAY map
    # NOTE: Every data point arary MUST contain the same number of elements or the DISPLAY map data will be skewed
    local resolution state rate name width cnt=0
    while IFS= read -r line; do
        if [[ $((cnt++ % 2)) -eq 0 ]]; then
            name="$(echo "$line" | grep ' connected ' | awk '{ print $1 }')"
            display_names+=("$name")
            display_offsets+=("$(echo "$line" | grep -oP "(\+|-)[[:digit:]]+(\+|-)[[:digit:]]+")")

            state="$(echo "$line" | grep -oP "[[:digit:]]+(mm x )[[:digit:]]+(mm)")"
            if [[ -n $state ]]; then
                display_states+=("enabled") 
            else 
                display_states+=("disabled") 
            fi

        else
            resolution="$(echo "$line" | awk '{ print $1 }')"
            width="$(echo "$resolution"| cut -d 'x' -f 1)"
            rate="$(echo "$line" | grep -oP '\s*\K[^[:space:]]*[*][^[:space:]]*\s*' | cut -d '*' -f 1)"

            if [[ -n "$rate" ]]; then
                [[ "$(echo "$rate" | cut -d '.' -f 2)" == '00' ]] && rate="$(echo "$rate" | cut -d '.' -f 1)"
            else
                rate="N/A"
            fi

            resolutions+=("$resolution")
            display_widths+=("$width")
            refresh_rates+=("$rate")

        fi
    done <<< "$raw_data"

    # Populate DISPLAY map
    num_rows=${#display_names[@]}
    for ((i=0;i<num_rows;i++)) do

        for ((j=0;j<"$num_columns";j++)) do

            if [[ $j -eq 0 ]]; then
                DISPLAYS[$i,$j]="${display_names[$i]}"
                [[ $1 == 'debug' ]] && echo "set name for ${display_names[$i]} to: ${DISPLAYS[$i,$j]}"
            elif [[ $j -eq 1 ]]; then
                DISPLAYS[$i,$j]="${resolutions[$i]}"
                [[ $1 == 'debug' ]] && echo "set resolution for ${display_names[$i]} to: ${DISPLAYS[$i,$j]}"
            elif [[ $j -eq 2 ]]; then
                DISPLAYS[$i,$j]="${display_widths[$i]}"
                [[ $1 == 'debug' ]] && echo "set width for ${display_names[$i]} to: ${DISPLAYS[$i,$j]}"
            elif [[ $j -eq 3 ]]; then
                DISPLAYS[$i,$j]="${display_offsets[$i]}"
                [[ $1 == 'debug' ]] && echo "set offset for ${display_names[$i]} to: ${DISPLAYS[$i,$j]}"
            elif [[ $j -eq 4 ]]; then
                DISPLAYS[$i,$j]="${refresh_rates[$i]}"
                [[ $1 == 'debug' ]] && echo "set refresh rate for ${display_names[$i]} to: ${DISPLAYS[$i,$j]}"
            elif [[ $j -eq 5 ]]; then
                DISPLAYS[$i,$j]="${display_states[$i]}"
                [[ $1 == 'debug' ]] && echo "set display state for ${display_names[$i]} to: ${DISPLAYS[$i,$j]}"
            elif [[ $j -eq 6 ]]; then
                if [[ "${display_names[$i]}" == "$primary_display" ]]; then 
                    DISPLAYS[$i,$j]="primary"
                else
                    DISPLAYS[$i,$j]='not primary'
                fi
                [[ $1 == 'debug' ]] && echo "set primary diplay status for ${display_names[$i]} as ${DISPLAYS[$i,$j]}"
            fi

        done
        [[ $1 == 'debug' ]] && echo
    done    

}

# Show display data in human readable format, still parseable
_Dump_DISPLAYS() {
    local num_rows=$DISPLAY_TOTAL
    local num_columns=$(( ${#DISPLAYS[@]} / DISPLAY_TOTAL ))
    local count

    for (( i=0; i < num_rows; i++ )) do
        for (( j=0; j < num_columns; j++ )) do
            count=$((i * j))
            [[ -n ${DISPLAYS[$i,$j]} ]] && echo -n "     ${DISPLAYS[$i,$j]}     "
        done
        # For human readability
        [[ $count -lt $num_columns ]] && echo
   done
   echo
}

# The nvidia driver will map aliases to the true display names issued by xorg
# This returns that mapping in a terse manner
_Get_Name_From_Alias() {
    local alias name raw_data match
    raw_data="$(nvidia-settings --query dpys | grep 'connected, enabled')"

    while IFS= read -r line; do
        # Strip out the brackets and bump to uppercase
        alias="$(echo "$line" | awk '{ print $2 }' | grep -oP '(?<=\[)[^\[\]]+(?=\])' | tr '[:lower:]' '[:upper:]')"
        # Swap the colon for a dash
        alias=${alias//:/-}

        # Strip out the parenthesis
        name="$(echo "$line" | awk '{ print $3 }' | grep -oP '(?<=\()[^\(\)]+(?=\))')"

        [[ $1 == "$alias" ]] && match="$name"
    done <<< "$raw_data"

    echo "$match"
}


_All_whitespace() {
    local arg="$1"
    arg=${arg%, }
    arg=${arg#, }
    [[ -n "$arg" ]] && return 1
    return 0
}

Test() {
    #echo "Test(): Contents of the DISPLAY map is"
    #_Dump_DISPLAYS
    echo "X11 Display Name for Nvidia Alias '$1' is '$(_Get_Name_From_Alias "$1")'"
 }

_Meets_reqs() {
    if ! which nvidia-settings > /dev/null; then
        echo "${e_prefix} nvidia-settings binary not found"
        return 1
    fi
    if ! which xrandr > /dev/null; then
        echo "${e_prefix} xrandr binary not found"
        return 1
    fi
}

_Valid_OnOff_Subcommand() {
    local e_prefix
    e_prefix="$(basename "${BASH_SOURCE[1]}") ERROR: Command: ${FUNCNAME[1]}:"
    cmds="Valid sub-commands are: <on|off>"

    [[ -z $1 ]] && echo -e "${e_prefix} requires a sub-command\n${cmds}" && return 1

    case $1 in 
        on )  return 0 ;;
        off)  return 0 ;;
        *  )  echo -e "${e_prefix} invalid sub-command: ${1}\n${cmds}" && return 1     
    esac
}

_Valid_Get_Subcommand() {
    local e_prefix
    e_prefix="$(basename "${BASH_SOURCE[1]}") ERROR: Command: ${FUNCNAME[1]}:"
    cmds="Valid sub-commands are: <metamode|primary>"

    [[ -z $1 ]] && echo -e "${e_prefix} requires a sub-command\n${cmds}" && return 1
    
    case $1 in 
        metamode )  return 0 ;;
        primary)  return 0 ;;
        *  )  echo -e "${e_prefix} invalid sub-command: ${1}\n${cmds}" && return 1     
    esac
}



_Initialize() { 
    [[ ${#DISPLAYS[@]} -eq 0 ]] && _Set_display_data
}

_Reinitialize() {
    declare -gA DISPLAYS && _Set_display_data
}


# Generates a syntactically correct nvidia CurrentMetaMode value
# Arguments passed in here should be validate @see function Fix(){...}
# Must be called with two args in the proper order: <metamode|primary> <on|off>
get() {
    local name=0     # Index of the display name value set in the DISPLAYS map @see _Set_display_data()
    local offset=3   # Index of the display offset value set in the DISPLAYS map @see _Set_display_data()
    local resolution=1   # Index of the display offset value set in the DISPLAYS map @see _Set_display_data()
    local num_rows="$DISPLAY_TOTAL"
    local num_columns=$(( ${#DISPLAYS[@]} / DISPLAY_TOTAL ))

    if ! _Valid_Get_Subcommand "$1"; then exit 1; fi
    if ! _Valid_OnOff_Subcommand "$2"; then exit 1; fi

    # Example of a successful command (payload)
    # DP-3:nvidia-auto-select+2560+0{ForceFullCompositionPipeline=On},DP-4:nvidia-auto-select+0+0{ForceFullCompositionPipeline=On}
    
    # Generate the payload (CurrentMetaMode) from the DISPLAYS map
    local chunk payload cnt=0
    for ((i=0;i<num_rows;i++)) do
        chunk="${DISPLAYS["$i,$name"]}:${DISPLAYS["$i,$resolution"]}${DISPLAYS["$i,$offset"]}{ForceFullCompositionPipeline=${2^}}"
        for ((j=0;j<num_columns;j++)) do
            # For every row of data
            if [[ $((++cnt % num_columns )) -eq 0 ]]; then
                [[ $cnt -ne "${#DISPLAYS[@]}" ]] && chunk="${chunk},"
                payload+="${chunk}"
            fi
        done
    done
    echo "${payload}"
}

fix () {
    declare -A previous_rates 
    declare -A current_rates
    declare -A active_modes
    local metamode name rates_differ='no'

    if ! _Valid_OnOff_Subcommand "$1"; then exit 1; fi

    metamode=$(get metamode "$1")

    if echo "$metamode" | grep -q 'ERROR'; then
        echo "${metamode/ERROR/INTERNAL ERROR}"
        exit 1
    fi

    # Save a map of the current refresh rates of enabled displays as the 'previous' ones using the name of the display as the key
    while IFS= read -r line; do
        if [[ $(echo "$line" | awk '{print$6}' ) == 'enabled' ]]; then
            key="$(echo "$line" | awk '{ print$1 }')"
            previous_rates["$key"]="$(echo "$line" | awk '{ print$5 }')"
        fi
    done <<< "$(_Dump_DISPLAYS)"

    # Save a map of the active mode (resolution) of enabled displays using the name of the display as the key
    while IFS= read -r line; do
        if [[ $(echo "$line" | awk '{print$6}' ) == 'enabled' ]]; then
            key="$(echo "$line" | awk '{ print$1 }')"
            # shellcheck disable=SC2034
            active_modes["$key"]="$(echo "$line" | awk '{ print$2 }')"
        fi
    done <<< "$(_Dump_DISPLAYS)"

    # Make the change/fix, comment out for a dry run test
    if ! nvidia-settings --assign CurrentMetaMode="${metamode}"; then exit 1; fi
    
    # Update the DISPLAYS map
    _Reinitialize

    # Save a map of the current refresh rates of enabled displays as the 'current' ones using the name of the display as the key
    local key=''
    while IFS= read -r line; do
        if [[ $(echo "$line" | awk '{print$6}' ) == 'enabled' ]]; then
            key="$(echo "$line" | awk '{ print$1 }')"
            current_rates["$key"]="$(echo "$line" | awk '{ print$5 }' )" 
            [[ ${current_rates["$key"]} != "${previous_rates["$key"]}" ]] && rates_differ='yes'
        fi
    done <<< "$(_Dump_DISPLAYS)"

    # Uncomment for a dry run to test restoring refresh rates without actaully making any changes
    # Note: Data should match your currently enabled displays
    #declare -A test_rates
    #test_rates["HDMI-0"]="59.95"
    #test_rates["DP-3"]="164.96"
    # shellcheck disable=SC2034 # Dont uncomment this
    #test_rates["DP-4"]="60"
    #rates_differ='yes'
    #[[ $rates_differ == 'yes' ]] && _Restore_Refresh_Rates previous_rates test_rates active_modes

    # comment this out when doing a dry run test
    [[ $rates_differ == 'yes' ]] && _Restore_Refresh_Rates previous_rates current_rates active_modes
}

_Restore_Refresh_Rates() {
    local -n previous=$1
    local -n current=$2
    # shellcheck disable=SC2178
    local -n resolutions=$3 # Why does this trigger SC2178 but new and previous do not???

    for key in "${!current[@]}"; do
        if [[ ${previous[$key]} != "${current[$key]}" ]]; then
            #echo "_Restore_Refresh_Rates() found a difference: previous=${previous[$key]}  ::  current=${current[$key]}"
            #local cmd="xrandr --output $key --mode ${resolutions[$key]} --rate ${previous[$key]}"
            #echo "restoring previous refresh rate using the command: $cmd"
            xrandr --output "${key}" --mode "${resolutions[$key]}" --rate "${previous[$key]}" # comment this out for a dry run test
        fi
    done
}

# Generate payload map: DISPLAYS[][]
_Initialize

# Require a command
if [[ $# -eq 0 ]]; then 
    echo "${e_prefix} missing required command"
    echo "valid commands and sub-commands are: Fix <on|off>"
    exit 1
fi

# Call functions gracefully
# Bump the first character of $1 to uppercase to match this scripts function naming convention
if declare -f "${1}" &> /dev/null; then "$@"; else echo "${e_prefix} '$1' is not a valid command" >&2; exit 1; fi
