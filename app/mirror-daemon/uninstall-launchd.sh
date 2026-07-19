#!/bin/bash
# Script de désinstallation du daemon miroir (macOS launchd)

PLIST_LABEL="com.compta.mirror-daemon"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

echo "=== Désinstallation du daemon miroir ==="

if [ -f "$PLIST_PATH" ]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "Service arrêté et plist supprimé."
else
    echo "Aucun service trouvé."
fi

echo "Terminé."
