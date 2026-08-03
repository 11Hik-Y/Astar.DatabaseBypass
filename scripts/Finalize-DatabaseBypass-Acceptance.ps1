[CmdletBinding()]
param(
    [string]$SptRoot = "D:\game\SPT-4.1.0-40743-e18bd1e",
    [string]$RepositoryRoot = "C:\D\repository\SPT_derive",
    [string]$AnalysisRoot = "D:\SPT_4_1_ModDev_TEMP"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$ServerRepo = Join-Path $RepositoryRoot "Astar.DatabaseBypass"
$ServerRuntime = Join-Path $SptRoot "SPT_Runtime"
$DatabasePath = Join-Path $ServerRuntime (
    "SPT_Data\database\globals.json"
)
$ModDirectory = Join-Path $ServerRuntime (
    "user\mods\Astar.DatabaseBypass"
)
$PlanningRoot = Join-Path $AnalysisRoot (
    "planning\Astar_SPT_4_1_DualMod_" +
    "DevelopmentBaseline_v1.1_20260803"
)
$EvidenceParent = Join-Path $AnalysisRoot "evidence"

function Set-NoteProperty {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Value
    )

    $InputObject |
        Add-Member `
            -NotePropertyName $Name `
            -NotePropertyValue $Value `
            -Force
}

function Append-Decision {
    param(
        [Parameter(Mandatory)]
        [string]$DecisionLogPath,

        [Parameter(Mandatory)]
        [string]$Marker,

        [Parameter(Mandatory)]
        [string]$Entry
    )

    if (-not (Test-Path -LiteralPath $DecisionLogPath -PathType Leaf)) {
        return
    }

    $Content = [System.IO.File]::ReadAllText(
        $DecisionLogPath
    )

    if ($Content -match [regex]::Escape($Marker)) {
        return
    }

    [System.IO.File]::AppendAllText(
        $DecisionLogPath,
        $Entry,
        [System.Text.UTF8Encoding]::new($false)
    )
}

Write-Host "`n=== 1. 查找刚才已经完成的 S1 验收目录 ===" `
    -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $EvidenceParent -PathType Container)) {
    throw "证据根目录不存在：$EvidenceParent"
}

$AcceptanceRoots = @(
    Get-ChildItem `
        -LiteralPath $EvidenceParent `
        -Directory `
        -Filter "server-s1-acceptance-*" `
        -ErrorAction SilentlyContinue |
        Where-Object {
            Test-Path `
                -LiteralPath (
                    Join-Path $_.FullName (
                        "01-control-without-mod\result.json"
                    )
                ) `
                -PathType Leaf

            Test-Path `
                -LiteralPath (
                    Join-Path $_.FullName (
                        "02-valid-hash-mismatch-with-mod\result.json"
                    )
                ) `
                -PathType Leaf

            Test-Path `
                -LiteralPath (
                    Join-Path $_.FullName (
                        "03-invalid-json-with-mod\result.json"
                    )
                ) `
                -PathType Leaf
        } |
        Sort-Object LastWriteTime -Descending
)

if ($AcceptanceRoots.Count -eq 0) {
    throw (
        "没有找到包含三份 result.json 的 " +
        "server-s1-acceptance 证据目录。"
    )
}

$EvidenceRoot = $AcceptanceRoots[0].FullName
$EvidenceZip = "$EvidenceRoot.zip"

Write-Host "使用证据目录：$EvidenceRoot" `
    -ForegroundColor Green

Write-Host "`n=== 2. 读取三组原始测试结果 ===" `
    -ForegroundColor Cyan

$ControlResultPath = Join-Path $EvidenceRoot (
    "01-control-without-mod\result.json"
)
$BypassResultPath = Join-Path $EvidenceRoot (
    "02-valid-hash-mismatch-with-mod\result.json"
)
$InvalidResultPath = Join-Path $EvidenceRoot (
    "03-invalid-json-with-mod\result.json"
)

$ControlResult = Get-Content `
    -LiteralPath $ControlResultPath `
    -Raw |
    ConvertFrom-Json

$BypassResult = Get-Content `
    -LiteralPath $BypassResultPath `
    -Raw |
    ConvertFrom-Json

$InvalidResult = Get-Content `
    -LiteralPath $InvalidResultPath `
    -Raw |
    ConvertFrom-Json

$ControlResult | Format-List | Out-Host
$BypassResult | Format-List | Out-Host
$InvalidResult | Format-List | Out-Host

foreach ($Pair in @(
    [pscustomobject]@{
        Label = "无 Mod 对照"
        Result = $ControlResult
    },
    [pscustomobject]@{
        Label = "有 Mod 合法 Hash 绕过"
        Result = $BypassResult
    },
    [pscustomobject]@{
        Label = "有 Mod 非法 JSON"
        Result = $InvalidResult
    }
)) {
    if (
        $null -eq $Pair.Result.PSObject.Properties["Passed"]
    ) {
        throw "$($Pair.Label) 的 result.json 缺少 Passed 字段。"
    }
}

$ControlPassed = [bool]$ControlResult.Passed
$BypassPassed = [bool]$BypassResult.Passed
$InvalidJsonPassed = [bool]$InvalidResult.Passed

$AcceptancePassed = (
    $ControlPassed -and
    $BypassPassed -and
    $InvalidJsonPassed
)

Write-Host "`n=== 3. 验证数据库与 Mod 已经恢复 ===" `
    -ForegroundColor Cyan

$OriginalEvidencePath = Join-Path $EvidenceRoot (
    "database-original.json"
)

if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
    throw "当前数据库文件不存在：$DatabasePath"
}

if (
    -not (
        Test-Path `
            -LiteralPath $OriginalEvidencePath `
            -PathType Leaf
    )
) {
    throw "证据目录缺少 database-original.json。"
}

$CurrentDatabaseHash = (
    Get-FileHash `
        -LiteralPath $DatabasePath `
        -Algorithm SHA256
).Hash

$OriginalEvidenceHash = (
    Get-FileHash `
        -LiteralPath $OriginalEvidencePath `
        -Algorithm SHA256
).Hash

$DatabaseRestored = (
    $CurrentDatabaseHash -eq $OriginalEvidenceHash
)

$ModDirectoryRestored = (
    Test-Path `
        -LiteralPath $ModDirectory `
        -PathType Container
)

Write-Host "当前数据库 SHA-256：$CurrentDatabaseHash"
Write-Host "原始证据 SHA-256：$OriginalEvidenceHash"
Write-Host "DatabaseRestored = $DatabaseRestored"
Write-Host "ModDirectoryRestored = $ModDirectoryRestored"

if (-not $DatabaseRestored) {
    throw (
        "当前 globals.json 与测试前原始证据不一致，" +
        "拒绝继续收口。"
    )
}

if (-not $ModDirectoryRestored) {
    throw "服务端 Mod 目录未恢复：$ModDirectory"
}

Write-Host "数据库与 Mod 恢复验证通过。" `
    -ForegroundColor Green

Write-Host "`n=== 4. 写入正式验收汇总 ===" `
    -ForegroundColor Cyan

$Results = @(
    $ControlResult,
    $BypassResult,
    $InvalidResult
)

$Results |
    Export-Csv `
        -LiteralPath (
            Join-Path $EvidenceRoot "trial-results.csv"
        ) `
        -NoTypeInformation `
        -Encoding utf8

$Results |
    ConvertTo-Json -Depth 8 |
    Set-Content `
        -LiteralPath (
            Join-Path $EvidenceRoot "trial-results.json"
        ) `
        -Encoding utf8NoBOM

$Summary = [ordered]@{
    GeneratedAt = (Get-Date).ToString("o")
    SptRoot = $SptRoot
    TargetPath = $DatabasePath
    CurrentDatabaseSha256 = $CurrentDatabaseHash
    OriginalEvidenceSha256 = $OriginalEvidenceHash
    ControlWithoutModPassed = $ControlPassed
    ValidHashMismatchWithModPassed = $BypassPassed
    InvalidJsonWithModPassed = $InvalidJsonPassed
    AcceptancePassed = $AcceptancePassed
    DatabaseRestored = $DatabaseRestored
    ModDirectoryRestored = $ModDirectoryRestored
    EvidenceRoot = $EvidenceRoot
    EvidenceZip = $EvidenceZip
}

$Summary |
    ConvertTo-Json -Depth 8 |
    Set-Content `
        -LiteralPath (
            Join-Path $EvidenceRoot "SUMMARY.json"
        ) `
        -Encoding utf8NoBOM

$SummaryLines = @(
    "Astar.DatabaseBypass S1 Acceptance",
    "",
    "Target: $DatabasePath",
    "Current database SHA-256: $CurrentDatabaseHash",
    "Original evidence SHA-256: $OriginalEvidenceHash",
    "",
    "Control without Mod passed: $ControlPassed",
    "Valid Hash mismatch with Mod passed: $BypassPassed",
    "Invalid JSON with Mod passed: $InvalidJsonPassed",
    "",
    "Acceptance passed: $AcceptancePassed",
    "Database restored: $DatabaseRestored",
    "Mod directory restored: $ModDirectoryRestored"
)

$SummaryLines |
    Set-Content `
        -LiteralPath (
            Join-Path $EvidenceRoot "SUMMARY.txt"
        ) `
        -Encoding utf8NoBOM

$SummaryLines | ForEach-Object {
    Write-Host $_
}

Write-Host "`n=== 5. 永久修复仓库验收脚本 ===" `
    -ForegroundColor Cyan

$DownloadScript = Join-Path $env:USERPROFILE (
    "Downloads\" +
    "Test-Astar-DatabaseBypass-" +
    "S1-Acceptance-v1.0.1.ps1"
)

$RepoAcceptanceScript = Join-Path $ServerRepo (
    "scripts\Test-DatabaseBypass-Acceptance.ps1"
)

if (Test-Path -LiteralPath $DownloadScript -PathType Leaf) {
    $SourceText = [System.IO.File]::ReadAllText(
        $DownloadScript
    )

    $Pattern = (
        '(?ms)^\s*\$Result\s*\|\s*' +
        '\r?\n\s*Format-List\s*' +
        '\r?\n\s*\r?\n\s*return\s+\$Result'
    )

    $Replacement = @'
    $Result | Format-List | Out-Host

    return $Result
'@

    $FixedText = [regex]::Replace(
        $SourceText,
        $Pattern,
        $Replacement,
        1
    )

    if ($FixedText -eq $SourceText) {
        throw (
            "没有在 v1.0.1 脚本中找到 " +
            "Format-List 管道污染片段。"
        )
    }

    [System.IO.File]::WriteAllText(
        $RepoAcceptanceScript,
        $FixedText,
        [System.Text.UTF8Encoding]::new($false)
    )

    Write-Host "已写入修正版仓库验收脚本："
    Write-Host $RepoAcceptanceScript
}
else {
    Write-Warning (
        "未找到下载目录中的 v1.0.1 脚本，" +
        "无法自动写入仓库长期验收脚本。"
    )
}

$RepoFinalizeScript = Join-Path $ServerRepo (
    "scripts\Finalize-DatabaseBypass-Acceptance.ps1"
)

Copy-Item `
    -LiteralPath $PSCommandPath `
    -Destination $RepoFinalizeScript `
    -Force

git -C $ServerRepo diff --check

Write-Host "仓库脚本静态检查通过。" `
    -ForegroundColor Green

Write-Host "`n=== 6. 更新权威规划与路线优先级 ===" `
    -ForegroundColor Cyan

if (Test-Path -LiteralPath $PlanningRoot -PathType Container) {
    $DecisionLogPath = Join-Path $PlanningRoot (
        "DECISION_LOG.md"
    )

    $Decision015 = @'

## 2026-08-03 D-015：当前优先离线单人，Fika 验收延期

状态：已采纳

- 当前正式开发和验收以 SPT 4.1.0 离线单人为主。
- Fika 4.1.x 尚未纳入当前可运行基线。
- Fika Host、Client 和 StrictSync 验收不阻塞 C1 至 C7。
- 等兼容 SPT 4.1.x 的 Fika 版本可用并稳定后，再恢复 C8。
- 当前客户端仍保留兼容边界，禁止引入阻碍未来 Fika 适配的直接库存写入。
'@

    Append-Decision `
        -DecisionLogPath $DecisionLogPath `
        -Marker "D-015：当前优先离线单人，Fika 验收延期" `
        -Entry $Decision015

    $Decision016 = @'

## 2026-08-03 D-016：函数内部格式化输出不得污染成功管道

状态：已采纳

- PowerShell 函数的所有成功流输出都会成为调用结果。
- Format-List 不能直接留在需要 return 对象的函数成功管道中。
- 调试展示必须使用 Format-List | Out-Host 或 Write-Host。
- 自动化结果必须从 result.json 或明确的 PSCustomObject 读取。
'@

    Append-Decision `
        -DecisionLogPath $DecisionLogPath `
        -Marker "D-016：函数内部格式化输出不得污染成功管道" `
        -Entry $Decision016

    $ProjectStatePath = Join-Path $PlanningRoot (
        "PROJECT_STATE.json"
    )

    if (
        Test-Path `
            -LiteralPath $ProjectStatePath `
            -PathType Leaf
    ) {
        $State = Get-Content `
            -LiteralPath $ProjectStatePath `
            -Raw |
            ConvertFrom-Json

        Set-NoteProperty `
            -InputObject $State `
            -Name "updatedAt" `
            -Value (Get-Date).ToString("o")

        if ($null -eq $State.server) {
            Set-NoteProperty `
                -InputObject $State `
                -Name "server" `
                -Value ([pscustomobject]@{})
        }

        Set-NoteProperty `
            -InputObject $State.server `
            -Name "compileStatus" `
            -Value "PASSED"

        $ServerRuntimeStatus = "S1_ACCEPTANCE_FAILED"

        if ($AcceptancePassed) {
            $ServerRuntimeStatus = "S1_ACCEPTANCE_PASSED"
        }

        Set-NoteProperty `
            -InputObject $State.server `
            -Name "runtimeStatus" `
            -Value $ServerRuntimeStatus

        Set-NoteProperty `
            -InputObject $State.server `
            -Name "latestEvidence" `
            -Value $EvidenceZip

        Set-NoteProperty `
            -InputObject $State `
            -Name "currentProductPriority" `
            -Value "OFFLINE_SINGLE_PLAYER"

        Set-NoteProperty `
            -InputObject $State `
            -Name "fikaValidation" `
            -Value (
                "DEFERRED_UNTIL_SPT_4_1_COMPATIBLE_RELEASE"
            )

        $State |
            ConvertTo-Json -Depth 12 |
            Set-Content `
                -LiteralPath $ProjectStatePath `
                -Encoding utf8NoBOM
    }

    $PhaseLedgerPath = Join-Path $PlanningRoot (
        "PHASE_LEDGER.json"
    )

    if (
        Test-Path `
            -LiteralPath $PhaseLedgerPath `
            -PathType Leaf
    ) {
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
                if ($AcceptancePassed) {
                    $Phase.status = "READY_TO_START"
                }
                else {
                    $Phase.status = "WAITING_FOR_S1_REVIEW"
                }
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

    $CurrentStatePath = Join-Path $PlanningRoot (
        "CURRENT_STATE.md"
    )

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
        "- 服务端 Mod 已编译、安装并成功命中数据库校验关闭 Patch。",
        "- 客户端 C0 安全探针运行通过。",
        "- 无 Mod 时合法 Hash 不匹配被阻止：$ControlPassed。",
        "- 有 Mod 时合法 Hash 不匹配成功启动：$BypassPassed。",
        "- 有 Mod 时非法 JSON 仍然失败：$InvalidJsonPassed。",
        "- 服务端 S1 总体验收：$AcceptancePassed。",
        "- 数据库恢复验证：$DatabaseRestored。",
        "- 服务端 Mod 目录恢复验证：$ModDirectoryRestored。",
        "",
        "## 剩余未完成",
        "",
        "- 两个仓库首次 Git 基线提交。",
        "- 客户端 C1 关键 DLL 静态分析。",
        "- 客户端 C2 离线单人只读运行探针。",
        "- C3 至 C7 离线单人功能开发与验收。",
        "- C8 Fika 验收等待兼容 SPT 4.1.x 的版本。",
        "",
        "## 阶段新增信息",
        "",
        "- 当前产品优先级锁定为离线单人。",
        "- Fika 不阻塞当前客户端开发。",
        "- PowerShell 格式化对象不得污染函数成功管道。",
        "- 服务端验收证据：$EvidenceRoot。",
        "",
        "## 下一步动作",
        "",
        "完成两个仓库基线提交，然后导出并分析客户端关键程序集。"
    )

    $CurrentStateLines |
        Set-Content `
            -LiteralPath $CurrentStatePath `
            -Encoding utf8NoBOM

    Write-Host "权威规划状态已更新。" `
        -ForegroundColor Green
}
else {
    Write-Warning "未找到权威规划目录：$PlanningRoot"
}

Write-Host "`n=== 7. 生成最终证据清单与 ZIP ===" `
    -ForegroundColor Cyan

$ManifestRows = @(
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

$ManifestRows |
    Export-Csv `
        -LiteralPath (
            Join-Path $EvidenceRoot "MANIFEST.csv"
        ) `
        -NoTypeInformation `
        -Encoding utf8

$ManifestRows |
    ConvertTo-Json -Depth 4 |
    Set-Content `
        -LiteralPath (
            Join-Path $EvidenceRoot "MANIFEST.json"
        ) `
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

Write-Host "`n服务端 S1 事后收口完成。" `
    -ForegroundColor Green

Write-Host "ControlWithoutModPassed = $ControlPassed"
Write-Host (
    "ValidHashMismatchWithModPassed = " +
    $BypassPassed
)
Write-Host "InvalidJsonWithModPassed = $InvalidJsonPassed"
Write-Host "AcceptancePassed = $AcceptancePassed"
Write-Host "DatabaseRestored = $DatabaseRestored"
Write-Host "ModDirectoryRestored = $ModDirectoryRestored"
Write-Host "证据目录：$EvidenceRoot"
Write-Host "证据 ZIP：$EvidenceZip"
Write-Host "ZIP SHA-256：$ZipHash"
Write-Host "长期验收脚本：$RepoAcceptanceScript"
Write-Host "事后收口脚本：$RepoFinalizeScript"

if (-not $AcceptancePassed) {
    Write-Warning (
        "三项验收未全部通过。" +
        "数据库与 Mod 已确认恢复；" +
        "请上传证据 ZIP继续分析。"
    )
}
