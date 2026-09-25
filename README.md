# 7-Zip Windows 11 Context Menu

让现有 7-Zip 直接出现在 Windows 11 新版右键菜单中。

这个项目给已有的 7-Zip 菜单扩展补充一个 Sparse Package（稀疏应用身份包），登记 `IExplorerCommand` 和 `windows.fileExplorerContextMenus`。压缩和解压仍由原来的 7-Zip 执行。

- 保留 Windows 11 新版右键菜单。
- 文件和文件夹的首层右键菜单显示 **7-Zip**。
- 不修改或替换 7-Zip 的 EXE、DLL。
- 不需要安装其他压缩软件，也不启用开发者模式。
- 支持卸载注册包及本项目添加的本地签名证书。

## 环境要求

- Windows 11 x64。
- 已安装 x64 版 7-Zip；默认目录为 `C:\Program Files\7-Zip`。
- 64 位 Windows PowerShell 5.1 或 PowerShell 7。
- 构建需要 Windows SDK 中的 `makeappx.exe` 和 `signtool.exe`。
- 安装、卸载需要同一 Windows 账户的管理员权限。

已验证环境：Windows 11 25H2（26200.9457）、7-Zip 25.01 x64。
其他版本尚未逐一验证；不提供 ARM64 或 32 位注册包。

## 构建

在项目根目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1
```

脚本会自动寻找 Windows SDK，生成 `dist` 目录。构建只生成文件和一次性签名，不安装菜单或信任证书。

自定义程序路径和 SDK 路径：

```powershell
.\Build.ps1 -SevenZipPath 'D:\Apps\7-Zip' -SdkBinPath 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64'
```

每次构建会生成新的本地代码签名证书。私钥不可导出，签名完成后立即删除。生成的 `LocalSevenZipMenu.cer` 只包含公钥。

## 安装

以**同一 Windows 账户**的管理员身份打开 PowerShell，在项目根目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

如果 7-Zip 不在默认目录：

```powershell
.\Install.ps1 -SevenZipPath 'D:\Apps\7-Zip'
```

安装会将本次构建的公钥证书加入 `LocalMachine\TrustedPeople`，然后为当前用户注册 `Local.SevenZipModernMenu`。这是本地自签名包的信任设置，不会安装根证书或关闭签名验证。

安装后右键文件或文件夹查看 **7-Zip**。如果菜单尚未刷新，保存工作后注销并重新登录，再试一次。

保留 `dist`，其中的 `installation.json` 用于准确卸载本次注册。该文件包含本机账户 SID，不应上传；已加入 `.gitignore`。

## 卸载

以安装时同一账户的管理员身份运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

卸载只移除本项目注册的包和本次安装添加的证书，保留原有 7-Zip。

若使用了自定义构建输出目录，安装和卸载都需传入 `-PackageDirectory`。
更换构建或 7-Zip 安装目录前，请先用原来的脚本及 `dist` 卸载；脚本不会覆盖已有注册。

## 验证记录

原始注册方案已完成以下验证：

- 用户确认 Windows 11 首层右键菜单出现 7-Zip，子菜单正常展开。
- 通过 Windows 包注册的 COM 激活路径枚举菜单并调用压缩、解压。
- 多文件、中文及带空格文件名处理通过。
- 生成的 7z 归档完整性检查通过，解压后的 SHA-256 与原文件一致。
- 原有 `7-zip.dll`、`7zFM.exe`、`7zG.exe` 的哈希未改变。

仓库整理后的脚本另行验证了语法、构建、签名以及注册清单与原方案一致性；尚未在干净系统上重新执行完整安装与卸载。

## 原理和范围

7-Zip 25.01 的 `7-zip.dll` 已实现 `IExplorerCommand`。本项目登记应用身份及 COM 类，让 Windows 11 能在新版右键菜单中加载它。注册包引用本地程序目录，不分发 7-Zip 二进制文件。

这是独立的本地配置项目，并非 7-Zip 官方发布。7-Zip 名称、图标和程序归其各自权利人所有；构建时从本机安装提取图标。

参考：[微软新版菜单扩展文档](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/integrate-packaged-app-with-file-explorer)、[稀疏应用身份包文档](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/grant-identity-to-nonpackaged-apps)、[7-Zip 官方源码](https://github.com/ip7z/7zip)。
