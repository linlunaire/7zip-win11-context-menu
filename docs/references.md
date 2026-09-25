# 参考与设计说明

本次对比核查了下列固定提交的 README、安装脚本、清单及菜单实现。这里记录源码观察和本项目的取舍，不把 README 的描述直接当作当前实现，也不代表对参考项目做了完整安全或功能审计。

## 对比与采纳

| 项目与源码快照 | 核查结果 | 本项目的处理 |
| --- | --- | --- |
| [Wings-Fantasy/7-Zip_Context_menu_plugin](https://github.com/Wings-Fantasy/7-Zip_Context_menu_plugin/tree/1a9967e28f1b11cdcbe75a2f7b76aa553cde12ce) | 自行实现菜单扩展，读取 7-Zip 设置并构造命令；说明了三级菜单展平的需求。 | 保留原 DLL 提供的菜单和设置，明确嵌套子菜单限制。没有为展平重写菜单层。 |
| [2xRon/7zipExplorerExtension](https://github.com/2xRon/7zipExplorerExtension/tree/e66805c04e191c2d0a1ec05aa6c884460d8f3929) | 当前路径发现只读 HKLM，优先 Path64、Path；安装脚本把自有 DLL 和启动程序放入签名 MSIX。 | 自动发现采用 HKLM 与标准目录，保留显式路径参数；包仍引用本地原版 DLL。 |
| [Nowaterisenough/7ZipContext](https://github.com/Nowaterisenough/7ZipContext/tree/08c7071587df8dc65f363a21252866b9bf4204fd) | 自有 C++ 菜单实现，并封装 7-Zip 核心接口。 | 将它视为自建菜单/归档调用层的另一条路线；当前不引入另一套命令逻辑。 |
| [spakov/GenericShellEx](https://github.com/spakov/GenericShellEx/tree/995388ab92ee17e700e857403778e10e7f1ee644) | 安装前核查包兼容条件；提醒 .NET Framework 的 OSVersion 可能不准确；证书卸载使用已知指纹。 | 从系统注册信息读取 Windows 构建号；持久保存本次证书指纹与所有权，保留失败恢复依据。 |
| [M2Team/NanaZip](https://github.com/M2Team/NanaZip/tree/5a0be02f266ab87a5328face8d3e35e9832d292b) | 清单使用文件/目录/磁盘的新版菜单注册，以及 STA 的 COM SurrogateServer。 | 交叉核对本项目文件/目录与 STA 注册方式；磁盘和空白区域仍待单独验证。 |

### 可定位的源码

- Wings-Fantasy：[RegistryReader.cpp](https://github.com/Wings-Fantasy/7-Zip_Context_menu_plugin/blob/1a9967e28f1b11cdcbe75a2f7b76aa553cde12ce/src/common/RegistryReader.cpp)、[GenericCommandEnum.cpp](https://github.com/Wings-Fantasy/7-Zip_Context_menu_plugin/blob/1a9967e28f1b11cdcbe75a2f7b76aa553cde12ce/src/command/GenericCommandEnum.cpp)、[README](https://github.com/Wings-Fantasy/7-Zip_Context_menu_plugin/blob/1a9967e28f1b11cdcbe75a2f7b76aa553cde12ce/README.md)。
- 2xRon：[SevenZipUtils.cs](https://github.com/2xRon/7zipExplorerExtension/blob/e66805c04e191c2d0a1ec05aa6c884460d8f3929/src/7ZipMenu/SevenZipUtils.cs)、[install.ps1](https://github.com/2xRon/7zipExplorerExtension/blob/e66805c04e191c2d0a1ec05aa6c884460d8f3929/scripts/install.ps1)。
- 7ZipContext：[ContextMenu.cpp](https://github.com/Nowaterisenough/7ZipContext/blob/08c7071587df8dc65f363a21252866b9bf4204fd/src/ContextMenu.cpp)、[SevenZipCore.cpp](https://github.com/Nowaterisenough/7ZipContext/blob/08c7071587df8dc65f363a21252866b9bf4204fd/src/SevenZipCore.cpp)。
- GenericShellEx：[兼容性检查](https://github.com/spakov/GenericShellEx/blob/995388ab92ee17e700e857403778e10e7f1ee644/GenericShellExInfrastructureInstaller/InstallerTasks/CheckMsixPackageCompatibility.cs)、[证书卸载](https://github.com/spakov/GenericShellEx/blob/995388ab92ee17e700e857403778e10e7f1ee644/GenericShellExInfrastructureInstaller/UninstallerTasks/UninstallCertificate.cs)。
- NanaZip：[Package.appxmanifest](https://github.com/M2Team/NanaZip/blob/5a0be02f266ab87a5328face8d3e35e9832d292b/NanaZipPackage/Package.appxmanifest)。

2xRon 的 README 在该快照仍提到 HKCU 和稀疏包，但路径发现代码仅使用 HKLM，安装代码复制自有 DLL/启动程序进包并直接调用 Add-AppxPackage。这里按源码描述实际行为。

## 本次改动

1. **安装前诊断。** 检查系统与进程架构、三个 7-Zip 文件的 PE 架构，以及选定 DLL 的真实 IExplorerCommand 支持；不通过全局 COM 注册来代替对这个文件的检查。
2. **恢复记录独立保存。** 默认保存在用户 LocalAppData，下发的构建目录删除后仍能卸载。先保存 Installing 状态，再修改证书和注册包；完成后更新 Installed 状态。
3. **按所有权清理。** 只删除匹配状态的包，以及本次新增的证书；其他账户仍使用同名包时保留证书和记录。回滚失败可以再次执行卸载恢复。
4. **重复操作有明确结果。** 相同构建重复安装直接返回，不同构建需先卸载；构建输出必须为空，避免混入旧内容。
5. **可重复验证。** 加入只读 Check.ps1、Pester 故障测试和升级说明。刷新使用 SHChangeNotify；必要时提示注销。

这些改动根据公开接口和对比结论独立编写，没有复制参考项目的实现代码或二进制文件。

## 保留的边界

稀疏包给本地程序提供身份，原版 7-Zip DLL 仍在用户的安装目录中。它不能获得“把扩展 DLL 放进签名包后保护整个扩展负载”的效果。这个取舍适合本项目复用既有安装的目标，不应与包含自有 DLL 的 MSIX 混为一谈。[微软稀疏包说明](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/grant-identity-to-nonpackaged-apps)

微软明确规定 Explorer 不支持子命令继续嵌套。复用原 DLL 无法仅靠改清单展平 CRC SHA 等多层菜单，因此保留经典菜单入口；自建菜单扩展才有重新组织命令的空间。[IExplorerCommand::EnumSubCommands](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iexplorercommand-enumsubcommands)

接口探测、单元测试、构建签名和用户界面验证是不同证据；具体已验证范围见 [README](../README.md#验证记录)。
