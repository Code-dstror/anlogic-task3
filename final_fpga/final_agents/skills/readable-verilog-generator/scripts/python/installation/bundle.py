"""读取并校验安装器的包内配置投影。"""

# 注解延迟求值保持 Python 运行时兼容性。
from __future__ import annotations

# 摘要计算需要标准库哈希实现。
import hashlib

# JSON 文件是安装器配置的机器权威格式。
import json

# 环境快照用于启动器和平台目录解析。
import os

# pathlib 统一表达包内资源 containment 边界。
from pathlib import Path

# 正则只解析声明字段，不执行 TOML 内容。
import re

# Any 描述目录驱动的 JSON 映射。
from typing import Any

# BundleError 把包内投影错误归并为单一失败类型。
class BundleError(ValueError):
    """表示安装包配置、路径或哈希合同不完整。"""

# canonical_json_bytes 为投影和收据提供稳定字节身份。
def canonical_json_bytes(dict_value: dict[str, Any]) -> bytes:
    """把配置映射编码为稳定 JSON 字节。

    参数：
        dict_value: 待编码的 JSON 对象。
    返回：
        排序后的 UTF-8 JSON 字节。
    异常：
        TypeError: 对象包含不可编码值。
    """

    # 排序键和紧凑分隔符保证相同配置产生相同摘要。
    bytes_payload = json.dumps(  # 配置摘要使用的规范化 JSON 字节。
        dict_value,  # 待编码配置对象。
        ensure_ascii=False,  # 保留中文配置文本。
        sort_keys=True,  # 稳定字段顺序。
        separators=(",", ":"),  # 稳定 JSON 分隔符。
    ).encode("utf-8")

    # 返回给投影构建器和运行时校验器复用。
    return bytes_payload

# sha256_bytes 计算内存投影的内容摘要。
def sha256_bytes(bytes_payload: bytes) -> str:
    """计算内存字节的 SHA-256 摘要。

    参数：
        bytes_payload: 待摘要的字节串。
    返回：
        小写十六进制摘要。
    """

    # 使用标准库摘要实现，避免运行时引入第三方依赖。
    str_digest = hashlib.sha256(bytes_payload).hexdigest()  # 配置或文件的摘要。

    # 返回用于投影绑定的摘要文本。
    return str_digest

# sha256_file 计算文件载荷的内容摘要。
def sha256_file(path_file: Path) -> str:
    """分块计算文件摘要。

    参数：
        path_file: 待读取的普通文件。
    返回：
        小写十六进制摘要。
    异常：
        OSError: 文件不可读。
    """

    # 使用固定的小型读取块，避免把载荷一次性放入内存。
    obj_digest = hashlib.sha256()  # 当前文件的增量摘要器。

    # 以二进制模式读取，摘要不受文本换行转换影响。
    with path_file.open("rb") as file_input:

        # 持续读取直到文件结束。
        while True:

            # 读取下一块文件内容。
            bytes_chunk = file_input.read(1024 * 1024)  # 当前摘要块。

            # 空块表示文件已经读完。
            if not bytes_chunk:

                # 跳出读取循环，保留完整摘要。
                break

            # 将当前块并入文件摘要。
            obj_digest.update(bytes_chunk)

    # 返回最终的十六进制摘要。
    return obj_digest.hexdigest()

# read_json 读取单个受管 JSON 配置对象。
def read_json(path_json: Path) -> dict[str, Any]:
    """读取一个顶层为对象的 UTF-8 JSON 文件。

    参数：
        path_json: JSON 配置路径。
    返回：
        JSON 对象。
    异常：
        BundleError: 文件缺失、JSON 非对象或内容非法。
    """

    # 配置必须以 UTF-8 读取，避免运行环境编码改变语义。
    try:

        # 读取配置文本并解析 JSON。
        object_value = json.loads(path_json.read_text(encoding="utf-8"))  # 当前配置对象。

    # 将底层读取和 JSON 错误统一成配置合同错误。
    except (OSError, json.JSONDecodeError) as object_error:

        # 保留原始错误作为诊断上下文，但不泄漏回溯。
        raise BundleError(f"> ERR: [Python] cannot read JSON configuration: {object_error}") from object_error

    # 顶层必须是对象，列表或标量无法表达配置合同。
    if not isinstance(object_value, dict):

        # 立即阻止后续字段访问产生误导性错误。
        raise BundleError("> ERR: [Python] JSON configuration must be an object")

    # 返回通过基本结构检查的对象。
    return object_value

# parse_manifest_env 把启动器投影解析为不可执行的字段映射。
def parse_manifest_env(path_env: Path) -> dict[str, str]:
    """解析键值形式的启动投影。

    参数：
        path_env: 启动投影文件。
    返回：
        去除空白后的键值映射。
    异常：
        BundleError: 文件不存在、键重复或行格式非法。
    """

    # 空映射用于检测重复键和必需字段缺失。
    dict_values: dict[str, str] = {}  # 启动投影字段。

    # 逐行读取，避免把外部 shell 语法当作 Python 代码执行。
    try:

        # 启动投影只允许普通 UTF-8 文本。
        list_lines = path_env.read_text(encoding="utf-8").splitlines()  # 启动投影行。

    # 底层读取错误转换为安装包配置错误。
    except OSError as object_error:

        # 让调用方在解释器启动前停止。
        raise BundleError(
            f"> ERR: [Python] cannot read installer bootstrap projection: {object_error}"
        ) from object_error

    # 逐行检查键和值的边界。
    for str_line in list_lines:

        # 空行只用于投影可读性，不产生配置字段。
        if not str_line.strip():

            # 继续处理下一行。
            continue

        # 只在第一个等号处分割，保留值中的其他等号。
        list_parts = str_line.split("=", 1)  # 当前投影键值对。

        # 每行必须恰好包含非空键和值分隔。
        if len(list_parts) != 2 or not list_parts[0].strip():

            # 禁止模糊解析导致后端路径被错误解释。
            raise BundleError("> ERR: [Python] bootstrap projection contains an invalid line")

        # 键文本决定后续配置字段的唯一索引。
        str_key = list_parts[0].strip()  # 当前投影字段名。

        # 值文本保留路径和摘要的真实内容。
        str_value = list_parts[1].strip()  # 当前投影字段值。

        # 重复键会使不同启动器得到不同事实，因此必须失败。
        if str_key in dict_values:

            # 不接受后出现的值覆盖先出现的值。
            raise BundleError(f"> ERR: [Python] bootstrap projection repeats key: {str_key}")

        # 保存通过格式检查的字段。
        dict_values[str_key] = str_value  # 启动投影键对应的配置值。

    # 返回原始文本投影的确定性解析结果。
    return dict_values

# resolve_contained_path 限制所有运行时资源留在包根内。
def resolve_contained_path(path_root: Path, str_relative_path: str) -> Path:
    """将包内相对路径解析为受 containment 约束的普通路径。

    参数：
        path_root: 唯一包根边界。
        str_relative_path: 配置投影声明的相对路径。
    返回：
        包根内的规范化路径。
    异常：
        BundleError: 路径为空、绝对或越过包根。
    """

    # 空路径和绝对路径都不能作为包内资源定位。
    if not str_relative_path or Path(str_relative_path).is_absolute():

        # 阻止外部文件重定向安装器启动。
        raise BundleError("> ERR: [Python] installer resource path must be relative")

    # 规范化路径后再执行 containment 检查。
    path_candidate = (path_root / str_relative_path).resolve()  # 包内资源候选路径。

    # pathlib 的 relative_to 失败表示路径已经越界。
    try:

        # 只验证边界，不要求资源此时已经存在。
        path_candidate.relative_to(path_root.resolve())

    # 将越界路径转换为稳定安装错误。
    except ValueError as object_error:

        # 保留路径合同失败而不触碰外部文件。
        raise BundleError("> ERR: [Python] installer resource path escapes bundle root") from object_error

    # 返回通过边界校验的路径。
    return path_candidate

# _read_project_field 从版本包元数据读取清单声明的身份字段。
def _read_project_field(path_project: Path, str_field: str) -> str:
    """读取简单 TOML 项目的单行字符串字段。

    参数：
        path_project: 项目元数据文件。
        str_field: 目录声明的字段名称。
    返回：
        字段值。
    异常：
        BundleError: 字段缺失或内容不是字符串。
    """

    # 项目元数据只需要读取名称字段，避免引入第三方 TOML 运行时。
    try:

        # 使用 UTF-8 保持包元数据可重复。
        str_text = path_project.read_text(encoding="utf-8")  # 项目元数据文本。

    # 元数据不可读时停止安装。
    except OSError as object_error:

        # 将文件错误映射到包身份校验。
        raise BundleError(f"> ERR: [Python] cannot read project metadata: {object_error}") from object_error

    # 允许键周围存在空格，但只接受双引号字符串。
    object_match = re.search(rf"(?m)^{re.escape(str_field)}\s*=\s*\"([^\"]+)\"", str_text)  # 项目字段匹配对象。

    # 缺失字段表示发布包身份无法证明。
    if object_match is None:

        # 不猜测技能名称或其他项目身份。
        raise BundleError(f"> ERR: [Python] project metadata field is missing: {str_field}")

    # 返回配置声明字段的字符串值。
    return object_match.group(1)

# load_bundle 绑定启动投影、配置摘要和技能身份。
def load_bundle(path_bundle: Path, path_env: Path) -> dict[str, Any]:
    """加载并校验安装器运行时所需的全部投影。

    参数：
        path_bundle: 版本化技能包根目录。
        path_env: 同包启动投影。
    返回：
        包含 manifest、catalog、projection、skill_id 和 version 的运行时映射。
    异常：
        BundleError: 任一资源缺失、越界、哈希失配或身份字段缺失。
    """

    # 包根必须是已经存在的目录。
    path_root = path_bundle.resolve()  # 规范化包根。

    # 目录边界必须真实存在后才能读取投影。
    if not path_root.is_dir():

        # 不允许把普通文件当作安装包根。
        raise BundleError("> ERR: [Python] installer bundle root is not a directory")

    # 启动投影也必须留在同一个包根内。
    path_bootstrap = path_env.resolve()  # 规范化启动投影。

    # 启动投影越界时禁止继续解析配置。
    try:

        # 验证启动投影的 containment。
        path_bootstrap.relative_to(path_root)

    # 越界启动投影阻止所有后续读取。
    except ValueError as object_error:

        # 统一报告启动资源越界。
        raise BundleError("> ERR: [Python] bootstrap projection is outside bundle root") from object_error

    # 解析投影字段，避免执行任何 shell 语法。
    dict_env = parse_manifest_env(path_bootstrap)  # 已解析启动字段。

    # 运行时所需字段集中声明，缺一即停。
    list_required_keys = [  # 启动投影必需字段集合。
        "MANIFEST_RELATIVE_PATH",  # 安装清单相对路径键。
        "CATALOG_RELATIVE_PATH",  # 平台目录相对路径键。
        "PROJECTION_RELATIVE_PATH",  # 合并投影相对路径键。
        "MANIFEST_SHA256",  # 安装清单摘要键。
        "CATALOG_SHA256",  # 平台目录摘要键。
        "PROJECTION_SHA256",  # 合并投影摘要键。
    ]

    # 逐项确认启动投影没有隐藏默认值。
    for str_key in list_required_keys:

        # 缺字段时无法证明配置来源。
        if not dict_env.get(str_key):

            # 在后端入口启动前阻止安装。
            raise BundleError(f"> ERR: [Python] bootstrap projection is missing key: {str_key}")

    # 安装清单路径由启动投影声明并限制在包根。
    path_manifest = resolve_contained_path(path_root, dict_env["MANIFEST_RELATIVE_PATH"])  # 安装清单路径。

    # 平台目录路径提供 Harness 解析事实。
    path_catalog = resolve_contained_path(path_root, dict_env["CATALOG_RELATIVE_PATH"])  # 平台目录路径。

    # 平台投影路径绑定合并后的运行时事实。
    path_projection = resolve_contained_path(path_root, dict_env["PROJECTION_RELATIVE_PATH"])  # 平台投影路径。

    # 三个资源必须是普通文件，不能跟随目录或链接。
    for path_resource in (path_manifest, path_catalog, path_projection):

        # 统一拒绝缺失或符号链接资源。
        if not path_resource.is_file() or path_resource.is_symlink():

            # 包内投影不完整时不进入事务。
            raise BundleError("> ERR: [Python] installer projection resource is missing or linked")

    # 校验 manifest、catalog 和 projection 的字节摘要。
    dict_expected_hashes = {  # 投影声明的资源摘要。
        path_manifest: dict_env["MANIFEST_SHA256"],  # 清单文件摘要。
        path_catalog: dict_env["CATALOG_SHA256"],  # 目录文件摘要。
        path_projection: dict_env["PROJECTION_SHA256"],  # 投影文件摘要。
    }

    # 逐项比较包内资源的真实摘要。
    for path_resource, str_expected_hash in dict_expected_hashes.items():

        # 计算当前包内资源的真实摘要。
        str_actual_hash = sha256_file(path_resource)  # 当前资源摘要。

        # 摘要失配表示启动投影已过期或被替换。
        if str_actual_hash != str_expected_hash:

            # 失配时不尝试重新生成运行时配置。
            raise BundleError("> ERR: [Python] installer projection hash mismatch")

    # 读取安装事务的命名和状态清单。
    dict_manifest = read_json(path_manifest)  # 安装事务清单。

    # 读取平台根和检测规则权威目录。
    dict_catalog = read_json(path_catalog)  # 平台权威目录。

    # 读取启动时使用的合并运行时投影。
    dict_projection = read_json(path_projection)  # 合并运行时投影。

    # 投影必须拥有平台数组，避免运行时回退到代码常量。
    list_platforms = dict_projection.get("platforms")  # 运行时平台记录。

    # 空平台数组不能生成唯一安装目标。
    if not isinstance(list_platforms, list) or not list_platforms:

        # 空目录无法支持平台选择或检测。
        raise BundleError("> ERR: [Python] installer platform projection is empty")

    # 版本文件路径由 manifest 身份合同声明。
    path_version = resolve_contained_path(path_root, str(dict_manifest.get("version_source", "")))  # 版本来源路径。

    # 技能身份描述决定项目元数据字段。
    str_skill_source = str(dict_manifest.get("skill_id_source", ""))  # 技能身份来源描述。

    # 版本文件和身份描述必须同时存在。
    if not path_version.is_file() or ":" not in str_skill_source:

        # 身份来源不完整时拒绝生成目标目录。
        raise BundleError("> ERR: [Python] installer identity source is incomplete")

    # 版本文本不接受隐式清理之外的变换。
    str_version = path_version.read_text(encoding="utf-8").strip()  # 发布版本文本。

    # 版本必须非空，具体值只来自版本权威文件。
    if not str_version:

        # 空版本会使收据无法绑定发布身份。
        raise BundleError("> ERR: [Python] installer version source is empty")

    # 将身份描述拆为元数据路径和字段。
    list_source_parts = str_skill_source.split(":", 1)  # 技能身份来源组成。

    # 解析包内项目元数据文件位置。
    path_skill_source = resolve_contained_path(path_root, list_source_parts[0])  # 技能身份文件路径。

    # 读取目录声明的项目身份字段名。
    str_skill_field = list_source_parts[1].split(".")[-1]  # 技能身份字段名。

    # 从项目元数据获得最终技能规范 ID。
    str_skill_id = _read_project_field(path_skill_source, str_skill_field)  # 技能规范 ID。

    # 返回后端所需的完整包上下文。
    return {
        "bundle_root": path_root,
        "bootstrap_env": path_bootstrap,
        "manifest": dict_manifest,
        "catalog": dict_catalog,
        "projection": dict_projection,
        "skill_id": str_skill_id,
        "version": str_version,
    }
