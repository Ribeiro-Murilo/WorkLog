#!/bin/bash
# Builda o WorkLog em Release, empacota, assina a atualização para o Sparkle
# e insere a entrada correspondente no appcast.xml.
#
# Não cria tags, não publica nem cria releases no GitHub — só prepara os
# arquivos e imprime os próximos passos manuais.
#
# Uso: scripts/release.sh <versão>   (ex.: scripts/release.sh 1.1.0)
set -euo pipefail

VERSION="${1:?Uso: scripts/release.sh <versão> (ex.: 1.1.0)}"
REPO_URL="https://github.com/Ribeiro-Murilo/WorkLog"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/WorkLog.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/WorkLog.app"
ZIP_NAME="WorkLog-$VERSION.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
APPCAST_PATH="$ROOT_DIR/appcast.xml"
SIGN_UPDATE="$ROOT_DIR/scripts/sparkle-bin/sign_update"

cd "$ROOT_DIR"

echo "==> Atualizando MARKETING_VERSION para $VERSION"
sed -i '' "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $VERSION;/g" WorkLog.xcodeproj/project.pbxproj

echo "==> Compilando Release"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
xcodebuild -project WorkLog.xcodeproj -scheme WorkLog -configuration Release -destination 'platform=macOS' archive -archivePath "$ARCHIVE_PATH"

echo "==> Empacotando $ZIP_NAME"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Assinando update para o Sparkle"
SIGNATURE_LINE=$("$SIGN_UPDATE" "$ZIP_PATH")
SIGNATURE=$(echo "$SIGNATURE_LINE" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGNATURE_LINE" | grep -o 'length="[^"]*"' | cut -d'"' -f2)

if [ -z "$SIGNATURE" ] || [ -z "$LENGTH" ]; then
    echo "Falha ao assinar o update. Saída do sign_update:"
    echo "$SIGNATURE_LINE"
    exit 1
fi

DOWNLOAD_URL="$REPO_URL/releases/download/v$VERSION/$ZIP_NAME"
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

ITEM=$(cat <<EOF
        <item>
            <title>Versão $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <enclosure url="$DOWNLOAD_URL"
                sparkle:edSignature="$SIGNATURE"
                length="$LENGTH"
                type="application/octet-stream" />
        </item>
EOF
)

echo "==> Inserindo entrada no appcast.xml"
python3 "$ROOT_DIR/scripts/insert_appcast_item.py" "$APPCAST_PATH" "$ITEM"

cat <<EOF

Pronto. Falta:
1. Revisar e commitar o bump de versão + appcast.xml
2. git tag v$VERSION && git push origin v$VERSION
3. Criar o Release no GitHub anexando o zip:
   gh release create v$VERSION "$ZIP_PATH" --title "Versão $VERSION" --notes "..."
4. Fazer push do appcast.xml atualizado para a branch main (é o que o Sparkle lê em produção)
EOF
