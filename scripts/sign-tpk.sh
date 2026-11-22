#!/usr/bin/env bash
# sign-tpk.sh <file.tpk>
#
# 给 TPK 写 JAR v1 签名。密钥来源（二选一）：
#   PLUGIN_KEYSTORE_BASE64   keystore 整份文件的 base64（CI 用）
#   PLUGIN_KEYSTORE          keystore 文件路径（本地用）
#
# 其它环境变量：
#   PLUGIN_STORE_PASSWORD    库口令（必需）
#   PLUGIN_KEY_PASSWORD      密钥口令（默认同库口令）
#   PLUGIN_KEY_ALIAS         别名（必需）
#   PLUGIN_KEYSTORE_TYPE     JKS / PKCS12（默认按文件头自动判断）
#   PLUGIN_CERT_SHA256       期望证书 SHA-256（可选，填了就强校验）
#
# 成功时向 stdout 输出一行签名证书的 SHA-256（冒号分隔大写），
# 日志一律走 stderr，方便调用方用 $(...) 取值。
#
# 退出码：
#   0   已签名
#   10  没有配置密钥（由调用方决定是否允许未签名）
#   其它 签名失败
set -euo pipefail

TPK=${1:-}
if [ -z "$TPK" ] || [ ! -f "$TPK" ]; then
    echo "❌ sign-tpk.sh: TPK 不存在: ${TPK:-<empty>}" >&2
    exit 1
fi

log() { echo "  $*" >&2; }
die() { echo "❌ $*" >&2; exit 1; }

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tpk-sign.XXXXXX")
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

KEYSTORE=""
if [ -n "${PLUGIN_KEYSTORE_BASE64:-}" ]; then
    KEYSTORE="$TMP_DIR/keystore.p12"
    # GNU base64 用 -d，BSD/macOS 用 -D。
    printf '%s' "$PLUGIN_KEYSTORE_BASE64" | base64 -d > "$KEYSTORE" 2>/dev/null \
        || printf '%s' "$PLUGIN_KEYSTORE_BASE64" | base64 -D > "$KEYSTORE" 2>/dev/null \
        || die "PLUGIN_KEYSTORE_BASE64 不是有效的 base64"
elif [ -n "${PLUGIN_KEYSTORE:-}" ]; then
    [ -f "$PLUGIN_KEYSTORE" ] || die "PLUGIN_KEYSTORE 不存在: $PLUGIN_KEYSTORE"
    KEYSTORE=$PLUGIN_KEYSTORE
else
    exit 10
fi

if [ ! -s "$KEYSTORE" ]; then
    die "keystore 是空文件"
fi

[ -n "${PLUGIN_STORE_PASSWORD:-}" ] || die "缺少 PLUGIN_STORE_PASSWORD"
[ -n "${PLUGIN_KEY_ALIAS:-}" ] || die "缺少 PLUGIN_KEY_ALIAS"
export PLUGIN_STORE_PASSWORD
export PLUGIN_KEY_PASSWORD=${PLUGIN_KEY_PASSWORD:-$PLUGIN_STORE_PASSWORD}

STORE_TYPE=${PLUGIN_KEYSTORE_TYPE:-}
if [ -z "$STORE_TYPE" ]; then
    MAGIC=$(od -An -tx1 -N4 "$KEYSTORE" | tr -d ' \n')
    if [ "$MAGIC" = "feedfeed" ]; then
        STORE_TYPE=JKS
    else
        STORE_TYPE=PKCS12
    fi
fi

keytool -J-Duser.language=en -list \
    -keystore "$KEYSTORE" -storetype "$STORE_TYPE" \
    -storepass:env PLUGIN_STORE_PASSWORD >/dev/null 2>&1 \
    || die "keystore 打不开：检查文件、PLUGIN_STORE_PASSWORD 和 PLUGIN_KEYSTORE_TYPE"

if ! keytool -J-Duser.language=en -list \
    -keystore "$KEYSTORE" -storetype "$STORE_TYPE" \
    -storepass:env PLUGIN_STORE_PASSWORD -alias "$PLUGIN_KEY_ALIAS" >/dev/null 2>&1; then
    die "keystore 里没有别名 $PLUGIN_KEY_ALIAS"
fi

actual_fp=$(keytool -J-Duser.language=en -list -v \
    -keystore "$KEYSTORE" -storetype "$STORE_TYPE" \
    -storepass:env PLUGIN_STORE_PASSWORD -alias "$PLUGIN_KEY_ALIAS" \
    | sed -n 's/.*SHA256: *//p' | head -1)

if [ -n "${PLUGIN_CERT_SHA256:-}" ]; then
    expected_norm=$(printf '%s' "$PLUGIN_CERT_SHA256" | tr -d ' :' | tr '[:upper:]' '[:lower:]')
    actual_norm=$(printf '%s' "$actual_fp" | tr -d ' :' | tr '[:upper:]' '[:lower:]')
    if [ "$expected_norm" != "$actual_norm" ]; then
        die "keystore 证书指纹不匹配：期望 $PLUGIN_CERT_SHA256，实际 $actual_fp"
    fi
fi

log "签名 ${TPK}（$STORE_TYPE / $PLUGIN_KEY_ALIAS）"
jarsigner \
    -keystore "$KEYSTORE" \
    -storetype "$STORE_TYPE" \
    -storepass:env PLUGIN_STORE_PASSWORD \
    -keypass:env PLUGIN_KEY_PASSWORD \
    -digestalg SHA-256 \
    "$TPK" "$PLUGIN_KEY_ALIAS" >/dev/null \
    || die "jarsigner 签名失败"

verify_output=$(jarsigner -verify -J-Duser.language=en "$TPK" 2>&1) \
    || die "签名后验签失败:\n$verify_output"
case "$verify_output" in
    *"jar verified"*) ;;
    *) die "签名后验签失败:\n$verify_output" ;;
esac

# 取 TPK 内实际签名证书，而不是 keystore 里的，防止签错 key。
signed_fp=$(keytool -J-Duser.language=en -printcert -jarfile "$TPK" 2>/dev/null \
    | sed -n 's/.*SHA256: *//p' | head -1)
[ -n "$signed_fp" ] || die "无法从 TPK 读取签名证书"

if [ -n "${PLUGIN_CERT_SHA256:-}" ]; then
    signed_norm=$(printf '%s' "$signed_fp" | tr -d ' :' | tr '[:upper:]' '[:lower:]')
    expected_norm=$(printf '%s' "$PLUGIN_CERT_SHA256" | tr -d ' :' | tr '[:upper:]' '[:lower:]')
    if [ "$signed_norm" != "$expected_norm" ]; then
        die "TPK 签名证书与 PLUGIN_CERT_SHA256 不一致：$signed_fp"
    fi
fi

log "🔐 已签名: $signed_fp"
printf '%s\n' "$signed_fp"
