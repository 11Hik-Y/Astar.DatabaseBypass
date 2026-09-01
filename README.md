# Astar.DatabaseBypass

[English](README.md) | [简体中文](README.zh-CN.md)

A server-side mod for **SPT 4.1.x** that bypasses the official database hash consistency check before database import.

## What it does

Astar.DatabaseBypass only disables SPT database hash verification for the current server process. It does **not** write, modify, or delete database files or player profile files.

SPT still performs its normal database reading, JSON parsing, deserialization, and error handling. Invalid JSON and other database errors are not suppressed by this mod.

## Compatibility

SPT 4.1.x performs database hash verification before import. This project builds a separate DLL/package for each exact SPT patch version so the mod metadata and referenced server assemblies match that version exactly.

Validated package targets currently included in the release matrix:

- SPT 4.1.0
- SPT 4.1.1
- SPT 4.1.2
- SPT 4.1.3

Use the ZIP whose `SPT-x.y.z` suffix exactly matches your installed SPT version.

## Installation

1. Stop the SPT server.
2. Choose the ZIP whose `SPT-x.y.z` suffix exactly matches your installed SPT version.
3. Merge the `SPT_Runtime` directory from the ZIP into the SPT installation root.
4. Start the SPT server.

The installed DLL should be located at:

```text
SPT_Runtime\user\mods\Astar.DatabaseBypass\Astar.DatabaseBypass.dll
```

## Uninstallation

Stop the SPT server and delete:

```text
SPT_Runtime\user\mods\Astar.DatabaseBypass
```

Uninstalling restores the official hash verification path. It does not revert database edits that were already made by the user or another tool.

## Disclaimer

Read the full [Disclaimer](DISCLAIMER.md) before using or redistributing this project.

In summary:

- the mod only bypasses database hash verification;
- the mod does not modify database or profile files;
- custom and third-party database edits are used entirely at the user's own risk;
- backups are recommended, but are not mandatory.

## Building

Requirements:

- server assemblies for the exact SPT 4.1.x version being targeted;
- .NET 10 SDK;
- PowerShell 7.

Build one Release DLL from a complete SPT 4.1.x installation:

```powershell
.\scripts\Build.ps1 `
    -SptInstallRoot "D:\path\to\SPT" `
    -Configuration Release
```

Build the exact-version 4.1.x package matrix from archived SPT ZIPs:

```powershell
.\scripts\Package-VersionMatrix.ps1 `
    -SptArchiveRoot "D:\path\to\SPT-version-archives" `
    -DotnetCommand "D:\path\to\dotnet10\dotnet.exe"
```

Packages are written to `artifacts\packages` as `Astar.DatabaseBypass_v0.1.1_SPT-4.1.x.zip` files together with SHA-256 and build-matrix manifests.

## License

Copyright © 2026 Astar.

The original material in this repository is licensed under the [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International Public License](LICENSE.md), SPDX identifier `CC-BY-NC-SA-4.0`.

You may share and adapt the licensed material for noncommercial purposes, provided that you give appropriate attribution, indicate changes, and distribute adapted material under the same license or a compatible license.

Commercial use requires separate permission from the copyright holder.

## Third-party notice

This project is an independent community project. It is not affiliated with, endorsed by, or sponsored by Battlestate Games or the SPT project.

SPT, Escape from Tarkov, and all referenced third-party components remain subject to their respective owners' licenses, trademarks, and other rights.
