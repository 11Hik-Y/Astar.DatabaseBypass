# Astar.DatabaseBypass

[English](README.md) | [简体中文](README.zh-CN.md)

面向 SPT 4.1.x 的服务端 Mod，用于在数据库导入前绕过官方数据库 Hash 一致性校验。

## 功能

Astar.DatabaseBypass 只会在当前服务端进程中关闭 SPT 数据库 Hash 校验。

它**不会**写入、修改或删除数据库文件，也**不会**写入、修改或删除玩家存档文件。

SPT 原有的数据库读取、JSON 解析、反序列化和错误处理仍会正常执行。非法 JSON 和其他数据库错误不会被本 Mod 吞掉。

## 兼容性

- **SPT 4.1.0：** 已完成运行验收。
- **SPT 4.1.x：** 按照官方 4.1.x 服务端源码分支设计兼容。
- 其他 SPT 主版本不在当前声明范围内。

## 安装

1. 关闭 SPT 服务端。
2. 将发布压缩包中的 `SPT_Runtime` 合并到 SPT 安装根目录。
3. 启动 SPT 服务端。

安装后的 DLL 应位于：

```text
SPT_Runtime\user\mods\Astar.DatabaseBypass\Astar.DatabaseBypass.dll
```

## 卸载

关闭 SPT 服务端并删除：

```text
SPT_Runtime\user\mods\Astar.DatabaseBypass
```

卸载后会恢复官方 Hash 校验路径，但不会撤销用户或其他工具此前已经完成的数据库修改。

## 免责声明

使用或二次分发本项目前，请阅读完整的英文 [Disclaimer](DISCLAIMER.md)。

概要：

- 本 Mod 只绕过数据库 Hash 校验；
- 本 Mod 不会修改数据库或玩家存档文件；
- 用户自定义修改和第三方数据库修改所产生的风险由使用者自行承担；
- 建议保留可恢复副本，但不强制要求备份。

## 构建

环境要求：

- 完整的 SPT 4.1.x 安装；
- .NET 10 SDK；
- PowerShell 7。

验证本地 SPT 引用：

```powershell
.\scripts\Verify-References.ps1 `
    -SptInstallRoot "D:\path\to\SPT"
```

构建 Release DLL：

```powershell
.\scripts\Build.ps1 `
    -SptInstallRoot "D:\path\to\SPT" `
    -Configuration Release
```

生成正式分发包：

```powershell
.\scripts\Publish-Release.ps1 `
    -SptInstallRoot "D:\path\to\SPT"
```

## 许可证

Copyright © 2026 Astar。

本仓库中的原创内容采用 [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International Public License](LICENSE.md) 授权，SPDX 标识为 `CC-BY-NC-SA-4.0`。

你可以在非商业目的下分享和修改授权内容，但必须正确署名、注明修改，并以相同许可证或兼容许可证发布衍生内容。

商业使用需要另行取得版权所有者许可。

## 第三方声明

本项目是独立社区项目，与 Battlestate Games 或 SPT 项目不存在隶属、授权、赞助或官方背书关系。

SPT、Escape from Tarkov 及所有引用的第三方组件，仍分别受其权利所有者的许可证、商标及其他权利约束。
