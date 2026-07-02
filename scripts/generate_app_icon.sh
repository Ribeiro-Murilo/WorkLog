#!/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Uso: $0 /caminho/para/imagem.png" >&2
  exit 1
fi

SOURCE_IMAGE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICONSET_DIR="$SCRIPT_DIR/../WorkLog/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SOURCE_IMAGE" ]; then
  echo "Arquivo não encontrado: $SOURCE_IMAGE" >&2
  exit 1
fi

WIDTH=$(sips -g pixelWidth "$SOURCE_IMAGE" | awk '/pixelWidth/{print $2}')
HEIGHT=$(sips -g pixelHeight "$SOURCE_IMAGE" | awk '/pixelHeight/{print $2}')
if [ "$WIDTH" != "$HEIGHT" ]; then
  echo "Aviso: a imagem não é quadrada (${WIDTH}x${HEIGHT}); o ícone pode ficar distorcido." >&2
fi

mkdir -p "$ICONSET_DIR"

SIZES=(16 32 128 256 512)

for size in "${SIZES[@]}"; do
  double=$((size * 2))
  sips -z "$size" "$size" "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_${size}x${size}.png" > /dev/null
  sips -z "$double" "$double" "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" > /dev/null
done

cat > "$ICONSET_DIR/Contents.json" << 'EOF'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16", "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16", "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32", "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32", "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF

echo "Ícone do app gerado a partir de: $SOURCE_IMAGE"
