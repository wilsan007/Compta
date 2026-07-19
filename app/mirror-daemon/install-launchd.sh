#!/bin/bash
# Script d'installation du daemon miroir en service macOS (launchd)
# À exécuter sur le PC désigné comme serveur miroir
#
# Usage: ./install-launchd.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_LABEL="com.compta.mirror-daemon"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

echo "=== Installation du daemon miroir (macOS launchd) ==="
echo "Dossier: $SCRIPT_DIR"
echo ""

# Vérifier que Node.js est installé
if ! command -v node &> /dev/null; then
  echo "ERREUR: Node.js n'est pas installé. Installez-le d'abord: https://nodejs.org"
  exit 1
fi

NODE_PATH=$(which node)
echo "Node.js trouvé: $NODE_PATH ($(node --version))"

# Installer les dépendances
echo ""
echo "Installation des dépendances..."
cd "$SCRIPT_DIR"
npm install --production 2>&1 | tail -3

# Créer le plist launchd
cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>${NODE_PATH}</string>
        <string>${SCRIPT_DIR}/daemon.mjs</string>
    </array>
    
    <key>WorkingDirectory</key>
    <string>${SCRIPT_DIR}</string>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>${SCRIPT_DIR}/daemon.log</string>
    
    <key>StandardErrorPath</key>
    <string>${SCRIPT_DIR}/daemon-error.log</string>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
EOF

echo ""
echo "Plist créé: $PLIST_PATH"

# Charger le service
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo ""
echo "=== Installation terminée ==="
echo "Le daemon démarre automatiquement:"
echo "  - Au démarrage de l'ordinateur"
echo "  - À l'ouverture de session"
echo "  - Il redémarre automatiquement s'il plante"
echo ""
echo "Logs: $SCRIPT_DIR/daemon.log"
echo "Erreurs: $SCRIPT_DIR/daemon-error.log"
echo ""
echo "Commandes utiles:"
echo "  Arrêter:    launchctl unload $PLIST_PATH"
echo "  Démarrer:   launchctl load $PLIST_PATH"
echo "  Statut:     launchctl list | grep compta"
echo "  Sync manuelle: cd $SCRIPT_DIR && node daemon.mjs --once --verbose"
