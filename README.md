# Template

UIN Tool 插件仓库模板。fork 后改 `source.json`、在 `plugins/` 下加插件，推送到 `main`，GitHub Actions 会构建并发布到 `dist` 分支。

## 快速开始

1. Fork 此仓库
2. 修改 `source.json`（`sourceId`、名称、描述、维护者）
3. 在 `plugins/` 下创建插件；示例插件默认 `visible=1`（显示），改成 `0` 即隐藏（仍构建发布，只是不进源列表）
4. 推送到 `main`
5. 在 UIN Tool：软件 → 插件源管理 → 添加 → 输入仓库地址

## 仓库结构

```
.
├── .github/workflows/build.yml    CI：构建 → 签名（可选）→ 发布 dist
├── assets/
│   ├── host-sdk.jar               原生插件编译用的宿主公开 API
│   └── host-sdk.sha256            固定版本，CI 强校验
├── scripts/
│   ├── build-plugin.sh            单个插件完整构建
│   ├── build-all.sh               本地批量构建
│   ├── changed-plugins.sh         CI 计算本次要构建的插件
│   ├── check-host-sdk.sh          校验 host-sdk.jar
│   ├── deploy-dist.sh             同步 dist、生成索引、推送
│   ├── generate-index.sh          生成 source.json 的入口
│   ├── lib.sh                     javac / d8 / 路径查找
│   ├── sign-tpk.sh                JAR v1 签名
│   ├── tpk.py                     打包 / 验签 / 索引 / 版本
│   └── update-host-sdk.sh         从 UIN Tool 工程同步 SDK
├── plugins/
│   └── your.author.pluginname/
│       ├── type                   构建方式（空 / native / other）
│       ├── visible                1 = 在源列表显示，0 = 隐藏
│       ├── plugin.json            插件元数据
│       ├── icon.png               PNG 图标
│       └── ...                    web/、scripts/、src/ 等
├── source.json                    源元数据
└── README.md
```

## 插件目录

### pluginId

- 格式：`作者.仓库.插件名`，例如 `your.name.hello`
- 只用小写字母、数字、下划线、点；每段以字母开头
- **目录名必须与 `plugin.json` 的 `pluginId` 完全一致**

### type

在插件根目录创建 `type` 文件：

| `type` 内容 | 构建方式 | 需要的文件 |
|-------------|----------|-----------|
| 空文件 | 直接打包 | `plugin.json`、图标、入口 |
| `native` | Java → DEX | `src/**/*.java`，或预编译 `plugin.dex` |
| `other` | 执行 `build.sh` | `build.sh` |

`type=native` 时 `plugin.json` 的 `uiType` 必须是 `native`。

### visible

| 内容 | 效果 |
|------|------|
| 无文件 / `1` / `true` | 显示在插件源列表 |
| `0` / `false` | 构建发布，但不写入 `source.json` |

模板自带的示例都是 `visible=1`，会直接出现在源列表里。不想让某个示例出现在列表时，把它的 `visible` 改成 `0`。

### plugin.json

最小 Web 插件：

```json
{
  "pluginId": "your.name.hello",
  "name": "Hello",
  "version": 0,
  "versionName": "1.0.0",
  "author": "YourName",
  "description": "插件描述",
  "category": "示例",
  "uiType": "web",
  "entry": "web/index.html"
}
```

`version`：

| 源仓库 version | 行为 |
|----------------|------|
| `0` | 每次构建在 dist 上次版本上 +1，推荐 |
| `>=1` | 固定版本；必须大于 dist 上次版本，否则构建失败 |

生效版本写进 TPK 内的 `plugin.json` 和 `dist/source.json`，源文件不会被改写。

其它常用字段：

| 字段 | 说明 |
|------|------|
| `uiType` | `web` / `cui` / `native` |
| `entry` | web/cui 入口，相对于插件根目录 |
| `mainClass` | native 插件的入口类 |
| `icon` | 图标路径，默认 `icon.png` |
| `minHostVersion` | 最低宿主 versionCode |
| `apiLevel` | 最低 Android API |
| `backend` | 有后端时填 `other`（统一启动命令模式） |
| `backendStartCommand` | 后端启动命令，例如 `python3 scripts/backend/server.py` |
| `backendAutoStart` | 是否自动启动后端 |
| `backendHealthCheck` | 健康检查路径，例如 `/health` |
| `notice` | 插件说明 |

旧字段 `backend: "python"` / `"node"` / `"php"` 仍兼容，客户端会迁移成 `other` + 启动命令；新插件建议直接写 `other`。

### 图标

- PNG，不能是 0 字节
- 建议 256×256，不超过 500 KiB
- 自定义 `icon` 路径也可以，发布时会统一复制成 `dist/plugins/<id>/icon.png`

### 各类型示例

**纯 Web**

```
plugins/your.name.hello/
├── type              ← 空文件
├── plugin.json       ← uiType: "web", entry: "web/index.html"
├── icon.png
└── web/index.html
```

**Web + 后端**

```
plugins/your.name.calc/
├── type
├── plugin.json       ← uiType: "web", backend: "other"
├── icon.png
├── web/index.html
└── scripts/
    ├── start.sh
    └── backend/server.py
```

**Native**

```
plugins/your.name.native/
├── type              ← native
├── plugin.json       ← uiType: "native", mainClass: "com.example.MainPlugin"
├── icon.png
└── src/com/example/MainPlugin.java
```

构建使用 `javac --release 11` + `d8 --min-api 23`，只接受单个 `plugin.dex`。没有源码时可以直接提交预编译 `plugin.dex`。

**CUI**

```
plugins/your.name.cui/
├── type              ← 空文件
├── plugin.json       ← uiType: "cui", entry: "scripts/main.sh"
├── icon.png
└── scripts/main.sh
```

**C / 自定义构建**

```
plugins/your.name.c/
├── type              ← other
├── build.sh          ← 编译到暂存目录
├── plugin.json       ← uiType: "cui", backend: "other"
├── icon.png
├── src/server.c
└── scripts/main.sh
```

`build.sh` 约定：

```bash
build.sh <暂存目录> <输出.tpk>
```

- 产物写到 `"$1"` 内，例如 `"$1/server"`。
- 不要自己打包；构建脚本会统一打包、签名。
- 旧脚本如果仍生成 `$2`，会直接使用并做同样校验。
- 打包自动排除 `type`、`visible`、`build.sh`、`src/`、`libs/`、`data/`、`*.tpk`、`*.class`。

C 示例的后端运行在插件实际使用的环境里：内置 proot 是 Debian (glibc)，实体 Termux 是 Android (bionic)。同时兼容两者的是**静态链接的 Linux aarch64 可执行文件**，`build.sh` 优先使用 `aarch64-linux-gnu-gcc -static`，并检查产物必须是 `ARM aarch64` 且 `statically linked`。Android NDK 的 bionic 动态可执行文件在 Debian 容器里缺少 `/system/bin/linker64`，不能作为后端。

宿主解压 TPK 不会保留 Unix 可执行位，共享存储通常也是 `noexec`。示例的 `scripts/start.sh` 会先把二进制复制到可执行目录再 `exec`：依次尝试 `$TMPDIR`、`/tmp`、`$HOME`，适配内置 proot 与实体 Termux。`backendStartCommand` 写 `sh scripts/start.sh`。

### .tpkignore

可选，每行一个 glob，匹配相对路径（`#` 注释）。用于额外排除不想进包的文件，不能反向包含默认排除的构建输入。

## 构建与发布

推送 `main` 后：

1. 根据 diff 找出改动的插件；`scripts/`、`assets/`、workflow 改动时全量构建
2. 从 `dist` 读取上次版本
3. 暂存 → 校验 → 编译/执行 build.sh → 打包 → 签名 → 验签
4. 同步 `dist/plugins/<id>/`，删除已移除的插件
5. 生成 `dist/source.json`，提交并推送（冲突自动 rebase 重试）

同一个仓库的发布有 `concurrency` 锁，不会两个 job 同时改 `dist`。在 Actions 页面手动 Run workflow 会全量构建。

## 签名（可选，强烈建议）

模板仓库默认 `REQUIRE_SIGNING=0`：没有密钥也能构建，但产物是未签名 TPK，客户端会显示「未知签名」。

正式发布建议：

1. 生成 keystore：`keytool -genkeypair -keystore release.p12 -storetype PKCS12 -alias plugin -keyalg RSA -keysize 4096 -validity 10000`
2. 仓库 Settings → Secrets and variables → Actions 添加：

| Secret | 说明 |
|--------|------|
| `PLUGIN_KEYSTORE_BASE64` | `base64 -w0 release.p12` |
| `PLUGIN_STORE_PASSWORD` | keystore 口令 |
| `PLUGIN_KEY_PASSWORD` | 密钥口令，PKCS12 可留空 |
| `PLUGIN_KEY_ALIAS` | 别名，例如 `plugin` |
| `PLUGIN_CERT_SHA256` | 证书 SHA-256，可选但推荐 |

3. 把 `.github/workflows/build.yml` 里的 `REQUIRE_SIGNING: '0'` 改成 `'1'`

签名规则：

- TPK 使用 **JAR v1 签名**（`META-INF/MANIFEST.MF` + `.SF` + `.RSA/.EC`）。
- 客户端按证书指纹判断身份；非官方签名安装时会要求确认。
- 已签名插件不能被无签名包更新；换签名会强警告后允许。
- 不要把 keystore、base64、口令提交到仓库或贴进 issue。

## 本地构建

需要 JDK 17、Android SDK platform + build-tools、Python 3、bash；原生插件需要 `d8`，C 示例需要 aarch64 静态交叉编译器（Ubuntu/Debian 安装 `gcc-aarch64-linux-gnu`）。

```bash
# 全部插件
bash scripts/build-all.sh

# 指定插件
bash scripts/build-all.sh your.name.hello

# 带签名
export PLUGIN_KEYSTORE=/secure/release.p12
export PLUGIN_STORE_PASSWORD='...'
export PLUGIN_KEY_ALIAS='plugin'
bash scripts/build-all.sh your.name.hello

# 本地预览 dist（不提交）
DIST_PUSH=0 bash scripts/deploy-dist.sh /tmp/dist-preview build source.json
```

产物在 `build/`，元数据在 `build/meta/`。`KEEP_WORK=1` 保留 `build/work/<id>/`。

## 更新 host-sdk

宿主插件 API 变更后，从 UIN Tool 工程同步：

```bash
bash scripts/update-host-sdk.sh /path/to/UIN_Tool
```

会更新 `assets/host-sdk.jar` 和 `assets/host-sdk.sha256`。CI 校验两者一致，并检查公开 API class 是否存在。

## dist 分支

```
dist/
├── source.json
└── plugins/<pluginId>/
    ├── <pluginId>.tpk
    ├── plugin.json
    ├── icon.png
    ├── visible            显示标记（可选，0 = 隐藏）
    ├── .version
    ├── .sha256
    ├── .signer
    └── .built
```

`source.json` 字段：`pluginId`、`name`、`version`、`versionName`、`author`、`description`、`category`、`uiType`、`size`、`tpkPath`、`iconPath`、`iconSha256`、`lastUpdate`、`updateLog`、`repositoryUrl`，以及 `sha256`、`signerSha256`、`signed`、`minHostVersion`。`iconSha256` 是 `icon.png` 的内容摘要，客户端下载图标后按它校验，不一致就不显示也不写缓存。

## 常见问题

**构建提示未签名**

模板默认允许；发布前配置 Secrets 并把 `REQUIRE_SIGNING` 改成 `'1'`。

**版本没有变化**

`version=0` 依赖 dist 的 `.version`；清空 dist 后会从 1 开始。固定版本必须大于已发布版本。

**native 构建失败**

检查 `ANDROID_HOME` / `ANDROID_JAR` / `d8`、`src` 下的 Java 文件、`mainClass` 与包名。

**C 产物架构不对**

CI 会自动安装 `gcc-aarch64-linux-gnu`；本地需要 aarch64 交叉编译器，或直接在 aarch64 Linux 上构建。产物必须是静态链接。

**删除插件后 dist 还有旧包**

部署阶段会同步删除，等本次 workflow 完成。
