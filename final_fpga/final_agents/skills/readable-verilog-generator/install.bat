@echo off
setlocal EnableExtensions

REM 将命令解释页切换到 UTF-8，避免同级中文注释被当作命令执行。
@chcp 65001 >nul

REM 从同级启动投影读取 PowerShell 候选，避免在 BAT 内复制运行时名称。
set "POWERSHELL_CANDIDATES="

REM 只把投影字段的值保存为后续宿主探测输入。
for /f "tokens=1,* delims==" %%A in ('findstr /b "POWERSHELL_CANDIDATES=" "%~dp0installer.manifest.env"') do set "POWERSHELL_CANDIDATES=%%B"

REM 同时读取投影声明的启动失败退出码，保持状态来源一致。
set "BOOTSTRAP_FAILURE_EXIT_CODE="

REM 只把投影声明的启动失败状态保存为退出码来源。
for /f "tokens=1,* delims==" %%A in ('findstr /b "BOOTSTRAP_FAILURE_EXIT_CODE=" "%~dp0installer.manifest.env"') do set "BOOTSTRAP_FAILURE_EXIT_CODE=%%B"

REM 为后续宿主探测准备清单声明的候选数据，保持调用者环境和包边界不变。
set "POWERSHELL_CANDIDATE_LIST=%POWERSHELL_CANDIDATES:|= %"

REM 按投影顺序探测宿主，成功后只转发同级入口和调用者参数。
for %%P in (%POWERSHELL_CANDIDATE_LIST%) do (

    REM 当前候选必须先通过 PATH 解析，避免执行未绑定命令。
    where %%P >nul 2>&1

    REM 当前候选的 PATH 定位结果决定是否允许它接管 install.ps1 的包根和调用者参数。
    if not errorlevel 1 (

        REM 将调用者参数保持原样交给同级 PowerShell 入口。
        %%P -NoProfile -File "%~dp0install.ps1" %*

        REM 将该候选启动的后端状态绑定到统一收尾变量。
        set "EXIT_CODE_BACKEND=%ERRORLEVEL%"

        REM 入口已完成，跳到统一 endlocal 收尾。
        goto :finish
    )
)

REM 缺少投影或宿主时不猜测运行时，直接返回清单声明的启动失败状态。
if defined BOOTSTRAP_FAILURE_EXIT_CODE (

    REM 投影存在时采用其声明的启动失败状态。
    set "EXIT_CODE_BACKEND=%BOOTSTRAP_FAILURE_EXIT_CODE%"
) else (

    REM 投影缺失时保留最近一次宿主探测结果，避免伪造成功状态。
    set "EXIT_CODE_BACKEND=%ERRORLEVEL%"
)

REM 统一收尾标签只负责保留已经确定的后端状态。
:finish

REM 保存 PowerShell 后端的原始退出状态，避免 endlocal 覆盖结果。
if not defined EXIT_CODE_BACKEND set "EXIT_CODE_BACKEND=%ERRORLEVEL%"

REM 将统一安装后端的状态交还给 BAT 调用者。
endlocal & exit /b %EXIT_CODE_BACKEND%
