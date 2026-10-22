#!/usr/bin/env bash
# ==============================================================================
# TracePOS - macOS DMG Installer Packaging Script
# ==============================================================================
set -e

echo "========================================================"
echo "  TracePOS - Construction du package DMG pour macOS"
echo "========================================================"

# Verify platform
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Erreur: Ce script doit être exécuté sur macOS."
  exit 1
fi

# Ensure flutter is available
if ! command -v flutter &> /dev/null; then
  echo "Erreur: Flutter n'est pas trouvé dans le PATH."
  exit 1
fi

# Ensure hdiutil is available
if ! command -v hdiutil &> /dev/null; then
  echo "Erreur: hdiutil n'est pas disponible sur ce système."
  exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="TracePOS"
BUILD_OUTPUT_APP="build/macos/Build/Products/Release/tracepos.app"
DIST_DIR="dist"
STAGING_DIR="$DIST_DIR/dmg_staging"
DMG_NAME="TracePOS-macOS.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo ""
echo "Étape 1/4 : Compilation Release macOS Universal (arm64 + x86_64)..."
flutter build macos --release

if [ ! -d "$BUILD_OUTPUT_APP" ]; then
  echo "Erreur: L'application compilée n'a pas été trouvée à $BUILD_OUTPUT_APP"
  exit 1
fi

echo ""
echo "Étape 2/4 : Préparation de l'environnement de staging..."
rm -rf "$STAGING_DIR"
rm -f "$DMG_PATH"
mkdir -p "$STAGING_DIR"
mkdir -p "$DIST_DIR"

# Copy the .app bundle
echo "Copie du bundle d'application..."
cp -R "$BUILD_OUTPUT_APP" "$STAGING_DIR/TracePOS.app"

# Create symlink to /Applications for drag-and-drop installation
echo "Création du lien Applications..."
ln -s /Applications "$STAGING_DIR/Applications"

# Create French instructions file
cat << 'EOF' > "$STAGING_DIR/LISEZ-MOI.txt"
============================================================
  TracePOS - Point de Vente & Gestion de Stock (macOS)
============================================================

INSTALLATION FACILE :
1. Glissez et déposez "TracePOS.app" dans le dossier "Applications".
2. Lancez TracePOS depuis vos Applications ou Spotlight.

CONFIGURATION DU MATÉRIEL DE CAISSE :
- Imprimante Ticket USB (CUPS) :
  Configurez votre imprimante thermique dans Préférences Système >
  Imprimantes et scanners, puis ouvrez TracePOS > Paramètres > Matériel
  et sélectionnez votre imprimante dans la liste.

- Imprimante Ticket Réseau (Wi-Fi / LAN) :
  Dans TracePOS > Paramètres > Matériel, sélectionnez "Réseau (Wi-Fi / LAN)",
  saisissez l'adresse IP de l'imprimante (ex: 192.168.1.100, port 9100),
  cliquez sur "Tester Ping" puis "Enregistrer & Activer".

- Tiroir-Caisse :
  Connectez votre tiroir-caisse au port RJ11/RJ12 de l'imprimante ticket.
  L'impulsion d'ouverture est envoyée automatiquement à chaque validation de vente.

Assistance & Documentation : TracePOS Support
EOF

echo ""
echo "Étape 3/4 : Création de l'image disque DMG ($DMG_NAME)..."
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo ""
echo "Étape 4/4 : Nettoyage du staging..."
rm -rf "$STAGING_DIR"

echo "========================================================"
echo "  SUCCÈS : Le package DMG est prêt !"
echo "  Fichier : $PROJECT_ROOT/$DMG_PATH"
echo "  Taille  : $(du -sh "$DMG_PATH" | cut -f1)"
echo "========================================================"
