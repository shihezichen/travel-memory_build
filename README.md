# travel-memory_build

「旅行记忆」App 两个原生壳的**本地编译打包脚本**（Windows / PowerShell）。
供本仓库复用，也方便其他 Agent 在干净的 Windows 机器上复现打包。

- 鸿蒙 HarmonyOS：`harmony/build-hap.ps1` → 产出 HAP
- 安卓 Android：`android/bootstrap-android-toolchain.ps1` + `android/build-apk.ps1` → 产出 APK

> 脚本内全部使用英文（ASCII）文案，避免 PowerShell 5.1 执行 `.ps1` 时的中文乱码问题。

---

## 目录结构

```
travel-memory_build/
├─ harmony/
│  └─ build-hap.ps1                 # 用 DevEco Studio 自带工具链编译 HAP
├─ android/
│  ├─ bootstrap-android-toolchain.ps1   # 下载并安装 JDK17 + Gradle + Android SDK
│  └─ build-apk.ps1                     # 用本地工具链编译 APK
└─ README.md
```

工具链默认装在脚本同级 `../.tools/`（已被 `.gitignore` 忽略，不会提交）。

## 产物与工具的放置约定

三个仓库分工：

| 仓库 | 放什么 |
|------|--------|
| `travel-memory_harmony` | 鸿蒙壳**源码** |
| `travel-memory_android` | 安卓壳**源码** |
| `travel-memory_build`（本仓库） | **编译脚本 + 编译产物 + 工具** |

- **编译产物（HAP / APK）**：**不进任何源码仓库**，统一作为本仓库的 **GitHub Releases** 附件发布。
  当前发布：**[v1.0.0](https://github.com/shihezichen/travel-memory_build/releases/tag/v1.0.0)**
  - `travel-memory-harmony-signed.hap`（签名，可装机）
  - `travel-memory-android-debug.apk`（debug，可直接安装）
- **编译工具（JDK / Gradle / Android SDK）**：**不进 git**（体积大、与机器相关、可由脚本重建），
  放在本仓库本地、被 `.gitignore` 忽略的 `.tools/` 目录；鸿蒙侧工具链即 **DevEco Studio 安装本身**。
  换机器或其他 Agent 克隆本仓库后，跑 `bootstrap-android-toolchain.ps1` 即可重建 `.tools/`。

---

## 一、鸿蒙 HAP

依赖：本机已安装 **DevEco Studio**（自带 Node / ohpm / hvigor / JBR，无需另装 Node/JDK/SDK）。

```powershell
# 自动探测 DevEco Studio 安装路径
.\harmony\build-hap.ps1 -ProjectDir D:\path\to\travel-memory_harmony

# 或显式指定 DevEco Studio 目录
.\harmony\build-hap.ps1 -ProjectDir D:\path\to\travel-memory_harmony `
                        -DevEcoDir "D:\Program Files\Huawei\DevEco Studio"
```

产物：`<ProjectDir>\entry\build\default\outputs\default\entry-default-unsigned.hap`

**关于签名（重要）**：命令行 hvigor 只在该工程的 `build-profile.json5` 里配置了
`signingConfigs` 时才会签名，否则产出 **unsigned HAP**。商业版 HarmonyOS 真机安装
**必须签名**（华为开发者证书 + 设备 UDID）。两种可行方式：

1. **推荐**：在 DevEco Studio 里 `File → Project Structure → Signing Configs`，登录华为账号并勾选
   「Automatically generate signature」，然后直接 `Build → Build HAP(s)/App(s)`。DevEco 会用它内部
   保存的证书签名（该 p12 口令由 DevEco 私密保管，命令行无法复现）。
2. 若要让命令行也能签名：把签名材料（`.p12/.cer/.p7b`）与口令写进 `build-profile.json5` 的
   `app.signingConfigs`，再运行本脚本即可。

---

## 二、安卓 APK

### 1) 首次：准备工具链（JDK 17 + Gradle + Android SDK）

```powershell
.\android\bootstrap-android-toolchain.ps1
# 自定义安装目录 / 版本：
.\android\bootstrap-android-toolchain.ps1 -ToolsDir D:\android-tools -GradleVersion 8.9
```

下载支持**断点续传**（HTTP Range），网络慢或中断后重跑同一命令即可继续，不会损坏半成品。

### 2) 编译 APK

```powershell
# 调试包（Android 自动签名，可直接 adb install）
.\android\build-apk.ps1 -ProjectDir D:\path\to\travel-memory_android

# 正式包（需要 app/build.gradle 里配置的 release keystore）
.\android\build-apk.ps1 -ProjectDir D:\path\to\travel-memory_android -Variant release
```

产物：`<ProjectDir>\app\build\outputs\apk\debug\app-debug.apk`

---

## 常见问题

- **`hvigor` 报 `Invalid value of 'DEVECO_SDK_HOME'`**：脚本已把 `DEVECO_SDK_HOME` 指向
  `DevEco Studio\sdk`（含 `sdk-pkg.json` 的父目录），不是 `sdk\default`。
- **安卓打包需要 java**：`build-apk.ps1` 使用 `.tools` 里的 JDK 17；`bootstrap` 阶段若系统无 java，
  会自动借用 DevEco Studio 的 `jbr` 跑 sdkmanager。
- **release 包缺 keystore**：仓库 `.gitignore` 排除了 keystore，需自行用 keytool 生成一次并在
  `app/build.gradle(.kts)` 的 `signingConfigs` 中引用。
