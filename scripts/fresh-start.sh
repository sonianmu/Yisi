#!/bin/bash
# Yisi 本机运行管理（Swift Package → macOS App）
set -euo pipefail
umask 077

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="com.sonianmu.yisi"
KEYCHAIN_SERVICE="com.yisi.app"
APP_BUNDLE="$REPO/build-app/Debug/Yisi.app"
LEGACY_APP_BUNDLE="$REPO/.build_app/Debug/Yisi.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
LOG_DIR="$HOME/Library/Logs/Yisi"
PREFERENCE_DOMAINS=("$BUNDLE_ID" "com.yisi.app" "Yisi")
MODE=""
KEEP_KEYS=0
KEEP_PERMISSIONS=0
DRY_RUN=0
YISI_TEMP_DIR=""
KEYS_NEED_RESTORE=0

usage() {
    cat <<'USAGE'
Yisi 三档启动脚本

用法：./scripts/fresh-start.sh <模式> [选项]

  --close   关闭 Yisi，不清除数据
  --start   构建并启动；已在运行时跳过构建和重复启动
  --new     关闭 → 构建并登记 → 重置授权 → 清除状态 → 重新启动

--new 可选：
  --keep-keys          保留旧版设置及钥匙串中的 API Key
  --keep-permissions   不重置辅助功能、输入监控和截图等系统授权

其他选项：
  --dry-run           只显示操作，不构建、不启动、不关闭、不清理
  -h / --help         显示帮助

注意：--new 会删除配置、预设、历史、历史截图和学习规则。
保留密钥不保留模型和服务地址；这些配置仍会恢复默认值。
--new 只有在构建成功后才清理数据，不删除已安装的 App 或源代码。
USAGE
}

for arg in "$@"; do
    case "$arg" in
        --close|--start|--new)
            if [ -n "$MODE" ]; then echo "只能选择一个模式：--close / --start / --new" >&2; exit 2; fi
            MODE="${arg#--}" ;;
        --keep-keys) KEEP_KEYS=1 ;;
        --keep-permissions) KEEP_PERMISSIONS=1 ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知参数：$arg" >&2; usage >&2; exit 2 ;;
    esac
done
if [ -z "$MODE" ]; then usage; exit 2; fi
if [ "$MODE" != "new" ] && { [ "$KEEP_KEYS" = 1 ] || [ "$KEEP_PERMISSIONS" = 1 ]; }; then
    echo "--keep-keys / --keep-permissions 只能和 --new 一起使用" >&2
    exit 2
fi
if [ "$(uname -s)" != "Darwin" ]; then echo "此脚本仅适用于 macOS。" >&2; exit 1; fi

cleanup() {
    if [ -n "$YISI_TEMP_DIR" ]; then
        if [ "$KEYS_NEED_RESTORE" = 1 ]; then
            echo "密钥恢复未完成，备份保留在：$YISI_TEMP_DIR/api-keys.plist" >&2
        else
            rm -rf -- "$YISI_TEMP_DIR"
        fi
    fi
}
trap cleanup EXIT

run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '  '
        printf '%q ' "$@"
        printf '\n'
    else
        "$@"
    fi
}

# Match executable paths, not command-line arguments containing the project name.
# This excludes the script itself, compiler commands, and YisiTests.
app_pids() {
    ps -axo pid=,comm= | awk -v repo="$REPO/" '
        {
            pid = $1
            sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "")
            if ($0 == "Yisi" || $0 ~ /\/Yisi\.app\/Contents\/MacOS\/Yisi$/ ||
                (index($0, repo) == 1 && $0 ~ /\/Yisi$/)) print pid
        }'
}

app_running() { [ -n "$(app_pids)" ]; }

current_app_running() {
    ps -axo comm= | awk -v executable="$APP_BUNDLE/Contents/MacOS/Yisi" '
        { sub(/^[[:space:]]+/, ""); if ($0 == executable) found = 1 }
        END { exit !found }'
}

signal_app() {
    local pid
    while IFS= read -r pid; do
        if [[ "$pid" =~ ^[0-9]+$ ]]; then kill "-$1" "$pid" 2>/dev/null || true; fi
    done < <(app_pids)
}

close_app() {
    echo "== 关闭 Yisi =="
    if [ "$DRY_RUN" = 1 ]; then
        echo "  向 Yisi App / 当前项目的 Yisi 可执行程序发送 TERM；5 秒后仍未退出则发送 KILL。"
        return
    fi
    if ! app_running; then echo "没有正在运行的 Yisi。"; return; fi
    signal_app TERM
    local attempt
    for ((attempt=0; attempt<20; attempt++)); do
        if ! app_running; then echo "Yisi 已关闭。"; return; fi
        sleep 0.25
    done
    echo "Yisi 未响应，正在强制结束。"
    signal_app KILL
    for ((attempt=0; attempt<8; attempt++)); do
        if ! app_running; then echo "Yisi 已关闭。"; return; fi
        sleep 0.25
    done
    echo "仍有 Yisi 进程无法关闭，已停止后续操作。" >&2
    return 1
}

build_app() {
    echo "== 构建本机 Debug App =="
    if [ "$DRY_RUN" = 1 ]; then
        run swift build --package-path "$REPO" -c debug --product Yisi
        echo "  将编译产物包装到：$APP_BUNDLE"
        echo "  写入 Info.plist（${BUNDLE_ID}），并对完整 App 作 ad-hoc 签名。"
        run "$LSREGISTER" -f "$APP_BUNDLE"
        return
    fi
    local tool bin_dir
    [ -x "$LSREGISTER" ] || { echo "找不到 macOS 应用登记工具：$LSREGISTER" >&2; return 1; }
    for tool in swift codesign plutil open; do
        command -v "$tool" >/dev/null || { echo "缺少命令：$tool。请安装 Xcode Command Line Tools。" >&2; return 1; }
    done
    mkdir -p "$LOG_DIR"
    if ! swift build --package-path "$REPO" -c debug --product Yisi 2>&1 | tee "$LOG_DIR/build.log"; then
        echo "构建失败；配置和历史数据未清理。日志：$LOG_DIR/build.log" >&2
        return 1
    fi
    bin_dir="$(swift build --package-path "$REPO" -c debug --show-bin-path)"
    [ -x "$bin_dir/Yisi" ] || { echo "找不到编译产物：$bin_dir/Yisi" >&2; return 1; }
    mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
    cp "$bin_dir/Yisi" "$APP_BUNDLE/Contents/MacOS/Yisi"
    chmod +x "$APP_BUNDLE/Contents/MacOS/Yisi"
    cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>Yisi</string>
    <key>CFBundleDisplayName</key><string>Yisi</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>Yisi</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSScreenCaptureUsageDescription</key><string>Yisi captures the area you select for screenshot translation.</string>
</dict></plist>
PLIST
    plutil -lint "$APP_BUNDLE/Contents/Info.plist"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
    codesign --verify "$APP_BUNDLE"
    # Retire only the obsolete bundle generated by the previous script. Keeping
    # two bundles with the same identity can route a restart to the old executable.
    if [ -d "$LEGACY_APP_BUNDLE" ]; then
        run "$LSREGISTER" -u "$LEGACY_APP_BUNDLE"
        local archive
        archive="$(mktemp -d "$REPO/.build_app/retired.XXXXXX")"
        run mv "$LEGACY_APP_BUNDLE" "$archive/Yisi.app.disabled"
        echo "旧开发 App 已停用并保留在：$archive/Yisi.app.disabled"
    fi
    # tccutil resolves bundle IDs through Launch Services. A newly packaged App
    # must be registered before its first launch or permission reset.
    run "$LSREGISTER" -f "$APP_BUNDLE"
    echo "构建完成：$APP_BUNDLE"
}

reset_permissions() {
    if [ "$KEEP_PERMISSIONS" = 1 ]; then
        echo "保留系统授权（--keep-permissions，不保证系统在重新签名后仍认可旧授权）。"
        return
    fi
    echo "== 重置 Yisi 系统授权 =="
    local permission output status
    for permission in Accessibility ListenEvent PostEvent ScreenCapture; do
        if [ "$DRY_RUN" = 1 ]; then
            run tccutil reset "$permission" "$BUNDLE_ID"
        elif output="$(tccutil reset "$permission" "$BUNDLE_ID" 2>&1)"; then
            echo "已重置 $permission 授权。"
        else
            status=$?
            case "$output" in
                *"No such bundle identifier \"$BUNDLE_ID\""*)
                    # Launch Services can still take time to resolve a first-run bundle.
                    # Do not turn this known missing-ID condition into a startup failure.
                    echo "macOS 尚未识别 Yisi 的应用标识，跳过本次系统授权重置并继续启动。" >&2
                    echo "首次使用时请完成系统授权；若仍有旧授权记录，请在系统设置中检查。" >&2
                    return ;;
                *)
                    printf '%s\n' "$output" >&2
                    echo "无法重置 $permission 授权（退出码 ${status}）；数据尚未清理，已停止重置。" >&2
                    return 1 ;;
            esac
        fi
    done
}

preserve_preference_keys() {
    if [ "$KEEP_KEYS" = 0 ]; then return; fi
    if [ "$DRY_RUN" = 1 ]; then
        echo "  在受限临时目录中提取旧版 API Key；重置后恢复到 ${BUNDLE_ID}。"
        return
    fi
    YISI_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/yisi-fresh-start.XXXXXX")"
    local domain index=0
    for domain in "${PREFERENCE_DOMAINS[@]}"; do
        if defaults read "$domain" >/dev/null 2>&1; then
            defaults export "$domain" "$YISI_TEMP_DIR/preferences-$index.plist"
        fi
        index=$((index+1))
    done
    # Keep secrets out of shell output and command-line arguments. First domain wins.
    cat > "$YISI_TEMP_DIR/keep-keys.swift" <<'SWIFT'
import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
var keys: [String: String] = [:]
for index in 0..<3 {
    let url = directory.appendingPathComponent("preferences-\(index).plist")
    guard FileManager.default.fileExists(atPath: url.path) else { continue }
    let data = try Data(contentsOf: url)
    guard let preferences = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        throw NSError(domain: "YisiFreshStart", code: 1)
    }
    for (key, value) in preferences where key.hasSuffix("_api_key") {
        if keys[key] == nil, let value = value as? String { keys[key] = value }
    }
}
let data = try PropertyListSerialization.data(fromPropertyList: keys, format: .xml, options: 0)
try data.write(to: directory.appendingPathComponent("api-keys.plist"), options: .atomic)
SWIFT
    swift "$YISI_TEMP_DIR/keep-keys.swift" "$YISI_TEMP_DIR"
}

wipe_state() {
    echo "== 清除 Yisi 状态（历史、截图、学习规则、预设与配置） =="
    preserve_preference_keys
    local domain status count=0
    for domain in "${PREFERENCE_DOMAINS[@]}"; do
        if [ "$DRY_RUN" = 0 ] && [ "$KEEP_KEYS" = 1 ] && [ "$domain" = "$BUNDLE_ID" ]; then
            KEYS_NEED_RESTORE=1
        fi
        if [ "$DRY_RUN" = 1 ]; then run defaults delete "$domain"
        elif defaults read "$domain" >/dev/null 2>&1; then defaults delete "$domain"
        fi
        # Restore retained keys before any directory removal can fail.
        if [ "$KEEP_KEYS" = 1 ] && [ "$domain" = "$BUNDLE_ID" ]; then
            if [ "$DRY_RUN" = 1 ]; then
                echo "  恢复旧版 API Key，保留 $KEYCHAIN_SERVICE 钥匙串项目。"
            else
                defaults import "$BUNDLE_ID" "$YISI_TEMP_DIR/api-keys.plist"
                KEYS_NEED_RESTORE=0
            fi
        fi
        run rm -rf -- "$HOME/Library/Caches/$domain" "$HOME/Library/HTTPStorages/$domain" \
            "$HOME/Library/Saved Application State/$domain.savedState" \
            "$HOME/Library/Application Support/$domain"
    done
    run rm -rf -- "$HOME/Library/Application Support/Yisi" "$HOME/Documents/HistoryImages"
    run rm -f -- "$HOME/Documents/YisiHistory.sqlite" "$HOME/Documents/YisiHistory.sqlite-wal" \
        "$HOME/Documents/YisiHistory.sqlite-shm" "$LOG_DIR/app.log"
    if [ "$KEEP_KEYS" = 1 ]; then
        echo "API Key 已保留；模型和服务地址会恢复默认配置。"
    elif [ "$DRY_RUN" = 1 ]; then
        echo "  删除服务 $KEYCHAIN_SERVICE 下的全部通用密码项目（包括自定义服务密钥）。"
    else
        while true; do
            if security delete-generic-password -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1; then
                count=$((count+1))
            else
                status=$?
                # errSecItemNotFound (-25300), represented as the CLI exit code 44.
                if [ "$status" != 44 ]; then
                    echo "钥匙串清理失败（退出码 ${status}），部分密钥可能尚未删除。" >&2
                    return 1
                fi
                break
            fi
        done
        echo "已删除 $count 个钥匙串项目。"
    fi
    echo "状态清理完成。"
}

launch_app() {
    echo "== 启动 Yisi =="
    run mkdir -p "$LOG_DIR"
    run touch "$LOG_DIR/app.log"
    # Argument-domain preference: disable update prompts for this development run only.
    # No saved preference is changed, and manual update checks remain available.
    run open -n --stdout "$LOG_DIR/app.log" --stderr "$LOG_DIR/app.log" "$APP_BUNDLE" --args -auto_check_updates NO
    if [ "$DRY_RUN" = 1 ]; then return; fi
    local attempt
    for ((attempt=0; attempt<40; attempt++)); do
        if current_app_running; then echo "Yisi 已启动：${APP_BUNDLE}。日志：$LOG_DIR/app.log"; return; fi
        sleep 0.25
    done
    echo "Yisi 未能启动，查看日志：$LOG_DIR/app.log" >&2
    return 1
}

cd "$REPO"
case "$MODE" in
    close) close_app ;;
    start)
        if [ "$DRY_RUN" = 0 ] && current_app_running; then
            echo "Yisi 已在运行，跳过构建与重复启动。加载新代码请先 --close 再 --start。"
        else
            if [ "$DRY_RUN" = 0 ] && app_running; then
                echo "正在关闭旧路径的 Yisi，以启动当前开发 App。"
                close_app
            fi
            build_app
            launch_app
        fi ;;
    new)
        close_app
        build_app
        reset_permissions
        wipe_state
        launch_app
        if [ "$DRY_RUN" = 1 ]; then
            echo "== 演练完成：未修改数据或应用状态 =="
        else
            echo "== 完成：按全新状态启动 Yisi =="
        fi ;;
esac
