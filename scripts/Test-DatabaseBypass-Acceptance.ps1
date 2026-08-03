[CmdletBinding()]
param(
    [string]$SptRoot = "D:\game\SPT-4.1.0-40743-e18bd1e",
    [string]$RepositoryRoot = "C:\D\repository\SPT_derive",
    [string]$AnalysisRoot = "D:\SPT_4_1_ModDev_TEMP",
    [int]$StartupTimeoutSeconds = 60,
    [int]$ServerPort = 6969
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$ServerRuntime = Join-Path $SptRoot "SPT_Runtime"
$ServerExe = Join-Path $ServerRuntime "SPT.Server.exe"
$ChecksPath = Join-Path $ServerRuntime "SPT_Data\checks.dat"
$ModDirectory = Join-Path $ServerRuntime "user\mods\Astar.DatabaseBypass"
$ServerRepo = Join-Path $RepositoryRoot "Astar.DatabaseBypass"
$PlanningRoot = Join-Path $AnalysisRoot (
    "planning\Astar_SPT_4_1_DualMod_" +
    "DevelopmentBaseline_v1.1_20260803"
)

$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$EvidenceRoot = Join-Path $AnalysisRoot (
    "evidence\server-s1-acceptance-$Stamp"
)
$EvidenceZip = "$EvidenceRoot.zip"
$HeldModDirectory = Join-Path $EvidenceRoot (
    "held-mod\Astar.DatabaseBypass"
)

New-Item -ItemType Directory -Path $EvidenceRoot -Force |
    Out-Null

function Test-TcpPort {
    param(
        [Parameter(Mandatory)]
        [int]$Port
    )

    $Client = [System.Net.Sockets.TcpClient]::new()

    try {
        $Task = $Client.ConnectAsync("127.0.0.1", $Port)

        if (-not $Task.Wait(500)) {
            return $false
        }

        return $Client.Connected
    }
    catch {
        return $false
    }
    finally {
        $Client.Dispose()
    }
}

function Stop-TrialProcess {
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process]$Process
    )

    try {
        $Process.Refresh()

        if (-not $Process.HasExited) {
            Stop-Process -Id $Process.Id -Force
        }
    }
    catch {
        Write-Warning (
            "停止测试服务端时出现异常：" +
            $_.Exception.Message
        )
    }

    try {
        $Process.WaitForExit(10000) | Out-Null
    }
    catch {
        # Ignore final wait errors.
    }
}

function Invoke-ServerTrial {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet("Ready", "ValidationFailure", "JsonFailure")]
        [string]$ExpectedOutcome
    )

    $TrialRoot = Join-Path $EvidenceRoot $Name
    $StdOutPath = Join-Path $TrialRoot "stdout.log"
    $StdErrPath = Join-Path $TrialRoot "stderr.log"

    New-Item -ItemType Directory -Path $TrialRoot -Force |
        Out-Null

    if (Test-TcpPort -Port $ServerPort) {
        throw "端口 $ServerPort 已被占用。"
    }

    Write-Host ""
    Write-Host "启动测试：$Name" -ForegroundColor Cyan
    Write-Host "预期结果：$ExpectedOutcome"

    $Process = Start-Process `
        -FilePath $ServerExe `
        -WorkingDirectory $ServerRuntime `
        -RedirectStandardOutput $StdOutPath `
        -RedirectStandardError $StdErrPath `
        -PassThru

    $Ready = $false
    $NaturalExit = $false
    $Deadline = (Get-Date).AddSeconds(
        $StartupTimeoutSeconds
    )

    try {
        while ((Get-Date) -lt $Deadline) {
            Start-Sleep -Milliseconds 500
            $Process.Refresh()

            if ($Process.HasExited) {
                $NaturalExit = $true
                break
            }

            if (Test-TcpPort -Port $ServerPort) {
                $Ready = $true
                break
            }
        }
    }
    finally {
        if ($Ready) {
            Start-Sleep -Seconds 2
        }

        Stop-TrialProcess -Process $Process
        Start-Sleep -Milliseconds 500
    }

    $StdOut = ""
    $StdErr = ""

    if (Test-Path -LiteralPath $StdOutPath -PathType Leaf) {
        $StdOut = [System.IO.File]::ReadAllText(
            $StdOutPath
        )
    }

    if (Test-Path -LiteralPath $StdErrPath -PathType Leaf) {
        $StdErr = [System.IO.File]::ReadAllText(
            $StdErrPath
        )
    }

    $Combined = $StdOut + "`n" + $StdErr

    $EarlyPatchSeen = (
        $Combined -match
        "Early database-verification patch installed"
    )

    $WarningSeen = (
        $Combined -match
        "SPT database hash verification has been disabled"
    )

    $ValidationFailureSeen = (
        $Combined -match (
            "ValidationErrorException|" +
            "validation_error|" +
            "validation error|" +
            "database.*hash|" +
            "hash.*(invalid|match|changed|modified)|" +
            "checks\.dat|" +
            "MD5|" +
            "哈希|" +
            "校验|" +
            "验证"
        )
    )

    $JsonFailureSeen = (
        $Combined -match (
            "JsonException|" +
            "JsonReaderException|" +
            "JsonSerializationException|" +
            "invalid.*JSON|" +
            "Unexpected.*character|" +
            "deserialize|" +
            "trailing.*data|" +
            "反序列|" +
            "JSON.*(错误|无效)|" +
            "解析.*失败"
        )
    )

    $Passed = $false

    if ($ExpectedOutcome -eq "Ready") {
        $Passed = (
            $Ready -and
            $EarlyPatchSeen -and
            $WarningSeen
        )
    }

    if ($ExpectedOutcome -eq "ValidationFailure") {
        $Passed = (
            (-not $Ready) -and
            $ValidationFailureSeen
        )
    }

    if ($ExpectedOutcome -eq "JsonFailure") {
        $Passed = (
            (-not $Ready) -and
            $JsonFailureSeen
        )
    }

    $Result = [pscustomobject]@{
        Name = $Name
        ExpectedOutcome = $ExpectedOutcome
        Passed = $Passed
        Ready = $Ready
        NaturalExit = $NaturalExit
        EarlyPatchSeen = $EarlyPatchSeen
        WarningSeen = $WarningSeen
        ValidationFailureSeen = $ValidationFailureSeen
        JsonFailureSeen = $JsonFailureSeen
        StdOutPath = $StdOutPath
        StdErrPath = $StdErrPath
    }

    $Result |
        ConvertTo-Json -Depth 5 |
        Set-Content `
            -LiteralPath (Join-Path $TrialRoot "result.json") `
            -Encoding utf8NoBOM

    $Result | Format-List | Out-Host

    return $Result
}

function Assert-JsonValid {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $Stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read
    )

    try {
        $Options = [System.Text.Json.JsonDocumentOptions]::new()

        $Document = [System.Text.Json.JsonDocument]::Parse(
            [System.IO.Stream]$Stream,
            $Options
        )

        try {
            # A successful parse is the assertion.
        }
        finally {
            $Document.Dispose()
        }
    }
    finally {
        $Stream.Dispose()
    }
}

function Assert-JsonInvalid {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $Invalid = $false

    $Stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read
    )

    try {
        try {
            $Options = [System.Text.Json.JsonDocumentOptions]::new()

            $Document = [System.Text.Json.JsonDocument]::Parse(
                [System.IO.Stream]$Stream,
                $Options
            )

            try {
                # Reaching this point means the file is still valid JSON.
            }
            finally {
                $Document.Dispose()
            }
        }
        catch {
            $Invalid = $true
        }
    }
    finally {
        $Stream.Dispose()
    }

    if (-not $Invalid) {
        throw "测试文件仍然是有效 JSON。"
    }
}

function Restore-TargetFile {
    param(
        [Parameter(Mandatory)]
        [string]$TargetPath,

        [Parameter(Mandatory)]
        [byte[]]$OriginalBytes,

        [Parameter(Mandatory)]
        [string]$OriginalSha256
    )

    [System.IO.File]::WriteAllBytes(
        $TargetPath,
        $OriginalBytes
    )

    $RestoredHash = (
        Get-FileHash `
            -LiteralPath $TargetPath `
            -Algorithm SHA256
    ).Hash

    if ($RestoredHash -ne $OriginalSha256) {
        throw (
            "数据库测试文件恢复失败。" +
            "`nExpected SHA-256: $OriginalSha256" +
            "`nActual SHA-256:   $RestoredHash"
        )
    }
}

Write-Host "`n=== 1. 验证验收环境 ===" `
    -ForegroundColor Cyan

foreach ($Path in @(
    $ServerExe,
    $ChecksPath,
    (Join-Path $ModDirectory "Astar.DatabaseBypass.dll")
)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "缺少验收文件：$Path"
    }
}

$ExistingServers = @(
    Get-Process `
        -Name "SPT.Server" `
        -ErrorAction SilentlyContinue
)

if ($ExistingServers.Count -gt 0) {
    throw "检测到正在运行的 SPT.Server，请先关闭。"
}

if (Test-TcpPort -Port $ServerPort) {
    throw "端口 $ServerPort 已被占用。"
}

Write-Host "验收环境通过。" -ForegroundColor Green

Write-Host "`n=== 2. 从 checks.dat 选择测试文件 ===" `
    -ForegroundColor Cyan

$Base64Content = (
    [System.IO.File]::ReadAllText($ChecksPath)
).Trim()

$ChecksJson = [System.Text.Encoding]::UTF8.GetString(
    [System.Convert]::FromBase64String($Base64Content)
)

$HashEntries = @(
    $ChecksJson | ConvertFrom-Json
)

if ($HashEntries.Count -eq 0) {
    throw "checks.dat 中没有 Hash 条目。"
}

$SelectedEntry = @(
    $HashEntries |
        Where-Object {
            [string]$_.Path -eq "database/globals.json"
        }
) |
    Select-Object -First 1

if ($null -eq $SelectedEntry) {
    $SelectedEntry = @(
        $HashEntries |
            Where-Object {
                ([string]$_.Path).EndsWith(
                    ".json",
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            }
    ) |
        Select-Object -First 1
}

if ($null -eq $SelectedEntry) {
    throw "无法从 checks.dat 中找到 JSON 条目。"
}

$RelativePath = (
    [string]$SelectedEntry.Path
).Replace("/", "\")

$TargetPath = Join-Path `
    (Join-Path $ServerRuntime "SPT_Data") `
    $RelativePath

if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
    throw "测试文件不存在：$TargetPath"
}

$ExpectedMd5 = (
    [string]$SelectedEntry.Hash
).ToUpperInvariant()

$OriginalMd5 = (
    Get-FileHash `
        -LiteralPath $TargetPath `
        -Algorithm MD5
).Hash

if ($OriginalMd5 -ne $ExpectedMd5) {
    throw (
        "测试前数据库已不匹配 checks.dat，拒绝覆盖。" +
        "`nFile: $TargetPath" +
        "`nExpected MD5: $ExpectedMd5" +
        "`nActual MD5:   $OriginalMd5"
    )
}

Assert-JsonValid -Path $TargetPath

$OriginalBytes = [System.IO.File]::ReadAllBytes(
    $TargetPath
)

$OriginalSha256 = (
    Get-FileHash `
        -LiteralPath $TargetPath `
        -Algorithm SHA256
).Hash

Copy-Item `
    -LiteralPath $TargetPath `
    -Destination (Join-Path $EvidenceRoot "database-original.json") `
    -Force

Write-Host "测试文件：$TargetPath"
Write-Host "官方 MD5：$ExpectedMd5"
Write-Host "原始 SHA-256：$OriginalSha256"

$ControlResult = $null
$BypassResult = $null
$InvalidResult = $null
$ModIsHeld = $false

try {
    Write-Host "`n=== 3. 制造合法 JSON Hash 不匹配 ===" `
        -ForegroundColor Cyan

    $WhitespaceSuffix = (
        [System.Text.Encoding]::UTF8.GetBytes(
            "`r`n "
        )
    )

    $ValidModifiedBytes = [byte[]](
        $OriginalBytes + $WhitespaceSuffix
    )

    [System.IO.File]::WriteAllBytes(
        $TargetPath,
        $ValidModifiedBytes
    )

    Assert-JsonValid -Path $TargetPath

    $ModifiedMd5 = (
        Get-FileHash `
            -LiteralPath $TargetPath `
            -Algorithm MD5
    ).Hash

    if ($ModifiedMd5 -eq $ExpectedMd5) {
        throw "合法修改未改变 MD5。"
    }

    Write-Host "修改后 MD5：$ModifiedMd5"
    Write-Host "JSON 有效且 Hash 已变化。" `
        -ForegroundColor Green

    Write-Host (
        "`n=== 4. 对照：无 Mod 时应被官方校验阻止 ==="
    ) -ForegroundColor Cyan

    New-Item `
        -ItemType Directory `
        -Path (Split-Path $HeldModDirectory -Parent) `
        -Force |
        Out-Null

    Move-Item `
        -LiteralPath $ModDirectory `
        -Destination $HeldModDirectory

    $ModIsHeld = $true

    $ControlResult = Invoke-ServerTrial `
        -Name "01-control-without-mod" `
        -ExpectedOutcome "ValidationFailure"

    Move-Item `
        -LiteralPath $HeldModDirectory `
        -Destination $ModDirectory

    $ModIsHeld = $false

    Write-Host (
        "`n=== 5. 有 Mod 时合法 Hash 不匹配应成功启动 ==="
    ) -ForegroundColor Cyan

    $BypassResult = Invoke-ServerTrial `
        -Name "02-valid-hash-mismatch-with-mod" `
        -ExpectedOutcome "Ready"

    Write-Host (
        "`n=== 6. 有 Mod 时非法 JSON 仍必须失败 ==="
    ) -ForegroundColor Cyan

    $InvalidSuffix = (
        [System.Text.Encoding]::UTF8.GetBytes(
            "`r`n{"
        )
    )

    $InvalidBytes = [byte[]](
        $OriginalBytes + $InvalidSuffix
    )

    [System.IO.File]::WriteAllBytes(
        $TargetPath,
        $InvalidBytes
    )

    Assert-JsonInvalid -Path $TargetPath

    $InvalidResult = Invoke-ServerTrial `
        -Name "03-invalid-json-with-mod" `
        -ExpectedOutcome "JsonFailure"
}
finally {
    Write-Host "`n=== 7. 恢复数据库和 Mod ===" `
        -ForegroundColor Cyan

    if ($ModIsHeld) {
        if (Test-Path -LiteralPath $HeldModDirectory) {
            Move-Item `
                -LiteralPath $HeldModDirectory `
                -Destination $ModDirectory
        }
    }

    Restore-TargetFile `
        -TargetPath $TargetPath `
        -OriginalBytes $OriginalBytes `
        -OriginalSha256 $OriginalSha256

    Assert-JsonValid -Path $TargetPath

    if (-not (Test-Path -LiteralPath $ModDirectory -PathType Container)) {
        throw "服务端 Mod 目录未恢复。"
    }

    Write-Host "数据库和 Mod 已恢复。" `
        -ForegroundColor Green
}

Write-Host "`n=== 8. 汇总结果 ===" `
    -ForegroundColor Cyan

if ($null -eq $ControlResult) {
    throw "缺少无 Mod 对照结果。"
}

if ($null -eq $BypassResult) {
    throw "缺少有 Mod 绕过结果。"
}

if ($null -eq $InvalidResult) {
    throw "缺少非法 JSON 结果。"
}

$ControlPassed = [bool]$ControlResult.Passed
$BypassPassed = [bool]$BypassResult.Passed
$InvalidJsonPassed = [bool]$InvalidResult.Passed

$AcceptancePassed = (
    $ControlPassed -and
    $BypassPassed -and
    $InvalidJsonPassed
)

$Results = @(
    $ControlResult,
    $BypassResult,
    $InvalidResult
)

$Results |
    Export-Csv `
        -LiteralPath (Join-Path $EvidenceRoot "trial-results.csv") `
        -NoTypeInformation `
        -Encoding utf8

$Results |
    ConvertTo-Json -Depth 6 |
    Set-Content `
        -LiteralPath (Join-Path $EvidenceRoot "trial-results.json") `
        -Encoding utf8NoBOM

$Summary = [ordered]@{
    GeneratedAt = (Get-Date).ToString("o")
    SptRoot = $SptRoot
    TargetPath = $TargetPath
    ExpectedMd5 = $ExpectedMd5
    OriginalMd5 = $OriginalMd5
    OriginalSha256 = $OriginalSha256
    ControlWithoutModPassed = $ControlPassed
    ValidHashMismatchWithModPassed = $BypassPassed
    InvalidJsonWithModPassed = $InvalidJsonPassed
    AcceptancePassed = $AcceptancePassed
    DatabaseRestored = $true
    ModDirectoryRestored = $true
    EvidenceRoot = $EvidenceRoot
    EvidenceZip = $EvidenceZip
}

$Summary |
    ConvertTo-Json -Depth 6 |
    Set-Content `
        -LiteralPath (Join-Path $EvidenceRoot "SUMMARY.json") `
        -Encoding utf8NoBOM

$SummaryLines = @(
    "Astar.DatabaseBypass S1 Acceptance",
    "",
    "Target: $TargetPath",
    "Expected MD5: $ExpectedMd5",
    "Original SHA-256: $OriginalSha256",
    "",
    "Control without Mod passed: $ControlPassed",
    "Valid Hash mismatch with Mod passed: $BypassPassed",
    "Invalid JSON with Mod passed: $InvalidJsonPassed",
    "",
    "Acceptance passed: $AcceptancePassed",
    "Database restored: True",
    "Mod directory restored: True"
)

$SummaryLines |
    Set-Content `
        -LiteralPath (Join-Path $EvidenceRoot "SUMMARY.txt") `
        -Encoding utf8NoBOM

$SummaryLines | ForEach-Object {
    Write-Host $_
}

Write-Host "`n=== 9. 生成证据 ZIP ===" `
    -ForegroundColor Cyan

$Manifest = @(
    Get-ChildItem `
        -LiteralPath $EvidenceRoot `
        -File `
        -Recurse |
        Sort-Object FullName |
        ForEach-Object {
            [pscustomobject]@{
                RelativePath = [System.IO.Path]::GetRelativePath(
                    $EvidenceRoot,
                    $_.FullName
                )
                Length = $_.Length
                SHA256 = (
                    Get-FileHash `
                        -LiteralPath $_.FullName `
                        -Algorithm SHA256
                ).Hash
            }
        }
)

$Manifest |
    Export-Csv `
        -LiteralPath (Join-Path $EvidenceRoot "MANIFEST.csv") `
        -NoTypeInformation `
        -Encoding utf8

$Manifest |
    ConvertTo-Json -Depth 4 |
    Set-Content `
        -LiteralPath (Join-Path $EvidenceRoot "MANIFEST.json") `
        -Encoding utf8NoBOM

if (Test-Path -LiteralPath $EvidenceZip -PathType Leaf) {
    Remove-Item -LiteralPath $EvidenceZip -Force
}

Compress-Archive `
    -Path (Join-Path $EvidenceRoot "*") `
    -DestinationPath $EvidenceZip `
    -CompressionLevel Optimal

$ZipHash = (
    Get-FileHash `
        -LiteralPath $EvidenceZip `
        -Algorithm SHA256
).Hash

$RepoScriptPath = Join-Path $ServerRepo (
    "scripts\Test-DatabaseBypass-Acceptance.ps1"
)

Copy-Item `
    -LiteralPath $PSCommandPath `
    -Destination $RepoScriptPath `
    -Force


Write-Host "`n=== 10. 更新权威规划与 Fika 优先级 ===" `
    -ForegroundColor Cyan

if (Test-Path -LiteralPath $PlanningRoot -PathType Container) {
    $DecisionLogPath = Join-Path $PlanningRoot "DECISION_LOG.md"

    if (Test-Path -LiteralPath $DecisionLogPath -PathType Leaf) {
        $DecisionText = [System.IO.File]::ReadAllText(
            $DecisionLogPath
        )

        if (
            $DecisionText -notmatch
            "D-015：当前优先离线单人，Fika 验收延期"
        ) {
            $DecisionEntry = @'

## 2026-08-03 D-015：当前优先离线单人，Fika 验收延期

状态：已采纳

- 当前正式开发和验收以 SPT 4.1.0 离线单人为主。
- Fika 4.1.x 尚未纳入当前可运行基线。
- Fika Host、Client 和 StrictSync 验收不阻塞 C1 至 C7。
- 等兼容 SPT 4.1.x 的 Fika 版本可用并稳定后，再恢复 C8。
- 当前客户端代码仍保留兼容层边界，禁止引入阻碍后续 Fika 适配的直接库存写入。
'@

            [System.IO.File]::AppendAllText(
                $DecisionLogPath,
                $DecisionEntry,
                [System.Text.UTF8Encoding]::new($false)
            )
        }
    }

    $ProjectStatePath = Join-Path $PlanningRoot "PROJECT_STATE.json"

    if (Test-Path -LiteralPath $ProjectStatePath -PathType Leaf) {
        $State = Get-Content `
            -LiteralPath $ProjectStatePath `
            -Raw |
            ConvertFrom-Json

        $State.updatedAt = (Get-Date).ToString("o")
        $State.server.compileStatus = "PASSED"

        if ($AcceptancePassed) {
            $State.server.runtimeStatus = "S1_ACCEPTANCE_PASSED"
        }
        else {
            $State.server.runtimeStatus = "S1_ACCEPTANCE_FAILED"
        }

        $State.server |
            Add-Member `
                -NotePropertyName latestEvidence `
                -NotePropertyValue $EvidenceZip `
                -Force

        $State |
            Add-Member `
                -NotePropertyName currentProductPriority `
                -NotePropertyValue "OFFLINE_SINGLE_PLAYER" `
                -Force

        $State |
            Add-Member `
                -NotePropertyName fikaValidation `
                -NotePropertyValue (
                    "DEFERRED_UNTIL_SPT_4_1_COMPATIBLE_RELEASE"
                ) `
                -Force

        $State |
            ConvertTo-Json -Depth 12 |
            Set-Content `
                -LiteralPath $ProjectStatePath `
                -Encoding utf8NoBOM
    }

    $PhaseLedgerPath = Join-Path $PlanningRoot "PHASE_LEDGER.json"

    if (Test-Path -LiteralPath $PhaseLedgerPath -PathType Leaf) {
        $Ledger = Get-Content `
            -LiteralPath $PhaseLedgerPath `
            -Raw |
            ConvertFrom-Json

        foreach ($Phase in @($Ledger.phases)) {
            if ($Phase.id -eq "S0") {
                $Phase.status = "PASSED"
            }

            if ($Phase.id -eq "S1") {
                if ($AcceptancePassed) {
                    $Phase.status = "PASSED"
                }
                else {
                    $Phase.status = "FAILED_REVIEW_EVIDENCE"
                }
            }

            if ($Phase.id -eq "C0") {
                $Phase.status = "RUNTIME_PROBE_PASSED"
            }

            if ($Phase.id -eq "C1") {
                $Phase.status = "READY_TO_START"
            }

            if ($Phase.id -eq "C8") {
                $Phase.status = (
                    "DEFERRED_UNTIL_FIKA_SPT_4_1_COMPATIBLE"
                )
            }
        }

        $Ledger |
            ConvertTo-Json -Depth 12 |
            Set-Content `
                -LiteralPath $PhaseLedgerPath `
                -Encoding utf8NoBOM
    }

    $CurrentStatePath = Join-Path $PlanningRoot "CURRENT_STATE.md"

    $CurrentStateLines = @(
        "# 当前状态",
        "",
        "更新时间：$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'))",
        "",
        "## 当前阶段目标",
        "",
        "封板服务端数据库 Hash 绕过，并开始面向离线单人的客户端 C1 静态分析。",
        "",
        "## 当前已完成",
        "",
        "- 服务端 Mod 已编译、安装并通过启动命中验证。",
        "- 客户端 C0 安全探针运行通过。",
        "- 服务端无 Mod Hash 对照通过：$ControlPassed。",
        "- 服务端有 Mod Hash 绕过通过：$BypassPassed。",
        "- 服务端非法 JSON 保护通过：$InvalidJsonPassed。",
        "- 服务端 S1 总体验收：$AcceptancePassed。",
        "",
        "## 剩余未完成",
        "",
        "- 两个仓库首次 Git 基线提交。",
        "- 客户端 C1 关键 DLL 静态分析。",
        "- 客户端 C2 离线单人只读运行探针。",
        "- C3 至 C7 离线单人功能开发与验收。",
        "- C8 Fika 验收等待兼容 SPT 4.1.x 的 Fika 版本。",
        "",
        "## 阶段新增信息",
        "",
        "- 当前产品优先级锁定为离线单人。",
        "- Fika 不再阻塞当前客户端开发。",
        "- 客户端仍保留 Fika 兼容边界，避免未来重构库存事务核心。",
        "",
        "## 下一步动作",
        "",
        "服务端验收通过后建立两个仓库基线提交，并导出客户端关键程序集进入 C1。"
    )

    $CurrentStateLines |
        Set-Content `
            -LiteralPath $CurrentStatePath `
            -Encoding utf8NoBOM

    Write-Host "权威规划和 Fika 延期决策已更新。" `
        -ForegroundColor Green
}
else {
    Write-Warning "未找到权威规划目录：$PlanningRoot"
}

Write-Host "`n服务端 S1 验收完成。" `
    -ForegroundColor Green

Write-Host "ControlWithoutModPassed = $ControlPassed"
Write-Host "ValidHashMismatchWithModPassed = $BypassPassed"
Write-Host "InvalidJsonWithModPassed = $InvalidJsonPassed"
Write-Host "AcceptancePassed = $AcceptancePassed"
Write-Host "证据目录：$EvidenceRoot"
Write-Host "证据 ZIP：$EvidenceZip"
Write-Host "ZIP SHA-256：$ZipHash"
Write-Host "仓库验收脚本：$RepoScriptPath"

if (-not $AcceptancePassed) {
    throw (
        "服务端验收未全部通过。" +
        "数据库和 Mod 已恢复，请上传证据 ZIP。"
    )
}
