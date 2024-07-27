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

# Activate the Desktop Application screen tearing fix for both monitors. 
# DP-4 is the laptop screen and DP-3 is the external monitor
nvidia-settings --assign CurrentMetaMode="DP-4: 2560x1600 +0+0 { ForceFullCompositionPipeline = On, AllowGSYNCComp
atible = On }, DP-3: 2560x1440 +2560+0 { ForceFullCompositionPipeline = On}"

# # Activate the Desktop Application screen tearing fix for both monitors.
# Also dopnt bother toggling off AllowGSYNCCompatible for DP-4 (laptop screen)
# It seems ok to leave it on, even if it will be turned on while its still on
# whenever gamemode starts
nvidia-settings --assign CurrentMetaMode="DP-4: 2560x1600 +0+0 { ForceFullCompositionPipeline = Off }, DP-3: 2560x
1440 +2560+0 { ForceFullCompositionPipeline = Off}"
