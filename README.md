# Astar.DatabaseBypass

[English](README.md) | [简体中文](README.zh-CN.md)

A server-side mod for SPT 4.1.x that bypasses the official database hash consistency check before database import.

## What it does

Astar.DatabaseBypass only disables SPT database hash verification for the current server process.

It does **not** write, modify, or delete database files. It also does **not** write, modify, or delete player profile files.

SPT still performs its normal database reading, JSON parsing, deserialization, and error handling. Invalid JSON and other database errors are not suppressed by this mod.

## Compatibility

- **SPT 4.1.0:** runtime acceptance completed.
- **SPT 4.1.x:** designed against the official 4.1.x server source line.
- Other major SPT versions are outside the declared compatibility range.

## Installation

1. Stop the SPT server.
2. Merge the `SPT_Runtime` directory from the release archive into the SPT installation root.
3. Start the SPT server.

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

- a complete SPT 4.1.x installation;
- .NET 10 SDK;
- PowerShell 7.

Verify local SPT references:

```powershell
.\scripts\Verify-References.ps1 `
    -SptInstallRoot "D:\path\to\SPT"
```

Build a Release DLL:

```powershell
.\scripts\Build.ps1 `
    -SptInstallRoot "D:\path\to\SPT" `
    -Configuration Release
```

Create the distributable package:

```powershell
.\scripts\Publish-Release.ps1 `
    -SptInstallRoot "D:\path\to\SPT"
```

## License

Copyright © 2026 Astar.

The original material in this repository is licensed under the [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International Public License](LICENSE.md), SPDX identifier `CC-BY-NC-SA-4.0`.

You may share and adapt the licensed material for noncommercial purposes, provided that you give appropriate attribution, indicate changes, and distribute adapted material under the same license or a compatible license.

Commercial use requires separate permission from the copyright holder.

## Third-party notice

This project is an independent community project. It is not affiliated with, endorsed by, or sponsored by Battlestate Games or the SPT project.

SPT, Escape from Tarkov, and all referenced third-party components remain subject to their respective owners' licenses, trademarks, and other rights.
