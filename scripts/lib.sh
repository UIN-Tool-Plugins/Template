#!/usr/bin/env bash
# 构建脚本公共函数。由 build-plugin.sh source，不单独执行。
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR="$ROOT_DIR/build"
TPK_PY="$ROOT_DIR/scripts/tpk.py"

log() { echo "$*"; }
die() { echo "❌ $*" >&2; exit 1; }

tpk() { python3 "$TPK_PY" "$@"; }

find_android_jar() {
    if [ -n "${ANDROID_JAR:-}" ]; then
        [ -f "$ANDROID_JAR" ] || die "ANDROID_JAR 不存在: $ANDROID_JAR"
        printf '%s\n' "$ANDROID_JAR"
        return
    fi

    local bases=()
    [ -n "${ANDROID_HOME:-}" ] && bases+=("$ANDROID_HOME")
    [ -n "${ANDROID_SDK_ROOT:-}" ] && bases+=("$ANDROID_SDK_ROOT")
    bases+=("/usr/lib/android-sdk" "$HOME/Android/Sdk")

    local base candidate platform
    for base in "${bases[@]}"; do
        [ -d "$base/platforms" ] || continue
        if [ -n "${ANDROID_PLATFORM:-}" ] && [ -f "$base/platforms/android-$ANDROID_PLATFORM/android.jar" ]; then
            printf '%s\n' "$base/platforms/android-$ANDROID_PLATFORM/android.jar"
            return
        fi
        candidate=$(ls -d "$base"/platforms/android-*/android.jar 2>/dev/null | sort -V | tail -1 || true)
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return
        fi
    done

    die "找不到 android.jar。设置 ANDROID_HOME / ANDROID_JAR，或在 CI 安装 platforms;android-${ANDROID_PLATFORM:-34}"
}

find_d8() {
    if [ -n "${D8:-}" ]; then
        [ -x "$D8" ] || die "D8 不可执行: $D8"
        printf '%s\n' "$D8"
        return
    fi

    local bases=()
    [ -n "${ANDROID_HOME:-}" ] && bases+=("$ANDROID_HOME")
    [ -n "${ANDROID_SDK_ROOT:-}" ] && bases+=("$ANDROID_SDK_ROOT")
    bases+=("/usr/lib/android-sdk" "$HOME/Android/Sdk")

    local base candidate
    for base in "${bases[@]}"; do
        [ -d "$base/build-tools" ] || continue
        candidate=$(ls -d "$base"/build-tools/*/d8 2>/dev/null | sort -V | tail -1 || true)
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return
        fi
    done

    die "找不到 d8（Android build-tools）。设置 D8，或安装 build-tools"
}

find_host_sdk() {
    local stage=$1 candidate
    for candidate in \
        "$stage/libs/host-sdk.jar" \
        "$stage/host-sdk.jar" \
        "$ROOT_DIR/assets/host-sdk.jar"; do
        if [ -f "$candidate" ]; then
            tpk host-sdk --jar "$candidate" >/dev/null \
                || die "host-sdk.jar 无效: $candidate"
            printf '%s\n' "$candidate"
            return
        fi
    done
    die "找不到 host-sdk.jar（插件 libs/ 或仓库 assets/）"
}

# compile_native <stage_dir> <plugin_id>
compile_native() {
    local stage=$1 plugin_id=$2
    local src_dir="$stage/src"

    if [ ! -d "$src_dir" ]; then
        return 0
    fi
    if ! find "$src_dir" -name '*.java' -print -quit | grep -q .; then
        return 0
    fi

    # 有源码就重新编译，不沿用旧 dex。
    rm -f "$stage/plugin.dex"

    local work="$BUILD_DIR/tmp/$plugin_id"
    rm -rf "$work"
    mkdir -p "$work/classes" "$work/dex"

    local android_jar host_sdk
    android_jar=$(find_android_jar)
    host_sdk=$(find_host_sdk "$stage")

    local -a sources=()
    while IFS= read -r -d '' file; do
        sources+=("$file")
    done < <(find "$src_dir" -name '*.java' -print0 | sort -z)

    log "  🔨 javac (${#sources[@]} 个源文件)"
    javac --release 11 \
        -encoding UTF-8 \
        -Xlint:-options \
        -classpath "$android_jar:$host_sdk" \
        -d "$work/classes" \
        "${sources[@]}" \
        || die "$plugin_id: Java 编译失败"

    local -a classes=()
    while IFS= read -r -d '' file; do
        classes+=("$file")
    done < <(find "$work/classes" -name '*.class' -print0 | sort -z)

    local d8
    d8=$(find_d8)
    log "  🔨 d8 (min-api 23)"
    "$d8" --release --min-api 23 \
        --lib "$android_jar" \
        --classpath "$host_sdk" \
        --output "$work/dex" \
        "${classes[@]}" \
        || die "$plugin_id: D8 失败"

    [ -f "$work/dex/classes.dex" ] || die "$plugin_id: D8 没有产出 classes.dex"
    if [ -f "$work/dex/classes2.dex" ]; then
        die "$plugin_id: 生成了多个 dex；宿主只加载 plugin.dex，请拆分插件"
    fi

    cp "$work/dex/classes.dex" "$stage/plugin.dex"
    log "  ✅ plugin.dex ($(wc -c < "$stage/plugin.dex") bytes)"
}
