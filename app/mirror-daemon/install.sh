#!/bin/bash
# Script d'installation complet du daemon miroir
# À exécuter sur le PC désigné comme serveur miroir
#
# Usage:
#   ./install.sh              -- installation + enregistrement
#   ./install.sh --force      -- force l'enregistrement (remplace l'ancien serveur)
#   ./install.sh --uninstall  -- désinstallation

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_LABEL="com.compta.mirror-daemon"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
FORCE=""
UNINSTALL=false

for arg in "$@"; do
  case $arg in
    --force) FORCE="--force" ;;
    --uninstall) UNINSTALL=true ;;
  esac
done

if [ "$UNINSTALL" = true ]; then
  echo "=== Désinstallation du daemon miroir ==="
  if [ -f "$PLIST_PATH" ]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "Service arrêté et plist supprimé."
  else
    echo "Aucun service trouvé."
  fi
  echo "Le dossier mirror-data/ n'est pas supprimé (vos données sont conservées)."
  echo "Pour supprimer les données: rm -rf $SCRIPT_DIR/mirror-data"
  echo "Terminé."
  exit 0
fi

echo "╔══════════════════════════════════════════════════════╗"
echo "║  INSTALLATION DU SERVEUR MIROIR COMPTA               ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Vérifier Node.js
if ! command -v node &> /dev/null; then
  echo "ERREUR: Node.js n'est pas installé."
  echo "Installez-le depuis: https://nodejs.org (version 18+)"
  exit 1
fi

NODE_PATH=$(which node)
echo "Node.js: $NODE_PATH ($(node --version))"
echo "Dossier: $SCRIPT_DIR"
echo ""

# Installer les dépendances
echo "=== Installation des dépendances ==="
cd "$SCRIPT_DIR"
npm install --production 2>&1 | tail -3
echo ""

# Enregistrer le serveur miroir sur Supabase
echo "=== Enregistrement du serveur miroir ==="
node daemon.mjs --register --once $FORCE --verbose
if [ $? -ne 0 ]; then
  echo ""
  echo "ERREUR: L'enregistrement a échoué."
  echo "Si la table mirror_servers n'existe pas, exécutez le SQL:"
  echo "  sql/create_mirror_servers.sql dans Supabase Dashboard > SQL Editor"
  exit 1
fi
echo ""

# Première sync
echo "=== Première synchronisation ==="
node daemon.mjs --once --verbose
echo ""

# Créer le plist launchd pour macOS
if [ "$(uname)" = "Darwin" ]; then
  echo "=== Configuration du démarrage automatique (macOS) ==="
  
  mkdir -p "$(dirname "$PLIST_PATH")"
  
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

  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  launchctl load "$PLIST_PATH"
  echo "Service launchd configuré et démarré."
  echo ""
fi

echo "╔══════════════════════════════════════════════════════╗"
echo "║  INSTALLATION TERMINÉE                               ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║                                                      ║"
echo "║  Le daemon est actif et synchronise automatiquement: ║"
echo "║  - Au démarrage de l'ordinateur                      ║"
echo "║  - À l'ouverture de session                          ║"
echo "║  - Toutes les 5 minutes (configurable)               ║"
echo "║  - Quand internet revient après une coupure          ║"
echo "║                                                      ║"
echo "║  Données synchronisées dans:                         ║"
echo "║  $SCRIPT_DIR/mirror-data/                            ║"
echo "║                                                      ║"
echo "║  Logs: $SCRIPT_DIR/daemon.log                        ║"
echo "║                                                      ║"
echo "║  Commandes utiles:                                   ║"
echo "║  Arrêter:    launchctl unload $PLIST_PATH           ║"
echo "║  Démarrer:   launchctl load $PLIST_PATH             ║"
echo "║  Sync manuelle: node daemon.mjs --once --verbose     ║"
echo "║  Désinstaller: ./install.sh --uninstall              ║"
echo "║                                                      ║"
echo "╚══════════════════════════════════════════════════════╝"
