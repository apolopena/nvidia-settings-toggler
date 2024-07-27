#!/usr/bin/env bash

# SUPER QUICK AND DIRTY FOR NOW, but here is the general gist of things...
#
# The idea here is to use this script to toggle on and off the proper settings for the proper monitors
# at the proper time in order to avoid screen teearing in Desktop applications AND to avoid breaking
# G-Sync/Adapative sync when Steam games are rnning using gamemoderun. 
#
# It is a very annoying Catch-22 bug indeed but this script should be able to address it
# For now This script will only work for my two screens, I hope to make it fully dynamic in the future
#
# We need ForceFullCompositionPipeline = On to avoid screen tearing in Desktop applications
# We need ForceFullCompositionPipeline = Off when running Steam games with G-Sync/Adaptive Sync
# otherwise we get 1fps hangups that require opening and closing a TTY just to keep the system
# from locking up and needing a cold boot
#
# We will use the script at startup time when the .desktop files in ~/.config/autostart are executed
# to set ForceFullCompositionPipeline = On
# We will then use the script another time in ~/.config/gamemode.ini so that when gamemode starts
# (a steam game launches) we can set ForceFullCompositionPipeline = Off
# Finally we will set ForceFullCompositionPipeline = On when gamemode ends (a steam game exits)
#
# I have no idea if a steam game crashing will trigger the gamemode end command, it will have to
# be tested
#
# For the sake of simplicity it will be assumed that these two monitors 
# will always using their native resolution of 1600p and 1440p respectively
# It will also (for now) be assumed that monitors will not be turned off or 
# on while games are playing, allthough that should ba able to be handled at a later time

#TODO: break these string up into dynamic pieces echoed from functions but for now keep it simple and hardcoded until it works
#TODO create function to set AllowGSYNCCompatible = On

# I CANT GET THE COMMANDS RIGHT THE CLOSETS I CAN GET IS TO DYNAMICALLY SWITCH MULTIPLE MONITORS TO USE THE FIX BUT THE PRIMARY LAPTOP MONITOR BUMBPS DOWN TO 60HZ
# TODO do it in two shots 1st run (which works except the above mentioned problem):
# nvidia-settings --assign CurrentMetaMode="$(xrandr | sed -nr '/(\S+) connected (primary )?[0-9]+x[0-9]+(\+\S+).*/{ s//\1: nvidia-auto-select \3 { ForceFullCompositionPipeline = On }, /; H }; ${ g; s/\n//g; s/, $//; p }')"
# THEN swap the refresh rate back to 240
#xrandr --output DP-4 --mode 2560x1600 --rate 240

#both_monitors_on='"DP-4: 2560x1600 +0+0 { ForceFullCompositionPipeline = On, AllowGSYNCCompatible = On }, DP-3: 2560x1440 +2560+0 { ForceFullCompositionPipeline = On}"'
#both_monitors_on='"DP-3:nvidia-auto-select+2560+160{ForceFullCompositionPipeline=On},DP-4:nvidia-auto-select+0+0{ForceFullCompositionPipeline=On}"'
#both_monitors_on='"DPY-3: @2560x1440 +2560+0 {ViewPortIn=2560x1440, ViewPortOut=2560x1440+0+0, ForceFullCompositionPipeline = On}, DPY-5: 2560x1600_240 @2560x1600 +0+0 {ViewPortIn=2560x1600, ViewPortOut=2560x1600+0+0, ForceFullCompositionPipeline= On, AllowGSYNCCompatible = On}"'
both_monitors_on='"DP-4: 2560x1600_240 +0+0 {ForceCompositionPipeline=On, ForceFullCompositionPipeline=On}, DP-3: nvidia-auto-select +2560+0 {ForceCompositionPipeline=On, ForceFullCompositionPipeline=On}"'
monitor_1600p_on='"DP-4: 2560x1600 +0+0 { ForceFullCompositionPipeline= On, AllowGSYNCCompatible = On }"'
monitor_1440p_on='"DP-3: 2560x1440 +0+0 { ForceFullCompositionPipeline = On}"'
#both_monitors_off='"DP-4: 2560x1600 +0+0 { ForceFullCompositionPipeline = Off }, DP-3: 2560x1440 +2560+0 { ForceFullCompositionPipeline = Off}"'
both_monitors_off='"DPY-3: nvidia-auto-select +2560+0, DPY-5: 2560x1600_240 +0+0 {AllowGSYNCCompatible=On}"'
monitor_1600p_off='"DP-4: 2560x1600 +0+0 { ForceFullCompositionPipeline = Off }"'
monitor_1440p_off='"DP-3: 2560x1440 +0+0 { ForceFullCompositionPipeline = Off }"'
e_prefix="tearing_fix.sh error:"

_monitor_names() {
    xrandr | grep " connected " | awk '{ print$1 }'
}

_is_all_whitespace() {
    local arg="$1"
    arg=${arg%, }
    arg=${arg#, }
    [[ -n "$arg" ]] && return 1
    return 0
}

_meets_reqs() {
    if ! which nvidia-settings > /dev/null; then
        echo "${e_prefix} nvidia-settings binary not found"
        return 1
    fi
}

fix() {
    local mons num_mons ec="fix command: "
    mons="$(_monitor_names)"
    num_mons="$(echo "$mons" | wc -l)"

    # Handle errors
    if ! _meets_reqs; then exit 1; fi

    if _is_all_whitespace "$mons"; then echo "${e_prefix} no monitors found" && exit 1; fi

    [[ -z $1 ]] && echo "${e_prefix} ${ec} missing required sub-command. valid sub-commands are <on|off>" && exit 1

    if [[ $1 != 'on' && $1 != 'off' ]]; then
        echo "${e_prefix} ${ec} invalid sub-command: ${1}"
        echo "valid commands are <on|off>"
        exit 1
    fi

    # Turn on 
    if [[ $1 == 'on' ]]; then
        [[ $num_mons -eq 2 ]] && nvidia-settings --assign CurrentMetaMode="${both_monitors_on}" && exit 0
        [[ $mons == 'DP-4' ]] && nvidia-settings --assign CurrentMetaMode="${monitor_1600p_on}" && exit 0
        [[ $mons == 'DP-3' ]] && nvidia-settings --assign CurrentMetaMode="${monitor_1440p_on}" && exit 0
    fi

    # Turn off
    if [[ $1 == 'off' ]]; then
        [[ $num_mons -eq 2 ]] && nvidia-settings --assign CurrentMetaMode="${both_monitors_off}" && exit 0
        [[ $mons == 'DP-4' ]] && nvidia-settings --assign CurrentMetaMode="${monitor_1600p_off}" && exit 0
        [[ $mons == 'DP-3' ]] && nvidia-settings --assign CurrentMetaMode="${monitor_1440p_off}" && exit 0
    fi
}

foo() {
    # Activate the Desktop Application screen tearing fix for both monitors. 
    # DP-4 is the laptop screen and DP-3 is the external monitor
    nvidia-settings --assign CurrentMetaMode="DP-4: 2560x1600 +0+0 { ForceFullCompositionPipeline = On, AllowGSYNCCompatible = On }, DP-3: 2560x1440 +2560+0 { ForceFullCompositionPipeline = On}"
}

bar() {
    # # Activate the Desktop Application screen tearing fix for both monitors.
    # Also dopnt bother toggling off AllowGSYNCCompatible for DP-4 (laptop screen)
    # It seems ok to leave it on, even if it will be turned on while its still on
    # whenever gamemode starts
    nvidia-settings --assign CurrentMetaMode="DP-4: 2560x1600 +0+0 { ForceFullCompositionPipeline = Off }, DP-3: 2560x
    1440 +2560+0 { ForceFullCompositionPipeline = Off}"
}

# Require a command
[[ $# -eq 0 ]] && echo "${e_prefix} missing required command. valid commands are: fix <on|off>" && exit 1

# Call functions gracefully
if declare -f "$1" > /dev/null; then "$@"; else echo "${e_prefix} '$1' is not a valid command" >&2; exit 1; fi
