# 1.1.0.0 验证记录

日期：2026-10-01。Windows 11 x64，原版 7-Zip 25.01，MSVC 14.51，Windows SDK 10.0.26100.0。

## 问题与修复

- 原版 IExplorerCommand 在顶层 `GetTitle` 中读取文件。适配层改用静态标题，在 `EnumSubCommands` 中初始化原版命令树。
- 原版 CRC SHA 是 7-Zip 子菜单内的嵌套分组。适配层将叶子命令展平，并在标题中保留 `CRC SHA / ` 前缀；执行仍调用原始命令对象。
- 每次选择拥有自己的命令缓存。枚举器与命令保持后端 DLL 的有效生命周期，根命令释放后仍可执行子命令。
- MSIX 包含适配层和应用激活入口，使用包内 COM 路径；后端按构建时固定的绝对路径加载。旧版稀疏包的安装和卸载兼容路径保留。

## 可复现的接口回归

在项目根目录运行：

```powershell
./native/Build-Native.ps1 -SevenZipPath 'C:\Program Files\7-Zip' -OutputDirectory './.build/native'
./tests/Test-NativeMenu.ps1 -AdapterDll './.build/native/SevenZipMenu.dll' -OriginalOnly
# 上一条应失败：原版顶层提前读取文件，且包含嵌套子菜单。
./tests/Test-NativeMenu.ps1 -AdapterDll './.build/native/SevenZipMenu.dll'
```

测试直接加载目标 DLL，经真实的 `IExplorerCommand` 接口枚举命令。`IShellItemArray` 包装真实本地文件选择，只对 `GetItemAt` 注入 250 毫秒延迟并计数。

| 检查 | 原版 DLL | 适配层 |
| --- | ---: | ---: |
| 顶层文件读取次数 | 1 | 0 |
| 不支持的嵌套分组 | 1 | 0 |
| 顶层标题调用耗时，注入延迟 | 约 258 ms | 约 0.01 ms |
| 保留的 CRC/SHA 命令 | 13 | 13，全部展平 |
| 普通文本文件的叶子命令 | 19 | 19，名称及顺序相符 |

枚举器批量读取、跳过、重置、克隆游标独立性、重复枚举不重复读取文件、根对象释放后的子命令生命周期，以及所有引用释放后的 `DllCanUnloadNow` 均通过。另行验证了文件夹、中文和空格路径、多文件选择及 7z 归档菜单。

**这些毫秒数是注入延迟后的接口测量，不是资源管理器右键端到端耗时，也不是冷启动性能结论。** 延迟移到了展开子菜单时；实际首次右键和闲置后的等待仍需在桌面账户完成安装后验证。

## 实际文件操作

经适配层返回的原始命令对象执行：

- 生成 SHA-256 校验文件，内容与 `Get-FileHash` 一致。
- 将本地文件压缩成 7z；`7z t` 返回 `Everything is Ok`。
- 经归档菜单解压至子目录，解压后 SHA-256 与原文件一致。

操作测试在调用前释放根命令和枚举器，验证命令仍持有原 DLL。测试未修改原版 7-Zip 程序文件。

## 安装脚本与打包

Windows PowerShell 5.1 + Pester 3.4.0 的 18 项生命周期测试通过，覆盖旧包恢复行为，以及新版安装不再使用 `ExternalLocation` 重定向包内文件。命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester -Script ./tests/Lifecycle.Tests.ps1 -EnableExit"
```

Pester 3.4 的异常断言在 PowerShell 7 下有兼容问题，本次结果使用上述 5.1 环境取得。

原生代码以 `/W4 /WX` 编译通过。DLL 为 132,608 字节，应用激活入口为 100,864 字节；两者静态链接 C++ 运行库。DLL 的直接依赖只有系统 DLL。完整 MSIX 通过 MakeAppx 默认验证，未签名包为 118,906 字节。

当前执行账户是沙箱账户。生成本地签名证书时 `New-SelfSignedCertificate` 返回 `0x80070002`，因此没有签名完成的新版安装包，也未替换桌面账户中的旧版本。尚未完成新版包 COM 激活、安装/卸载实测及资源管理器界面验证。

旧版 `dist` 文件保留用于回退。后续应在正常桌面账户构建到新的空目录，确认签名和测试通过，再按 README 的升级步骤安装。
