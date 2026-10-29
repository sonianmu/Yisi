#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_BUNDLE="${1:-build-app/Release/Yisi.app}"
OUTPUT="${2:-Yisi-Assisted.zip}"
/usr/bin/codesign --verify --deep --strict "${APP_BUNDLE}"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/yisi-assisted.XXXXXXXX")
trap '/bin/rm -rf "${STAGE}"' EXIT
PACKAGE="${STAGE}/Yisi-Assisted"
mkdir -p "${PACKAGE}"
/usr/bin/ditto "${APP_BUNDLE}" "${PACKAGE}/Yisi.app"
/bin/cp scripts/install-assisted.command "${PACKAGE}/Install Yisi.command"
/bin/chmod 755 "${PACKAGE}/Install Yisi.command"
/bin/cp docs/assisted-install.txt "${PACKAGE}/READ ME.txt"
(cd "${PACKAGE}" && /usr/bin/shasum -a 256 Yisi.app/Contents/MacOS/Yisi > SHA256.txt)
/bin/rm -f "${OUTPUT}"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${PACKAGE}" "${OUTPUT}"
printf 'Build complete: %s\n' "${OUTPUT}"
