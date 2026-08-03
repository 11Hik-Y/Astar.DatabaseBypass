# Astar.DatabaseBypass

SPT 4.1.x 服务端 Mod。关闭 `SPT_Data/database` 的官方 Hash 验证，但保留数据库读取、JSON 解析和后续服务错误。

## 当前版本

`0.1.0-dev`

## 当前状态

- 首个源码实现已完成。
- 尚未在用户完整 SPT 4.1.0 环境中编译。
- 尚未完成运行验收。

## 设计

Mod DLL 加载时通过模块初始化器提前安装 Harmony Prefix。Prefix 只把：

```csharp
shouldVerifyDatabase = false;
```

然后继续执行官方 `LoadDatabaseAsync`。

## 风险

安装后，SPT 不再验证数据库文件是否与官方 Hash 一致。错误修改仍可能导致服务端无法启动、运行异常或存档问题。Mod 不吞掉 JSON 错误，也不保证第三方修改可用。

## 构建

需要：

- 完整 SPT 4.1.x 安装；
- .NET 10 SDK；
- PowerShell 7。

```powershell
.\scripts\Verify-References.ps1 -SptInstallRoot D:\game\SPT-4.1.0-40743-e18bd1e
.\scripts\Build.ps1 -SptInstallRoot D:\game\SPT-4.1.0-40743-e18bd1e -Configuration Debug
```
