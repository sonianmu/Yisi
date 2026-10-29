#!/bin/bash
set -euo pipefail

PAYLOAD_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SOURCE="${PAYLOAD_DIR}/Yisi.app"
DRY_RUN=0
case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    *) printf 'Usage: bash "%s" [--dry-run]\n' "$0"; exit 2 ;;
esac

fail() { printf '\n安装未完成 / Installation stopped: %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "This installer requires macOS."
[ -d "${SOURCE}" ] && [ ! -L "${SOURCE}" ] || fail "Missing Yisi.app beside this script."
IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${SOURCE}/Contents/Info.plist")
[ "${IDENTIFIER}" = "com.sonianmu.yisi" ] || fail "Unexpected app identifier."
/usr/bin/codesign --verify --deep --strict "${SOURCE}" || fail "The app signature is invalid. Download the package again."
(cd "${PAYLOAD_DIR}" && /usr/bin/shasum -a 256 -c SHA256.txt) || fail "Payload checksum mismatch."

DESTINATION="/Applications"
if [ ! -w "${DESTINATION}" ] || { [ -e "${DESTINATION}/Yisi.app" ] && [ ! -w "${DESTINATION}/Yisi.app" ]; }; then
    DESTINATION="${HOME}/Applications"
fi
TARGET="${DESTINATION}/Yisi.app"
[ ! -L "${TARGET}" ] || fail "The destination is a symbolic link; resolve it manually first."

printf '\nYisi 辅助安装 / Assisted installation\n\n'
printf '安装位置 / Destination: %s\n' "${TARGET}"
printf '只移除这一份 Yisi 的 com.apple.quarantine 下载隔离标记。\n'
printf 'This removes download quarantine from this Yisi copy only.\n'
printf '不会关闭 Gatekeeper、SIP，不会修改或授予录屏、辅助功能权限。\n'
printf 'Gatekeeper, SIP and privacy permissions stay unchanged.\n'
printf '此包未经过 Apple 公证。仅在信任下载来源时继续。\n'
printf 'This package is not notarized by Apple. Continue only if you trust its source.\n'
printf '已安装版本会保留备份；请先退出正在运行的 Yisi。\n'
printf 'Any installed copy is backed up. Quit Yisi before continuing.\n\n'

if [ "${DRY_RUN}" = "1" ]; then
    printf 'Dry run: no files or security settings changed.\n'
    exit 0
fi

printf '继续安装？/ Continue? [y/N] '
read -r CONFIRM
case "${CONFIRM}" in y|Y) ;; *) printf '已取消 / Cancelled.\n'; exit 0 ;; esac
if /usr/bin/pgrep -x Yisi >/dev/null; then
    fail "请退出 Yisi 后重试 / Quit Yisi and retry."
fi

mkdir -p "${DESTINATION}"
STAGE=$(mktemp -d "${DESTINATION}/.Yisi-install.XXXXXXXX")
BACKUP=""
INSTALLED=0
rollback() {
    local result=$?
    trap - EXIT
    if [ "${result}" -ne 0 ] && [ "${INSTALLED}" = "1" ]; then
        /bin/mv "${TARGET}" "${STAGE}/failed-Yisi.app"
    fi
    if [ "${result}" -ne 0 ] && [ -n "${BACKUP}" ] && [ -d "${BACKUP}/Yisi.app.disabled" ] && [ ! -e "${TARGET}" ]; then
        /bin/mv "${BACKUP}/Yisi.app.disabled" "${TARGET}"
    fi
    /bin/rm -rf "${STAGE}"
    exit "${result}"
}
trap rollback EXIT

/usr/bin/ditto "${SOURCE}" "${STAGE}/Yisi.app"
/usr/bin/xattr -dr com.apple.quarantine "${STAGE}/Yisi.app"
/usr/bin/codesign --verify --deep --strict "${STAGE}/Yisi.app"
if [ -e "${TARGET}" ]; then
    BACKUP=$(mktemp -d "${DESTINATION}/.Yisi-previous.XXXXXXXX")
    /bin/mv "${TARGET}" "${BACKUP}/Yisi.app.disabled"
fi
/bin/mv "${STAGE}/Yisi.app" "${TARGET}"
INSTALLED=1
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${TARGET}"
/usr/bin/open "${TARGET}"
printf '\n安装完成 / Installed: %s\n' "${TARGET}"
if [ -n "${BACKUP}" ]; then printf '旧版本备份 / Previous version: %s/Yisi.app.disabled\n' "${BACKUP}"; fi
printf '录屏与辅助功能仍需由您在系统设置中授权。\n'
printf 'Screen recording and Accessibility still require your permission in System Settings.\n'
