# 7-Zip Windows 11 Context Menu

让现有 7-Zip 直接出现在 Windows 11 新版右键菜单中。

这个项目给已有的 7-Zip 菜单扩展补充一个 Sparse Package（稀疏应用身份包），登记 `IExplorerCommand` 和 `windows.fileExplorerContextMenus`。压缩和解压仍由原来的 7-Zip 执行。

- 保留 Windows 11 新版右键菜单，文件和文件夹的首层菜单显示 **7-Zip**。
- 自动查找本机 7-Zip，并检查 x64 架构和 DLL 的菜单接口。
- 不修改或替换 7-Zip 的 EXE、DLL，不分发 7-Zip 二进制文件。
- 安装前保存恢复记录；失败时回滚，卸载不依赖构建目录。
- 不需要其他压缩软件或开发者模式。

## 环境要求

- Windows 11 x64；不支持 ARM64、32 位系统或 32 位 PowerShell。
- 已安装 x64 版 7-Zip，且 DLL 实现本项目使用的菜单接口。
- 64 位 Windows PowerShell 5.1 或 PowerShell 7。
- 构建需要 Windows SDK 中的 `makeappx.exe` 和 `signtool.exe`。
- 安装、卸载需要**同一 Windows 账户**的管理员权限。

已验证环境：Windows 11 25H2（26200.9457）、7-Zip 25.01 x64。其他版本需运行兼容性检查，不能仅凭版本号保证支持。

## 检查和构建

在项目根目录先做只读检查：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Check.ps1
```

尚未安装本项目时，`PackageRegistered = False` 是正常结果。脚本直接加载选定目录的 DLL 验证接口；已注册时还会检查包状态、通过包激活 COM，并核对菜单返回的 DLL 路径。它不能代替在资源管理器中实际点击菜单。

构建注册包：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1
```

路径查找依次使用 `HKLM\SOFTWARE\7-Zip` 的 `Path64`、`Path` 和 `%ProgramFiles%\7-Zip`，跳过缺少必要文件的目录。不会自动从 HKCU 或 App Paths 加载 DLL。显式指定的目录无效时会报错，不会悄悄使用另一份安装。

自定义路径：

```powershell
.\Build.ps1 -SevenZipPath 'D:\Apps\7-Zip' -SdkBinPath 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64' -OutputDirectory '.\dist-custom'
```

脚本自动查找 SDK，默认输出到 `dist`。输出目录必须为空或不存在；再次构建请指定新目录，避免混入旧文件。构建只生成文件和一次性签名，不安装菜单或信任证书。

每次构建生成新的本地代码签名证书。私钥不可导出，签名结束后删除；`LocalSevenZipMenu.cer` 只包含公钥。

## 安装

以**同一 Windows 账户**的管理员身份打开 PowerShell，在项目根目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

使用自定义路径时：

```powershell
.\Install.ps1 -SevenZipPath 'D:\Apps\7-Zip' -PackageDirectory '.\dist-custom'
```

安装会核对包哈希、内嵌身份和签名证书，将本次构建的公钥证书加入 `LocalMachine\TrustedPeople`，然后为当前用户注册 `Local.SevenZipModernMenu`。不会安装根证书或关闭签名验证。

恢复记录默认保存在：

```text
%LOCALAPPDATA%\SevenZipModernMenu\installation.json
```

记录在修改证书或包注册**之前**落盘。安装出错时会尝试回滚；回滚失败则保留记录，之后用 `Uninstall.ps1` 清理。相同构建、路径和已完成状态重复安装会直接返回；不同构建或待恢复状态须先卸载。

安装成功后可以删除构建输出，但请保留项目脚本和恢复记录。记录包含本机账户 SID，不应上传。可用 `-StatePath` 自定义位置，后续检查和卸载传入同一路径。

安装后运行 `Check.ps1`，再右键文件和文件夹验证菜单及压缩、解压操作。脚本会通知资源管理器刷新；若尚未生效，保存工作后注销并重新登录。

## 卸载与升级

以安装时同一账户的管理员身份运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

卸载只移除恢复记录对应的包，以及本次安装新增的准确证书指纹。已有证书不会删除；若其他账户仍使用同名菜单包，会保留证书和恢复记录，待其他账户卸载后再运行一次。

- **7-Zip 在原目录升级：**运行 `Check.ps1` 检查新 DLL；`DllChangedSinceInstall` 只表示文件改变。接口检查通过后仍需实际验证菜单。
- **更换 7-Zip 路径或重新构建注册包：**先用原有恢复记录卸载，再安装新构建。
- **旧版仓库脚本：**若记录仍位于原构建目录，可运行 `.\Uninstall.ps1 -PackageDirectory '旧构建目录'`。保留旧目录直到卸载完成。
- **最初的一次性安装包：**其记录格式不同，请使用随它提供的原版卸载脚本。新脚本不会自动接管没有匹配恢复记录的已安装包。
- **记录丢失：**脚本停止并保留现状，不按证书名称猜测删除对象。

## 功能边界

本项目复用 7-Zip 原有菜单与设置，没有自行重写命令。`lib/Native.cs` 仅用于检查和刷新通知，不是另一个注册到系统的菜单扩展。

Windows 的 `IExplorerCommand` 菜单不支持子命令继续嵌套子命令。7-Zip 的 **CRC SHA 等多层子菜单可能无法完整呈现**；这些操作请从“显示更多选项”进入经典菜单。本项目不承诺与经典菜单的全部项目完全一致。要展开或重排这些项目，需要另外实现菜单扩展。[微软接口说明](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iexplorercommand-enumsubcommands)

注册范围是文件和文件夹；尚未增加磁盘或文件夹空白处菜单。

## 验证记录

原始注册方案已完成：

- 用户确认 Windows 11 首层菜单出现 7-Zip，子菜单正常展开。
- 经包注册的 COM 激活路径调用压缩、解压，覆盖多文件、中文及带空格文件名。
- 7z 归档完整性检查通过，解压后的 SHA-256 与原文件一致。
- 原有 `7-zip.dll`、`7zFM.exe`、`7zG.exe` 哈希未改变。

本次脚本优化另行验证构建与签名、兼容性检查和 14 项自动化测试：包括部分安装后失败、首次/最终状态写入失败、回滚失败后恢复、证书共享、删除构建目录后的卸载、路径发现和无效 PE 文件。包与证书修改通过 mock 模拟，恢复记录使用真实临时文件。

测试使用 Windows PowerShell 5.1 + Pester 3.4.0：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester -Script .\tests\Lifecycle.Tests.ps1 -EnableExit"
```

优化后的安装、卸载流程**尚未在干净系统上进行完整实装回归**。实际检查现有注册成功，不等于已经完成这一项验证。

## 参考项目

对 NanaZip、7-Zip_Context_menu_plugin、7zipExplorerExtension、7ZipContext、GenericShellEx 的源码对比，以及本次采纳和保留的取舍，见 [参考与设计说明](docs/references.md)。

这是独立的本地配置项目，并非 7-Zip 官方发布。7-Zip 名称、图标和程序归其各自权利人所有；构建时从本机安装提取图标。

基础文档：[微软新版菜单扩展](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/integrate-packaged-app-with-file-explorer)、[稀疏应用身份包](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/grant-identity-to-nonpackaged-apps)、[7-Zip 官方源码](https://github.com/ip7z/7zip)。
