[CmdletBinding()]
param(
    [string]$Platform,
    [string]$Source,
    [string]$PlatformRoot,
    [string]$TargetDir,
    [Alias("Replace")]
    [switch]$IsReplace,
    [Alias("Yes")]
    [switch]$IsYes,
    [Alias("DryRun")]
    [switch]$IsDryRun,
    [Alias("Json")]
    [switch]$IsJson
)

# 入口目录是唯一受管包根，所有投影搜索都从这里开始。
$listManifestCandidates = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.manifest.env" -File -ErrorAction Stop)

# 候选数量不为一时无法确定投影身份，继续启动会让后端读取不确定配置。
if ($listManifestCandidates.Count -ne 1) {

    # 入口不确定时不启动解释器，也不触碰用户目标目录。
    throw "> ERR: [PowerShell] installer bootstrap projection is not unique"
}

# 将已确认的投影文件绑定到摘要校验和后端参数，避免重新扫描其它配置。
$pathManifest = $listManifestCandidates[0].FullName

# 将投影字段保存在字典中，后端模块和解释器都从同一哈希绑定来源读取。
$dictManifestValues = @{}

# 投影每行只作为键值数据读取，不执行其中的 PowerShell 语法。
foreach ($strManifestLine in Get-Content -LiteralPath $pathManifest -Encoding UTF8) {

    # 空行不产生配置事实，避免把可读性间隔当作字段。
    if ([string]::IsNullOrWhiteSpace($strManifestLine)) {

        # 空行不代表配置事实，跳过它可避免无效字段进入摘要映射。
        continue
    }

    # 每行只在第一个等号处分隔键和值，保留路径内部字符。
    $listManifestParts = $strManifestLine -split "=", 2

    # 结构异常时停止解析，防止调用方看到不完整后端身份。
    if ($listManifestParts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($listManifestParts[0])) {

        # 非键值行无法形成可验证摘要，继续解析会把格式错误传入后端。
        throw "> ERR: [PowerShell] installer bootstrap projection contains an invalid line"
    }

    # 将键文本固定为字段索引，重复检查才能阻止后端身份覆盖。
    $strManifestKey = $listManifestParts[0].Trim()

    # 将值文本原样保留给路径解析、模块启动和摘要校验。
    $strManifestValue = $listManifestParts[1].Trim()

    # 重复键会覆盖先前投影事实，因此必须在映射写入前终止。
    if ($dictManifestValues.ContainsKey($strManifestKey)) {

        # 解析歧义发生在任何安装副作用之前。
        throw "> ERR: [PowerShell] installer bootstrap projection repeats a key"
    }

    # 将通过格式检查的键值写入冻结映射。
    $dictManifestValues[$strManifestKey] = $strManifestValue
}

# 读取哈希绑定模块字段，避免入口凭空拼接包内导入路径。
$strBackendModule = $dictManifestValues["BACKEND_MODULE"]

# 解释器候选顺序由清单控制，空值不能形成可运行入口。
$pathListPythonCandidates = @($dictManifestValues["PYTHON_CANDIDATES"] -split '\|')

# 模块或候选缺失会使包根身份不可验证，必须停止在写入之前。
if ([string]::IsNullOrWhiteSpace($strBackendModule) -or $pathListPythonCandidates.Count -eq 0) {

    # 投影完整性失败时不允许把空值解释成默认运行时。
    throw "> ERR: [PowerShell] installer bootstrap projection is incomplete"
}

# 解释器探测按投影顺序进行，确保同一包每次选择一致。
$commandPython = $null

# 首个可用解释器决定包内模块的加载运行时，后续事务不会更换该路径。
foreach ($strPythonCandidate in $pathListPythonCandidates) {

    # 当前记录没有可执行文本，循环继续读取下一条目录候选。
    if ([string]::IsNullOrWhiteSpace($strPythonCandidate)) {

        # 当前候选无效时继续检查下一个记录。
        continue
    }

    # 只解析命令位置而不执行候选，避免启动阶段产生副作用。
    $commandInfo = @(Get-Command -Name $strPythonCandidate.Trim() -CommandType Application -ErrorAction SilentlyContinue) | Select-Object -First 1

        # 将解析出的命令路径写入 commandPython，后续不再改写启动身份。
    if ($null -ne $commandInfo) {

        # 版本探针确认候选命令可启动后端，失败候选不会进入事务。
        & $commandInfo.Source --version *> $null

        # 当前候选的启动失败不会污染后续解释器选择，继续读取投影顺序。
        if ($LASTEXITCODE -ne 0) {

            # 失败候选不改变后端身份，继续按投影顺序尝试下一个命令。
            continue
        }

        # 首个可调用路径成为后端身份，后续参数全部交给它。
        $commandPython = $commandInfo.Source

        # 已锁定投影顺序中的解释器，避免一次事务混用多个运行时。
        break
    }
}

# 没有可用运行时就无法加载后端模块，入口必须保持零安装副作用。
if ([string]::IsNullOrWhiteSpace($commandPython)) {

    # 让调用者修复投影声明的运行时环境。
    throw "> ERR: [PowerShell] no configured Python candidate is available"
}

# 统一参数数组先绑定包根和启动投影，后端复用同一边界。
$listForwardArguments = @("--bundle-root", $PSScriptRoot, "--manifest-env", $pathManifest)

# 显式平台参数交给目录驱动后端进行精确校验。
if ($Platform) {

    # 平台参数保持调用者原值，后端目录校验负责拒绝未知 ID。
    $listForwardArguments += @("--platform", $Platform)
}

# 只有调用者明确提供源目录时才把它送入发布收据检查。
if ($Source) {

    # 发布源只用于收据验证，入口不替换或拼接调用者路径。
    $listForwardArguments += @("--source", $Source)
}

# 显式平台根参数控制 Harness 根目录解析。
if ($PlatformRoot) {

    # 平台根覆盖保持调用者的路径边界。
    $listForwardArguments += @("--platform-root", $PlatformRoot)
}

# 显式最终目标参数直接绑定单事务写入目录。
if ($TargetDir) {

    # 目标目录覆盖交给后端执行 containment 检查。
    $listForwardArguments += @("--target-dir", $TargetDir)
}

# 显式 Replace 参数仍允许调用者表达覆盖意图并保持向后兼容。
if ($IsReplace) {

    # 将调用者的显式覆盖意图传给统一后端。
    $listForwardArguments += "--replace"
}

# Yes 切换声明非交互写入已经获得确认。
if ($IsYes) {

    # 非交互确认保持一次性显式传递。
    $listForwardArguments += "--yes"
}

# DryRun 切换要求后端跳过所有文件写入。
if ($IsDryRun) {

    # 预演标记只影响事务阶段，不改变目录解析。
    $listForwardArguments += "--dry-run"
}

# 真实写入默认启用受管替换，让已有目标先进入自动备份目录。
if (-not $IsDryRun) {

    # 后端仍负责判断目标是否存在以及执行原子备份和恢复。
    $listForwardArguments += @("--replace", "--yes")
}

# Json 切换要求后端输出单一机器对象。
if ($IsJson) {

    # 结构化输出由 CLI 后端统一生成。
    $listForwardArguments += "--json"
}

# 在包根启动模块，保证本地包导入不依赖调用者当前目录。
Push-Location -LiteralPath $PSScriptRoot

# 临时切换目录只包围后端调用，finally 会恢复调用者位置。
try {

    # 后端退出码必须原样返回，入口不重新解释状态。
    & $commandPython -B -m $strBackendModule @listForwardArguments

    # 保存后端原始退出码，避免入口重新解释状态。
    $exitCodeBackend = $LASTEXITCODE
}

# 无论后端结果如何都恢复调用者目录。
finally {

    # 恢复动作发生在离开临时包根之前。
    Pop-Location
}

# 把后端返回的退出状态交还给调用方，避免入口重映射。
exit $exitCodeBackend
