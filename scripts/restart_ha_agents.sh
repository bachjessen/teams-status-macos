#!/bin/bash
#####################################################################################
# Script Name   : restart_ha_agents.sh
# Description   : Restart Home Assistant LaunchAgents (Local + External)
# Author        : Simon
# Version       : 1.0
#####################################################################################

# Get the current user's UID
USER_ID=$(id -u)

# Paths to LaunchAgents
LOCAL_AGENT="$HOME/Library/LaunchAgents/com.homeassistant.MSTeamsStatusSender-Local.plist"
EXTERNAL_AGENT="$HOME/Library/LaunchAgents/com.homeassistant.MSTeamsStatusSender-External.plist"

echo "Restarting Home Assistant LaunchAgents..."

# Restart Local agent
echo "Restarting Local agent..."
launchctl bootout gui/$USER_ID "$LOCAL_AGENT"
launchctl bootstrap gui/$USER_ID "$LOCAL_AGENT"

# Restart External agent
echo "Restarting External agent..."
launchctl bootout gui/$USER_ID "$EXTERNAL_AGENT"
launchctl bootstrap gui/$USER_ID "$EXTERNAL_AGENT"

echo "✅ Both LaunchAgents restarted successfully."
