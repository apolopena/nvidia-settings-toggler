#!/usr/bin/env bash

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

e_prefix="tearing_fix.sh error:"

declare -A DISPLAYS

# SGenerates a zero-based multidimensional array (matrix) of connected monitor information
# Data will be stored as follows:
#       Each row pertains to a connected monitor
#       Each column in a row pertains to specific information for that connected monitor
#               col 0: Display Name
#               col 1: Display Resolution
#               col 2: Display Width
#               col 2: Display Refresh Rate
#               col 3: Will contain the string 'primary' if the monitor is the primary display, the string will be blank if not

_Set_display_data() {
    local num_columns=5 # Amount of data points (items) per connected display: name, resolution, width, refresh rate and primary display status, 
    local num_rows # Number of connected displays
    local raw_data # xrandr output used to generate the data points for all connected displays
    local raw_refresh_rates # xrandr output used to generate the refreh rates per connected display
    local primary_display # Name of the primary display
    local display_names=() # Names of connected displays
    local resolutions=() # Resolutions of connected displays
    local display_widths=() # Widths of connected displays
    local refresh_rates=() # Refresh rates of connected displays

    # round off the decimal values of the refresh rate, hopefully this wont cause a problem
    raw_refresh_rates="$(xrandr | grep -C1 " connected " | grep -oP '\s*\K[^[:space:]]*[*][^[:space:]]*\s*' | cut -d '*' -f 1 | cut -d '.' -f 1)"

    # Get the raw data for all connected displays
    raw_data="$(xrandr | grep -A 1 --no-group-separator ' connected ')"

    # Get the name of the primary display
    primary_display="$( echo "$raw_data" | grep " primary " | awk '{print $1;}' )"

    # Store the refresh rates of connected monitors in an array
    while IFS= read -r line; do
        refresh_rates+=("$line")
    done <<< "$raw_refresh_rates"


    # Store the display name, resolution and width of each connected display in its own array
    local dname dres 
    while IFS= read -r line; do
        dname="$(echo "$line" | grep ' connected ' | awk '{ print $1 }')"
        [[ -n "$dname" ]] && display_names+=("$dname")
        #[[ $line =~ ^[0-9]+ ]] && dres="$(echo "$line" | awk '{ print $1 }')"
        dres="$(echo "$line" | awk '{ print $1 }')"
        if [[ $dres != "$dname" ]]; then 
            resolutions+=("$dres")
            display_widths+=("$(echo "$dres" | cut -d 'x' -f 1)")
        fi
    done <<< "$raw_data"

    # Generate the main payload: DISPLAYS
    num_rows=${#display_names[@]}
    for ((i=0;i<num_columns;i++)) do
        for ((j=0;j<"$num_rows";j++)) do
            # Uncomment below lines to debug assigment of the multidimensional array DISPLAYS
            #local cache=$RANDOM
            #echo "row ${display_names[$j]}, column $i, data: $cache"
            # Set each data point in the proper location of the payload
            if [[ $i -eq 0 ]]; then
                DISPLAYS[$i,$j]="${display_names[$j]}"
            elif [[ $i -eq 1 ]]; then
                DISPLAYS[$i,$j]="${resolutions[$j]}"
            elif [[ $i -eq 2 ]]; then
                DISPLAYS[$i,$j]="${display_widths[$j]}"
            elif [[ $i -eq 3 ]]; then
                DISPLAYS[$i,$j]="${refresh_rates[$j]}"
            elif [[ $i -eq 4 ]]; then
                [[ "${display_names[$j]}" == "$primary_display" ]] && DISPLAYS[$i,$j]="primary" || DISPLAYS[$i,$j]=''
            fi   
        done
    done    

}

# For debugging the DISPLAYs map, A.K.A the 'multidimensional array' holding our data aka DISPLAYS
_Dump_DISPLAYS() {
    local columns=()
    local num_rows
    local num_columns
    local linebreak_max

    # Since the length of DISPLAYS is nested it will be num_ros * num_columns long
    # Divide by 2 to get the number of line breaks to display this as humn readble without extraneous line breaks
    linebreak_max=$(( ${#DISPLAYS[@]} / 2 )) 

    # The number of rows shold be the number of connected displays
    for i in "${!DISPLAYS[@]}"; do
        ((num_rows++))
        columns+=("$i")
    done

    local count
    num_columns=${#columns[@]}
    for ((j=0;j<num_rows;j++)) do
        for ((i=0;i<num_columns;i++)) do
        count=$((i * j))
            [[ $count -lt $linebreak_max ]] && echo -n "     ${DISPLAYS[$i,$j]}     "
        done
        # Add linebreaks to increase readability
        [[ $count -lt $linebreak_max ]] && echo
   done
   echo

}

_Monitor_names() {
    xrandr | grep " connected " | awk '{ print$1 }'
}

_All_whitespace() {
    local arg="$1"
    arg=${arg%, }
    arg=${arg#, }
    [[ -n "$arg" ]] && return 1
    return 0
}

Test() {
    echo "Test(): Contents of the DISPLAY map is"
    _Dump_DISPLAYS
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

# works but we are refactoring it
Old_fix() {
    local mons
    local num_mons
    local ec="fix command: "
    mons="$(_Monitor_names)"
    num_mons="$(echo "$mons" | wc -l)"

    # Handle errors
    if ! _Meets_reqs; then exit 1; fi

    if _All_whitespace "$mons"; then echo "${e_prefix} no monitors found" && exit 1; fi

    [[ -z $1 ]] && echo "${e_prefix} ${ec} missing required sub-command. valid sub-commands are <on|off>" && exit 1

    if [[ $1 != 'on' && $1 != 'off' ]]; then
        echo "${e_prefix} ${ec} invalid sub-command: ${1}"
        echo "valid commands are <on|off>"
        exit 1
    fi

    # Turn on 
    if [[ $1 == 'on' ]]; then
        #[[ $num_mons -eq 2 ]] && nvidia-settings --assign CurrentMetaMode="${both_monitors_on}" && exit 0
        [[ $num_mons -eq 2 ]] && nvidia-settings --assign CurrentMetaMode="$(xrandr | sed -nr '/(\S+) connected (primary )?[0-9]+x[0-9]+(\+\S+).*/{ s//\1: nvidia-auto-select \3 { ForceFullCompositionPipeline = On }, /; H }; ${ g; s/\n//g; s/, $//; p }')" \
        && xrandr --output DP-4 --mode 2560x1600 --rate 240 && exit 0
        [[ $mons == 'DP-4' ]] && nvidia-settings --assign CurrentMetaMode="${monitor_1600p_on}" && exit 0
        [[ $mons == 'DP-3' ]] && nvidia-settings --assign CurrentMetaMode="${monitor_1440p_on}" && exit 0
    fi

    # Turn off
    if [[ $1 == 'off' ]]; then
        [[ $num_mons -eq 2 ]] && nvidia-settings --assign CurrentMetaMode="$(xrandr | sed -nr '/(\S+) connected (primary )?[0-9]+x[0-9]+(\+\S+).*/{ s//\1: nvidia-auto-select \3 { ForceFullCompositionPipeline = Off }, /; H }; ${ g; s/\n//g; s/, $//; p }')" \
        && xrandr --output DP-4 --mode 2560x1600 --rate 240 && exit 0
        [[ $mons == 'DP-4' ]] && nvidia-settings --assign CurrentMetaMode="${monitor_1600p_off}" && exit 0
        [[ $mons == 'DP-3' ]] && nvidia-settings --assign CurrentMetaMode="${monitor_1440p_off}" && exit 0
    fi
}

Fix() {
    local cmd="Fix"

    if [[ -z $1 ]]; then 
        echo "${e_prefix} Command: ${cmd} :: requires a sub-command"
        echo "Valid sub-commands are: <on|off>"
        exit 1
    fi

    if [[ $1 != 'on' && $1 != 'off' ]]; then
        echo "${e_prefix} Command: ${cmd} :: invalid sub-command: ${1}"
        echo "Valid sub-commands are <on|off>"
        exit 1
    fi 

    # Generate CurrentMetaModeString
    # TODO: make this a function
    if [[ $1 == 'on' ]]; then
        # Sample command that works
        # DP-3:nvidia-auto-select+2560+0{ForceFullCompositionPipeline=On},DP-4:nvidia-auto-select+0+0{ForceFullCompositionPipeline=On}

        # Does the order matter? try it
        # nvidia-settings --assign CurrentMetaMode="DP-4:nvidia-auto-select+0+0{ForceFullCompositionPipeline=On},DP-3:nvidia-auto-select+2560+0{ForceFullCompositionPipeline=On}"

        # I tried it and yay, order does not matter!

        echo
    fi

    if [[ $1 == 'off' ]]; then
        #DP-3:nvidia-auto-select+2560+0{ForceFullCompositionPipeline=Off},DP-4:nvidia-auto-select+0+0{ForceFullCompositionPipeline=On}
        echo
    fi

}

# Generates a syntactically correct nvidia CurrentMetaMode value
# Arguments passed in here should be validate @see function Fix(){...}
_Generate_CurrentMetaMode() {
    local e_prefix
    if [[ -z $1 ]]; then 
        echo "${e_prefix} ${ec} Internal: Missing required parameter for private function: _Generate_CurrentMetaMode()"
        echo "Valid sub-commands are: <on|off>"
        exit 1
    fi

    case "$1" in
        'on')
            echo
            ;;
        'off')
            echo 
            ;;
        *)
            echo
            ;;
    esac
}

_Init() { 
    [[ ${#DISPLAYS[@]} -eq 0 ]] && _Set_display_data
}

# Generate payload map: DISPLAYS[][]
_Init

# Require a command
if [[ $# -eq 0 ]]; then 
    echo "${e_prefix} missing required command"
    echo "valid commands and sub-commands are: Fix <on|off>"
    exit 1
fi

# Call functions gracefully
# Bump the first character of $1 to uppercase to match this scripts function naming convention
if declare -f "${1^}" > /dev/null; then "$@"; else echo "${e_prefix} '$1' is not a valid command" >&2; exit 1; fi
