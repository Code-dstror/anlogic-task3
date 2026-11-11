"""执行安装器字面量审计与配置驱动隔离 smoke。"""

# 注解延迟求值保持验证器兼容性。
from __future__ import annotations

# argparse 提供两个公开验证子命令。
import argparse

# json 读取权威配置并写入机器报告。
import json

# pathlib 表达技能和临时目录边界。
from pathlib import Path

# shutil 复制隔离发布源。
import shutil

# subprocess 调用安装后端。
import subprocess

# sys 提供当前 Python 解释器路径。
import sys

# tempfile 提供系统临时根。
import tempfile

# Any 描述配置驱动 JSON 节点。
from typing import Any

# 复用安装包投影和摘要实现。
from scripts.python.installation.bundle import load_bundle, sha256_file
from scripts.python.installation.catalog import load_platform_records

# AuditFailure 统一验证失败边界。
class AuditFailure(ValueError):
    """表示审计或隔离 smoke 不能形成可信结论。"""

# parse_args 绑定验证命令的权威输入。
def parse_args(list_arguments: list[str] | None = None) -> argparse.Namespace:
    """解析 audit 或 smoke 子命令。

    参数：
        list_arguments: 可选显式参数列表。
    返回：
        验证命名空间。
    """

    # 顶层解析器只负责选择验证行为。
    parser = argparse.ArgumentParser(description="Verify the parameterized installer.")  # 验证 CLI 解析器。

    # 两个子命令拥有不同的权威输入。
    subparsers = parser.add_subparsers(dest="command", required=True)  # audit/smoke 子命令集合。

    # audit 扫描产品源码和入口脚本。
    argument_parser_audit = subparsers.add_parser("audit")  # 字面量审计解析器。

    # audit 参数名称由调用者逐项提供。
    for str_argument in ("skill-root", "manifest", "catalog", "cases", "report"):

        # 统一绑定必需的 audit 路径参数。
        argument_parser_audit.add_argument(f"--{str_argument}", required=True)

    # smoke 从同一 case 权威源动态展开。
    argument_parser_smoke = subparsers.add_parser("smoke")  # 隔离 smoke 解析器。

    # smoke 参数通过同一入口合同注册。
    for str_argument in ("skill-root", "manifest-env", "cases", "report"):

        # 将 smoke 路径字段标记为必填。
        argument_parser_smoke.add_argument(f"--{str_argument}", required=True)

    # 返回调用者提供的验证请求。
    return parser.parse_args(list_arguments)

# read_json 读取顶层对象配置。
def read_json(path_json: Path) -> dict[str, Any]:
    """读取 UTF-8 JSON 对象。

    参数：
        path_json: JSON 文件路径。
    返回：
        JSON 对象。
    异常：
        AuditFailure: 顶层类型不正确。
    """

    # 解析当前权威 JSON 文件。
    object_value = json.loads(path_json.read_text(encoding="utf-8"))  # 当前配置对象。

    # 顶层标量不能表达验证目录。
    if not isinstance(object_value, dict):

        # 让调用方修复 Schema 输入。
        raise AuditFailure("> ERR: [Python] installer verification source must be a JSON object")

    # 返回已确认的对象配置。
    return object_value

# collect_json_strings 展开 JSON 节点并收集字符串事实。
def collect_json_strings(object_root: Any, set_values: set[str]) -> None:
    """把配置节点中的字符串加入审计集合。

    参数：
        object_root: 待扫描 JSON 节点。
        set_values: 共享的动态值集合。
    返回：
        无；直接扩展 set_values。
    """

    # 显式队列避免递归深度依赖。
    list_nodes = [object_root]  # 待扫描 JSON 节点。

    # 按节点类型展开配置内容。
    while list_nodes:

        # 取出一个待处理节点。
        object_node = list_nodes.pop()  # 当前 JSON 节点。

        # 字典值继续进入扫描队列。
        if isinstance(object_node, dict):

            # 字段名不是业务值，只展开对象值。
            list_nodes.extend(object_node.values())

            # 当前对象已经展开，不再走标量分支。
            continue

        # 列表成员同样继续展开。
        if isinstance(object_node, list):

            # 目录和 case 数组成员进入队列。
            list_nodes.extend(object_node)

            # 当前列表已经展开，不再走标量分支。
            continue

        # 非字符串节点不形成动态值。
        if not isinstance(object_node, str):

            # 跳过数字、布尔和空对象。
            continue

        # 短文本不能可靠表示路径或身份。
        if len(object_node) < 4:

            # 保持审计集合聚焦于可变事实。
            continue

        # 模板文本不是当前运行时固定值。
        if "{" in object_node or "}" in object_node:

            # 跳过清单模板变量。
            continue

        # 保存当前配置字符串。
        set_values.add(object_node)

# authority_values 提取可能随环境变化的配置事实。
def authority_values(
    dict_manifest: dict[str, Any],
    dict_catalog: dict[str, Any],
    dict_cases: dict[str, Any],
    str_version: str,
) -> set[str]:
    """收集不得复制到安装产品源码的动态值。

    参数：
        dict_manifest: 安装清单对象。
        dict_catalog: 平台目录对象。
        dict_cases: 验证 case 对象。
        str_version: 当前版本文本。
    返回：
        去重后的动态字符串集合。
    """

    # 版本、状态和验证路径属于安装协议动态值。
    set_values = {str_version}  # 动态审计值集合。

    # 纳入清单状态文本。
    collect_json_strings(dict_manifest.get("status_values", {}), set_values)

    # 纳入验证临时目录名称。
    collect_json_strings(dict_manifest.get("verification", {}), set_values)

    # 平台记录中会随 Harness 变化的字段属于适配权威源。
    tuple_platform_identity_fields = ("id", "display_name", "aliases")  # 平台身份字段。

    # 平台根目录解析相关字段。
    tuple_platform_location_fields = ("environment_names", "fallback_home_relative")  # 平台位置字段。

    # 平台安装目录和可选元数据字段。
    tuple_platform_payload_fields = ("skill_install_dir", "metadata_files")  # 平台载荷字段。

    # 汇合全部平台可变字段。
    tuple_platform_location_fields += tuple_platform_payload_fields  # 平台位置与载荷字段。

    # 形成目录记录的完整动态字段集合。
    tuple_platform_fields = tuple_platform_identity_fields + tuple_platform_location_fields  # 平台可变字段集合。

    # 只提取目录值，不把检测算法关键词当作环境值。
    for dict_platform in dict_catalog.get("platforms", []):

        # 非对象记录由 Schema 门禁处理。
        if not isinstance(dict_platform, dict):

            # 当前字段无法形成平台事实。
            continue

        # 按字段提取平台适配文本。
        for str_field in tuple_platform_fields:

            # 平台字段值进入动态集合。
            collect_json_strings(dict_platform.get(str_field), set_values)

    # case 只审计身份、令牌和保护路径。
    tuple_case_fields = ("id", "token", "preserve_relative_path", "source_relative_path", "target_relative_path")  # case 动态字段。

    # 逐条读取 case 的动态值。
    for dict_case in dict_cases.get("cases", []):

        # 非对象 case 交给 Schema 修复。
        if not isinstance(dict_case, dict):

            # 不猜测缺失的 case 字段。
            continue

        # 只收集配置声明的可变字段。
        for str_field in tuple_case_fields:

            # 读取当前 case 字段内容。
            object_value = dict_case.get(str_field)  # 当前 case 字段值。

            # 只有非空字符串形成审计事实。
            if isinstance(object_value, str) and object_value.strip():

                # 将 case 动态值加入集合。
                set_values.add(object_value)

    # 返回非空且去重后的权威值。
    return {str_value for str_value in set_values if str_value.strip()}

# product_paths 由清单派生后端模块和公开入口。
def product_paths(path_skill_root: Path, dict_manifest: dict[str, Any]) -> list[Path]:
    """返回需要扫描的产品文件。

    参数：
        path_skill_root: 技能根目录。
        dict_manifest: 安装清单对象。
    返回：
        安装模块和公开入口列表。
    """

    # 后端相对路径是安装模块扫描边界。
    path_backend = path_skill_root / str(dict_manifest["backend_relative_path"])  # 后端源码路径。

    # 同目录 Python 模块全部属于安装产品。
    list_backend_files = sorted(path_backend.parent.glob("*.py"))  # 安装模块文件。

    # 入口文件名由清单声明，不在审计器复制。
    list_entrypoints = [path_skill_root / str(value) for value in dict_manifest.get("entrypoints", [])]  # 入口文件。

    # 返回完整产品扫描范围。
    return [*list_backend_files, *list_entrypoints]

# run_audit 执行动态字面量扫描。
def run_audit(namespace_args: argparse.Namespace) -> dict[str, Any]:
    """检查产品源码与注释是否复制权威动态值。

    参数：
        namespace_args: audit 命令参数。
    返回：
        静态审计报告对象。
    异常：
        AuditFailure: 权威源或产品文件缺失。
    """

    # 规范化审计边界和权威文件。
    path_skill_root = Path(namespace_args.skill_root).expanduser().resolve()  # 静态审计包根边界。

    # 绑定清单权威文件。
    path_manifest = Path(namespace_args.manifest).expanduser().resolve()  # 清单路径。

    # 绑定平台目录权威文件。
    path_catalog = Path(namespace_args.catalog).expanduser().resolve()  # 平台目录路径。

    # 绑定验证 case 定义边界。
    path_cases = Path(namespace_args.cases).expanduser().resolve()  # 动态场景路径。

    # 读取清单、平台目录和验证 case。
    dict_manifest = read_json(path_manifest)  # 安装清单对象。

    # 读取平台目录权威值。
    dict_catalog = read_json(path_catalog)  # 平台目录对象。

    # 读取验证 case 权威值。
    dict_cases = read_json(path_cases)  # 验证 case 对象。

    # 版本值必须从清单声明的文件读取。
    str_version = (path_skill_root / str(dict_manifest["version_source"])).read_text(encoding="utf-8").strip()  # 版本权威文本。

    # 当前审计值集合由外部权威源生成。
    set_values = authority_values(dict_manifest, dict_catalog, dict_cases, str_version)  # 动态审计值。

    # 保存产品文件中的动态值命中。
    list_findings: list[dict[str, str]] = []  # 字面量命中记录。

    # 逐文件读取 Python 和入口脚本。
    for path_product in product_paths(path_skill_root, dict_manifest):

        # 缺少产品文件时不能报告通过。
        if not path_product.is_file():

            # 包结构不完整时停止审计。
            raise AuditFailure(f"> ERR: [Python] installer product file is missing: {path_product}")

        # 源码和注释共同参与扫描。
        str_source = path_product.read_text(encoding="utf-8")  # 产品源码文本。

        # 先检查较长值，避免短片段遮蔽证据。
        for str_value in sorted(set_values, key=len, reverse=True):

            # 只记录完整字符串片段命中。
            if str_value in str_source:

                # 结果使用技能相对路径，不泄漏绝对路径。
                str_relative_file = path_product.relative_to(path_skill_root).as_posix()  # 命中文件相对路径。

                # 将动态值命中保存为可审计记录。
                list_findings.append({"file": str_relative_file, "value": str_value})

    # 返回静态审计结论。
    list_product_paths = product_paths(path_skill_root, dict_manifest)  # 产品扫描路径。

    # 将产品路径转换为报告相对路径。
    list_scanned_files = [path.relative_to(path_skill_root).as_posix() for path in list_product_paths]  # 扫描文件列表。

    # 交付静态审计结论。
    return {
        "status": "PASS" if not list_findings else "FAIL",
        "finding_count": len(list_findings),
        "findings": list_findings,
        "scanned_files": list_scanned_files,
    }

# write_report 原子写入机器报告。
def write_report(path_report: Path, dict_report: dict[str, Any]) -> None:
    """写入 JSON 报告。

    参数：
        path_report: 报告目标。
        dict_report: 报告对象。
    返回：
        无。
    """

    # 报告目录由调用者显式指定。
    path_report.parent.mkdir(parents=True, exist_ok=True)

    # 临时文件避免中断留下半份报告。
    path_temporary = path_report.with_name(path_report.name + ".tmp")  # 临时报告路径。

    # 结构化内容只写入调用者指定文件。
    path_temporary.write_text(json.dumps(dict_report, ensure_ascii=False, sort_keys=True, indent=2), encoding="utf-8")

    # 原子替换正式报告。
    path_temporary.replace(path_report)

# expand_cases 把目录选择器展开为运行时 case。
def expand_cases(dict_cases: dict[str, Any], list_platform_ids: list[str]) -> list[dict[str, Any]]:
    """按 case 选择器展开平台运行记录。

    参数：
        dict_cases: case 权威对象。
        list_platform_ids: 当前平台 ID 序列。
    返回：
        可执行 case 列表。
    异常：
        AuditFailure: case 选择器或 token 无效。
    """

    # 保存动态展开的 case 记录。
    list_records: list[dict[str, Any]] = []  # 动态 case 列表。

    # 逐条解析 case 选择器。
    for dict_case in dict_cases.get("cases", []):

        # 非对象 case 不能表达选择器。
        if not isinstance(dict_case, dict):

            # 保留失败边界而不猜测字段。
            raise AuditFailure("> ERR: [Python] installer case is not an object")

        # 读取当前 case 的选择策略。
        str_selector = str(dict_case.get("selector", ""))  # 当前 case 的目录展开策略。

        # 目录选择器为每个平台生成一条记录。
        if str_selector == "each_catalog_platform":

            # 复制 case 并写入目录平台 ID。
            for str_platform_id in list_platform_ids:

                # 当前平台值来自投影目录。
                dict_record = dict(dict_case)  # case 展开副本。

                # 将目录平台绑定到当前记录。
                dict_record["platform_id"] = str_platform_id  # 当前记录的平台身份。

                # 追加可执行 case。
                list_records.append(dict_record)

        # 未知平台选择器只读取 case token。
        elif str_selector == "unknown_platform_token":

            # 未知 token 不能为空。
            if not str(dict_case.get("token", "")).strip():

                # 缺失 token 无法验证未知分支。
                raise AuditFailure("> ERR: [Python] unknown platform case token is empty")

            # 保存未知值 case。
            list_records.append(dict(dict_case))

        # 新选择器必须先进入 Schema 和实现合同。
        else:

            # 不允许隐式解释未声明选择器。
            raise AuditFailure(f"> ERR: [Python] unsupported installer case selector: {str_selector}")

    # 返回动态展开结果。
    return list_records

# build_case_result 收束单条 smoke 的机器结果。
def build_case_result(dict_case: dict[str, Any], dict_case_values: dict[str, Any]) -> dict[str, Any]:
    """创建一条可比较的 smoke 结果。

    参数：
        dict_case: 权威 case 记录。
        dict_case_values: 当前 case 的状态、退出码和保护检查字段。
    返回：
        单条 smoke 结果对象。
    """

    # 读取 case 的动态比较字段。
    str_platform = str(dict_case_values.get("platform", ""))  # 当前平台值。

    # 读取 case 的期望状态。
    str_expected = str(dict_case_values.get("expected_status", ""))  # 预期状态。

    # 读取后端观察状态。
    str_observed = str(dict_case_values.get("observed_status", ""))  # 实际状态。

    # 读取后端退出码。
    int_exit_code = int(dict_case_values.get("exit_code", -1))  # 实际退出码。

    # 读取 case 声明的退出码。
    object_expected_exit_code = dict_case_values.get("expected_exit_code")  # 预期退出码。

    # 读取保护文件校验结果。
    bool_preserved = bool(dict_case_values.get("preserved", False))  # 保护文件结果。

    # 退出码字段缺失时保持失败而不猜测默认值。
    bool_exit_code = isinstance(object_expected_exit_code, int) and int_exit_code == object_expected_exit_code  # 退出码比较结果。

    # 先创建结果对象，再分组写入字段。
    dict_result: dict[str, Any] = {}  # 单条 case 结果。

    # 绑定权威 case 身份，便于报告回溯。
    dict_result["case_id"] = str(dict_case.get("id", ""))  # 报告回溯使用的权威 case 身份。

    # 记录本次 CLI 选择的平台。
    dict_result["platform_id"] = str_platform  # 动态平台身份。

    # 记录 case 权威的目标状态。
    dict_result["expected_status"] = str_expected  # 目标状态文本。

    # 记录后端实际观察状态。
    dict_result["observed_status"] = str_observed  # 观察状态文本。

    # 记录子进程真实退出码。
    dict_result["exit_code"] = int_exit_code  # 真实退出码。

    # 记录 case 声明的退出码。
    dict_result["expected_exit_code"] = object_expected_exit_code  # 权威退出码。

    # 记录用户文件保护检查。
    dict_result["preserved_check"] = bool_preserved  # 保护结果。

    # 只有状态、退出码和保护内容都匹配时 case 才通过。
    dict_result["ok"] = str_expected == str_observed and bool_exit_code and bool_preserved  # 状态、退出码和保护内容的合取结果。

    # 返回可比较的机器结果。
    return dict_result

# create_smoke_source 复制技能并生成隔离发布收据。
def create_smoke_source(path_skill_root: Path, path_temp_root: Path, dict_bundle: dict[str, Any]) -> Path:
    """创建带有效收据的隔离发布源。

    参数：
        path_skill_root: 当前技能根。
        path_temp_root: smoke 临时根。
        dict_bundle: 已校验包上下文。
    返回：
        隔离发布源路径。
    异常：
        AuditFailure: 发布边界配置为空。
    """

    # 读取验证目录名称和收据名称。
    dict_manifest = dict_bundle["manifest"]  # 当前安装清单。

    # 读取 smoke 路径配置。
    dict_verification = dict_manifest.get("verification", {})  # smoke 路径配置。

    # 读取隔离源目录名称。
    str_source_name = str(dict_verification.get("source_directory_name", "")).strip()  # 隔离源目录名。

    # 读取清单声明的发布收据名称。
    str_receipt_name = str(dict_manifest.get("release_receipt_filename", "")).strip()  # 发布收据文件名。

    # 空配置不能形成受控临时源。
    if not str_source_name or not str_receipt_name:

        # 拒绝回退到代码默认路径。
        raise AuditFailure("> ERR: [Python] installer verification source naming is incomplete")

    # 读取清单声明的禁止载荷名称。
    list_forbidden_names = dict_manifest.get("source_policy", {}).get("forbidden_names", [])  # 禁止名称列表。

    # 将禁止名称规范化为集合。
    set_forbidden_names = {str(value) for value in list_forbidden_names if str(value).strip()}  # 禁止名称集合。

    # 隔离源位于 smoke 临时根内。
    path_source = path_temp_root / str_source_name  # 隔离发布源路径。

    # 复制发布源时排除清单声明的非载荷目录。
    def ignore_forbidden(path_current: str, list_names: list[str]) -> list[str]:
        """过滤清单禁止的发布源成员。

        参数：
            path_current: 当前复制目录。
            list_names: 当前目录成员名称。
        返回：
            应忽略的成员名称。
        """

        # 仅按清单成员名过滤，不引入运行环境常量。
        return [str_name for str_name in list_names if str_name in set_forbidden_names]

    # 将受管源码复制到临时发布根。
    shutil.copytree(path_skill_root, path_source, ignore=ignore_forbidden)

    # 收集隔离源的普通文件摘要。
    list_receipt_files: list[dict[str, Any]] = []  # 隔离发布文件条目。

    # 逐项生成发布收据的文件摘要。
    for path_file in sorted(path_source.rglob("*")):

        # 收据只覆盖普通文件，链接和目录由安装器另行拒绝。
        if not path_file.is_file() or path_file.name == str_receipt_name:

            # 目录、链接和收据自身不进入文件清单。
            continue

        # 追加当前载荷的路径、大小和摘要。
        str_relative = path_file.relative_to(path_source).as_posix()  # 载荷相对路径。

        # 读取当前文件大小。
        int_file_size = path_file.stat().st_size  # 载荷字节数。

        # 计算当前文件摘要。
        str_file_hash = sha256_file(path_file)  # 用于收据完整性比对的 SHA-256。

        # 追加当前载荷条目。
        list_receipt_files.append({"path": str_relative, "size": int_file_size, "sha256": str_file_hash})

    # 写入与当前包身份匹配的隔离发布收据。
    path_receipt = path_source / str_receipt_name  # 隔离发布收据路径。

    # 创建收据的技能身份字段。
    dict_receipt = {"skill_name": dict_bundle["skill_id"]}  # 收据技能身份。

    # 写入当前包版本身份。
    dict_receipt["version"] = dict_bundle["version"]  # 收据版本身份。

    # 写入逐文件完整性清单。
    dict_receipt["files"] = list_receipt_files  # 收据文件条目。

    # 先写完整收据文本，再交给 CLI 校验。
    str_receipt_text = json.dumps(dict_receipt, ensure_ascii=False, sort_keys=True, indent=2)  # 收据 JSON 文本。

    # 将完整收据文本落到隔离源。
    path_receipt.write_text(str_receipt_text, encoding="utf-8")

    # 返回已经带有收据的隔离源。
    return path_source

# apply_source_mutations 注入 case 声明的源故障。
def apply_source_mutations(path_source: Path, object_mutations: Any) -> None:
    """按 case 数据修改隔离源以验证故障门禁。

    参数：
        path_source: 已带发布收据的隔离源。
        object_mutations: case 声明的相对路径和文本数组。
    返回：
        无；只修改当前 smoke 临时源。
    异常：
        AuditFailure: 故障路径越界或记录格式不正确。
    """

    # 没有故障注入时保持发布源原样。
    if object_mutations is None:

        # 空 mutation 不产生副作用。
        return

    # 故障注入必须是数组，避免隐式解释字符串。
    if not isinstance(object_mutations, list):

        # 配置结构错误阻止 smoke 继续。
        raise AuditFailure("> ERR: [Python] installer source mutations must be an array")

    # 逐项应用 case 声明的源变化。
    for object_mutation in object_mutations:

        # 每条 mutation 必须是对象。
        if not isinstance(object_mutation, dict):

            # 非对象无法表达相对路径和内容。
            raise AuditFailure("> ERR: [Python] installer source mutation is not an object")

        # 读取 mutation 相对路径和内容。
        str_relative = str(object_mutation.get("path", "")).strip()  # 故障文件相对路径。

        # 读取 mutation 要写入的故障文本。
        str_content = str(object_mutation.get("content", ""))  # 故障文件文本。

        # 空路径不能形成可验证的故障。
        if not str_relative:

            # 让 Schema 或 case 修复缺失字段。
            raise AuditFailure("> ERR: [Python] installer source mutation path is empty")

        # 将 mutation 绑定到隔离源 containment。
        path_mutation = (path_source / str_relative).resolve()  # 故障文件目标。

        # 故障路径越界时停止，不触碰临时根外部文件。
        if not path_mutation.is_relative_to(path_source.resolve()):

            # 路径故障本身不能逃逸验证边界。
            raise AuditFailure("> ERR: [Python] installer source mutation escapes source")

        # 故障目标必须已经存在于收据覆盖范围。
        if not path_mutation.is_file():

            # 不允许 mutation 凭空添加未声明文件。
            raise AuditFailure("> ERR: [Python] installer source mutation target is missing")

        # 写入 case 声明的故障内容，使原收据失配。
        path_mutation.write_text(str_content, encoding="utf-8")

# apply_precondition_files 创建 case 声明的目标初态。
def apply_precondition_files(path_target: Path, object_preconditions: Any) -> list[dict[str, Any]]:
    """创建并返回 case 前置文件记录。

    参数：
        path_target: 当前 case 目标目录。
        object_preconditions: case 声明的前置文件数组。
    返回：
        通过路径检查的前置文件记录。
    异常：
        AuditFailure: 前置记录或路径越界。
    """

    # 缺少前置数组时使用空记录。
    if object_preconditions is None:

        # 统一后置检查的输入形状。
        return []

    # 前置数据必须是数组，避免隐式遍历字符串。
    if not isinstance(object_preconditions, list):

        # 前置数据类型错误阻止 smoke 继续。
        raise AuditFailure("> ERR: [Python] installer case preconditions must be an array")

    # 保存通过检查的前置记录。
    list_preconditions: list[dict[str, Any]] = []  # 当前 case 前置文件。

    # 逐项创建 case 要求的目标初态。
    for object_precondition in object_preconditions:

        # 前置文件记录必须是对象。
        if not isinstance(object_precondition, dict):

            # 非对象不能表达路径和文本。
            raise AuditFailure("> ERR: [Python] installer case precondition is not an object")

        # 读取前置文件相对路径和文本。
        str_relative = str(object_precondition.get("path", "")).strip()  # 前置文件相对路径。

        # 读取 case 声明的原始文本内容。
        str_content = str(object_precondition.get("content", ""))  # 前置文件文本内容。

        # 空路径不形成前置文件副作用。
        if not str_relative:

            # 忽略空记录但不猜测路径。
            continue

        # 解析并固定当前前置文件的目标路径。
        path_precondition = (path_target / str_relative).resolve()  # 前置文件目标。

        # 前置文件必须保持在当前目标根内。
        if not path_precondition.is_relative_to(path_target.resolve()):

            # 越界 case 直接阻止 smoke。
            raise AuditFailure("> ERR: [Python] installer case precondition escapes target")

        # 创建前置文件父目录。
        path_precondition.parent.mkdir(parents=True, exist_ok=True)

        # 写入 case 声明的前置文本。
        path_precondition.write_text(str_content, encoding="utf-8")

        # 保存后置检查需要的相对文件。
        list_preconditions.append({"path": str_relative, "content": str_content})

    # 返回规范化前置记录。
    return list_preconditions

# build_smoke_command 由 case 数据组装公开 CLI 参数。
def build_smoke_command(dict_command_context: dict[str, Any]) -> list[str]:
    """构造单条 smoke 的 CLI 命令。

    参数：
        dict_command_context: 后端、源、目标和 case 参数。
    返回：
        可直接传给 subprocess 的参数列表。
    """

    # 从上下文读取已校验包。
    dict_bundle = dict_command_context["bundle"]  # 包投影和清单。

    # 读取包根路径。
    path_skill_root = dict_command_context["skill_root"]  # 模块导入根。

    # 读取启动投影路径。
    path_manifest_env = dict_command_context["manifest_env"]  # 投影摘要路径。

    # 读取隔离发布源路径。
    path_source = dict_command_context["source"]  # 发布载荷根。

    # 读取本次平台参数。
    str_platform = str(dict_command_context["platform"])  # 用于目标选择的目录平台标识。

    # 读取单事务目标路径。
    path_target = dict_command_context["target"]  # 安装目标路径。

    # 读取 case 命令覆盖字段。
    dict_case = dict_command_context["case"]  # CLI 参数记录。

    # 从清单读取唯一后端模块入口。
    str_backend_module = str(dict_bundle["manifest"]["backend_module"])  # 后端模块名。

    # 先绑定解释器和模块执行前缀。
    list_command = [sys.executable, "-m", str_backend_module]  # Python 模块命令。

    # 绑定包根和启动投影。
    list_command.extend(["--bundle-root", str(path_skill_root), "--manifest-env", str(path_manifest_env)])  # 包根和投影参数。

    # 绑定隔离源和当前平台。
    list_command.extend(["--source", str(path_source), "--platform", str_platform])  # 源和平台参数。

    # 绑定单事务目标并启用机器输出。
    list_command.extend(["--target-dir", str(path_target), "--json"])  # 目标和输出参数。

    # 追加 case 自己声明的只读、覆盖和确认参数。
    list_command.extend(str(value) for value in dict_case.get("cli_flags", []))

    # 返回数据驱动的公开 CLI 参数。
    return list_command

# check_precondition_files 校验 case 保护文件是否保持原文。
def check_precondition_files(path_target: Path, list_preconditions: list[dict[str, Any]]) -> bool:
    """检查所有保护文件。

    参数：
        path_target: 当前 case 目标目录。
        list_preconditions: 已通过路径检查的文件记录。
    返回：
        全部存在且内容一致时为 True。
    """

    # 保护文件校验从成功开始。
    bool_preserved = True  # 保护文件校验初值。

    # 逐项检查 case 声明的保护文件是否保持原文。
    for dict_precondition in list_preconditions:

        # 读取保护文件相对路径和预期文本。
        str_relative = str(dict_precondition.get("path", "")).strip()  # 保护文件相对路径。

        # 读取保护文件的预期文本。
        str_content = str(dict_precondition.get("content", ""))  # 保护文件预期文本。

        # 生成保护文件的实际观察路径。
        path_observed = path_target / str_relative  # 保护文件观察路径。

        # 缺少保护文件时立即保留失败结果。
        bool_preserved = bool_preserved and path_observed.is_file()  # 文件存在性结果。

        # 存在时继续比较其内容摘要。
        if path_observed.is_file():

            # 保护内容必须与 case 原文一致。
            bool_preserved = bool_preserved and path_observed.read_text(encoding="utf-8") == str_content  # 内容比较结果。

    # 返回保护文件一致性结论。
    return bool_preserved

# execute_smoke_case 执行一条隔离 case 并收集结果。
def execute_smoke_case(tuple_case_context: tuple[Any, ...]) -> dict[str, Any]:
    """执行并比较一条 case。

    参数：
        tuple_case_context: 包、路径和 case 参数元组。
    返回：
        单条 case 的比较结果。
    异常：
        AuditFailure: case 前置数据或路径不合法。
    """

    # 将元组字段还原为单条 case 的执行上下文。
    dict_bundle, path_skill_root, path_manifest_env, path_source, path_temp_root, dict_case = tuple_case_context  # case 执行上下文。

    # 当前 case 的平台值来自目录或未知 token。
    str_platform = str(dict_case.get("platform_id", dict_case.get("token", "")))  # 本次 CLI 的平台参数。

    # 在写入事务前应用 case 声明的源故障注入。
    apply_source_mutations(path_source, dict_case.get("source_mutations"))

    # 目标目录名称由清单验证配置提供。
    str_target_name = str(dict_bundle["manifest"].get("verification", {}).get("target_directory_name", "")).strip()  # 目标集合目录名。

    # 缺少目标集合名称时拒绝路径回退。
    if not str_target_name:

        # 不把当前测试目录名写入验证器。
        raise AuditFailure("> ERR: [Python] installer verification target naming is incomplete")

    # 目标模式由 case 数据决定，默认使用隔离目标集合。
    str_target_mode = str(dict_case.get("target_mode", "isolated_target")).strip()  # 目标模式。

    # 源目标重叠 case 直接把源根交给后端，验证 containment 失败。
    if str_target_mode == "source_root":

        # 该路径只指向当前临时源，不会触碰真实工作区。
        path_target = path_source  # 源目标重叠路径。

    # 其它 case 使用临时根内的独立目标。
    else:

        # 当前目标路径只在 smoke 临时根中生成。
        path_target = path_temp_root / str_target_name / str_platform  # 当前目标路径。

    # 为当前 case 准备目标父目录。
    path_target.parent.mkdir(parents=True, exist_ok=True)

    # 创建并规范化 case 前置文件。
    list_preconditions = apply_precondition_files(path_target, dict_case.get("precondition_files"))  # 前置文件记录。

    # 公开后端参数保持数据驱动。
    dict_command_context = {"bundle": dict_bundle, "skill_root": path_skill_root}  # CLI 包上下文。

    # 继续绑定启动投影参数。
    dict_command_context["manifest_env"] = path_manifest_env  # 启动摘要位置。

    # 绑定隔离发布源参数。
    dict_command_context["source"] = path_source  # 发布载荷位置。

    # 绑定当前平台选择参数。
    dict_command_context["platform"] = str_platform  # 目录平台标识。

    # 绑定单事务目标参数。
    dict_command_context["target"] = path_target  # 安装目标位置。

    # 把本次 case 的 flags 交给后端构造器。
    dict_command_context["case"] = dict_case  # case 覆盖记录。

    # 由 case 上下文组装公开命令。
    list_command = build_smoke_command(dict_command_context)  # 公开 CLI 参数列表。

    # 执行同一公开 CLI，捕获机器输出和退出码。
    completed_process = subprocess.run(list_command, cwd=path_skill_root, capture_output=True, text=True, check=False)  # 子进程结果。

    # 最后一行 JSON 是公开 CLI 的状态摘要。
    list_output = [line for line in completed_process.stdout.splitlines() if line.strip()]  # 后端输出行。

    # 解析状态摘要对象。
    dict_output = json.loads(list_output[-1]) if list_output else {}  # 机器状态对象。

    # 读取 case 权威目标状态。
    str_expected = str(dict_case.get("expected_status", ""))  # 权威目标状态。

    # 读取后端实际状态文本。
    str_observed = str(dict_output.get("status", ""))  # 后端观察状态。

    # 比较保护文件的最终内容。
    bool_preserved = check_precondition_files(path_target, list_preconditions)  # 保护文件检查。

    # 汇集单条 case 的比较输入。
    dict_case_values = {"platform": str_platform, "expected_status": str_expected}  # case 比较字段。

    # 把后端状态放入比较载荷。
    dict_case_values["observed_status"] = str_observed  # 观察状态字段。

    # 把真实返回码放入比较载荷。
    dict_case_values["exit_code"] = completed_process.returncode  # 进程返回码字段。

    # 把权威返回码约束放入比较载荷。
    dict_case_values["expected_exit_code"] = dict_case.get("expected_exit_code")  # case 返回码字段。

    # 填充用户文件保护结论。
    dict_case_values["preserved"] = bool_preserved  # 保护内容结果。

    # 生成单条 case 的比较结果。
    return build_case_result(dict_case, dict_case_values)

# run_smoke 使用公开 CLI 在临时根执行 case。
def run_smoke(namespace_args: argparse.Namespace) -> dict[str, Any]:
    """执行隔离安装器 smoke。

    参数：
        namespace_args: smoke 命令参数。
    返回：
        每条 case 的观察状态。
    异常：
        AuditFailure: case 或隔离路径不合法。
    """

    # 解析调用者给出的技能包根。
    path_skill_root = Path(namespace_args.skill_root).expanduser().resolve()  # smoke 包根读取路径。

    # 锁定入口发现的启动摘要。
    path_manifest_env = Path(namespace_args.manifest_env).expanduser().resolve()  # 启动投影路径。

    # 通过同一校验链确认包身份。
    dict_bundle = load_bundle(path_skill_root, path_manifest_env)  # 已校验包上下文。

    # 加载外部 case 数据，不在验证器内复制测试值。
    dict_cases = read_json(Path(namespace_args.cases).expanduser().resolve())  # 当前 smoke case 对象。

    # 从运行时平台投影取得候选目录。
    list_records = load_platform_records(dict_bundle["projection"])  # 当前平台目录记录。

    # 仅提取目录提供的平台规范 ID。
    list_platform_ids = [record.platform_id for record in list_records]  # 当前平台 ID 序列。

    # 使用 case 选择器生成实际运行记录。
    list_cases = expand_cases(dict_cases, list_platform_ids)  # 动态 smoke case 序列。

    # 使用系统默认临时根，避免固定开发机路径。
    with tempfile.TemporaryDirectory() as str_temp_root:

        # 当前 smoke 临时根只由运行时提供。
        path_temp_root = Path(str_temp_root)  # 隔离根路径。

        # 复制技能并生成与当前身份一致的发布收据。
        path_source = create_smoke_source(path_skill_root, path_temp_root, dict_bundle)  # 隔离发布源。

        # 按 case 顺序保存机器结果。
        list_results: list[dict[str, Any]] = []  # smoke 结果集合。

        # 每条 case 使用独立目标并调用同一后端。
        for dict_case in list_cases:

            # 组装当前 case 的隔离执行上下文列表。
            list_case_context_values = [dict_bundle, path_skill_root, path_manifest_env]  # 包和投影上下文。

            # 追加源、临时根和 case 记录。
            list_case_context_values.extend([path_source, path_temp_root, dict_case])  # 运行边界上下文。

            # 将列表冻结为后端读取的元组。
            tuple_case_context = tuple(list_case_context_values)  # case 执行上下文元组。

            # 将上下文送入隔离后端并取得比较结果。
            dict_case_result = execute_smoke_case(tuple_case_context)  # 当前 case 结果。

            # 将完成比较的结果追加到 smoke 汇总。
            list_results.append(dict_case_result)

        # 汇总所有 case 的通过状态。
        bool_all_passed = all(item["ok"] for item in list_results)  # 全部 case 通过结果。

        # 返回完整 smoke 摘要。
        return {
            "status": "PASS" if bool_all_passed else "FAIL",
            "case_count": len(list_results),
            "results": list_results,
        }

# main 负责报告写入和短状态输出。
def main(list_arguments: list[str] | None = None) -> int:
    """执行 audit 或 smoke。

    参数：
        list_arguments: 可选显式参数列表。
    返回：
        成功为 0，失败为非零。
    """

    # 解析当前验证命令。
    namespace_args = parse_args(list_arguments)  # 验证命令参数。

    # 选择目录驱动审计或隔离 smoke。
    try:

        # 完整结果稍后写入报告文件。
        dict_report = run_audit(namespace_args) if namespace_args.command == "audit" else run_smoke(namespace_args)  # 验证结果。

    # 错误同样落盘并保持非零状态。
    except (AuditFailure, OSError, ValueError, KeyError, json.JSONDecodeError) as object_error:

        # 失败报告保留稳定错误前缀。
        dict_report = {"status": "FAIL", "message": f"> ERR: [Python] {object_error}"}  # 失败报告对象。

    # 报告路径由调用者指定。
    write_report(Path(namespace_args.report).expanduser().resolve(), dict_report)

    # 把报告状态提取为短文本。
    str_report_status = str(dict_report.get("status", "FAIL"))  # 报告状态摘要。

    # 通过固定分支输出可静态识别的成功状态。
    if str_report_status == "PASS":

        # 成功摘要不泄漏完整报告内容。
        print("> INFO: [Python] installer verification status: PASS")

    # 失败状态使用错误前缀，便于调用方识别阻断。
    else:

        # 失败摘要仍只输出短状态。
        print("> ERR: [Python] installer verification status: FAIL")

    # 报告状态决定进程结果。
    return 0 if dict_report.get("status") == "PASS" else 1

# 直接执行模块时透传验证结果。
if __name__ == "__main__":

    # SystemExit 透传验证结果。
    raise SystemExit(main())
