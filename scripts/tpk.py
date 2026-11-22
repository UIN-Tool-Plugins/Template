#!/usr/bin/env python3
"""UIN Tool 插件构建工具。

子命令：

  package       把暂存目录打成确定性 TPK（固定时间戳、固定顺序、无目录条目）
  verify        检查 TPK 结构 / JAR v1 签名 / 证书指纹
  index         从 dist 目录生成 source.json
  set-version   把生效版本号写进 plugin.json
  get           读取 plugin.json 字段
  version       计算本次构建应使用的版本号
  meta          写出构建元数据（部署脚本据此更新 dist）
  host-sdk      检查 host-sdk.jar 是否包含公开 API

只用 Python 标准库，CI 和本地都能跑。
"""

import argparse
import base64
import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone

PLUGIN_ID_RE = re.compile(r"^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$")
ZIP_TIME = (1980, 1, 1, 0, 0, 0)

# 这些是构建输入或仓库元数据，不属于运行期插件。
TOP_LEVEL_IGNORES = {
    "type",
    "visible",
    "build.sh",
    "src",
    "libs",
    "data",
    ".gitignore",
    ".tpkignore",
    ".version",
    ".built",
}

ALWAYS_IGNORE_DIRS = {
    ".git",
    ".github",
    ".idea",
    ".gradle",
    "build",
    "dist",
    "out",
    "node_modules",
    "__pycache__",
    ".venv",
    "venv",
    "META-INF",
}

ALWAYS_IGNORE_FILES = {
    ".DS_Store",
    "Thumbs.db",
    ".gitignore",
    ".tpkignore",
    ".version",
    ".built",
}


def log(message):
    print(message, flush=True)


def fail(message):
    print("❌ " + message, file=sys.stderr, flush=True)
    sys.exit(1)


def now_utc():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_fingerprint(value):
    """把 76:65:... / sha256 Fingerprint=... 统一成 64 位小写 hex。"""
    if not value:
        return ""
    hex_only = re.sub(r"[^0-9A-Fa-f]", "", value)
    return hex_only.lower()


def format_fingerprint(value):
    value = normalize_fingerprint(value)
    if len(value) != 64:
        return value
    return ":".join(value[i:i + 2] for i in range(0, 64, 2)).upper()


def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        fail("文件不存在: " + path)
    except json.JSONDecodeError as exc:
        fail("JSON 解析失败: %s (%s)" % (path, exc))


def write_json(path, data):
    parent = os.path.dirname(os.path.abspath(path))
    if parent:
        os.makedirs(parent, exist_ok=True)
    temp = path + ".tmp"
    with open(temp, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    os.replace(temp, path)


def read_text(path, default=""):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return default


def is_hidden_marker(path):
    """visible 标记：0 / false 隐藏；1 / true / 无文件显示。"""
    return read_text(path).lower() in {"0", "false", "off", "no"}


def validate_plugin_json(info, plugin_dir, require_entry=True):
    plugin_id = info.get("pluginId", "")
    if not isinstance(plugin_id, str) or not PLUGIN_ID_RE.match(plugin_id):
        fail("pluginId 不合法: %r（必须像 author.repo.plugin，全小写）" % plugin_id)

    dir_name = os.path.basename(os.path.normpath(plugin_dir))
    if dir_name != plugin_id:
        fail("目录名 %s 与 pluginId %s 不一致" % (dir_name, plugin_id))

    version = info.get("version", 1)
    if not isinstance(version, int) or version < 0:
        fail("version 必须是非负整数，当前为 %r" % version)

    ui_type = info.get("uiType", "")
    if ui_type not in ("web", "cui", "native"):
        fail("uiType 必须是 web / cui / native，当前为 %r" % ui_type)

    version_name = info.get("versionName", "")
    if not isinstance(version_name, str) or not version_name:
        fail("versionName 不能为空")

    min_host = info.get("minHostVersion", 1)
    if not isinstance(min_host, int) or min_host < 1:
        fail("minHostVersion 必须是正整数")

    api_level = info.get("apiLevel", 21)
    if not isinstance(api_level, int) or api_level < 1:
        fail("apiLevel 必须是正整数")

    icon = info.get("icon") or "icon.png"
    icon_path = os.path.join(plugin_dir, icon)
    if not os.path.isfile(icon_path):
        fail("图标不存在: " + icon)
    if os.path.getsize(icon_path) == 0:
        fail("图标是 0 字节: " + icon)
    with open(icon_path, "rb") as handle:
        if handle.read(8) != b"\x89PNG\r\n\x1a\n":
            fail("图标不是 PNG: " + icon)

    if not require_entry:
        return

    if ui_type in ("web", "cui"):
        entry = info.get("entry", "")
        if not isinstance(entry, str) or not entry:
            fail("%s 插件必须填写 entry" % ui_type)
        entry_path = os.path.normpath(os.path.join(plugin_dir, entry))
        root = os.path.normpath(plugin_dir) + os.sep
        if not entry_path.startswith(root):
            fail("entry 不能跳出插件目录: " + entry)
        if not os.path.isfile(entry_path):
            fail("entry 文件不存在: " + entry)
    else:
        main_class = info.get("mainClass", "")
        if not isinstance(main_class, str) or not main_class:
            fail("native 插件必须填写 mainClass")


def load_ignore_patterns(plugin_dir):
    patterns = []
    path = os.path.join(plugin_dir, ".tpkignore")
    if not os.path.isfile(path):
        return patterns
    for line in read_text(path).splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        patterns.append(line)
    return patterns


def should_ignore(rel_path, ui_type, extra_patterns):
    parts = rel_path.split("/")
    name = parts[-1]

    if name in ALWAYS_IGNORE_FILES:
        return True
    if any(part in ALWAYS_IGNORE_DIRS for part in parts):
        return True
    if any(part.startswith(".") for part in parts):
        return True
    if len(parts) == 1 and parts[0] in TOP_LEVEL_IGNORES:
        return True

    # 构建产物和临时文件
    if name.endswith((".tpk", ".class", ".log", ".iml")):
        return True
    if ui_type != "native" and name == "plugin.dex":
        return True

    for pattern in extra_patterns:
        if fnmatch.fnmatch(rel_path, pattern):
            return True
        if pattern.endswith("/") and fnmatch.fnmatch(rel_path, pattern.rstrip("/") + "/*"):
            return True

    return False


def collect_files(plugin_dir, ui_type):
    extra_patterns = load_ignore_patterns(plugin_dir)
    result = []
    for root, dirs, files in os.walk(plugin_dir):
        rel_root = os.path.relpath(root, plugin_dir)
        rel_root = "" if rel_root == "." else rel_root.replace(os.sep, "/")

        kept_dirs = []
        for dir_name in sorted(dirs):
            rel = dir_name if not rel_root else rel_root + "/" + dir_name
            if should_ignore(rel, ui_type, extra_patterns):
                continue
            kept_dirs.append(dir_name)
        dirs[:] = kept_dirs

        for file_name in sorted(files):
            rel = file_name if not rel_root else rel_root + "/" + file_name
            if should_ignore(rel, ui_type, extra_patterns):
                continue
            full = os.path.join(root, file_name)
            if os.path.islink(full):
                fail("TPK 不允许符号链接: " + rel)
            if not os.path.isfile(full):
                continue
            result.append((rel, full))

    result.sort(key=lambda item: item[0])
    return result


def cmd_package(args):
    plugin_dir = os.path.abspath(args.dir)
    if not os.path.isdir(plugin_dir):
        fail("插件目录不存在: " + plugin_dir)

    plugin_json = os.path.join(plugin_dir, "plugin.json")
    info = load_json(plugin_json)
    validate_plugin_json(info, plugin_dir)

    if info.get("uiType") == "native":
        dex = os.path.join(plugin_dir, "plugin.dex")
        if not os.path.isfile(dex):
            fail("native 插件缺少 plugin.dex")
        with open(dex, "rb") as handle:
            if handle.read(4) != b"dex\n":
                fail("plugin.dex 不是有效的 DEX 文件")
        if os.path.getsize(dex) < 16:
            fail("plugin.dex 过小")

    files = collect_files(plugin_dir, info.get("uiType"))
    if not files:
        fail("插件目录里没有可打包的文件")

    output = os.path.abspath(args.output)
    os.makedirs(os.path.dirname(output) or ".", exist_ok=True)
    temp = output + ".tmp"
    if os.path.exists(temp):
        os.remove(temp)

    try:
        with zipfile.ZipFile(temp, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for rel, full in files:
                info_zip = zipfile.ZipInfo(rel, date_time=ZIP_TIME)
                info_zip.compress_type = zipfile.ZIP_DEFLATED
                info_zip.create_system = 3
                mode = os.stat(full).st_mode & 0o777
                info_zip.external_attr = (mode & 0xFFFF) << 16
                with open(full, "rb") as handle:
                    archive.writestr(info_zip, handle.read(), compress_type=zipfile.ZIP_DEFLATED)
        os.replace(temp, output)
    except Exception:
        if os.path.exists(temp):
            os.remove(temp)
        raise

    log("  📦 打包 %d 个文件，%.1f KiB" % (len(files), os.path.getsize(output) / 1024.0))
    return 0


def parse_manifest(raw):
    """返回 (main_section, [entry_names])。支持 72 字节折行。"""
    text = raw.decode("utf-8", "replace")
    sections = []
    current = {}
    last_key = None

    def flush():
        nonlocal current, last_key
        if current:
            sections.append(current)
            current = {}
            last_key = None

    for line in text.splitlines():
        if line == "":
            flush()
            continue
        if line.startswith(" ") and last_key:
            current[last_key] += line[1:]
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        current[key] = value.lstrip(" ")
        last_key = key
    flush()

    main = sections[0] if sections else {}
    names = []
    for section in sections[1:]:
        name = section.get("Name")
        if name:
            names.append(name)
    return main, names


def run_quiet(command, env=None):
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )


def java_tool_env():
    env = dict(os.environ)
    # 让 keytool / jarsigner 输出英文，便于解析。
    env.setdefault("JAVA_TOOL_OPTIONS", "")
    return env


def extract_signer_fingerprint(tpk):
    env = dict(os.environ)
    opts = env.get("JAVA_TOOL_OPTIONS", "")
    env["JAVA_TOOL_OPTIONS"] = (opts + " -Duser.language=en -Duser.country=US").strip()
    result = run_quiet(["keytool", "-printcert", "-jarfile", tpk], env=env)
    if result.returncode != 0:
        return None, "keytool 读不出签名证书: " + result.stdout.strip()
    output = result.stdout
    signers = len(re.findall(r"^Signer #", output, flags=re.MULTILINE))
    if signers == 0:
        signers = len(re.findall(r"^签名者 #", output, flags=re.MULTILINE))
    if signers > 1:
        return None, "TPK 有多个签名者（%d），宿主只接受单一签名" % signers
    match = re.search(r"SHA256:\s*([0-9A-Fa-f:]{95})", output)
    if not match:
        return None, "证书里找不到 SHA-256 指纹"
    return normalize_fingerprint(match.group(1)), None


def cmd_verify(args):
    tpk = os.path.abspath(args.tpk)
    if not os.path.isfile(tpk) or os.path.getsize(tpk) == 0:
        fail("TPK 不存在或为空: " + tpk)

    try:
        archive = zipfile.ZipFile(tpk)
    except zipfile.BadZipFile:
        fail("不是有效的 ZIP/TPK: " + tpk)

    with archive:
        infos = archive.infolist()
        names = [item.filename for item in infos]
        duplicates = sorted({name for name in names if names.count(name) > 1})
        if duplicates:
            fail("TPK 有重复条目: " + ", ".join(duplicates[:5]))

        files = {item.filename for item in infos if not item.filename.endswith("/")}
        meta_files = {name for name in files if name.startswith("META-INF/")}
        sf_files = {name for name in meta_files if name.upper().endswith(".SF")}
        block_files = {
            name
            for name in meta_files
            if name.upper().endswith((".RSA", ".DSA", ".EC"))
        }
        signed = bool(sf_files and block_files)

        if not signed:
            if args.require_signature:
                fail("TPK 未签名（缺少 META-INF/*.SF 或 *.RSA/*.EC）")
            log("  ⚠️  TPK 未签名（本地构建可以，发布前必须签名）")
        else:
            if not sf_files:
                fail("JAR 签名不完整：缺少 .SF")
            if not block_files:
                fail("JAR 签名不完整：缺少 .RSA/.DSA/.EC")

            unexpected = []
            for name in meta_files:
                upper = name.upper()
                if name == "META-INF/MANIFEST.MF":
                    continue
                if upper.endswith(".SF") or upper.endswith((".RSA", ".DSA", ".EC")):
                    continue
                if name.startswith("META-INF/SIG-"):
                    continue
                unexpected.append(name)
            if unexpected:
                fail("META-INF 里有非签名文件: " + ", ".join(unexpected[:5]))

            if "META-INF/MANIFEST.MF" not in files:
                fail("已签名 TPK 缺少 META-INF/MANIFEST.MF")
            _, manifest_names = parse_manifest(archive.read("META-INF/MANIFEST.MF"))
            manifest_names = [
                name for name in manifest_names if not name.startswith("META-INF/")
            ]
            if not manifest_names:
                fail("MANIFEST.MF 没有登记任何业务文件")

            for name in manifest_names:
                if name not in files:
                    fail("MANIFEST.MF 登记了不存在的文件: " + name)
            for name in files:
                if name.startswith("META-INF/"):
                    continue
                if name not in manifest_names:
                    fail("TPK 里有未签名条目: " + name)

            result = run_quiet(
                ["jarsigner", "-verify", "-J-Duser.language=en", tpk],
                env=java_tool_env(),
            )
            output = result.stdout or ""
            if result.returncode != 0 or "jar verified" not in output:
                fail("jarsigner 验签失败:\n" + output.strip())

            fingerprint, error = extract_signer_fingerprint(tpk)
            if error:
                fail(error)
            if args.expected_signer:
                expected = normalize_fingerprint(args.expected_signer)
                if fingerprint != expected:
                    fail(
                        "签名证书不匹配：期望 %s，实际 %s"
                        % (format_fingerprint(expected), format_fingerprint(fingerprint))
                    )
            log("  🔐 签名有效: " + format_fingerprint(fingerprint))

        # ---------- 插件内容检查 ----------
        if "plugin.json" not in files:
            fail("TPK 根目录缺少 plugin.json")
        try:
            info = json.loads(archive.read("plugin.json").decode("utf-8"))
        except Exception as exc:
            fail("TPK 内 plugin.json 无法解析: %s" % exc)

        plugin_id = info.get("pluginId", "")
        if not PLUGIN_ID_RE.match(str(plugin_id)):
            fail("TPK 内 pluginId 不合法: %r" % plugin_id)
        if args.plugin_id and plugin_id != args.plugin_id:
            fail("TPK 内 pluginId %s 与目录 %s 不一致" % (plugin_id, args.plugin_id))

        version = info.get("version")
        if not isinstance(version, int) or version < 1:
            fail("TPK 内 version 必须是正整数，当前为 %r" % version)

        ui_type = info.get("uiType")
        if ui_type not in ("web", "cui", "native"):
            fail("TPK 内 uiType 不合法: %r" % ui_type)

        if ui_type in ("web", "cui"):
            entry = info.get("entry", "")
            if not entry or entry not in files:
                fail("TPK 内 entry 不存在: %r" % entry)
        else:
            if "plugin.dex" not in files:
                fail("native TPK 缺少 plugin.dex")
            head = archive.read("plugin.dex")[:4]
            if head != b"dex\n":
                fail("TPK 内 plugin.dex 不是有效 DEX")

        icon = info.get("icon") or "icon.png"
        if icon not in files:
            fail("TPK 内缺少图标: " + icon)
        icon_info = archive.getinfo(icon)
        if icon_info.file_size == 0:
            fail("TPK 内图标是 0 字节: " + icon)
        if archive.read(icon)[:8] != b"\x89PNG\r\n\x1a\n":
            fail("TPK 内图标不是 PNG: " + icon)

        # 构建输入不应该进包
        forbidden_top = {"type", "build.sh", "visible", "src", "libs", "data"}
        for name in sorted(files):
            top = name.split("/")[0]
            if top in forbidden_top or top in (".git", ".github"):
                fail("TPK 里混入了构建输入: " + name)
            if name.endswith((".tpk", ".class")):
                fail("TPK 里混入了构建产物: " + name)

    log("  ✅ TPK 校验通过 (%s, version %s)" % (plugin_id, version))
    return 0


def cmd_index(args):
    dist_dir = os.path.abspath(args.dist)
    if not os.path.isdir(dist_dir):
        fail("dist 目录不存在: " + dist_dir)

    meta_path = args.meta
    if not meta_path:
        candidate = os.path.join(os.path.dirname(dist_dir), "source.json")
        meta_path = candidate if os.path.isfile(candidate) else os.path.join(dist_dir, "source.json")
    meta = load_json(meta_path) if os.path.isfile(meta_path) else {}

    source_id = meta.get("sourceId", "")
    if not source_id:
        repo = os.environ.get("GITHUB_REPOSITORY", "")
        source_id = repo.split("/")[-1].lower() if repo else "source"

    plugins = []
    plugins_root = os.path.join(dist_dir, "plugins")
    if os.path.isdir(plugins_root):
        for plugin_id in sorted(os.listdir(plugins_root)):
            plugin_dir = os.path.join(plugins_root, plugin_id)
            if not os.path.isdir(plugin_dir) or plugin_id.startswith("."):
                continue

            if is_hidden_marker(os.path.join(plugin_dir, "visible")):
                log("  ⏭️  隐藏（visible=0）: " + plugin_id)
                continue

            plugin_json_path = os.path.join(plugin_dir, "plugin.json")
            if not os.path.isfile(plugin_json_path):
                log("  ⚠️  跳过 %s：缺少 plugin.json" % plugin_id)
                continue

            tpk_path = os.path.join(plugin_dir, plugin_id + ".tpk")
            if not os.path.isfile(tpk_path):
                log("  ⚠️  跳过 %s：缺少 %s.tpk" % (plugin_id, plugin_id))
                continue

            info = load_json(plugin_json_path)
            version_file = os.path.join(plugin_dir, ".version")
            version_text = read_text(version_file)
            if version_text:
                try:
                    version = int(version_text)
                except ValueError:
                    fail("%s 的 .version 不是整数: %r" % (plugin_id, version_text))
            else:
                version = info.get("version", 1)
                if not isinstance(version, int):
                    version = 1
                log("  ⚠️  %s 缺少 .version，按 plugin.json 的 %s 处理" % (plugin_id, version))

            json_version = info.get("version")
            if isinstance(json_version, int) and json_version != version:
                log(
                    "  ⚠️  %s 的 .version=%s 与 plugin.json=%s 不一致，以 .version 为准"
                    % (plugin_id, version, json_version)
                )

            built_file = os.path.join(plugin_dir, ".built")
            last_update = read_text(built_file)
            if not last_update:
                stamp = datetime.fromtimestamp(
                    os.path.getmtime(tpk_path), timezone.utc
                )
                last_update = stamp.strftime("%Y-%m-%dT%H:%M:%SZ")

            sha_file = os.path.join(plugin_dir, ".sha256")
            tpk_sha = read_text(sha_file) or sha256_file(tpk_path)

            signer = read_text(os.path.join(plugin_dir, ".signer"))
            icon_name = info.get("icon") or "icon.png"
            icon_path = os.path.join(plugin_dir, "icon.png")
            if not os.path.isfile(icon_path):
                icon_path = os.path.join(plugin_dir, icon_name)

            entry = {
                "pluginId": plugin_id,
                "name": info.get("name") or plugin_id,
                "version": version,
                "versionName": info.get("versionName", "1.0.0"),
                "author": info.get("author", ""),
                "description": info.get("description", ""),
                "category": info.get("category", ""),
                "uiType": info.get("uiType", ""),
                "size": os.path.getsize(tpk_path),
                "tpkPath": "plugins/%s/%s.tpk" % (plugin_id, plugin_id),
                "sha256": tpk_sha,
                "signed": bool(signer),
                "lastUpdate": last_update,
                "lastUpdated": last_update,
            }
            if signer:
                entry["signerSha256"] = format_fingerprint(signer)
            if os.path.isfile(icon_path):
                entry["iconPath"] = "plugins/%s/icon.png" % plugin_id
            if info.get("updateLog"):
                entry["updateLog"] = str(info["updateLog"])
            if info.get("minHostVersion"):
                entry["minHostVersion"] = info["minHostVersion"]
            if info.get("repositoryUrl"):
                entry["repositoryUrl"] = info["repositoryUrl"]
            elif meta.get("repositoryUrl"):
                entry["repositoryUrl"] = meta["repositoryUrl"]

            plugins.append(entry)

    plugins.sort(key=lambda item: item["pluginId"])
    timestamps = [item["lastUpdate"] for item in plugins if item.get("lastUpdate")]
    top_last_update = max(timestamps) if timestamps else now_utc()

    index = {
        "sourceId": source_id,
        "name": meta.get("name") or source_id,
        "description": meta.get("description", ""),
        "maintainer": meta.get("maintainer", ""),
        "lastUpdated": top_last_update,
        "plugins": plugins,
    }
    if meta.get("repositoryUrl"):
        index["repositoryUrl"] = meta["repositoryUrl"]
    elif os.environ.get("GITHUB_REPOSITORY"):
        index["repositoryUrl"] = "https://github.com/" + os.environ["GITHUB_REPOSITORY"]

    output = args.output or os.path.join(dist_dir, "source.json")
    write_json(output, index)
    log("  ✅ 生成 %s：%d 个可见插件" % (output, len(plugins)))
    return 0


def cmd_set_version(args):
    info = load_json(args.plugin_json)
    info["version"] = args.version
    write_json(args.plugin_json, info)
    log("  📌 %s version -> %d" % (info.get("pluginId", "?"), args.version))
    return 0


def cmd_get(args):
    info = load_json(args.plugin_json)
    value = info.get(args.field, args.default)
    if isinstance(value, bool):
        print("true" if value else "false")
    elif value is None:
        print("")
    else:
        print(value)
    return 0


def cmd_version(args):
    source = args.source
    prev = args.prev
    if prev < 0:
        fail("prev-version 不能是负数")
    if source > 0:
        if prev > 0 and source < prev:
            fail(
                "plugin.json version=%d 小于 dist 里已发布的 %d；"
                "降版本会导致客户端不更新，请提高版本号" % (source, prev)
            )
        if prev > 0 and source == prev and not args.force:
            fail(
                "plugin.json version=%d 与已发布版本相同；"
                "内容有更新时请提高 version，或显式加 --force 重发同版本" % source
            )
        print(source)
        return 0
    # version=0 表示每次构建自动递增
    print(prev + 1 if prev > 0 else 1)
    return 0


def cmd_meta(args):
    tpk = os.path.abspath(args.tpk)
    info = load_json(args.plugin_json)
    signer = read_text(args.signer_file) if args.signer_file else ""
    meta = {
        "pluginId": info.get("pluginId", ""),
        "version": info.get("version", 1),
        "versionName": info.get("versionName", ""),
        "sha256": sha256_file(tpk),
        "size": os.path.getsize(tpk),
        "signed": bool(signer),
        "signerSha256": format_fingerprint(signer) if signer else "",
        "builtAt": now_utc(),
        "pluginJson": info,
    }
    write_json(args.output, meta)
    log("  📝 元数据: " + args.output)
    return 0


def cmd_export_plugin_json(args):
    meta = load_json(args.meta)
    info = meta.get("pluginJson")
    if not isinstance(info, dict):
        fail("构建元数据里没有 pluginJson: " + args.meta)
    write_json(args.output, info)
    log("  📝 导出 plugin.json: " + args.output)
    return 0


def cmd_summary(args):
    meta_dir = os.path.abspath(args.meta_dir)
    print("| 插件 | 版本 | 大小 | 签名 |")
    print("|------|------|------|------|")
    files = sorted(
        os.path.join(meta_dir, name)
        for name in os.listdir(meta_dir)
        if name.endswith(".json")
    ) if os.path.isdir(meta_dir) else []
    for path in files:
        meta = load_json(path)
        print(
            "| `%s` | %s | %.1f KiB | %s |"
            % (
                meta.get("pluginId", "?"),
                meta.get("version", "?"),
                meta.get("size", 0) / 1024.0,
                "已签名" if meta.get("signed") else "未签名",
            )
        )
    if not files:
        print("| — | — | — | 本次没有构建产物 |")
    return 0


def cmd_host_sdk(args):
    jar = os.path.abspath(args.jar)
    if not os.path.isfile(jar):
        fail("host-sdk.jar 不存在: " + jar)
    required = [
        "com/UIN/Tool/plugin/PluginInterface.class",
        "com/UIN/Tool/plugin/PluginContext.class",
    ]
    try:
        with zipfile.ZipFile(jar) as archive:
            names = set(archive.namelist())
    except zipfile.BadZipFile:
        fail("host-sdk.jar 不是有效 ZIP")
    missing = [name for name in required if name not in names]
    if missing:
        fail("host-sdk.jar 缺少公开 API: " + ", ".join(missing))
    log(
        "  ✅ host-sdk.jar 有效：%d 个 class，sha256=%s"
        % (len([name for name in names if name.endswith(".class")]), sha256_file(jar))
    )
    return 0


def cmd_host_sdk_sha(args):
    print(sha256_file(args.jar))
    return 0


def cmd_stage(args):
    """把插件目录复制到暂存区，去掉构建输出和 VCS 内容。"""
    source = os.path.abspath(args.source)
    target = os.path.abspath(args.target)
    if os.path.isdir(target):
        shutil.rmtree(target)
    os.makedirs(target, exist_ok=True)

    ignored = {".git", ".github", ".idea", ".gradle", "dist", "build", "out"}
    for name in os.listdir(source):
        if name in ignored:
            continue
        src = os.path.join(source, name)
        dst = os.path.join(target, name)
        if os.path.isdir(src) and not os.path.islink(src):
            shutil.copytree(src, dst, symlinks=False)
        else:
            shutil.copy2(src, dst)

    # 暂存区里的旧产物一律清掉，避免把上一次的 dex/tpk 打进去。
    for root, dirs, files in os.walk(target):
        for name in files:
            if name.endswith((".tpk", ".class")):
                os.remove(os.path.join(root, name))
    log("  📂 暂存: " + target)
    return 0


def build_parser():
    parser = argparse.ArgumentParser(description="UIN Tool 插件构建工具")
    sub = parser.add_subparsers(dest="command", required=True)

    package = sub.add_parser("package", help="打包确定性 TPK")
    package.add_argument("--dir", required=True, help="已暂存的插件目录")
    package.add_argument("--output", required=True)
    package.set_defaults(func=cmd_package)

    verify = sub.add_parser("verify", help="校验 TPK 结构与签名")
    verify.add_argument("--tpk", required=True)
    verify.add_argument("--plugin-id", default="")
    verify.add_argument("--expected-signer", default="")
    verify.add_argument("--require-signature", action="store_true")
    verify.set_defaults(func=cmd_verify)

    index = sub.add_parser("index", help="生成 source.json")
    index.add_argument("--dist", required=True)
    index.add_argument("--meta", default="")
    index.add_argument("--output", default="")
    index.set_defaults(func=cmd_index)

    set_version = sub.add_parser("set-version", help="写入 plugin.json version")
    set_version.add_argument("--plugin-json", required=True)
    set_version.add_argument("--version", required=True, type=int)
    set_version.set_defaults(func=cmd_set_version)

    get = sub.add_parser("get", help="读取 plugin.json 字段")
    get.add_argument("--plugin-json", required=True)
    get.add_argument("--field", required=True)
    get.add_argument("--default", default="")
    get.set_defaults(func=cmd_get)

    version = sub.add_parser("version", help="计算生效版本号")
    version.add_argument("--source", required=True, type=int)
    version.add_argument("--prev", required=True, type=int)
    version.add_argument("--force", action="store_true")
    version.set_defaults(func=cmd_version)

    meta = sub.add_parser("meta", help="写构建元数据")
    meta.add_argument("--tpk", required=True)
    meta.add_argument("--plugin-json", required=True)
    meta.add_argument("--signer-file", default="")
    meta.add_argument("--output", required=True)
    meta.set_defaults(func=cmd_meta)

    meta_export = sub.add_parser("export-plugin-json", help="从构建元数据导出 plugin.json")
    meta_export.add_argument("--meta", required=True)
    meta_export.add_argument("--output", required=True)
    meta_export.set_defaults(func=cmd_export_plugin_json)

    summary = sub.add_parser("summary", help="输出构建摘要 Markdown")
    summary.add_argument("--meta-dir", required=True)
    summary.set_defaults(func=cmd_summary)

    host_sdk = sub.add_parser("host-sdk", help="检查 host-sdk.jar")
    host_sdk.add_argument("--jar", required=True)
    host_sdk.set_defaults(func=cmd_host_sdk)

    host_sdk_sha = sub.add_parser("host-sdk-sha", help="输出 host-sdk.jar sha256")
    host_sdk_sha.add_argument("--jar", required=True)
    host_sdk_sha.set_defaults(func=cmd_host_sdk_sha)

    stage = sub.add_parser("stage", help="复制插件到暂存目录")
    stage.add_argument("--source", required=True)
    stage.add_argument("--target", required=True)
    stage.set_defaults(func=cmd_stage)

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        fail("已取消")
