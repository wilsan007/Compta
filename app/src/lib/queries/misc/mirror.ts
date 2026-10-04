// ============================================================================
// misc — mirror.ts
// Extrait de l'ancien misc.ts le 2026-10-01 ; imports recalcules ;
// aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { requireAdminOfTenant } from './multiTenant'

// ============ Mirror Server Management ============
export interface MirrorServer {
  id: string
  tenant_id: string
  machine_id: string
  machine_name: string
  os: string | null
  ip_address: string | null
  mirror_dir: string | null
  registered_at: string
  last_heartbeat: string
  status: 'active' | 'inactive' | 'revoked'
  config: Record<string, any> | null
}

export async function registerMirrorServer(data: {
  tenant_id: string
  machine_id: string
  machine_name: string
  os?: string
  ip_address?: string
  mirror_dir?: string
  config?: Record<string, any>
}): Promise<{ success: boolean; error?: string; server?: MirrorServer }> {
  const { data: existing, error: checkError } = await supabase
    .from('mirror_servers')
    .select('*')
    .eq('tenant_id', data.tenant_id)
    .eq('status', 'active')
    .maybeSingle()

  if (checkError) {
    return { success: false, error: checkError.message }
  }

  if (existing && existing.machine_id !== data.machine_id) {
    return {
      success: false,
      error: `Un serveur miroir est déjà enregistré pour ce tenant sur la machine "${existing.machine_name}". Un seul serveur miroir par tenant est autorisé. Révoquez-le d'abord pour enregistrer un nouveau.`,
    }
  }

  if (existing && existing.machine_id === data.machine_id) {
    const { data: updated, error: updateError } = await supabase
      .from('mirror_servers')
      .update({
        machine_name: data.machine_name,
        os: data.os || null,
        ip_address: data.ip_address || null,
        mirror_dir: data.mirror_dir || null,
        last_heartbeat: new Date().toISOString(),
        status: 'active',
        config: data.config || null,
      })
      .eq('id', existing.id)
      .select()
      .single()
    if (updateError) return { success: false, error: updateError.message }
    return { success: true, server: updated as MirrorServer }
  }

  const { data: created, error: insertError } = await supabase
    .from('mirror_servers')
    .insert({
      tenant_id: data.tenant_id,
      machine_id: data.machine_id,
      machine_name: data.machine_name,
      os: data.os || null,
      ip_address: data.ip_address || null,
      mirror_dir: data.mirror_dir || null,
      status: 'active',
      config: data.config || null,
    })
    .select()
    .single()

  if (insertError) {
    if (insertError.code === '23505') {
      return { success: false, error: 'Un serveur miroir est déjà enregistré pour ce tenant.' }
    }
    return { success: false, error: insertError.message }
  }

  return { success: true, server: created as MirrorServer }
}

export async function getMirrorServer(tenantId: string): Promise<MirrorServer | null> {
  const { data, error } = await supabase
    .from('mirror_servers')
    .select('*')
    .eq('tenant_id', tenantId)
    .maybeSingle()
  if (error) {
    console.error('Error getting mirror server:', error)
    return null
  }
  return data as MirrorServer | null
}

export async function updateMirrorHeartbeat(machineId: string): Promise<void> {
  await supabase
    .from('mirror_servers')
    .update({ last_heartbeat: new Date().toISOString() })
    .eq('machine_id', machineId)
}

export async function revokeMirrorServer(tenantId: string): Promise<{ error?: string }> {
  // SECURITY: Verify caller is an admin of the target tenant
  const guard = await requireAdminOfTenant(tenantId)
  if (!guard.ok) return { error: guard.error }

  const { error } = await supabase
    .from('mirror_servers')
    .update({ status: 'revoked' })
    .eq('tenant_id', tenantId)
  if (error) return { error: error.message }
  return {}
}



// ============ Mirror Server Installation Flow ============

export async function preRegisterMirrorServer(data: {
  tenant_id: string
  install_platform: 'mac' | 'windows' | 'linux'
}): Promise<{ success: boolean; error?: string; install_token?: string }> {
  // SECURITY: Verify caller is an admin of the target tenant
  const guard = await requireAdminOfTenant(data.tenant_id)
  if (!guard.ok) return { success: false, error: guard.error }

  const { data: existing } = await supabase
    .from('mirror_servers')
    .select('*')
    .eq('tenant_id', data.tenant_id)
    .in('status', ['active'])
    .maybeSingle()

  if (existing && existing.install_status === 'verified') {
    return { success: false, error: 'Un serveur miroir vérifié est déjà installé pour ce tenant.' }
  }

  const installToken = crypto.randomUUID()

  if (existing) {
    const { error } = await supabase
      .from('mirror_servers')
      .update({
        install_status: 'pending',
        install_token: installToken,
        install_platform: data.install_platform,
      })
      .eq('id', existing.id)
    if (error) return { success: false, error: error.message }
  } else {
    const { error } = await supabase
      .from('mirror_servers')
      .insert({
        tenant_id: data.tenant_id,
        machine_id: 'pending-' + installToken,
        machine_name: 'En attente d\'installation',
        status: 'active',
        install_status: 'pending',
        install_token: installToken,
        install_platform: data.install_platform,
      })
    if (error) return { success: false, error: error.message }
  }

  return { success: true, install_token: installToken }
}

export async function getMirrorServerStatus(tenantId: string): Promise<{
  exists: boolean
  install_status?: string
  install_platform?: string
  machine_name?: string
  verified_at?: string
  verification_data?: Record<string, any>
  last_heartbeat?: string
}> {
  const { data, error } = await supabase
    .from('mirror_servers')
    .select('*')
    .eq('tenant_id', tenantId)
    .maybeSingle()

  if (error) { console.error('checkMirrorServerExists:', error); return { exists: false } }
  if (!data) return { exists: false }

  return {
    exists: true,
    install_status: data.install_status,
    install_platform: data.install_platform,
    machine_name: data.machine_name,
    verified_at: data.verified_at,
    verification_data: data.verification_data,
    last_heartbeat: data.last_heartbeat,
  }
}

export async function getMirrorVerificationDetails(serverId: string): Promise<any[]> {
  const { data, error } = await supabase
    .from('mirror_verification_details')
    .select('*')
    .eq('mirror_server_id', serverId)
    .order('table_name')
  if (error) { console.error('getMirrorVerificationDetails:', error); return [] }
  return data || []
}

export function generateMacInstaller(config: {
  supabaseUrl: string
  supabaseKey: string
  tenantId: string
  installToken: string
}): string {
  return `#!/bin/bash
# Installateur du serveur miroir Compta - macOS
# Généré automatiquement depuis la plateforme

set -e

INSTALL_DIR="$HOME/compta-mirror"
TENANT_ID="${config.tenantId}"
SUPABASE_URL="${config.supabaseUrl}"
SUPABASE_KEY="${config.supabaseKey}"
INSTALL_TOKEN="${config.installToken}"

echo "======================================================"
echo "  INSTALLATION SERVEUR MIROIR COMPTA - macOS          "
echo "======================================================"
echo ""

# Vérifier Node.js
if ! command -v node &> /dev/null; then
  echo "ERREUR: Node.js n'est pas installé."
  echo "Installez-le depuis: https://nodejs.org (version 18+)"
  exit 1
fi
NODE_PATH=$(which node)
echo "Node.js: $NODE_PATH ($(node --version))"

# Créer le dossier
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
echo "Dossier: $INSTALL_DIR"

# Écrire la configuration
cat > config.json << EOF
{
  "supabaseUrl": "$SUPABASE_URL",
  "supabaseKey": "$SUPABASE_KEY",
  "mirrorDir": "./mirror-data",
  "pollIntervalMs": 300000,
  "syncOnStart": true,
  "tenantId": "$TENANT_ID",
  "installToken": "$INSTALL_TOKEN"
}
EOF

# Écrire package.json
cat > package.json << EOF
{
  "name": "compta-mirror-daemon",
  "version": "1.0.0",
  "type": "module",
  "dependencies": { "@supabase/supabase-js": "^2.45.0" }
}
EOF

echo "Installation des dépendances..."
npm install --production 2>&1 | tail -3

# Télécharger le daemon depuis le bucket de stockage Supabase
echo "Téléchargement du daemon..."
DAEMON_URL="$SUPABASE_URL/storage/v1/object/public/mirror-daemon/daemon.mjs"
curl -sfL "$DAEMON_URL" -o daemon.mjs || {
  echo "ERREUR: Impossible de télécharger daemon.mjs depuis $DAEMON_URL"
  echo "Veuillez télécharger manuellement le fichier daemon.mjs et le placer dans $INSTALL_DIR/"
  exit 1
}

# Enregistrer + première sync + vérification
echo ""
echo "=== Enregistrement et synchronisation ==="
node daemon.mjs --register --force --once --verbose

if [ $? -ne 0 ]; then
  echo "ERREUR: L'installation a échoué."
  exit 1
fi

# Configurer launchd
PLIST_LABEL="com.compta.mirror-daemon"
PLIST_PATH="$HOME/Library/LaunchAgents/\${PLIST_LABEL}.plist"
mkdir -p "$(dirname "$PLIST_PATH")"

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>\${PLIST_LABEL}</string>
  <key>ProgramArguments</key><array>
    <string>\${NODE_PATH}</string>
    <string>\${INSTALL_DIR}/daemon.mjs</string>
  </array>
  <key>WorkingDirectory</key><string>\${INSTALL_DIR}</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>\${INSTALL_DIR}/daemon.log</string>
  <key>StandardErrorPath</key><string>\${INSTALL_DIR}/daemon-error.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo ""
echo "======================================================"
echo "  INSTALLATION TERMINÉE ET VÉRIFIÉE                   "
echo "  Le daemon est actif. Données dans:                  "
echo "  $INSTALL_DIR/mirror-data/                           "
echo "  Démarrage automatique au boot.                      "
echo "======================================================"
`
}

export function generateWindowsInstaller(config: {
  supabaseUrl: string
  supabaseKey: string
  tenantId: string
  installToken: string
}): string {
  return `# Installateur du serveur miroir Compta - Windows (PowerShell)
# Genere automatiquement depuis la plateforme
# Usage: Right-click > Run with PowerShell

$ErrorActionPreference = "Stop"

$INSTALL_DIR = "$env:USERPROFILE\\compta-mirror"
$TENANT_ID = "${config.tenantId}"
$SUPABASE_URL = "${config.supabaseUrl}"
$SUPABASE_KEY = "${config.supabaseKey}"
$INSTALL_TOKEN = "${config.installToken}"

Write-Host "======================================================="
Write-Host "  INSTALLATION SERVEUR MIROIR COMPTA - Windows        "
Write-Host "======================================================="
Write-Host ""

# Verifier Node.js
$nodePath = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodePath) {
    Write-Host "ERREUR: Node.js n'est pas installe." -ForegroundColor Red
    Write-Host "Installez-le depuis: https://nodejs.org (version 18+)"
    exit 1
}
Write-Host "Node.js: $nodePath ($(node --version))"

# Creer le dossier
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
Set-Location $INSTALL_DIR
Write-Host "Dossier: $INSTALL_DIR"

# Ecrire la configuration
$conf = @{
    supabaseUrl = $SUPABASE_URL
    supabaseKey = $SUPABASE_KEY
    mirrorDir = "./mirror-data"
    pollIntervalMs = 300000
    syncOnStart = $true
    tenantId = $TENANT_ID
    installToken = $INSTALL_TOKEN
} | ConvertTo-Json
$conf | Out-File -FilePath "config.json" -Encoding utf8

# Ecrire package.json
$pkg = @{
    name = "compta-mirror-daemon"
    version = "1.0.0"
    type = "module"
    dependencies = @{ "@supabase/supabase-js" = "^2.45.0" }
} | ConvertTo-Json
$pkg | Out-File -FilePath "package.json" -Encoding utf8

Write-Host "Installation des dependances..."
npm install --production 2>&1 | Select-Object -Last 3

# Telecharger le daemon depuis le bucket de stockage Supabase
Write-Host "Telechargement du daemon..."
$daemonUrl = "$SUPABASE_URL/storage/v1/object/public/mirror-daemon/daemon.mjs"
try {
    Invoke-WebRequest -Uri $daemonUrl -OutFile "daemon.mjs" -ErrorAction Stop
} catch {
    Write-Host "ERREUR: Impossible de telecharger daemon.mjs depuis $daemonUrl" -ForegroundColor Red
    Write-Host "Veuillez telecharger manuellement le fichier daemon.mjs et le placer dans $INSTALL_DIR/"
    exit 1
}

# Enregistrer + premiere sync + verification
Write-Host ""
Write-Host "=== Enregistrement et synchronisation ==="
node daemon.mjs --register --force --once --verbose

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERREUR: L'installation a echoue." -ForegroundColor Red
    exit 1
}

# Creer la tache planifiee Windows
$action = New-ScheduledTaskAction -Execute $nodePath -Argument "daemon.mjs" -WorkingDirectory $INSTALL_DIR
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "ComptaMirrorDaemon" -Action $action -Trigger $trigger -Settings $settings -Force

Write-Host ""
Write-Host "======================================================="
Write-Host "  INSTALLATION TERMINEE ET VERIFIEE                   "
Write-Host "  Tache planifiee: ComptaMirrorDaemon                  "
Write-Host "  Donnees dans: $INSTALL_DIR\\mirror-data\\           "
Write-Host "======================================================="
`
}
