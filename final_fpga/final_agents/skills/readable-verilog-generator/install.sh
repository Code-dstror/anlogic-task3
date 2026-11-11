#!/usr/bin/env bash
set -euo pipefail

# 脚本目录是启动投影和 Python 包模块的唯一查找根。
path_script_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# 统计投影文件数量，只有一个文件时才能确定后端配置身份。
count_manifest="$(find "$path_script_root" -maxdepth 1 -type f -name '*.manifest.env' -print | wc -l)"

# 候选数量异常会让后端读取不确定路径，因此立即停止。
if [[ "$count_manifest" != "1" ]]; then

    # 入口失败不创建目标目录，也不启动未绑定的 Python。
    printf '%s\n' '> ERR: [Shell] installer bootstrap projection is not unique' >&2

    # 将投影完整性失败状态交还调用者。
    exit 1
fi

# 读取唯一投影路径，后续摘要和参数都使用同一个文件。
path_manifest="$(find "$path_script_root" -maxdepth 1 -type f -name '*.manifest.env' -print -quit)"

# 将投影字段集中保存，后端模块和解释器从同一哈希绑定来源读取。
declare -A dict_manifest_values=()

# 逐行读取投影文本，不把其中内容交给 shell 执行。
while IFS= read -r str_manifest_line || [[ -n "$str_manifest_line" ]]; do

    # 空行不代表配置事实，跳过它可避免无效字段进入摘要映射。
    if [[ -z "${str_manifest_line//[[:space:]]/}" ]]; then

        # 当前行没有字段，继续读取下一条投影记录。
        continue
    fi

    # 第一个等号分隔键和值，保留值内部字符。
    str_manifest_key="${str_manifest_line%%=*}"

    # 当前投影字段值决定后续资源 containment，先固定这项绑定事实。
    str_manifest_value="${str_manifest_line#*=}"

    # 非键值行无法形成可验证身份，继续解析会把格式错误传入后端。
    if [[ -z "$str_manifest_key" || "$str_manifest_line" != *=* ]]; then

        # 格式错误发生在任何安装副作用之前。
        printf '%s\n' '> ERR: [Shell] installer bootstrap projection contains an invalid line' >&2

        # 将格式错误状态交还调用者，停止读取后续字段。
        exit 1
    fi

    # 重复键会覆盖先前投影事实，必须在映射写入前终止。
    if [[ -v "dict_manifest_values[$str_manifest_key]" ]]; then

        # 配置歧义必须在 Python 启动前失败。
        printf '%s\n' '> ERR: [Shell] installer bootstrap projection repeats a key' >&2

        # 将重复键状态交还调用者，禁止覆盖先前配置。
        exit 1
    fi

    # 保存当前投影字段，后端随后只读取这份冻结映射。
    dict_manifest_values["$str_manifest_key"]="$str_manifest_value"

    # 当前键值已经进入冻结映射，下一轮读取从后续行开始。
done < "$path_manifest"

# 后端模块字段控制 Python 的唯一模块入口。
str_backend_module="${dict_manifest_values[BACKEND_MODULE]-}"

# 解释器候选字段控制运行时探测顺序。
str_python_candidates="${dict_manifest_values[PYTHON_CANDIDATES]-}"

# 模块或候选缺失会使包根身份不可验证，必须停止在写入之前。
if [[ -z "$str_backend_module" || -z "$str_python_candidates" ]]; then

    # 缺少投影事实时保持零安装副作用。
    printf '%s\n' '> ERR: [Shell] installer bootstrap projection is incomplete' >&2

    # 将启动字段缺失状态交还调用者，后端尚未启动。
    exit 1
fi

# 首个可用命令决定包内模块的加载运行时，后续事务不更换路径。
command_python=""

# 按投影顺序拆分解释器候选，避免不同入口混用 runtime。
mapfile -t list_python_candidates < <(printf '%s\n' "$str_python_candidates" | tr '|' '\n')

# 逐个确认候选命令位置但不执行候选程序。
for str_python_candidate in "${list_python_candidates[@]}"; do

    # 当前记录没有可执行文本，循环继续读取下一条目录候选。
    if [[ -z "$str_python_candidate" ]]; then

        # 当前候选为空，保持既有命令状态并继续检查后续清单项。
        continue
    fi

    # command -v 只解析命令路径，避免启动阶段产生业务副作用。
    if command_python="$(command -v -- "$str_python_candidate" 2>/dev/null)"; then

        # 首个可解析路径锁定本次包的解释器身份，后续不再切换。
        break
    fi
done

# 没有可用运行时就无法加载后端模块，入口保持零安装副作用。
if [[ -z "$command_python" ]]; then

    # 调用者需要先准备清单声明的运行时。
    printf '%s\n' '> ERR: [Shell] no configured Python candidate is available' >&2

    # 将解释器缺失状态交还调用者，后端尚未启动。
    exit 1
fi

# 共享参数数组绑定包根、投影和调用者原始参数。
list_forward_arguments=(--bundle-root "$path_script_root" --manifest-env "$path_manifest" "$@")

# 该状态控制是否跳过自动替换，避免预演意外进入写入事务。
is_bool_dry_run_requested=false

# 扫描原始参数，保持 DryRun 与自动备份的边界清晰。
for str_forward_argument in "$@"; do

    # 只要出现 dry-run，后续就不能创建备份或写入目标。
    if [[ "$str_forward_argument" == "--dry-run" ]]; then

        # 命令参数已声明只读边界，后端不得创建备份或替换目标。
        is_bool_dry_run_requested=true

        # 已经找到边界参数，不再扫描后续值。
        break
    fi
done

# 真实写入默认启用受管替换，让已有目标先进入自动备份目录。
if [[ "$is_bool_dry_run_requested" == "false" ]]; then

    # 后端负责判断目标是否存在以及执行原子备份和恢复。
    list_forward_arguments+=(--replace --yes)
fi

# 在包根运行模块，确保包内导入不依赖调用者当前目录。
cd -- "$path_script_root"

    # 后端原始退出码直接返回，不在 Shell 层重新解释状态。
"$command_python" -B -m "$str_backend_module" "${list_forward_arguments[@]}"

# 记录后端退出状态，脚本末尾据此透传调用结果。
exit_code_backend="$?"

# 将清单映射后的最终状态交还调用者。
exit "$exit_code_backend"
