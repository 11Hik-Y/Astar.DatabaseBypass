[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SptArchiveRoot,
    [string[]]$SptVersions = @(),
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [string]$DotnetCommand = "dotnet"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$RepoRoot = Split-Path $PSScriptRoot -Parent
$Project = Join-Path $RepoRoot "src\Astar.DatabaseBypass\Astar.DatabaseBypass.csproj"
$BuildScript = Join-Path $PSScriptRoot "Build.ps1"
$DisclaimerSource = Join-Path $RepoRoot "DISCLAIMER.md"
$ReferenceCacheRoot = Join-Path $RepoRoot "artifacts\spt-refs"
$PackageStage = Join-Path $RepoRoot "artifacts\package"
$PackageRoot = Join-Path $RepoRoot "artifacts\packages"
$SptArchiveRoot = [System.IO.Path]::GetFullPath($SptArchiveRoot)

if (-not (Test-Path -LiteralPath $BuildScript -PathType Leaf)) { throw "未找到构建脚本：$BuildScript" }
if (-not (Test-Path -LiteralPath $DisclaimerSource -PathType Leaf)) { throw "未找到免责声明：$DisclaimerSource" }
if (-not (Test-Path -LiteralPath $SptArchiveRoot -PathType Container)) { throw "SPT 版本包目录不存在：$SptArchiveRoot" }

$ProjectText = Get-Content -LiteralPath $Project -Raw
$VersionMatch = [regex]::Match($ProjectText, '<Version>(?<version>[^<]+)</Version>')
if (-not $VersionMatch.Success) { throw "无法从项目文件读取 Mod 版本号。" }
$ModVersion = $VersionMatch.Groups['version'].Value

Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

$ArchiveCandidates = @(
    Get-ChildItem -LiteralPath $SptArchiveRoot -File -Filter "SPT-4.1.*.zip" |
        ForEach-Object {
            $match = [regex]::Match($_.Name, '^SPT-(?<version>4\.1\.\d+)-.+\.zip$')
            if ($match.Success) {
                [pscustomobject]@{
                    VersionText = $match.Groups['version'].Value
                    Version = [version]$match.Groups['version'].Value
                    Archive = $_
                }
            }
        }
)

if ($ArchiveCandidates.Count -eq 0) { throw "没有找到 SPT 4.1.x ZIP。" }

$SelectedTargets = @(
    $ArchiveCandidates |
        Group-Object VersionText |
        ForEach-Object {
            $selected = $_.Group |
                Sort-Object @{ Expression = { $_.Archive.LastWriteTimeUtc }; Descending = $true }, @{ Expression = { $_.Archive.Name }; Descending = $true } |
                Select-Object -First 1

            if ($_.Count -gt 1) {
                $skipped = @($_.Group | Where-Object { $_.Archive.FullName -ne $selected.Archive.FullName } | ForEach-Object { $_.Archive.Name }) -join ', '
                Write-Host "SPT $($_.Name) 存在多个归档；使用 $($selected.Archive.Name)，其余不重复产包：$skipped" -ForegroundColor Yellow
            }

            $selected
        } |
        Sort-Object Version
)

if ($SptVersions.Count -gt 0) {
    $wanted = [System.Collections.Generic.HashSet[string]]::new([string[]]$SptVersions, [System.StringComparer]::OrdinalIgnoreCase)
    $SelectedTargets = @($SelectedTargets | Where-Object { $wanted.Contains($_.VersionText) })
    $found = @($SelectedTargets.VersionText)
    $missing = @($SptVersions | Where-Object { $_ -notin $found })
    if ($missing.Count -gt 0) { throw "未找到请求的 SPT 版本：$($missing -join ', ')" }
}

if ($SelectedTargets.Count -eq 0) { throw "没有可构建的 SPT 4.1.x 目标版本。" }

$RequiredAssemblies = @(
    "SPT.Server.dll",
    "SPTarkov.Server.Core.dll",
    "SPTarkov.Reflection.dll",
    "SPTarkov.Common.dll",
    "SPTarkov.DI.dll",
    "SemanticVersioning.dll",
    "0Harmony.dll"
)

if (Test-Path -LiteralPath $PackageRoot -PathType Container) { Remove-Item -LiteralPath $PackageRoot -Recurse -Force }
if (Test-Path -LiteralPath $ReferenceCacheRoot -PathType Container) { Remove-Item -LiteralPath $ReferenceCacheRoot -Recurse -Force }
New-Item -ItemType Directory -Path $PackageRoot -Force | Out-Null
New-Item -ItemType Directory -Path $ReferenceCacheRoot -Force | Out-Null

$Results = [System.Collections.Generic.List[object]]::new()

foreach ($target in $SelectedTargets) {
    $SptVersion = $target.VersionText
    $ServerDirectoryName = "SPT_Runtime"
    $Framework = "net10.0"

    Write-Host "`n=== SPT $SptVersion / $Framework ===" -ForegroundColor Cyan
    Write-Host "Archive: $($target.Archive.Name)"
    Write-Host "dotnet: $DotnetCommand"

    $ReferenceInstallRoot = Join-Path $ReferenceCacheRoot "SPT-$SptVersion"
    $ReferenceServerRoot = Join-Path $ReferenceInstallRoot $ServerDirectoryName
    New-Item -ItemType Directory -Path $ReferenceServerRoot -Force | Out-Null

    $zip = [System.IO.Compression.ZipFile]::OpenRead($target.Archive.FullName)
    try {
        foreach ($assemblyName in $RequiredAssemblies) {
            $entryName = "$ServerDirectoryName/$assemblyName"
            $entry = $zip.GetEntry($entryName)
            if ($null -eq $entry) { throw "$($target.Archive.Name) 缺少 $entryName" }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $ReferenceServerRoot $assemblyName), $true)
        }
    }
    finally { $zip.Dispose() }

    $ServerDll = Join-Path $ReferenceServerRoot "SPT.Server.dll"
    $ServerAssemblyVersion = [Reflection.AssemblyName]::GetAssemblyName($ServerDll).Version
    $AssemblySemVer = "$($ServerAssemblyVersion.Major).$($ServerAssemblyVersion.Minor).$($ServerAssemblyVersion.Build)"
    if ($AssemblySemVer -ne $SptVersion) {
        throw "归档名版本 $SptVersion 与 SPT.Server.dll AssemblyVersion $AssemblySemVer 不一致。"
    }

    & $BuildScript -SptInstallRoot $ReferenceInstallRoot -Configuration $Configuration -DotnetCommand $DotnetCommand

    $ModStage = Join-Path $PackageStage "$ServerDirectoryName\user\mods\Astar.DatabaseBypass"
    $DllPath = Join-Path $ModStage "Astar.DatabaseBypass.dll"
    $DisclaimerPath = Join-Path $ModStage "DISCLAIMER.txt"
    Copy-Item -LiteralPath $DisclaimerSource -Destination $DisclaimerPath -Force

    $ExpectedStageNames = @("Astar.DatabaseBypass.dll", "DISCLAIMER.txt") | Sort-Object
    $ActualStageNames = @(Get-ChildItem -LiteralPath $ModStage -File -Recurse | Select-Object -ExpandProperty Name) | Sort-Object
    if (@(Compare-Object -ReferenceObject $ExpectedStageNames -DifferenceObject $ActualStageNames).Count -gt 0) {
        throw "SPT $SptVersion 的打包暂存目录白名单验证失败。"
    }

    $PackageName = "Astar.DatabaseBypass_v${ModVersion}_SPT-${SptVersion}.zip"
    $ZipPath = Join-Path $PackageRoot $PackageName
    [System.IO.Compression.ZipFile]::CreateFromDirectory($PackageStage, $ZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

    $ExpectedZipEntries = @(
        "SPT_Runtime/user/mods/Astar.DatabaseBypass/Astar.DatabaseBypass.dll",
        "SPT_Runtime/user/mods/Astar.DatabaseBypass/DISCLAIMER.txt"
    ) | Sort-Object

    $roundTrip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $ActualZipEntries = @($roundTrip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) } | ForEach-Object { $_.FullName.Replace('\', '/') }) | Sort-Object
        if (@(Compare-Object -ReferenceObject $ExpectedZipEntries -DifferenceObject $ActualZipEntries).Count -gt 0) {
            throw "SPT $SptVersion 的 ZIP 内容白名单验证失败。"
        }
    }
    finally { $roundTrip.Dispose() }

    $DllHash = (Get-FileHash -LiteralPath $DllPath -Algorithm SHA256).Hash
    $ZipHash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash

    $Results.Add([pscustomobject]@{
        SptVersion = $SptVersion
        Framework = $Framework
        Dotnet = $DotnetCommand
        Archive = $target.Archive.Name
        AssemblyVersion = $ServerAssemblyVersion.ToString()
        DllSha256 = $DllHash
        Package = $PackageName
        ZipSha256 = $ZipHash
    })

    Write-Host "Package: $ZipPath" -ForegroundColor Green
    Write-Host "DLL SHA-256: $DllHash"
    Write-Host "ZIP SHA-256: $ZipHash"
}

$ShaPath = Join-Path $PackageRoot "SHA256.txt"
[System.IO.File]::WriteAllLines($ShaPath, @($Results | ForEach-Object { "$($_.ZipSha256)  $($_.Package)" }), [System.Text.UTF8Encoding]::new($false))

$MatrixPath = Join-Path $PackageRoot "BUILD-MATRIX.txt"
$MatrixLines = [System.Collections.Generic.List[string]]::new()
$MatrixLines.Add("Astar.DatabaseBypass SPT 4.1.x package matrix")
$MatrixLines.Add("Mod version: $ModVersion")
$MatrixLines.Add("")
foreach ($result in $Results) {
    $MatrixLines.Add("SPT $($result.SptVersion)")
    $MatrixLines.Add("  Framework: $($result.Framework)")
    $MatrixLines.Add("  Archive: $($result.Archive)")
    $MatrixLines.Add("  SPT.Server AssemblyVersion: $($result.AssemblyVersion)")
    $MatrixLines.Add("  DLL SHA-256: $($result.DllSha256)")
    $MatrixLines.Add("  Package: $($result.Package)")
    $MatrixLines.Add("  ZIP SHA-256: $($result.ZipSha256)")
    $MatrixLines.Add("")
}
[System.IO.File]::WriteAllLines($MatrixPath, $MatrixLines, [System.Text.UTF8Encoding]::new($false))

Write-Host "`nSPT 4.1.x 精确版本包全部构建完成。" -ForegroundColor Green
Write-Host "Packages: $PackageRoot"
Write-Host "SHA-256: $ShaPath"
Write-Host "Matrix: $MatrixPath"
