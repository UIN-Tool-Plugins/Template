# Template

UIN Tool 插件仓库模板。fork 此仓库即可创建你自己的插件源。

## 快速开始

1. Fork 此仓库
2. 修改 `source.json`（源名称、描述等）
3. 在 `plugins/` 下添加插件
4. 推送到 `main` 分支，GitHub Actions 自动构建并部署到 `dist` 分支
5. 在 UIN Tool 中添加你的源地址

## 仓库结构

```
├── .github/workflows/build.yml    ← CI 自动构建
├── scripts/
│   ├── build-plugin.sh            ← 构建脚本
│   ├── package-tpk.sh             ← 默认打包
│   └── generate-index.sh          ← 生成 source.json
├── source.json                    ← 源元数据（修改此处）
├── plugins/
│   └── your.author.pluginname/
│       ├── type                   ← 必须
│       ├── plugin.json            ← 必须
│       ├── icon.png               ← 必须
│       ├── visible                ← 可选（1=隐藏, 0/无=显示）
│       └── ...                    ← 插件文件
└── README.md
```

## 制作插件

### 1. 创建插件目录

在 `plugins/` 下创建目录，目录名 = pluginId：

```
plugins/your.author.pluginname/
```

**pluginId 命名规则：**
- 格式：`作者.仓库.插件名`（如 `uin.official.calculator`）
- 只能使用英文、数字和点
- 全小写
- 目录名必须与 plugin.json 中的 pluginId 一致

### 2. 创建 type 文件

在插件根目录创建 `type` 文件，内容决定构建方式：

| type 内容 | 含义 | 需要的文件 |
|-----------|------|-----------|
| 空文件 | 直接打包 | 插件文件 |
| `native` | 编译 Java → DEX | `src/*.java` |
| `other` | 执行自定义 `build.sh` | `build.sh` |

### 3. 创建 visible 文件（可选）

在插件根目录创建 `visible` 文件：

| 内容 | 效果 |
|------|------|
| 无此文件 | 插件正常显示 |
| `0` 或 `false` | 插件正常显示 |
| `1` 或 `true` | 插件隐藏（不写入 source.json） |

隐藏的插件仍然会被构建，但不会出现在软件的插件列表中。

### 4. 创建 plugin.json

```json
{
  "pluginId": "your.author.pluginname",
  "name": "插件显示名称",
  "version": 0,
  "versionName": "1.0.0",
  "author": "YourName",
  "description": "插件描述",
  "category": "分类",
  "uiType": "web",
  "entry": "web/index.html"
}
```

**version 字段：**
- `0` = CI 每次构建自动递增
- `>=1` = 使用固定版本号

### 5. 各类型插件示例

#### 纯 Web 插件

```
plugins/your.plugin/
├── type              ← 空文件
├── plugin.json       ← uiType: "web", entry: "web/index.html"
├── icon.png
└── web/
    └── index.html
```

#### Web + 后端插件

```
plugins/your.plugin/
├── type              ← 空文件或 other
├── plugin.json       ← uiType: "web", backend: "python"
├── icon.png
├── web/
│   └── index.html
└── scripts/
    ├── start.sh
    └── backend/
        └── server.py
```

plugin.json 额外字段：
```json
{
  "backend": "python",
  "backendEntry": "scripts/backend/server.py",
  "backendStartCommand": "pip install flask && python scripts/backend/server.py",
  "backendAutoStart": true,
  "backendHealthCheck": "/health"
}
```

#### Native 插件

```
plugins/your.plugin/
├── type              ← 内容: native
├── plugin.json       ← uiType: "native", mainClass: "com.example.MainPlugin"
├── icon.png
└── src/
    └── com/example/
        └── MainPlugin.java
```

#### CUI 插件

```
plugins/your.plugin/
├── type              ← 空文件或 other
├── plugin.json       ← uiType: "cui", entry: "scripts/main.sh"
├── icon.png
└── scripts/
    └── main.sh
```

#### C 语言后端插件

```
plugins/your.plugin/
├── type              ← 内容: other
├── plugin.json       ← uiType: "cui", backend: "other"
├── build.sh          ← gcc 编译脚本
├── icon.png
├── src/
│   └── server.c
└── scripts/
    └── main.sh       ← CUI 入口
```

### 6. icon.png 要求

- 格式：PNG
- 建议尺寸：256x256 像素
- 文件大小：不超过 500KB

## CI 工作流

推送到 `main` 分支后，GitHub Actions 自动：

1. 检测变更的插件
2. 根据 `type` 文件选择构建方式
3. 编译产物推送到 `dist` 分支
4. 生成 `source.json` 索引（hidden 插件不包含在内）

## 在 UIN Tool 中添加源

软件 → 插件源管理 → 添加 → 输入仓库地址：

```
https://github.com/{你的用户名}/{仓库名}
```
