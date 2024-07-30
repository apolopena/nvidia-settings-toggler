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

# Globals
declare -A DISPLAYS
DISPLAY_TOTAL=
e_prefix="tearing_fix.sh error:"


# BIG BUG HERE TO FIX: if a monitor is disabled it will skew all the data because it does not have a refresh rate since there will be no asterisk next to it and that is the hook
# Generates a zero-based multidimensional array (matrix) of connected monitor information
# Data will be stored as follows:
#       Each row pertains to a connected monitor
#       Each column in a row pertains to specific information for that connected monitor
#               col 0: Display Name
#               col 1: Display Resolution
#               col 2: Display Width
#               col 2: Display Refresh Rate
#               col 3: Will contain the string 'primary' if the monitor is the primary display, the string will be blank if not
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

    # Total number of connected displays so we can retrieve the data later
    DISPLAY_TOTAL="$(( $(echo "$raw_data" | wc -l) / 2 ))"

    # Name of the primary display, there will only be one
    primary_display="$( echo "$raw_data" | grep " primary " | awk '{print $1;}' )"

    # Build the data point arrays that will be used to populate the DISPLAY map
    # NOTE: Every data point arary MUST contain the same number of elements or the DISPLAY map data will be skewed
    local resolution state rate cnt=0
    while IFS= read -r line; do
        if [[ $((cnt++ % 2)) -eq 0 ]]; then

            display_names+=("$(echo "$line" | grep ' connected ' | awk '{ print $1 }')")
            display_offsets+=("$(echo "$line" | grep -oP "(\+|-)[[:digit:]]+(\+|-)[[:digit:]]")")

            state="$(echo "$line" | grep -oP "[[:digit:]]+(mm x )[[:digit:]]+(mm)")"
            if [[ -n $state ]]; then
                display_states+=("enabled") 
            else 
                display_states+=("disabled")
            fi

        else
            resolution="$(echo "$line" | awk '{ print $1 }')"
            resolutions+=("$resolution")

            display_widths+=("$(echo "$resolution"| cut -d 'x' -f 1)")

            rate="$(echo "$line" | grep -oP '\s*\K[^[:space:]]*[*][^[:space:]]*\s*' | cut -d '*' -f 1 | cut -d '.' -f 1)"
            [[ -z $rate ]] && rate="N/A"
            refresh_rates+=("$rate")

        fi
    done <<< "$raw_data"

    # Populate DISPLAY map
    num_rows=${#display_names[@]}
    for ((i=0;i<num_rows;i++)) do

        for ((j=0;j<"$num_columns";j++)) do

            # Uncomment below lines to debug assigment of the multidimensional array DISPLAYS
            #local cache=$RANDOM
            #echo "row ${display_names[$j]}, column $i, data: $cache"
            # Set each data point in the proper location of the payload
            if [[ $j -eq 0 ]]; then
                DISPLAYS[$i,$j]="${display_names[$i]}"
            elif [[ $j -eq 1 ]]; then
                DISPLAYS[$i,$j]="${resolutions[$i]}"
            elif [[ $j -eq 2 ]]; then
                DISPLAYS[$i,$j]="${display_widths[$i]}"
            elif [[ $j -eq 3 ]]; then
                DISPLAYS[$i,$j]="${display_offsets[$i]}"
            elif [[ $j -eq 4 ]]; then
                DISPLAYS[$i,$j]="${refresh_rates[$i]}"
            elif [[ $j -eq 5 ]]; then
                DISPLAYS[$i,$j]="${display_states[$i]}"
            elif [[ $j -eq 6 ]]; then
                [[ "${display_names[$i]}" == "$primary_display" ]] && DISPLAYS[$i,$j]="primary" || DISPLAYS[$i,$j]='not primary'
            fi

        done

    done    

}

# For debugging the DISPLAYs map, A.K.A the 'multidimensional array' holding our data aka DISPLAYS
_Dump_DISPLAYS() {
    local columns=()
    local num_rows=$DISPLAY_TOTAL
    local num_columns=$(( ${#DISPLAYS[@]} / DISPLAY_TOTAL ))
    local linebreak_max=num_columns

    local count
    for (( i=0; i < num_rows; i++ )) do
        for (( j=0; j < num_columns; j++ )) do
            count=$((i * j))
            [[ $count -lt $linebreak_max ]] && [[ -n ${DISPLAYS[$i,$j]} ]] && echo -n "     ${DISPLAYS[$i,$j]}     "
        done
        # Add linebreaks to increase readability
        [[ $count -lt $linebreak_max ]] && echo
   done
   echo

}

_Get_2DValueAt() {  
    echo "${DISPLAYS["$1,$2"]}"
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

_Valid_OnOff_Subcommand() {
    local e_prefix
    e_prefix="$(basename "${BASH_SOURCE[1]}") error: Command: ${FUNCNAME[1]}:"

    if [[ -z $1 ]]; then 
        echo "${e_prefix} requires a sub-command"
        echo "Valid sub-commands are: <on|off>"
        
        return 1
    fi

    if [[ $1 != 'on' && $1 != 'off' ]]; then
        echo "${e_prefix} invalid sub-command: ${1}"
        echo "Valid sub-commands are <on|off>"
        return 1
    fi 
}

# Generates a syntactically correct nvidia CurrentMetaMode value
# Arguments passed in here should be validate @see function Fix(){...}
_Generate_CurrentMetaMode() {
    if ! _Valid_OnOff_Subcommand "$1"; then exit 1; fi


}

_Init() { 
    [[ ${#DISPLAYS[@]} -eq 0 ]] && _Set_display_data
}

fix() {
    local name=0     # Index of the display name value set in the DISPLAYS map @see _Set_display_data()
    local offset=3   # Index of the display name value set in the DISPLAYS map @see _Set_display_data()
    local nas='nvidia-auto-select'
    local num_rows="$DISPLAY_TOTAL"
    local num_columns=$(( ${#DISPLAYS[@]} / DISPLAY_TOTAL ))

    if ! _Valid_OnOff_Subcommand "$1"; then exit 1; fi

    # Example of a successful command (payload)
    # DP-3:nvidia-auto-select+2560+0{ForceFullCompositionPipeline=On},DP-4:nvidia-auto-select+0+0{ForceFullCompositionPipeline=On}
    
    # Generate the payload (CurrentMetaMode) from the DISPLAYS map
    local chunk payload cnt=0
    for ((i=0;i<num_rows;i++)) do
        chunk="${DISPLAYS["$i,$name"]}:${nas}${DISPLAYS["$i,$offset"]}{ForceFullCompositionPipeline=${1^}}"
        for ((j=0;j<num_columns;j++)) do
            # For every row of data (connected display) in the DISPLAYS map...
            if [[ $((++cnt % num_columns )) -eq 0 ]]; then
                [[ $cnt -ne "${#DISPLAYS[@]}" ]] && chunk="${chunk},"
                payload+="${chunk}"
            fi
        done
        
    done
    echo "CurrentMetaMode=\"${payload}\"" # debug
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
if declare -f "${1}" &> /dev/null; then "$@"; else echo "${e_prefix} '$1' is not a valid command" >&2; exit 1; fi


