#!/bin/bash
# Compila todas as fontes/testes em um pacote temporário, sem lançar WorkLog.app.
# Uso: scripts/test-headless.sh [--filter expressão]
set -euo pipefail

if [[ $# -ne 0 && ( $# -ne 2 || "$1" != "--filter" ) ]]; then
    echo "Uso: $0 [--filter expressão]" >&2
    exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/worklog-headless.XXXXXX")"
CACHE_DIR="${HOME}/Library/Caches/WorkLog/headless-swiftpm"
mkdir -p "$CACHE_DIR"

# A seleção de fontes é automática: novos arquivos entram no próximo teste.
ln -s "$ROOT_DIR/WorkLog" "$RUN_DIR/WorkLog"
ln -s "$ROOT_DIR/WorkLogTests" "$RUN_DIR/WorkLogTests"

python3 - "$ROOT_DIR" "$RUN_DIR" <<'PY'
import glob
import json
import os
from pathlib import Path
import re
import subprocess
import sys

root, run = map(Path, sys.argv[1:])
resolved = root / "WorkLog.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
pins = json.loads(resolved.read_text())["pins"]
pin = next(pin for pin in pins if pin["identity"].lower() == "sparkle")
version, revision = pin["state"]["version"], pin["state"]["revision"]
project = (root / "WorkLog.xcodeproj/project.pbxproj").read_text()
deployment = re.search(r"MACOSX_DEPLOYMENT_TARGET = ([\d.]+);", project).group(1)

# Reutiliza somente um binário cujo checkout e metadados correspondam ao pin.
patterns = [
    str(Path.home() / "Library/Developer/Xcode/DerivedData/WorkLog-*/SourcePackages"),
    "/tmp/worklog-*/SourcePackages",
    str(Path(os.environ.get("TMPDIR", "/tmp")) / "worklog-*/SourcePackages"),
]
artifact = None
for source_packages in sorted({path for pattern in patterns for path in glob.glob(pattern)}):
    packages = Path(source_packages)
    checkout = packages / "checkouts/Sparkle"
    state_file = packages / "workspace-state.json"
    if not checkout.is_dir() or not state_file.is_file():
        continue
    head = subprocess.run(
        ["git", "-C", str(checkout), "rev-parse", "HEAD"],
        capture_output=True, text=True, check=False,
    )
    if head.returncode or head.stdout.strip() != revision:
        continue
    state = json.loads(state_file.read_text()).get("object", {})
    for item in state.get("artifacts", []):
        source = item.get("source", {})
        if (item.get("targetName") == "Sparkle"
                and f"/download/{version}/" in source.get("url", "")
                and Path(item["path"]).is_dir()):
            artifact = Path(item["path"])
            break
    if artifact:
        break

if artifact:
    (run / "Sparkle.xcframework").symlink_to(artifact, target_is_directory=True)
    dependencies = "[]"
    sparkle_target = '.binaryTarget(name: "Sparkle", path: "Sparkle.xcframework"),'
    target_dependency = '"Sparkle"'
    print(f"Sparkle {version}: cache local {artifact}")
else:
    dependencies = f'[.package(url: {json.dumps(pin["location"])}, exact: {json.dumps(version)})]'
    sparkle_target = ""
    target_dependency = '.product(name: "Sparkle", package: "Sparkle")'
    print(f"Sparkle {version}: resolução pela versão exata do Package.resolved")

manifest = f'''// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WorkLogHeadless",
    platforms: [.macOS("{deployment}")],
    dependencies: {dependencies},
    targets: [
        {sparkle_target}
        .target(
            name: "WorkLog",
            dependencies: [{target_dependency}],
            path: "WorkLog",
            exclude: ["App/WorkLogApp.swift", "Info.plist", "Assets.xcassets"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "WorkLogTests", dependencies: ["WorkLog"], path: "WorkLogTests")
    ],
    swiftLanguageModes: [.v5]
)
'''
(run / "Package.swift").write_text(manifest)
PY

echo "Pacote e log: $RUN_DIR"
# O runner Swift Testing executa sequencialmente, pois a suite compartilha SwiftData.
# Somente o executável de testes do SwiftPM é iniciado; @main do app foi excluído.
swift test --package-path "$RUN_DIR" --cache-path "$CACHE_DIR" \
    --no-parallel --disable-xctest --enable-swift-testing "$@" \
    2>&1 | tee "$RUN_DIR/test.log"
