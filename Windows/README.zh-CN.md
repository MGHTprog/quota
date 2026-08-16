# Quota Windows 版

这是原 macOS Quota 的原生 Windows 重写版。macOS Swift 源码仍保留在 `Sources/`，Windows 代码位于 `Windows/Quota.Windows/`，两者互不覆盖。

## 已实现功能

- Windows 系统托盘常驻，左键打开/关闭额度窗口，右键刷新、设置或退出
- 使用内嵌的 Quota 托盘图标；Windows Explorer/任务栏重启后会自动重新注册
- 类似 360 网速窗口的桌面额度悬浮窗：始终置顶、可拖动贴边、直接显示各服务剩余额度
- 悬浮窗左键打开主面板，右键可刷新、设置、隐藏或退出；显示状态和位置会自动保存
- Codex：通过本地 `codex app-server` JSON-RPC 读取 5 小时和周额度
- Claude：读取 `%USERPROFILE%\.claude\.credentials.json`，调用 Claude Code OAuth usage API
- Grok：读取 `%USERPROFILE%\.grok\auth.json`，调用 Grok CLI billing API
- 小米 MiMo：自动读取 MiMoCode 的小米登录项，通过 Token Plan 控制台显示套餐与补偿 Credits 合计额度
- 每 2 分钟自动刷新，也可手动刷新
- 全部/单服务筛选、服务启用与优先级排序
- 自动、手动或关闭代理
- 低于 20%、10%、5% 时发送 Windows 托盘通知，恢复到 50% 后允许再次提醒
- 全局快捷键（默认 `Ctrl+Alt+Q`）
- 跟随系统、简体中文和英文界面
- 设置保存在 `%APPDATA%\Quota\settings.json`

## 构建

在仓库根目录打开 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\Windows\build.ps1
```

构建脚本使用 Windows 自带的 .NET Framework C# 编译器，不需要另外安装 Visual Studio 或 .NET SDK。脚本会同时运行 Codex、Claude、Grok 和 MiMo 的数据映射测试。

输出文件：

```text
Windows\dist\Quota.Windows.exe
Windows\dist\Quota.Windows.exe.config
```

## 使用

1. 确认相应 CLI 已在 Windows 中登录。
2. 双击 `Quota.Windows.exe`。
3. 程序默认只显示桌面额度悬浮窗；左键悬浮窗可打开完整额度面板。
4. 拖动悬浮窗可移动并贴靠屏幕边缘，右键可刷新、设置、隐藏或退出。
5. 也可在任务栏通知区域找到 Quota 图标，左键打开额度窗口。

Windows 11 可能会把首次运行的新托盘图标放进“隐藏的图标”区域。点击任务栏右侧的 `^` 即可找到；若希望始终显示，可在“设置 → 个性化 → 任务栏 → 其他系统托盘图标”中开启 Quota。

Codex 必须能在命令行中执行 `codex`。Claude Windows 版使用凭据文件，不访问 macOS Keychain。Grok 需要先执行 `grok login`。

### 小米 MiMo 配置

1. 确认小米账号已经开通 Token Plan，并登录 [小米 MiMo Token Plan 控制台](https://platform.xiaomimimo.com/console/plan-manage)。
2. 打开浏览器开发者工具，从任意 `platform.xiaomimimo.com` 请求复制 Cookie 值或完整请求头。
3. 打开 Quota 的“设置 → 服务”，粘贴到 `MiMo Cookie` 后保存。

Windows 版可选择性识别 MiMoCode 的 `auth.json`，但不再强制要求本机安装 MiMoCode。`tp-...` API key 不能直接访问控制台额度接口，因此仍需要网页 Cookie。Cookie 使用 Windows DPAPI 按当前用户加密，单独保存在 `%APPDATA%\Quota\mimo-cookie.dat`，不会以明文写进 `settings.json`。如果提示未授权，请重新复制已登录控制台的 Cookie。

## 当前平台差异

- Windows 没有 Touch Bar，对应功能不迁移。
- Windows 版使用托盘 Balloon Tip 通知；是否进入通知中心由 Windows 版本和系统通知设置决定。
- 当前生成的是免安装可执行程序，尚未制作 MSI/安装包或代码签名。
