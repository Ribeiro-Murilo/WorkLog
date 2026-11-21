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
APPCAST_PATH="$ROOT_DIR/appcast-v2.xml"
SIGN_UPDATE="$ROOT_DIR/scripts/sparkle-bin/sign_update"
SIGNING_ACCOUNT="WorkLog-updates-v2"
GENERATE_KEYS="$ROOT_DIR/scripts/sparkle-bin/generate_keys"

cd "$ROOT_DIR"

EMBEDDED_PUBLIC_KEY=$(plutil -extract SUPublicEDKey raw WorkLog/Info.plist)
if ! KEYCHAIN_PUBLIC_KEY=$("$GENERATE_KEYS" --account "$SIGNING_ACCOUNT" -p) ||
   [ "$KEYCHAIN_PUBLIC_KEY" != "$EMBEDDED_PUBLIC_KEY" ]; then
    echo "A chave Sparkle da conta $SIGNING_ACCOUNT precisa corresponder à chave pública do WorkLog." >&2
    exit 1
fi

echo "==> Atualizando MARKETING_VERSION para $VERSION"
sed -i '' "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $VERSION;/g" WorkLog.xcodeproj/project.pbxproj

# O Sparkle compara versões pelo CFBundleVersion (CURRENT_PROJECT_VERSION), que
# precisa ser um inteiro monotonicamente crescente. O MARKETING_VERSION (0.1.1)
# é só o texto exibido ao usuário e NÃO é usado na comparação.
CURRENT_BUILD=$(grep -m1 -o 'CURRENT_PROJECT_VERSION = [0-9]*;' WorkLog.xcodeproj/project.pbxproj | grep -o '[0-9]*')
BUILD_NUMBER=$((CURRENT_BUILD + 1))
echo "==> Incrementando CURRENT_PROJECT_VERSION: $CURRENT_BUILD -> $BUILD_NUMBER"
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" WorkLog.xcodeproj/project.pbxproj

echo "==> Compilando Release"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
xcodebuild -project WorkLog.xcodeproj -scheme WorkLog -configuration Release -destination 'platform=macOS' archive -archivePath "$ARCHIVE_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "==> Empacotando $ZIP_NAME"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Assinando update para o Sparkle"
if ! SIGNATURE_LINE=$("$SIGN_UPDATE" --account "$SIGNING_ACCOUNT" "$ZIP_PATH"); then
    echo "$SIGNATURE_LINE" >&2
    exit 1
fi
SIGNATURE=$(echo "$SIGNATURE_LINE" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGNATURE_LINE" | grep -o 'length="[^"]*"' | cut -d'"' -f2)

if [ -z "$SIGNATURE" ] || [ -z "$LENGTH" ]; then
    echo "Falha ao extrair a assinatura e o tamanho do update." >&2
    exit 1
fi

DOWNLOAD_URL="$REPO_URL/releases/download/v$VERSION/$ZIP_NAME"
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

ITEM=$(cat <<EOF
        <item>
            <title>Versão $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <enclosure url="$DOWNLOAD_URL"
                sparkle:edSignature="$SIGNATURE"
                length="$LENGTH"
                type="application/octet-stream" />
        </item>
EOF
)

echo "==> Inserindo entrada em ${APPCAST_PATH##*/}"
python3 "$ROOT_DIR/scripts/insert_appcast_item.py" "$APPCAST_PATH" "$ITEM"

cat <<EOF

Pronto. Falta:
1. Revisar e commitar o bump de versão + ${APPCAST_PATH##*/}
2. git tag v$VERSION && git push origin v$VERSION
3. Criar o Release no GitHub anexando o zip:
   gh release create v$VERSION "$ZIP_PATH" --title "Versão $VERSION" --notes "..."
4. Fazer push de ${APPCAST_PATH##*/} para main depois da publicação do ZIP
EOF
