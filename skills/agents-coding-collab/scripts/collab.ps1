<#
.SYNOPSIS
    多 agent 协作开发：1 个写代码 + 4 个并行审查 + 1 个修订 + 1 个验证。
.DESCRIPTION
    架构（迭代闭环）：
      1) Writer (GLM-5.2) 写初版
      2) N 个并行 Reviewer (Kimi) 各盯一个维度：bug/边界、安全、性能、需求完整性
      3) 脚本内合并 N 份审查为一份优先级清单（0 次 API 调用）
      4) Reviser (GLM-5.2) 根据合并审查修订
      5) Validator (Kimi) 闭环验证，输出 PASS/FAIL + 残留问题
      6) 若 FAIL 且未达 MaxRounds，自动把残留问题喂回 step 4 再修订，直到 PASS 或达上限
    -Quick 模式：1 个审查员 + 跳过多轮，2 次 API 搞定简单任务。
    并行审查用 .NET HttpClient 实现，兼容 PS 5.1 和 PS 7。
.PARAMETER Task
    要开发的任务描述。必填。
.PARAMETER Language
    目标语言/技术栈。默认 python。
.PARAMETER BaseUrl
    API 网关地址。默认 https://inference.xd.ci
.PARAMETER ApiKey
    网关令牌。不传则从环境变量 XD_API_KEY 读取；若仍为空，则读取本机私有 key 文件。
.PARAMETER WriterModel
    负责写初版代码的模型。默认 glm-5.2。
.PARAMETER WriterBaseUrl
    写初版代码的模型网关地址。不传则使用 BaseUrl。
.PARAMETER WriterApiKey
    写初版代码的模型 API Key。不传则使用 AGENTS_CODING_WRITER_API_KEY，再回退到 ApiKey。
.PARAMETER ReviewerModel
    负责并行审查的模型。默认 kimi-k2.7-code-highspeed。
.PARAMETER ReviewerModels
    多 reviewer 模型列表。可为不同审查维度指定不同模型；数量不足时复用最后一个。
.PARAMETER ReviewerBaseUrl
    并行审查模型网关地址。不传则使用 BaseUrl。
.PARAMETER ReviewerBaseUrls
    多 reviewer 网关地址列表。可为不同审查维度指定不同地址；数量不足时复用最后一个。
.PARAMETER ReviewerApiKey
    并行审查模型 API Key。不传则使用 AGENTS_CODING_REVIEWER_API_KEY，再回退到 ApiKey。
.PARAMETER ReviewerApiKeys
    多 reviewer API Key 列表。可为不同审查维度指定不同 Key；数量不足时复用最后一个。
.PARAMETER ReviserModel
    负责修订代码的模型。不传则使用 WriterModel。
.PARAMETER ReviserBaseUrl
    修订模型网关地址。不传则使用 WriterBaseUrl。
.PARAMETER ReviserApiKey
    修订模型 API Key。不传则使用 AGENTS_CODING_REVISER_API_KEY，再回退到 WriterApiKey。
.PARAMETER ValidatorModel
    负责最终验证的模型。不传则使用 ReviewerModel。
.PARAMETER ValidatorBaseUrl
    验证模型网关地址。不传则使用 ReviewerBaseUrl。
.PARAMETER ValidatorApiKey
    验证模型 API Key。不传则使用 AGENTS_CODING_VALIDATOR_API_KEY，再回退到 ReviewerApiKey。
.PARAMETER ReviewerCount
    并行审查维度数量，1-4。默认 4。传 1 退化为单审查员模式。
.PARAMETER MaxRounds
    修订-验证最大迭代轮数，1-5。默认 3。FAIL 时自动再修订直到 PASS 或达上限。
.PARAMETER RequestTimeoutSec
    单次模型/API 调用等待秒数。默认 3600，避免长任务写到一半被本地脚本中断；传 0 表示不设置本地超时。
.PARAMETER ModelTraceChars
    在 Codex 终端显示每个模型输出预览的最大字符数。默认 1200；传 0 只显示模型调度和 token，不显示内容预览。
.PARAMETER NoModelTrace
    关闭 Codex 终端里的模型调度追踪输出。默认开启。
.PARAMETER Quick
    快速模式：1 个审查员 + 单轮，适合简单任务。
.PARAMETER OutDir
    产物输出目录。默认当前目录。
.EXAMPLE
    .\collab.ps1 -Task "写一个防抖函数" -Language javascript
.EXAMPLE
    .\collab.ps1 -Task "实现 LRU 缓存" -Language python -ReviewerCount 2
.EXAMPLE
    .\collab.ps1 -Task "写个add函数" -Quick
.EXAMPLE
    .\collab.ps1 -Task "实现分布式锁" -MaxRounds 5
.EXAMPLE
    .\collab.ps1 -Task "重构鉴权模块" -Language typescript `
      -WriterModel glm-5.2 -WriterBaseUrl "https://gateway-a.example" -WriterApiKey $env:WRITER_KEY `
      -ReviewerModels kimi-k2.7-code-highspeed,glm-5.2,model-c,model-d `
      -ReviewerBaseUrls "https://gateway-b.example","https://gateway-c.example" `
      -ReviewerApiKeys $env:REVIEWER_KEY_A,$env:REVIEWER_KEY_B
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Task,

    [string]$Language      = "python",
    [string]$BaseUrl       = "https://inference.xd.ci",
    [string]$ApiKey        = [System.Environment]::GetEnvironmentVariable("XD_API_KEY"),
    [string]$WriterModel   = "glm-5.2",
    [string]$WriterBaseUrl = [System.Environment]::GetEnvironmentVariable("AGENTS_CODING_WRITER_BASE_URL"),
    [string]$WriterApiKey  = [System.Environment]::GetEnvironmentVariable("AGENTS_CODING_WRITER_API_KEY"),
    [string]$ReviewerModel = "kimi-k2.7-code-highspeed",
    [string[]]$ReviewerModels = @(),
    [string]$ReviewerBaseUrl = [System.Environment]::GetEnvironmentVariable("AGENTS_CODING_REVIEWER_BASE_URL"),
    [string[]]$ReviewerBaseUrls = @(),
    [string]$ReviewerApiKey  = [System.Environment]::GetEnvironmentVariable("AGENTS_CODING_REVIEWER_API_KEY"),
    [string[]]$ReviewerApiKeys = @(),
    [string]$ReviserModel = "",
    [string]$ReviserBaseUrl = [System.Environment]::GetEnvironmentVariable("AGENTS_CODING_REVISER_BASE_URL"),
    [string]$ReviserApiKey = [System.Environment]::GetEnvironmentVariable("AGENTS_CODING_REVISER_API_KEY"),
    [string]$ValidatorModel = "",
    [string]$ValidatorBaseUrl = [System.Environment]::GetEnvironmentVariable("AGENTS_CODING_VALIDATOR_BASE_URL"),
    [string]$ValidatorApiKey = [System.Environment]::GetEnvironmentVariable("AGENTS_CODING_VALIDATOR_API_KEY"),
    [int]$ReviewerCount    = 4,
    [int]$MaxRounds        = 3,
    [int]$RequestTimeoutSec = 3600,
    [int]$ModelTraceChars  = 1200,
    [switch]$NoModelTrace,
    [switch]$Quick,
    [string]$OutDir        = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

$PrivateKeyPath = Join-Path $env:USERPROFILE ".codex\secrets\dual-model-collab.key"
if (-not $ApiKey -and (Test-Path $PrivateKeyPath)) {
    $ApiKey = ([System.IO.File]::ReadAllText($PrivateKeyPath, [System.Text.Encoding]::UTF8)).Trim()
}

if (-not $WriterBaseUrl) { $WriterBaseUrl = $BaseUrl }
if (-not $ReviewerBaseUrl) { $ReviewerBaseUrl = $BaseUrl }
if (-not $ReviserModel) { $ReviserModel = $WriterModel }
if (-not $ReviserBaseUrl) { $ReviserBaseUrl = $WriterBaseUrl }
if (-not $ValidatorModel) {
    if ($ReviewerModels -and $ReviewerModels.Count -gt 0) {
        $ValidatorModel = [string]$ReviewerModels[$ReviewerModels.Count - 1]
    } else {
        $ValidatorModel = $ReviewerModel
    }
}
if (-not $ValidatorBaseUrl) {
    if ($ReviewerBaseUrls -and $ReviewerBaseUrls.Count -gt 0) {
        $ValidatorBaseUrl = [string]$ReviewerBaseUrls[$ReviewerBaseUrls.Count - 1]
    } else {
        $ValidatorBaseUrl = $ReviewerBaseUrl
    }
}

if (-not $WriterApiKey) { $WriterApiKey = $ApiKey }
if (-not $ReviewerApiKey) { $ReviewerApiKey = $ApiKey }
if (-not $ReviserApiKey) { $ReviserApiKey = $WriterApiKey }
if (-not $ValidatorApiKey) {
    if ($ReviewerApiKeys -and $ReviewerApiKeys.Count -gt 0) {
        $ValidatorApiKey = [string]$ReviewerApiKeys[$ReviewerApiKeys.Count - 1]
    } else {
        $ValidatorApiKey = $ReviewerApiKey
    }
}

$missingKeys = @()
if (-not $WriterApiKey) { $missingKeys += "writer" }
if (-not $ReviewerApiKey -and (-not $ReviewerApiKeys -or $ReviewerApiKeys.Count -eq 0)) { $missingKeys += "reviewer" }
if (-not $ReviserApiKey) { $missingKeys += "reviser" }
if (-not $ValidatorApiKey) { $missingKeys += "validator" }
if ($missingKeys.Count -gt 0) {
    throw "缺少 API Key：$($missingKeys -join ', ')。请用角色专用参数/环境变量传入，或设置 -ApiKey、XD_API_KEY，或写入 $PrivateKeyPath。"
}
if ($MaxRounds -lt 1 -or $MaxRounds -gt 5) {
    throw "MaxRounds 必须在 1-5 之间。"
}
if ($RequestTimeoutSec -lt 0) {
    throw "RequestTimeoutSec 必须大于等于 0。"
}
if ($ModelTraceChars -lt 0) {
    throw "ModelTraceChars 必须大于等于 0。"
}
if ($ReviewerCount -lt 1 -or $ReviewerCount -gt 4) { throw "ReviewerCount 必须在 1-4 之间。" }

# ============ 工具函数 ============

# 写无 BOM UTF-8 文件
$script:utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, $script:utf8NoBom)
}
function Read-Utf8([string]$Path) {
    [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}
function Get-IndexedOrDefault([array]$Values, [int]$Index, [string]$Default) {
    if ($Values -and $Values.Count -gt 0) {
        if ($Index -lt $Values.Count) { return [string]$Values[$Index] }
        return [string]$Values[$Values.Count - 1]
    }
    return $Default
}
function Get-ObjectValue($Object, [string]$Name, $Default) {
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $Default
}
function Format-TracePreview([string]$Text, [int]$Limit) {
    if (-not $Text) { return "" }
    $normalized = $Text.Trim()
    if ($Limit -eq 0) { return "" }
    if ($normalized.Length -le $Limit) { return $normalized }
    return $normalized.Substring(0, $Limit) + "`n... [truncated in terminal; full output is in artifact file]"
}
function Write-ModelTraceStart([string]$Role, [string]$Model, [string]$Action, [string]$BaseUrl, [string]$Name = "") {
    if ($NoModelTrace) { return }
    $label = if ($Name) { "$Role/$Name" } else { $Role }
    Write-Host ""
    Write-Host "[MODEL START] $label" -ForegroundColor Magenta
    Write-Host "  model : $Model" -ForegroundColor Magenta
    Write-Host "  action: $Action" -ForegroundColor Magenta
    Write-Host "  api   : $BaseUrl" -ForegroundColor DarkGray
}
function Write-ModelTraceEnd([string]$Role, [string]$Model, $Result, [string]$Preview, [string]$Artifact = "", [string]$Name = "") {
    if ($NoModelTrace) { return }
    $label = if ($Name) { "$Role/$Name" } else { $Role }
    $finish = Get-ObjectValue $Result "Finish" "unknown"
    $tokens = Get-ObjectValue $Result "Tokens" 0
    $reasonTok = Get-ObjectValue $Result "ReasonTok" 0
    $ok = Get-ObjectValue $Result "OK" $true
    $status = if ($ok) { "OK" } else { "ERROR" }
    Write-Host "[MODEL END]   $label" -ForegroundColor Magenta
    Write-Host "  model : $Model" -ForegroundColor Magenta
    Write-Host "  status: $status | finish=$finish | tokens=$tokens | reasoning=$reasonTok" -ForegroundColor DarkGray
    if ($Artifact) { Write-Host "  file  : $Artifact" -ForegroundColor DarkGray }
    $previewText = Format-TracePreview $Preview $ModelTraceChars
    if ($previewText) {
        Write-Host "----- $label output preview -----" -ForegroundColor DarkCyan
        Write-Host $previewText -ForegroundColor Gray
        Write-Host "----- end preview -----" -ForegroundColor DarkCyan
    }
}
function New-ModelTraceErrorResult([string]$Message) {
    [pscustomobject]@{
        OK        = $false
        Finish    = "error"
        Tokens    = 0
        ReasonTok = 0
        Error     = $Message
    }
}

# 串行调用（用于 writer / reviser / validator）
function Invoke-Chat {
    param(
        [string]$Model,
        [string]$SystemPrompt,
        [string]$UserPrompt,
        [int]$MaxTokens   = 8000,
        [double]$Temp     = 0.4,
        [int]$TimeoutSec  = 3600,
        [string]$RequestBaseUrl = $BaseUrl,
        [string]$RequestApiKey = $ApiKey
    )
    $msgs = @()
    if ($SystemPrompt) { $msgs += @{ role = "system"; content = $SystemPrompt } }
    $msgs += @{ role = "user"; content = $UserPrompt }

    $tmpIn  = Join-Path $env:TEMP "chat_$(Get-Random).json"
    $tmpOut = Join-Path $env:TEMP "chat_$(Get-Random).json"
    $tempsToTry = @($Temp)
    if ($Temp -ne 1) { $tempsToTry += 1 }
    $lastErr = $null

    try {
        foreach ($t in $tempsToTry) {
            $payload = @{ model = $Model; messages = $msgs; max_tokens = $MaxTokens; temperature = $t } | ConvertTo-Json -Depth 8
            Write-Utf8 $tmpIn $payload

            $curlArgs = @("-s")
            if ($TimeoutSec -gt 0) { $curlArgs += @("-m", "$TimeoutSec") }
            $curlArgs += @(
                "-X", "POST", "$RequestBaseUrl/v1/chat/completions",
                "-H", "Authorization: Bearer $RequestApiKey",
                "-H", "Content-Type: application/json",
                "--data-binary", "@$tmpIn",
                "-o", $tmpOut
            )
            & curl.exe @curlArgs

            if ($LASTEXITCODE -ne 0) { throw "curl 退出码 $LASTEXITCODE" }
            $raw = Read-Utf8 $tmpOut
            $j = $raw | ConvertFrom-Json

            if (-not $j.choices -or $j.choices.Count -eq 0) {
                $lastErr = if ($j.error) { $j.error.message } else { $raw }
                if ($lastErr -match "temperature" -and $t -ne 1) { continue }
                throw "API 没返回 choices：$($lastErr.Substring(0,[Math]::Min(500,$lastErr.Length)))"
            }
            $content = $j.choices[0].message.content
            $reason  = $j.choices[0].message.reasoning_content
            if (-not $content -and $reason) { $content = $reason }
            return [pscustomobject]@{
                Content   = $content
                Finish    = $j.choices[0].finish_reason
                Tokens    = if ($j.usage) { $j.usage.completion_tokens } else { 0 }
                ReasonTok = if ($j.usage.completion_tokens_details.reasoning_tokens) { $j.usage.completion_tokens_details.reasoning_tokens } else { 0 }
            }
        }
        throw "API 始终没返回 choices。最后一次错误：$lastErr"
    }
    finally { Remove-Item $tmpIn, $tmpOut -ErrorAction SilentlyContinue }
}

# 并行调用（用于多个 reviewer 同时跑，用 .NET HttpClient 做真并行）
function Invoke-ChatParallel {
    param(
        [array]$Jobs,  # @( @{ Name; Model; SystemPrompt; UserPrompt; MaxTokens; Temp }, ... )
        [int]$TimeoutSec = 3600,
        [string]$RequestBaseUrl = $BaseUrl,
        [string]$RequestApiKey = $ApiKey
    )

    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    $client = New-Object System.Net.Http.HttpClient
    if ($TimeoutSec -eq 0) {
        $client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
    } else {
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $tasks = @()
    $names = @()

    # 构建所有异步请求
    foreach ($i in 0..($Jobs.Count - 1)) {
        $job = $Jobs[$i]
        $msgs = @()
        if ($job.SystemPrompt) { $msgs += @{ role = "system"; content = $job.SystemPrompt } }
        $msgs += @{ role = "user"; content = $job.UserPrompt }
        $payload = @{ model = $job.Model; messages = $msgs; max_tokens = $job.MaxTokens; temperature = $job.Temp } | ConvertTo-Json -Depth 8
        $names += $job.Name
        $jobBaseUrl = if ($job.BaseUrl) { $job.BaseUrl } else { $RequestBaseUrl }
        $jobApiKey = if ($job.ApiKey) { $job.ApiKey } else { $RequestApiKey }

        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, "$jobBaseUrl/v1/chat/completions")
        $req.Headers.Add("Authorization", "Bearer $jobApiKey")
        $req.Content = New-Object System.Net.Http.StringContent($payload, $utf8NoBom, "application/json")
        $tasks += $client.SendAsync($req)
    }

    # 等待全部完成。单个任务失败时仍继续收集其它 reviewer 的结果。
    try {
        [System.Threading.Tasks.Task]::WaitAll($tasks)
    } catch {
        # 具体失败原因在下面逐个 task 读取时记录。
    }

    # 收集结果
    $results = @{}
    for ($i = 0; $i -lt $tasks.Count; $i++) {
        $name = $names[$i]
        try {
            $raw = $tasks[$i].Result.Content.ReadAsStringAsync().Result
            $j = $raw | ConvertFrom-Json
            if ($j.choices -and $j.choices.Count -gt 0) {
                $content = $j.choices[0].message.content
                $reason  = $j.choices[0].message.reasoning_content
                if (-not $content -and $reason) { $content = $reason }
                $results[$name] = [pscustomobject]@{
                    Content = $content
                    Finish  = $j.choices[0].finish_reason
                    Tokens  = if ($j.usage) { $j.usage.completion_tokens } else { 0 }
                    OK      = $true
                }
            } else {
                $errMsg = if ($j.error) { $j.error.message } else { "无 choices" }
                $results[$name] = [pscustomobject]@{ Content = ""; Finish = "error"; Tokens = 0; OK = $false; Error = $errMsg }
            }
        } catch {
            $results[$name] = [pscustomobject]@{ Content = ""; Finish = "error"; Tokens = 0; OK = $false; Error = $_.Exception.Message }
        }
    }
    $client.Dispose()
    return $results
}

# ============ Prompt 定义 ============

$writerSystem = @"
你是资深 $Language 工程师。只输出可直接运行的 $Language 代码，放在一个 ```$Language 代码块里。
不要解释、不要寒暄、不要多余文字。代码要完整、自包含、带必要注释、处理好边界和异常。
如果需求依赖当前 API、库版本、平台规则或外部服务，只能使用用户/上下文提供的已验证资料；未提供资料时选择保守兼容写法，不要编造最新接口。
"@

# 4 个专精审查员的 system prompt
$reviewerPrompts = @{
    "bug" = @"
你是 bug 猎手和边界条件专家。审查 $Language 代码，专注找：逻辑 bug、边界遗漏、异常未处理、空值/越界、资源泄漏，以及缺少新鲜资料导致的可疑 API/版本假设。
输出格式：
## 问题清单
1. [高/中/低] 问题描述 + 代码位置
## 修改建议
1. 具体修改方案
无实质问题则写"无"和"无需修改"。
"@
    "security" = @"
你是安全审查专家。审查 $Language 代码，专注找：注入风险、输入未校验、敏感信息泄漏、权限问题、不安全或可能过时的依赖/调用。
输出格式：
## 问题清单
1. [高/中/低] 问题描述 + 代码位置
## 修改建议
1. 具体修改方案
无实质问题则写"无"和"无需修改"。
"@
    "performance" = @"
你是性能优化专家。审查 $Language 代码，专注找：算法复杂度、冗余计算、内存浪费、IO 效率、可预编译/缓存但未做的事，以及可能因版本差异导致的性能/兼容风险。
输出格式：
## 问题清单
1. [高/中/低] 问题描述 + 代码位置
## 修改建议
1. 具体修改方案
无实质问题则写"无"和"无需修改"。
"@
    "requirements" = @"
你是需求分析专家。审查 $Language 代码与原始需求的匹配度，专注找：需求遗漏、语义偏差、过度设计、文档/注释与实现不符，以及缺少工具/互联网/项目规则验证的地方。
输出格式：
## 问题清单
1. [高/中/低] 问题描述 + 代码位置
## 修改建议
1. 具体修改方案
无实质问题则写"无"和"无需修改"。
"@
}

if ($Quick) {
    $ReviewerCount = 1
    $MaxRounds = 1
}
$reviewerNames = @("bug", "security", "performance", "requirements")[0..($ReviewerCount - 1)]

$reviserSystem = @"
你是资深 $Language 工程师。你会收到初版代码和多位审查专家的合并审查意见。
请根据审查意见修订代码，解决所有高/中严重度的问题。
只输出修订后的完整 $Language 代码，放在一个 ```$Language 代码块里。
代码块之后用"## 修订说明"列出改了什么、为什么。
如果审查意见指出缺少当前文档或项目规则证据，不要编造外部事实；用保守实现，并在修订说明中标记需要 Codex 进一步工具验证。
"@

$validatorSystem = @"
你是最终验证官。你会收到修订后的代码和之前的审查意见。
检查是否所有高/中严重度问题都已解决。输出格式：
## 验证结果
PASS 或 FAIL
## 残留问题（如有）
1. ...
## 总体评价
一句话总结代码质量。
同时检查是否存在未由上下文证据支持的当前 API/库版本/项目规则假设；如有，必须列为残留问题。
"@

# ============ 主流程 ============

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reviewerLabel = if ($ReviewerCount -eq 1) { "1 审查员" } else { "$ReviewerCount 审查员并行" }
$reviewerModelLabel = if ($ReviewerModels -and $ReviewerModels.Count -gt 0) { ($ReviewerModels -join ", ") } else { "$ReviewerModel x$ReviewerCount" }

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " 多 Agent 协作开发" -ForegroundColor Cyan
Write-Host "  写代码: $WriterModel | 修订: $ReviserModel | 审查: $reviewerModelLabel | 验证: $ValidatorModel" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[任务] $Task" -ForegroundColor Yellow
Write-Host "[语言] $Language | [审查维度] $($reviewerNames -join ', ')" -ForegroundColor Yellow
$timeoutLabel = if ($RequestTimeoutSec -eq 0) { "不限时" } else { "$RequestTimeoutSec 秒" }
Write-Host "[等待] 单次模型调用最多 $timeoutLabel" -ForegroundColor Yellow
if (-not $NoModelTrace) {
    $previewLabel = if ($ModelTraceChars -eq 0) { "关闭内容预览，只显示调度" } else { "每个模型最多显示 $ModelTraceChars 字符预览" }
    Write-Host "[终端追踪] Model Trace 已开启，$previewLabel" -ForegroundColor Yellow
}
Write-Host ""

# Step 1: Writer 写初版
Write-Host "[1/5] $WriterModel 正在写初版代码..." -ForegroundColor Green
Write-ModelTraceStart -Role "writer" -Model $WriterModel -Action "draft initial code" -BaseUrl $WriterBaseUrl
try {
    $step1 = Invoke-Chat -Model $WriterModel -SystemPrompt $writerSystem -UserPrompt "需求：$Task" -MaxTokens 8000 -Temp 0.3 -TimeoutSec $RequestTimeoutSec -RequestBaseUrl $WriterBaseUrl -RequestApiKey $WriterApiKey
} catch {
    $traceErr = New-ModelTraceErrorResult $_.Exception.Message
    Write-ModelTraceEnd -Role "writer" -Model $WriterModel -Result $traceErr -Preview $_.Exception.Message -Artifact "1-draft-$stamp.md"
    throw
}
$draft = $step1.Content
Write-Host "      完成（$($step1.Tokens) token，思考 $($step1.ReasonTok) token，$($step1.Finish)）" -ForegroundColor DarkGray

Write-Utf8 (Join-Path $OutDir "1-draft-$stamp.md") "# 初版代码（$WriterModel）`n`n$draft"
Write-Host "      -> 1-draft-$stamp.md" -ForegroundColor DarkGray
Write-ModelTraceEnd -Role "writer" -Model $WriterModel -Result $step1 -Preview $draft -Artifact "1-draft-$stamp.md"

# Step 2: 并行审查
Write-Host ""
Write-Host "[2/5] $reviewerLabel 正在并行审查..." -ForegroundColor Green
$jobs = for ($i = 0; $i -lt $reviewerNames.Count; $i++) {
    $name = $reviewerNames[$i]
    @{
        Name = $name
        Model = (Get-IndexedOrDefault $ReviewerModels $i $ReviewerModel)
        BaseUrl = (Get-IndexedOrDefault $ReviewerBaseUrls $i $ReviewerBaseUrl)
        ApiKey = (Get-IndexedOrDefault $ReviewerApiKeys $i $ReviewerApiKey)
        SystemPrompt = $reviewerPrompts[$name]
        UserPrompt = "原始需求：$Task`n`n待审查的 $Language 代码：`n$draft"
        MaxTokens = 12000
        Temp = 1
    }
}
$jobByName = @{}
foreach ($job in $jobs) { $jobByName[$job.Name] = $job }
foreach ($job in $jobs) {
    Write-ModelTraceStart -Role "reviewer" -Name $job.Name -Model $job.Model -Action "parallel review: $($job.Name)" -BaseUrl $job.BaseUrl
}
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$reviewResults = Invoke-ChatParallel -Jobs $jobs -TimeoutSec $RequestTimeoutSec -RequestBaseUrl $ReviewerBaseUrl -RequestApiKey $ReviewerApiKey
$sw.Stop()

$failedReviewers = @($reviewResults.Keys | Where-Object { -not $reviewResults[$_].OK })
if ($failedReviewers.Count -gt 0) {
    Write-Warning "  以下审查员失败: $($failedReviewers -join ', ')"
}
foreach ($name in $reviewerNames) {
    $r = $reviewResults[$name]
    $jobModel = if ($jobByName[$name]) { $jobByName[$name].Model } else { $ReviewerModel }
    $status = if ($r.OK) { "$jobModel | $($r.Tokens) token" } else { "$jobModel | 失败: $($r.Error)" }
    Write-Host "  [$name] $status" -ForegroundColor $(if ($r.OK) { 'DarkGray' } else { 'Red' })
    $reviewPreview = if ($r.OK) { $r.Content } else { $r.Error }
    Write-ModelTraceEnd -Role "reviewer" -Name $name -Model $jobModel -Result $r -Preview $reviewPreview -Artifact "2-review-$stamp.md"
}
Write-Host "      并行耗时 $([Math]::Round($sw.Elapsed.TotalSeconds, 1)) 秒" -ForegroundColor DarkGray

# Step 3: 合并审查意见（脚本内，0 次 API 调用）
Write-Host ""
Write-Host "[3/5] 合并审查意见..." -ForegroundColor Green
$consolidated = ""
foreach ($name in $reviewerNames) {
    $r = $reviewResults[$name]
    $dimLabel = switch ($name) {
        "bug"          { "Bug & 边界" }
        "security"     { "安全" }
        "performance"  { "性能" }
        "requirements" { "需求完整性" }
    }
    $content = if ($r.OK -and $r.Content) { $r.Content } else { "（审查失败，跳过此维度）" }
    $consolidated += "### $dimLabel 审查`n`n$content`n`n---`n`n"
}
Write-Utf8 (Join-Path $OutDir "2-review-$stamp.md") "# 合并审查意见（$reviewerModelLabel）`n`n$consolidated"
Write-Host "      -> 2-review-$stamp.md" -ForegroundColor DarkGray

# ============ 迭代循环：修订 → 验证 → 再修订 ============

$currentCode = $draft
$allVerdicts = @()
$allFinals = @()
$roundResults = @()
$isPass = $false
$totalApiCalls = 1 + $ReviewerCount  # writer + reviewers

for ($round = 1; $round -le $MaxRounds; $round++) {
    $roundLabel = "Round $round/$MaxRounds"

    # -- 修订 --
    Write-Host ""
    if ($round -eq 1) {
        Write-Host "[$roundLabel] $ReviserModel 正在根据合并审查修订..." -ForegroundColor Green
        $revisePrompt = "原始需求：`n$Task`n`n初版代码：`n$currentCode`n`n合并审查意见：`n$consolidated`n`n请修订代码。"
    } else {
        Write-Host "[$roundLabel] $ReviserModel 正在根据残留问题再修订..." -ForegroundColor Green
        $revisePrompt = "原始需求：`n$Task`n`n当前代码：`n$currentCode`n`n上一轮验证结论（未通过）：`n$($allVerdicts[-1])`n`n请针对残留问题修订代码，解决所有高/中严重度问题。"
    }
    Write-ModelTraceStart -Role "reviser" -Model $ReviserModel -Action "revise from merged review ($roundLabel)" -BaseUrl $ReviserBaseUrl
    try {
        $step4 = Invoke-Chat -Model $ReviserModel -SystemPrompt $reviserSystem -UserPrompt $revisePrompt -MaxTokens 8000 -Temp 0.3 -TimeoutSec $RequestTimeoutSec -RequestBaseUrl $ReviserBaseUrl -RequestApiKey $ReviserApiKey
    } catch {
        $traceErr = New-ModelTraceErrorResult $_.Exception.Message
        Write-ModelTraceEnd -Role "reviser" -Model $ReviserModel -Result $traceErr -Preview $_.Exception.Message -Artifact "3-final-round${round}-$stamp.md"
        throw
    }
    $currentCode = $step4.Content
    $totalApiCalls++
    Write-Host "      修订完成（$($step4.Tokens) token，思考 $($step4.ReasonTok) token，$($step4.Finish)）" -ForegroundColor DarkGray
    Write-ModelTraceEnd -Role "reviser" -Model $ReviserModel -Result $step4 -Preview $currentCode -Artifact "3-final-round${round}-$stamp.md"

    # -- 验证 --
    Write-Host "[$roundLabel] $ValidatorModel 正在验证..." -ForegroundColor Green
    $validatePrompt = "修订后的代码：`n$currentCode`n`n原始合并审查意见：`n$consolidated`n`n请验证是否所有高/中严重度问题已解决。"
    Write-ModelTraceStart -Role "validator" -Model $ValidatorModel -Action "validate revised code ($roundLabel)" -BaseUrl $ValidatorBaseUrl
    try {
        $step5 = Invoke-Chat -Model $ValidatorModel -SystemPrompt $validatorSystem -UserPrompt $validatePrompt -MaxTokens 4000 -Temp 1 -TimeoutSec $RequestTimeoutSec -RequestBaseUrl $ValidatorBaseUrl -RequestApiKey $ValidatorApiKey
    } catch {
        $traceErr = New-ModelTraceErrorResult $_.Exception.Message
        Write-ModelTraceEnd -Role "validator" -Model $ValidatorModel -Result $traceErr -Preview $_.Exception.Message -Artifact "4-validation-round${round}-$stamp.md"
        throw
    }
    $verdict = $step5.Content
    $totalApiCalls++
    Write-Host "      验证完成（$($step5.Tokens) token，$($step5.Finish)）" -ForegroundColor DarkGray
    Write-ModelTraceEnd -Role "validator" -Model $ValidatorModel -Result $step5 -Preview $verdict -Artifact "4-validation-round${round}-$stamp.md"

    $allVerdicts += $verdict
    $allFinals += $currentCode

    # 保存本轮产物
    $roundFile = Join-Path $OutDir "3-final-round${round}-$stamp.md"
    Write-Utf8 $roundFile "# 第 ${round} 轮代码（$ReviserModel）`n`n$currentCode"
    $valFile = Join-Path $OutDir "4-validation-round${round}-$stamp.md"
    Write-Utf8 $valFile "# 第 ${round} 轮验证（$ValidatorModel）`n`n$verdict"

    $isPass = $verdict -match "PASS" -and $verdict -notmatch "FAIL"

    $roundResults += [pscustomobject]@{
        Round     = $round
        ReviseTok = $step4.Tokens
        ValidTok  = $step5.Tokens
        Verdict   = if ($isPass) { "PASS" } else { "FAIL" }
        File      = "3-final-round${round}-$stamp.md"
    }

    $resultLabel = if ($isPass) { "PASS" } else { "FAIL" }
    $resultColor = if ($isPass) { "Green" } else { "Yellow" }
    Write-Host "      [$roundLabel] 结果: $resultLabel" -ForegroundColor $resultColor

    if ($isPass) { break }
    if ($round -lt $MaxRounds) {
        Write-Host "      自动进入下一轮修订..." -ForegroundColor DarkGray
    }
}

$final = $allFinals[-1]
$verdict = $allVerdicts[-1]

# ============ 运行报告 JSON ============
$report = [pscustomobject]@{
    task          = $Task
    language      = $Language
    timestamp     = $stamp
    writerModel   = $WriterModel
    writerBaseUrl = $WriterBaseUrl
    reviserModel  = $ReviserModel
    reviserBaseUrl = $ReviserBaseUrl
    reviewerModel = $ReviewerModel
    reviewerBaseUrl = $ReviewerBaseUrl
    reviewerJobs  = @($jobs | ForEach-Object { [pscustomobject]@{ name = $_.Name; model = $_.Model; baseUrl = $_.BaseUrl } })
    reviewerCount = $ReviewerCount
    validatorModel = $ValidatorModel
    validatorBaseUrl = $ValidatorBaseUrl
    maxRounds     = $MaxRounds
    requestTimeoutSec = $RequestTimeoutSec
    actualRounds  = $roundResults.Count
    totalApiCalls = $totalApiCalls
    finalVerdict  = if ($isPass) { "PASS" } else { "FAIL" }
    rounds        = $roundResults
}
$reportJson = $report | ConvertTo-Json -Depth 5
Write-Utf8 (Join-Path $OutDir "summary-$stamp.json") $reportJson

# ============ 汇总 ============
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " 完成！$(if ($isPass) { '验证通过 PASS' } else { '验证未通过 FAIL（已达最大轮数）' })" -ForegroundColor $(if ($isPass) { 'Green' } else { 'Yellow' })
Write-Host " 轮数: $($roundResults.Count)/$MaxRounds | API调用: $totalApiCalls 次" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
foreach ($r in $roundResults) {
    $color = if ($r.Verdict -eq "PASS") { 'Green' } else { 'Yellow' }
    Write-Host "  Round $($r.Round): $($r.Verdict)  (修订 $($r.ReviseTok) tok + 验证 $($r.ValidTok) tok)  -> $($r.File)" -ForegroundColor $color
}
Write-Host "  报告     : summary-$stamp.json" -ForegroundColor White
Write-Host ""
Write-Host "----- 最终代码 -----" -ForegroundColor Cyan
Write-Host ""
Write-Host $final -ForegroundColor White
Write-Host ""
Write-Host "----- 验证结论 -----" -ForegroundColor Cyan
Write-Host $verdict -ForegroundColor $(if ($isPass) { 'Green' } else { 'Yellow' })
Write-Host ""
