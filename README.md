# Android AAR 私有分发技术方案

基于 **GitHub Packages (Maven Registry)** 实现 Android AAR 库的私有化分发与权限管控。

---

## 一、方案概述

### 1.1 背景

团队需要将内部 Android SDK（AAR 格式）以 Maven 依赖的方式分发给授权的外部开发者，要求：

- **私有化**：未授权用户无法发现和下载
- **权限可控**：可随时授权/撤销访问
- **接入简单**：开发者通过标准 Gradle 依赖即可集成
- **版本管理**：支持多版本并存，开发者按需选择

### 1.2 技术选型

| 方案 | 私有性 | 成本 | 接入难度 | 选择 |
|---|---|---|---|---|
| GitHub Packages | ✅ 私有仓库天然支持 | 免费（500MB） | 低，标准 Maven | ✅ 采用 |
| 自建 Maven 仓库 (Nexus) | ✅ | 需服务器 | 中 | ❌ |
| JitPack | ❌ 私有需付费 | $9.9/月起 | 低 | ❌ |
| 直接分发 AAR 文件 | ⚠️ 无法管控二次传播 | 免费 | 高，手动集成 | ❌ |

### 1.3 架构图

```
┌──────────────────────────────────────────────────────────┐
│                     仓库管理员                             │
│                                                          │
│  1. 将 AAR 放入版本文件夹（如 1.5.1/）                     │
│  2. 执行 ./gradlew publish                               │
│  3. AAR 自动发布到 GitHub Packages                        │
│  4. 在仓库 Settings 管理开发者访问权限                      │
└────────────────────────┬─────────────────────────────────┘
                         │ publish
                         ▼
┌──────────────────────────────────────────────────────────┐
│              GitHub Packages (Maven Registry)             │
│                                                          │
│  tencent.odcfrontend:tan-sdk:1.5.1                         │
│  tencent.odcfrontend:mintegraladapter:17.0.31              │
│  tencent.odcfrontend:pangleadapter:6.4.0.6                 │
└────────────────────────┬─────────────────────────────────┘
                         │ implementation '...'
                         ▼
┌──────────────────────────────────────────────────────────┐
│                   授权开发者                               │
│                                                          │
│  1. 接受仓库邀请                                          │
│  2. 创建 read:packages Token                              │
│  3. 在 build.gradle 中添加 Maven 仓库 + 依赖              │
│  4. Gradle Sync 即可使用                                  │
└──────────────────────────────────────────────────────────┘
```

---

## 二、仓库结构

```
TAN_Android_Maven/
├── build.gradle          # 自动扫描 + 发布脚本
├── gradle.properties     # 管理员凭证（不提交到 Git）
├── settings.gradle
├── 1.5.1/                # 版本文件夹
│   ├── TAN_SDK-1.5.1.aar
│   ├── MintegralAdapter-17.0.31.aar
│   └── PangleAdapter-6.4.0.6.aar
├── 1.6.0/                # 新版本只需新建文件夹
│   ├── TAN_SDK-1.6.0.aar
│   └── ...
└── README.md
```

---

## 三、发布端配置（管理员）

### 3.1 Gradle 发布脚本

`build.gradle` 采用**自动扫描机制**，无需手动为每个版本编写 publication：

```groovy
plugins {
    id 'maven-publish'
}

def groupName = 'tencent.odcfrontend'

// AAR 文件名前缀 → artifactId 映射表
def artifactMap = [
    'MintegralAdapter' : 'mintegraladapter',
    'PangleAdapter'    : 'pangleadapter',
    'TAN_SDK'          : 'tan-sdk',
]

publishing {
    publications {
        // 自动扫描所有版本文件夹（匹配 x.x.x 格式）
        projectDir.listFiles()
            .findAll { it.isDirectory() && it.name ==~ /\d+\.\d+\.\d+.*/ }
            .each { versionDir ->
                def versionName = versionDir.name
                versionDir.listFiles()
                    .findAll { it.name.endsWith('.aar') }
                    .each { aarFile ->
                        def baseName = aarFile.name.replace('.aar', '')
                        def matchedKey = artifactMap.keySet().find { baseName.startsWith(it) }
                        if (matchedKey) {
                            def artifactId = artifactMap[matchedKey]
                            def pubName = "${artifactId}${versionName}".replaceAll('[^a-zA-Z0-9]', '')
                            create(pubName, MavenPublication) {
                                it.groupId = groupName
                                it.artifactId = artifactId
                                it.version = versionName
                                it.artifact(aarFile) { extension = 'aar' }
                            }
                        }
                    }
            }
    }

    repositories {
        maven {
            name = 'GitHubPackages'
            url = uri("https://maven.pkg.github.com/odcfrontend/TAN_Android_Maven")
            credentials {
                username = project.findProperty("gpr.user") ?: System.getenv("GITHUB_USER")
                password = project.findProperty("gpr.token") ?: System.getenv("GITHUB_TOKEN")
            }
        }
    }
}
```

### 3.2 凭证配置

`gradle.properties`（已加入 `.gitignore`）：

```properties
gpr.user=你的GitHub用户名
gpr.token=ghp_xxxxxxxxxxxx
```

Token 需要 **`write:packages`** 和 **`read:packages`** 权限。

### 3.3 发布命令

```bash
# 发布所有新版本（已存在的会报 409 Conflict，可忽略）
./gradlew publish --continue

# 单独发布某个包
./gradlew publish<Name>PublicationToGitHubPackagesRepository
```

### 3.4 新增版本 / 新增 SDK 流程

**新增版本**（无需改代码）：
1. 创建版本文件夹，如 `1.6.0/`
2. 放入 AAR 文件
3. 执行 `./gradlew publish --continue`

**新增 SDK 类型**（改一行）：
1. 在 `build.gradle` 的 `artifactMap` 中新增映射
2. 将 AAR 放入对应版本文件夹
3. 执行 `./gradlew publish --continue`

---

## 四、权限管理（管理员）

### 4.1 授权开发者

1. 打开 `https://github.com/ODCFrontend/TAN_Android_Maven/settings/access`
2. 点击 **Add people**
3. 输入对方 GitHub 用户名，角色选择 **Read**

### 4.2 撤销授权

在同一页面移除协作者，对方立即失去下载权限。

### 4.3 权限模型

```
仓库 Owner（你）     →  可发布、可管理权限
Read 协作者（开发者） →  仅可下载，无法发布、无法看到源码（如仓库为 private）
未授权用户            →  完全不可见
```

---

## 五、接入指南（开发者）

### 5.1 前置条件

- 已接受仓库管理员的 GitHub 邀请
- 已创建 [Personal Access Token](https://github.com/settings/tokens)，勾选 **`read:packages`**

### 5.2 配置 Maven 仓库

在项目 `settings.gradle` 中添加：

```groovy
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven {
            url "https://maven.pkg.github.com/odcfrontend/TAN_Android_Maven"
            credentials {
                username = project.findProperty("gpr.user") ?: System.getenv("GITHUB_USER")
                password = project.findProperty("gpr.token") ?: System.getenv("GITHUB_TOKEN")
            }
        }
    }
}
```

在 `gradle.properties` 中配置凭证（**不要提交到 Git**）：

```properties
gpr.user=开发者的GitHub用户名
gpr.token=开发者的GitHub Token
```

### 5.3 添加依赖

```groovy
dependencies {
    implementation 'tencent.odcfrontend:tan-sdk:1.5.1'
    implementation 'tencent.odcfrontend:mintegraladapter:17.0.31'
    implementation 'tencent.odcfrontend:pangleadapter:6.4.0.6'
}
```

### 5.4 Sync & 使用

点击 Android Studio **Sync Now**，完成接入。

---

## 六、已发布的包

| groupId | artifactId | 版本 | 说明 |
|---|---|---|---|
| `tencent.odcfrontend` | `tan-sdk` | 1.5.1 | TAN SDK 主库 |
| `tencent.odcfrontend` | `mintegraladapter` | 17.0.31 | Mintegral 广告适配器 |
| `tencent.odcfrontend` | `pangleadapter` | 6.4.0.6 | Pangle 广告适配器 |

包管理页面：https://github.com/ODCFrontend?tab=packages

---

## 七、GitHub Packages 限制与注意事项

| 项目 | 说明 |
|---|---|
| 存储配额 | 免费账户 500MB，Pro 2GB |
| 流量配额 | 免费账户 1GB/月 |
| 版本不可覆盖 | 同一 artifactId + version 只能发布一次 |
| artifactId 必须全小写 | GitHub Packages 限制，不支持大写字母 |
| URL 中 owner 必须小写 | 即使 GitHub 用户名含大写 |
| 不支持 CocoaPods | iOS 需使用其他方案（私有 Podspec 仓库 / SPM） |

---

## 八、FAQ

**Q：开发者 Token 勾选了 `write:packages` 而不是 `read:packages`，有影响吗？**
A：没有影响。`write:packages` 自动包含 `read:packages`，且开发者无仓库写权限，无法发布。

**Q：已发布的版本能删除吗？**
A：可以。在 GitHub 仓库的 Packages 页面点击对应包，进入版本管理删除。

**Q：发布时报 409 Conflict？**
A：说明该版本已发布过。GitHub Packages 不允许覆盖已有版本，使用 `--continue` 跳过。

**Q：需要先 git commit 再发布吗？**
A：不需要。`./gradlew publish` 是将本地 AAR 上传到 GitHub Packages，与 Git 提交无关。
