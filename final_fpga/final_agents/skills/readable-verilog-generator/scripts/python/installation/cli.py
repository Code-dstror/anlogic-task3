"""参数化单 Harness 安装命令。

本模块声明 machine-readable stdout protocol：启用 --json 时，标准输出只包含一个
JSON 对象；普通模式只输出带固定前缀的短状态摘要。
"""

# 注解延迟求值保持 CLI 与包内模型兼容。
from __future__ import annotations

# argparse 暴露三个入口共享的参数协议。
import argparse

# json 负责单对象机器输出。
import json

# os 提供目录驱动的平台环境快照。
import os

# pathlib 统一表达调用者覆盖路径。
from pathlib import Path

# sys 提供终端检测和错误输出。
import sys

# Any 描述配置驱动的结构化结果。
from typing import Any

# BundleError 表达包内投影和完整性失败。
from .bundle import BundleError

# load_bundle 绑定包内清单、目录和投影摘要。
from .bundle import load_bundle

# parse_manifest_env 提供启动失败时的退出码来源。
from .bundle import parse_manifest_env

# CatalogError 表达平台目录和目标解析失败。
from .catalog import CatalogError

# PlatformRecord 标注选定的平台目录记录。
from .catalog import PlatformRecord

# detect_platforms 发现当前环境中的平台候选。
from .catalog import detect_platforms

# find_platform 执行规范 ID 或别名精确查找。
from .catalog import find_platform

# load_platform_records 将投影转换为不可变记录。
from .catalog import load_platform_records

# resolve_platform_root 解析平台根目录。
from .catalog import resolve_platform_root

# resolve_target 生成最终技能目标目录。
from .catalog import resolve_target

# resolve_user_home 解析用户目录边界。
from .catalog import resolve_user_home
from .receipt import load_release_receipt
from .transaction import InstallRequest, TransactionError, execute_transaction

# InstallerFailure 携带清单状态键和已前缀错误文本。
class InstallerFailure(Exception):
    """携带清单状态键的安装器失败。"""

    # __init__ 保存失败状态键供清单状态和退出码映射。
    def __init__(self, str_message: str, str_status_key: str) -> None:
        """保存状态键和短错误摘要。

        参数：
            str_message: 已带 Python 错误前缀的短摘要。
            str_status_key: 清单声明的失败状态键。
        返回：
            无。
        """

        # 保存状态键供清单值和退出码映射。
        self.str_status_key = str_status_key  # 当前安装失败状态键。

        # 保存不含结构化载荷的短错误文本。
        self.str_message = str_message  # 当前错误摘要。

        # 让 Exception 保留同一错误文本。
        super().__init__(str_message)

# _status_value 读取清单声明的机器状态文本。
def _status_value(dict_manifest: dict[str, Any], str_status_key: str) -> str:
    """读取一个配置驱动的状态文本。

    参数：
        dict_manifest: 安装清单对象。
        str_status_key: 状态键。
    返回：
        清单声明的状态文本。
    异常：
        BundleError: 状态键缺失或值为空。
    """

    # 状态值必须来自清单，代码不维护备用协议文本。
    dict_status_values = dict_manifest.get("status_values", {})  # 清单状态键到机器文本的映射。

    # 缺失或非字符串状态不能进入机器输出。
    str_value = dict_status_values.get(str_status_key)  # 当前状态键对应的清单文本。

    # 只有清单提供非空文本时才允许进入机器输出。
    if not isinstance(str_value, str) or not str_value.strip():

        # 配置缺失必须在任何业务动作前终止。
        raise BundleError(f"> ERR: [Python] status value is missing: {str_status_key}")

    # 返回已经去除外围空白的清单值。
    return str_value.strip()

# parse_args 解析三个入口共享的安装请求。
def parse_args(list_arguments: list[str] | None = None) -> argparse.Namespace:
    """解析安装器公共参数。

    参数：
        list_arguments: 可选的显式参数列表。
    返回：
        argparse 命名空间。
    异常：
        SystemExit: argparse 处理帮助或语法错误。
    """

    # 顶层解析器保持三个启动器共享同一参数协议。
    parser = argparse.ArgumentParser(description="Install a validated skill release into one Harness.")  # 公共 CLI 解析器。

    # 包根参数绑定入口所在的受管发布目录。
    parser.add_argument("--bundle-root", required=True)

    # 启动投影参数绑定经过入口发现的配置文件。
    parser.add_argument("--manifest-env", required=True)

    # 平台值不使用 choices，候选由目录投影动态提供。
    parser.add_argument("--platform")

    # 发布源参数指定待校验的版本化载荷。
    parser.add_argument("--source")

    # 平台根覆盖控制 Harness 根解析。
    parser.add_argument("--platform-root")

    # 最终目录覆盖控制单事务写入边界。
    parser.add_argument("--target-dir")

    # 替换开关声明覆盖意图。
    parser.add_argument("--replace", action="store_true")

    # yes 开关声明非交互写入确认。
    parser.add_argument("--yes", action="store_true")

    # dry-run 开关要求全流程保持只读。
    parser.add_argument("--dry-run", action="store_true")

    # json 开关选择单对象机器协议。
    parser.add_argument("--json", action="store_true")

    # 返回调用方提供的参数命名空间。
    return parser.parse_args(list_arguments)

# emit_result 输出短人类摘要或声明的 JSON 对象。
def emit_result(dict_result: dict[str, Any], bool_json: bool, bool_error: bool = False) -> None:
    """按调用者选择输出短摘要或单一 JSON 对象。

    参数：
        dict_result: 机器可读结果对象。
        bool_json: 是否启用单对象 JSON 协议。
        bool_error: 是否使用错误输出级别。
    返回：
        无；副作用是向标准输出或标准错误输出摘要。
    """

    # JSON 模式只输出一个完整对象，不混入人类日志。
    if bool_json:

        # 结构化结果属于明确声明的 CLI stdout 协议。
        print(json.dumps(dict_result, ensure_ascii=False, sort_keys=True))

        # JSON 已经是完整输出，不继续生成文本摘要。
        return

    # 人类模式只保留短状态，不打印路径清单或完整配置。
    str_status = str(dict_result.get("status", dict_result.get("status_key", "")))  # 当前结果状态。

    # 摘要文本只保留短状态和清单消息。
    str_message = str(dict_result.get("message", str_status))  # 当前结果摘要。

    # 错误输出使用静态 ERR 前缀，质量门可以稳定识别严重级别。
    if bool_error:

        # 错误摘要不混入标准输出协议。
        print(f"> ERR: [Python] {str_status}: {str_message}", file=sys.stderr)

    # 成功输出使用静态 INFO 前缀，保留短状态摘要。
    else:

        # 普通摘要输出到标准输出。
        print(f"> INFO: [Python] {str_status}: {str_message}")

# _exit_code 将状态键绑定到清单声明的数值。
def _exit_code(dict_manifest: dict[str, Any], str_status_key: str) -> int:
    """从安装清单解析状态键的退出码。

    参数：
        dict_manifest: 安装清单对象。
        str_status_key: 当前状态键。
    返回：
        清单声明的数值退出码。
    异常：
        InstallerFailure: 清单缺少状态映射。
    """

    # 退出码映射只能来自安装清单。
    dict_exit_codes = dict_manifest.get("exit_codes", {})  # 清单退出码映射。

    # 状态键先解析为清单文本，再读取退出码。
    str_status = _status_value(dict_manifest, str_status_key)  # 当前状态的清单文本。

    # 读取清单声明的数值退出码。
    object_code = dict_exit_codes.get(str_status)  # 当前状态退出码。

    # 缺少映射时不能猜测数值。
    if not isinstance(object_code, int):

        # 配置错误本身使用 Python 异常前缀。
        raise InstallerFailure("> ERR: [Python] exit code mapping is missing", "integrity_error")

    # 返回受清单约束的进程状态。
    return object_code

# _select_platform 解析显式值或目录探测候选。
def _select_platform(
    list_records: list[PlatformRecord],
    str_requested: str | None,
    path_home: Path,
    bool_noninteractive: bool,
) -> PlatformRecord:
    """根据显式值或目录检测选择唯一平台。

    参数：
        list_records: 包内平台记录。
        str_requested: 显式平台 ID 或别名。
        path_home: 已解析用户目录。
        bool_noninteractive: 是否禁止交互式选择。
    返回：
        唯一平台记录。
    异常：
        InstallerFailure: 平台未知、候选歧义或输入不可用。
    """

    # 显式平台始终优先于环境探测。
    if str_requested:

        # 精确目录查找失败时向上层报告输入错误。
        try:

            # 平台 ID 和别名均由目录解析。
            return find_platform(list_records, str_requested)

        # 把目录错误映射为用户可处理的输入状态。
        except CatalogError as object_error:

            # 保留未知值信息但不自动纠错。
            raise InstallerFailure(f"> ERR: [Python] {object_error}", "input_error") from object_error

    # 没有显式值时按当前环境探测目录记录。
    list_detected = detect_platforms(list_records, path_home, dict(os.environ))  # 当前环境候选平台。

    # 只有一个候选时可以安全自动选择。
    if len(list_detected) == 1:

        # 返回唯一检测结果。
        return list_detected[0]

    # 非交互模式下不能猜测零个或多个候选。
    if bool_noninteractive:

        # 机器调用者需要显式平台值。
        raise InstallerFailure("> ERR: [Python] platform selection is ambiguous", "input_error")

    # 交互菜单只展示目录动态生成的候选。
    list_menu = list_detected if list_detected else list_records  # 交互平台菜单。

    # 按目录顺序显示候选并保留用户选择序号。
    for int_index, platform_record_value in enumerate(list_menu, start=1):

        # 菜单内容由平台目录的显示名称提供。
        print(
            f"> INFO: [Python] {int_index}: "
            f"{platform_record_value.display_name} ({platform_record_value.platform_id})"
        )

    # 读取用户选择并验证范围。
    str_choice = input("> INFO: [Python] Select one platform: ").strip()  # 用户平台选择。

    # 将交互文本转换为菜单序号。
    try:

        # 菜单序号是交互层局部协议，不写入平台业务逻辑。
        int_choice = int(str_choice)  # 用户选择序号。

    # 非整数选择返回输入错误。
    except ValueError as object_error:

        # 交互错误不能回退到默认平台。
        raise InstallerFailure("> ERR: [Python] platform selection is not an integer", "input_error") from object_error

    # 只接受当前菜单中的合法序号。
    if int_choice < 1 or int_choice > len(list_menu):

        # 越界时停止而不是循环猜测。
        raise InstallerFailure("> ERR: [Python] platform selection is outside the menu", "input_error")

    # 返回用户明确选择的目录记录。
    return list_menu[int_choice - 1]

# _build_request 生成一个 Harness 一个目标的规范化请求。
def _build_request(
    namespace_args: argparse.Namespace,
    dict_bundle: dict[str, Any],
    platform_record_value: PlatformRecord,
    path_home: Path,
) -> InstallRequest:
    """解析源、根和目标并生成单事务请求。

    参数：
        namespace_args: CLI 参数。
        dict_bundle: 已校验包上下文。
        platform_record_value: 唯一平台记录。
        path_home: 已解析用户目录。
    返回：
        规范化安装请求。
    异常：
        InstallerFailure: 路径、源或确认条件不满足。
    """

    # 显式平台根覆盖只影响目标根解析，不改变平台身份。
    path_root_override = Path(namespace_args.platform_root).expanduser() if namespace_args.platform_root else None  # 平台根覆盖。

    # 由目录记录和清单规则解析平台根。
    try:

        # 平台根可能尚不存在，但必须通过 containment 规则。
        path_platform_root = resolve_platform_root(  # 规范化平台根。
            platform_record_value,  # 目录平台记录。
            path_home,  # 用户根目录。
            dict(os.environ),  # 环境变量快照。
            path_root_override,  # 调用者传入的平台根替代值。
        )

    # 平台根配置错误映射为输入状态。
    except CatalogError as object_error:

        # 不在代码中加入平台根默认值。
        raise InstallerFailure(f"> ERR: [Python] {object_error}", "input_error") from object_error

    # 最终目标覆盖保持显式路径语义。
    path_target_override = Path(namespace_args.target_dir).expanduser() if namespace_args.target_dir else None  # 最终目录覆盖。

    # 目标路径由目录模板或调用者覆盖值计算。
    try:

        # 目标目录尚不存在时仍先完成字符串边界检查。
        path_target = resolve_target(  # 规范化最终目标。
        platform_record_value,  # 选定的目录平台值。
            path_platform_root,  # 解析后的平台根。
            dict_bundle["skill_id"],  # 包元数据技能 ID。
            dict_bundle["manifest"],  # 安装路径清单。
            path_target_override,  # 调用者目标覆盖。
        )

    # 目标模板或覆盖值错误映射为输入状态。
    except (CatalogError, ValueError, KeyError) as object_error:

        # 不允许目标模板缺失时继续事务。
        raise InstallerFailure(
            f"> ERR: [Python] cannot resolve target directory: {object_error}",
            "input_error",
        ) from object_error

    # Source 缺省时使用包根，但必须通过发布收据验证。
    path_source = Path(namespace_args.source).expanduser() if namespace_args.source else dict_bundle["bundle_root"]  # 发布源目录。

    # 源和目标的 containment 关系在 dry-run 阶段也必须先被拒绝。
    path_source_resolved = path_source.resolve()  # 规范化发布源根。

    # 目标规范路径供包含关系比较使用。
    path_target_resolved = path_target.resolve()  # 规范化安装目标。

    # 源与目标只要存在包含关系就不能执行复制。
    if (
        path_source_resolved == path_target_resolved
        or path_source_resolved.is_relative_to(path_target_resolved)
        or path_target_resolved.is_relative_to(path_source_resolved)
    ):

        # 交叠目录会使收据和暂存边界失效。
        raise InstallerFailure("> ERR: [Python] source and target directories overlap", "input_error")

    # 已存在目标需要显式 replace。
    if path_target.exists() and not namespace_args.replace and not namespace_args.dry_run:

        # 不把用户现有安装当作可静默覆盖。
        raise InstallerFailure("> ERR: [Python] target exists; --replace is required", "input_error")

    # 非 dry-run 替换还需要显式确认。
    if path_target.exists() and namespace_args.replace and not namespace_args.yes and not namespace_args.dry_run:

        # 非交互脚本不会自动同意破坏性覆盖。
        raise InstallerFailure("> ERR: [Python] replacement requires --yes", "input_error")

    # 收束单 Harness 的源、目标和确认边界。
    dict_install_request: dict[str, Any] = {  # 规范化请求字段。
        "platform_id": platform_record_value.platform_id,  # 目录平台 ID。
        "source_root": path_source.resolve(),  # 已规范化发布源。
        "platform_root": path_platform_root,  # 已解析平台根。
        "target_dir": path_target,  # 最终安装目标。
        "replace": namespace_args.replace,  # 覆盖意图。
        "assume_yes": namespace_args.yes,  # 非交互确认。
        "dry_run": namespace_args.dry_run,  # 只读预演开关。
    }

    # 使用字段映射创建类型明确的事务请求。
    install_request_value: InstallRequest = InstallRequest(**dict_install_request)  # 单事务请求。

    # 将带有明确类型的请求交给上层安装流程。
    return install_request_value

# run_install 执行投影校验、源验证和事务调度。
def run_install(namespace_args: argparse.Namespace) -> tuple[dict[str, Any], str]:
    """执行一次安装请求并返回结果与状态名。

    参数：
        namespace_args: 已解析命令行参数。
    返回：
        结果对象和清单符号状态。
    异常：
        InstallerFailure: 已分类安装失败。
    """

    # 启动器提供的包根和 manifest 路径是唯一入口边界。
    path_bundle = Path(namespace_args.bundle_root).expanduser().resolve()  # 包根路径。

    # 启动投影路径由入口发现并显式绑定。
    path_env = Path(namespace_args.manifest_env).expanduser().resolve()  # 启动投影路径。

    # 读取并校验包内投影和技能身份。
    try:

        # 运行时不读取外部 agents-md-generator。
        dict_bundle = load_bundle(path_bundle, path_env)  # 已验证的包上下文。

    # 投影错误属于完整性失败。
    except BundleError as object_error:

        # 保留 Python 错误前缀和原始诊断。
        raise InstallerFailure(f"> ERR: [Python] {object_error}", "integrity_error") from object_error

    # 平台目录来自合并投影，而非源代码枚举。
    try:

        # 构造目录记录供显式选择和探测。
        list_records = load_platform_records(dict_bundle["projection"])  # 平台记录。

    # 目录错误属于完整性失败。
    except CatalogError as object_error:

        # 不让损坏目录进入路径解析。
        raise InstallerFailure(f"> ERR: [Python] {object_error}", "integrity_error") from object_error

    # 用户目录由清单环境变量候选解析。
    try:

        # Path.home 只作为清单环境变量都缺失时的运行时回退。
        path_home = resolve_user_home(dict_bundle["manifest"], dict(os.environ), Path.home())  # 用户目录。

    # 用户目录失败属于输入环境错误。
    except CatalogError as object_error:

        # 调用者可以通过平台根覆盖修复环境边界。
        raise InstallerFailure(f"> ERR: [Python] {object_error}", "input_error") from object_error

    # JSON 或无终端模式不得进入交互选择。
    bool_noninteractive = bool(namespace_args.json or not sys.stdin.isatty())  # 是否禁止交互。

    # 选择一个且仅一个平台。
    platform_record_value: PlatformRecord = _select_platform(  # 唯一平台记录。
        list_records,  # 当前投影的候选记录。
        namespace_args.platform,  # 显式平台请求。
        path_home,  # 当前用户根。
        bool_noninteractive,  # 非交互选择边界。
    )

    # 解析源、平台根和目标目录。
    install_request_value: InstallRequest = _build_request(  # 复用当前目标的结构化安装请求，避免复制阶段重新推断目录边界。
        namespace_args,  # CLI 提供的覆盖和确认参数集合。
        dict_bundle,  # 已验证包投影与技能身份映射。
        platform_record_value,  # 目录选定的 Harness 根解析记录。
        path_home,  # 清单环境变量解析出的用户目录边界。
    )

    # 收据身份需要当前包元数据，临时注入清单只在内存中存在。
    dict_manifest = dict(dict_bundle["manifest"])  # 当前事务清单副本。

    # 将包技能 ID写入内存清单供收据校验。
    dict_manifest["_runtime_skill_id"] = dict_bundle["skill_id"]  # 收据校验用技能身份。

    # 把包版本绑定到当前收据身份检查。
    dict_manifest["_runtime_version"] = dict_bundle["version"]  # 收据校验用版本。

    # Source 必须通过发布收据和逐文件摘要校验。
    try:

        # 源码根缺收据时在复制前失败。
        dict_source_receipt, dict_source_files = load_release_receipt(  # 源发布证据。
            install_request_value.source_root,  # 待校验的发布目录。
            dict_manifest,  # 当前包身份清单。
        )

    # 收据错误属于完整性失败。
    except BundleError as object_error:

        # 明确拒绝源码目录直接安装。
        raise InstallerFailure(f"> ERR: [Python] {object_error}", "integrity_error") from object_error

    # dry-run 只返回计划，不创建任何事务资源。
    if install_request_value.dry_run:

        # 机器结果只包含规范化路径和状态摘要。
        return (
            {
                "status": _status_value(dict_manifest, "dry_run"),
                "message": "validated one Harness installation plan",
                "platform_id": install_request_value.platform_id,
                "source_root": str(install_request_value.source_root),
                "target_dir": str(install_request_value.target_dir),
            },
            "success",
        )

    # 真实写入由事务模块执行，失败时负责回滚。
    try:

        # 事务使用包上下文和已校验源文件索引。
        dict_result = execute_transaction(  # 安装结果。
            install_request_value,  # 单 Harness 安装请求。
            dict_bundle | {"manifest": dict_manifest},  # 绑定运行时身份的包上下文。
            dict_source_receipt,  # 已校验源收据。
            dict_source_files,  # 已校验源文件索引。
        )

    # 事务错误使用清单的回滚状态。
    except TransactionError as object_error:

        # 回滚是否完整由事务错误文本和后续收据判定。
        raise InstallerFailure(f"> ERR: [Python] {object_error}", object_error.str_status_key) from object_error

    # 返回安装结果和成功符号状态。
    return dict_result, "success"

# main 提供三类入口共享的安装 CLI。
def main(list_arguments: list[str] | None = None) -> int:
    """执行安装器 CLI 并返回清单映射的退出码。

    参数：
        list_arguments: 可选显式参数列表；为空时读取进程命令行。
    返回：
        安装清单声明的数值退出码。
    异常：
        SystemExit: 启动投影无法提供退出码映射时交由宿主处理。
    """

    # 先解析参数，帮助和语法错误由 argparse 负责。
    namespace_args = parse_args(list_arguments)  # 当前安装请求参数。

    # 失败前需要尽早知道输出模式。
    bool_json = bool(namespace_args.json)  # 是否使用机器 JSON 协议。

    # 执行主流程并统一映射失败。
    try:

        # 主流程内部会读取真实清单并返回符号状态。
        tuple_install_result: tuple[dict[str, Any], str] = run_install(namespace_args)  # 安装结果和符号状态。

        # 拆出机器结果映射供输出协议使用。
        dict_result = tuple_install_result[0]  # 安装结果对象。

        # 拆出清单状态供退出码映射使用。
        str_status = tuple_install_result[1]  # 安装符号状态。

        # 主流程成功后再读取真实清单用于退出码映射。
        dict_bundle = load_bundle(  # 重新读取不可变投影以取得清单。
            Path(namespace_args.bundle_root).expanduser().resolve(),  # 成功路径的包根。
            Path(namespace_args.manifest_env).expanduser().resolve(),  # 成功路径的启动投影。
        )

        # 成功路径的清单提供最终退出码映射。
        dict_manifest = dict_bundle["manifest"]  # 真实安装清单。

        # 输出成功摘要或单 JSON 对象。
        emit_result(dict_result, bool_json)

        # 返回清单声明的成功状态码。
        return _exit_code(dict_manifest, str_status)

    # 已分类错误使用错误对象携带状态。
    except InstallerFailure as object_error:

        # 失败时尽力读取清单，仍不在代码中猜测数值。
        try:

            # 只有包内投影可读时才能取得清单退出码。
            dict_bundle = load_bundle(  # 失败路径的清单读取。
                Path(namespace_args.bundle_root).expanduser().resolve(),  # 失败路径的包根。
                Path(namespace_args.manifest_env).expanduser().resolve(),  # 失败路径的启动投影。
            )

            # 失败路径仍优先使用包内清单状态。
            dict_manifest = dict_bundle["manifest"]  # 失败路径的真实清单。

        # 失败路径的二次读取错误保持最小映射。
        except BundleError:

            # 投影不可读时从启动 env 读取清单声明的 bootstrap 状态。
            try:

                # 启动投影仍是唯一可用的退出码来源。
                dict_bootstrap = parse_manifest_env(Path(namespace_args.manifest_env).expanduser().resolve())  # 启动状态映射。

                # 将清单声明的启动失败状态解析为整数。
                int_bootstrap_code = int(dict_bootstrap["BOOTSTRAP_FAILURE_EXIT_CODE"])  # 启动失败退出码。

            # 投影和退出码同时损坏时交由宿主处理非零状态。
            except (BundleError, KeyError, ValueError) as bootstrap_error:

                # 不在代码中猜测新的数值退出码。
                raise SystemExit(
                    f"> ERR: [Python] installer bootstrap exit mapping unavailable: {bootstrap_error}"
                ) from bootstrap_error

            # 输出失败摘要后使用启动投影声明的数值。
            emit_result(  # 启动失败摘要。
                {"status_key": object_error.str_status_key, "message": object_error.str_message},
                bool_json,
                True,
            )

            # 启动投影的状态是当前唯一可验证退出码。
            return int_bootstrap_code

        # 输出短失败摘要，不泄漏结构化路径清单。
        emit_result(  # 失败结果摘要。
            {
                "status": _status_value(dict_manifest, object_error.str_status_key),
                "message": object_error.str_message,
            },
            bool_json,
            True,
        )

        # 读取到完整清单时仍使用清单的符号映射。
        return _exit_code(dict_manifest, object_error.str_status_key)

# 直接执行模块时保留清单映射出的退出码。
if __name__ == "__main__":

    # SystemExit 保留 CLI 的清单退出码。
    raise SystemExit(main())
