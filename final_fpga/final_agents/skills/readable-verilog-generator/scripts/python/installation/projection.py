"""从显式权威源生成安装器运行时投影。

本模块声明 machine-readable stdout protocol：标准输出只包含一个 JSON 构建摘要对象。
"""

# 注解延迟求值保持投影构建器运行时兼容性。
from __future__ import annotations

# argparse 提供显式输入输出参数。
import argparse

# JSON 负责输出投影构建摘要。
import json

# pathlib 统一表达技能根和投影输出路径。
from pathlib import Path

# Any 描述目录驱动的 JSON 映射。
from typing import Any

# 复用包内 JSON 规范化、读取和摘要实现。
from .bundle import BundleError, canonical_json_bytes, read_json, sha256_file

# _status_value 读取投影构建结果的清单状态文本。
def _status_value(dict_manifest: dict[str, Any], str_status_key: str) -> str:
    """读取清单声明的投影状态文本。

    参数：
        dict_manifest: 安装清单对象。
        str_status_key: 状态键。
    返回：
        清单声明的状态文本。
    异常：
        BundleError: 状态键缺失或值为空。
    """

    # 投影构建器不复制状态协议值。
    dict_status_values = dict_manifest.get("status_values", {})  # 清单状态键到机器文本的映射。

    # 缺少状态值时停止生成不完整摘要。
    str_value = dict_status_values.get(str_status_key)  # 当前状态键对应的清单文本。

    # 只有清单提供非空文本时才允许生成摘要。
    if not isinstance(str_value, str) or not str_value.strip():

        # 配置缺失必须在投影写入前终止。
        raise BundleError(f"> ERR: [Python] status value is missing: {str_status_key}")

    # 返回已规范化的清单文本。
    return str_value.strip()

# parse_args 绑定投影构建的所有输入输出路径。
def parse_args(list_arguments: list[str] | None = None) -> argparse.Namespace:
    """解析投影构建的显式输入输出路径。

    参数：
        list_arguments: 可选显式参数列表。
    返回：
        投影构建参数命名空间。
    """

    # 投影构建不猜测当前目录或输出目录。
    parser: argparse.ArgumentParser = argparse.ArgumentParser(  # 投影 CLI 解析器。
        description="Build installer projections from explicit authority files.",  # CLI 用途说明。
    )

    # 技能根是投影输入的 containment 边界。
    parser.add_argument("--skill-root", required=True)

    # manifest 路径绑定安装清单权威源。
    parser.add_argument("--manifest", required=True)

    # catalog 路径绑定平台目录权威源。
    parser.add_argument("--catalog", required=True)

    # output 路径绑定平台投影文件。
    parser.add_argument("--output", required=True)

    # manifest-output 路径绑定清单合并投影。
    parser.add_argument("--manifest-output", required=True)

    # env-output 路径绑定跨语言启动投影。
    parser.add_argument("--env-output", required=True)

    # 返回投影构建参数。
    return parser.parse_args(list_arguments)

# _validate_catalog 确认平台目录可展开为唯一菜单。
def _validate_catalog(dict_catalog: dict[str, Any]) -> list[dict[str, Any]]:
    """验证平台目录的最小结构和唯一身份。

    参数：
        dict_catalog: 平台目录 JSON 对象。
    返回：
        平台对象列表。
    异常：
        BundleError: Schema 或平台身份无效。
    """

    # 顶层平台数组是投影构建的唯一来源。
    list_platforms = dict_catalog.get("platforms")  # 权威平台数组。

    # 空平台目录不能生成任何启动菜单。
    if not isinstance(list_platforms, list) or not list_platforms:

        # 空目录不能生成启动投影。
        raise BundleError("> ERR: [Python] platform catalog is empty")

    # 保存已经占用的规范 ID 和别名。
    set_identifiers: set[str] = set()  # 平台身份集合。

    # 逐条校验对象字段。
    for dict_platform in list_platforms:

        # 每条记录必须是对象且包含可识别 ID。
        if not isinstance(dict_platform, dict) or not str(dict_platform.get("id", "")).strip():

            # 不用默认平台值修复配置。
            raise BundleError("> ERR: [Python] platform catalog record is invalid")

        # 检查规范 ID 和别名的全局唯一性。
        list_names = [str(dict_platform["id"]), *[str(value) for value in dict_platform.get("aliases", [])]]  # 当前平台身份。

        # 逐项确认平台身份没有重复。
        for str_name in list_names:

            # 空或重复标识无法生成唯一菜单。
            if not str_name.strip() or str_name in set_identifiers:

                # 在投影生成阶段就拒绝歧义。
                raise BundleError("> ERR: [Python] platform catalog has duplicate identity")

            # 记录已使用身份。
            set_identifiers.add(str_name)

    # 返回通过结构和身份检查的目录数组。
    return list_platforms

# _write_atomic 将完整投影原子替换到调用者指定路径。
def _write_atomic(path_target: Path, bytes_content: bytes) -> None:
    """原子写入一个投影文件。

    参数：
        path_target: 目标路径。
        bytes_content: UTF-8 或 JSON 字节。
    返回：
        无。
    异常：
        OSError: 写入或替换失败。
    """

    # 临时文件与目标同目录，保证替换边界一致。
    path_temporary = path_target.with_name(path_target.name + ".tmp")  # 投影临时文件。

    # 输出父目录由显式目标路径决定。
    path_target.parent.mkdir(parents=True, exist_ok=True)

    # 临时文件完整后才进入原子替换。
    path_temporary.write_bytes(bytes_content)

    # 替换动作完成后调用者才看到新文件。
    path_temporary.replace(path_target)

# build_projection 从权威 JSON 生成运行时 JSON 和 env 投影。
def build_projection(namespace_args: argparse.Namespace) -> dict[str, Any]:
    """按显式配置生成 JSON 投影和启动 env 投影。

    参数：
        namespace_args: 投影构建参数。
    返回：
        投影构建摘要。
    异常：
        BundleError: 输入配置、路径或输出合同无效。
    """

    # 技能根决定所有投影输入输出的 containment 边界。
    path_skill_root = Path(namespace_args.skill_root).expanduser().resolve()  # 技能包根。

    # 清单输入来自调用者显式绑定的权威文件。
    path_manifest = Path(namespace_args.manifest).expanduser().resolve()  # 安装清单源。

    # 平台目录输入决定投影的平台记录。
    path_catalog = Path(namespace_args.catalog).expanduser().resolve()  # 平台目录源。

    # 平台投影输出由调用者显式指定。
    path_projection = Path(namespace_args.output).expanduser().resolve()  # 平台投影输出。

    # 清单投影输出保存启动器所需的合并事实。
    path_manifest_projection = Path(namespace_args.manifest_output).expanduser().resolve()  # 清单投影输出。

    # env 输出提供跨语言启动字段。
    path_env = Path(namespace_args.env_output).expanduser().resolve()  # 启动 env 输出。

    # 输入文件必须存在且位于技能根内。
    for path_input in (path_manifest, path_catalog):

        # 统一执行输入存在性和 containment 校验。
        if not path_input.is_file() or not path_input.is_relative_to(path_skill_root):

            # 不允许投影引用技能包外部配置。
            raise BundleError("> ERR: [Python] projection input is missing or outside skill root")

    # 读取安装清单权威对象。
    dict_manifest = read_json(path_manifest)  # 安装清单权威对象。

    # 读取平台目录权威对象。
    dict_catalog = read_json(path_catalog)  # 平台目录权威对象。

    # 验证平台目录并保持其目录顺序。
    list_platforms = _validate_catalog(dict_catalog)  # 已验证平台数组。

    # 计算安装清单摘要供运行时绑定。
    str_manifest_hash = sha256_file(path_manifest)  # 安装清单摘要。

    # 计算平台目录摘要供投影校验。
    str_catalog_hash = sha256_file(path_catalog)  # 平台目录摘要。

    # 平台投影只包含运行时需要的目录事实和来源摘要。
    dict_projection = {  # 运行时平台投影。
        "schema_version": dict_manifest.get("schema_version"),  # 平台投影格式版本。
        "manifest_sha256": str_manifest_hash,  # 平台投影引用的清单摘要。
        "catalog_sha256": str_catalog_hash,  # 平台投影引用的目录摘要。
        "platforms": list_platforms,  # 目录驱动的平台记录。
    }

    # 编码 JSON 投影，排序键保证构建可复现。
    bytes_projection = canonical_json_bytes(dict_projection)  # 平台投影字节。

    # 清单投影保存启动器读取的路径与协议事实。
    dict_manifest_projection = {  # 运行时清单投影。
        "schema_version": dict_manifest.get("schema_version"),  # 投影格式版本。
        "manifest_sha256": str_manifest_hash,  # 清单权威摘要。
        "catalog_sha256": str_catalog_hash,  # 平台目录权威摘要。
        "manifest": dict_manifest,  # 启动器和后端共享清单。
    }

    # 将清单投影编码为稳定的 JSON 字节。
    bytes_manifest_projection = canonical_json_bytes(dict_manifest_projection)  # 清单投影字节。

    # 写入两个 JSON 投影后再计算最终平台摘要。
    _write_atomic(path_projection, bytes_projection)

    # 清单投影与平台投影共享同一构建输入。
    _write_atomic(path_manifest_projection, bytes_manifest_projection)

    # 计算写入后的平台投影摘要。
    str_projection_hash = sha256_file(path_projection)  # 平台投影摘要。

    # 启动器所需 Python 候选来自 manifest。
    list_python_candidates = [str(value) for value in dict_manifest.get("python_candidates", [])]  # 清单排序后的 Python 探测序列。

    # 后端模块名由 manifest 投影声明。
    str_backend_module = str(dict_manifest.get("backend_module", "")).strip()  # 后端模块名。

    # 缺少任一启动字段都不能生成入口投影。
    if not list_python_candidates or not str_backend_module:

        # 缺少启动字段时不生成不可运行的入口。
        raise BundleError("> ERR: [Python] manifest does not declare launcher runtime")

    # 启动失败状态键由清单声明，不复制具体状态文本。
    str_bootstrap_status_key = str(dict_manifest.get("bootstrap_failure_status_key", "")).strip()  # 启动失败状态键。

    # 将状态键解析为清单文本，再读取对应退出码。
    str_bootstrap_status = _status_value(dict_manifest, str_bootstrap_status_key)  # 启动失败状态文本。

    # 读取清单声明的启动退出码。
    object_bootstrap_code = dict_manifest.get("exit_codes", {}).get(str_bootstrap_status)  # 启动失败退出码。

    # 缺少启动退出码时拒绝生成入口投影。
    if not isinstance(object_bootstrap_code, int):

        # 启动器必须拥有可验证的失败返回状态。
        raise BundleError("> ERR: [Python] bootstrap failure exit code is missing")

    # 使用一行一个字段的格式兼容三个启动器。
    list_env_lines = [  # 启动 env 投影行。
        f"MANIFEST_RELATIVE_PATH={dict_manifest['manifest_relative_path']}",  # 清单相对路径。
        f"CATALOG_RELATIVE_PATH={dict_manifest['catalog_relative_path']}",  # 目录相对路径。
        f"PROJECTION_RELATIVE_PATH={dict_manifest['projection_relative_path']}",  # 投影相对路径。
        f"MANIFEST_SHA256={str_manifest_hash}",  # 清单摘要。
        f"CATALOG_SHA256={str_catalog_hash}",  # 目录摘要。
        f"PROJECTION_SHA256={str_projection_hash}",  # 投影摘要。
        f"BACKEND_MODULE={str_backend_module}",  # 启动器执行的后端模块。
        f"PYTHON_CANDIDATES={'|'.join(list_python_candidates)}",  # Python 候选序列。
        f"POWERSHELL_CANDIDATES={'|'.join(str(value) for value in dict_manifest.get('powershell_candidates', []))}",  # Windows 启动候选序列。
        f"POWERSHELL_ENTRY_RELATIVE={dict_manifest['powershell_entry_relative']}",  # PowerShell 入口相对路径。
        f"BOOTSTRAP_FAILURE_EXIT_CODE={object_bootstrap_code}",  # 启动失败状态。
    ]

    # 将跨语言启动字段编码为 UTF-8 文本。
    bytes_env = ("\n".join(list_env_lines) + "\n").encode("utf-8")  # 启动 env 字节。

    # 原子写入启动投影，启动器只把它当作数据读取。
    _write_atomic(path_env, bytes_env)

    # 返回可持久化的构建摘要。
    return {
        "status": _status_value(dict_manifest, "projection_built"),
        "manifest_sha256": str_manifest_hash,
        "catalog_sha256": str_catalog_hash,
        "projection_sha256": str_projection_hash,
        "platform_count": len(list_platforms),
        "output": str(path_projection),
        "manifest_output": str(path_manifest_projection),
        "env_output": str(path_env),
    }

# main 提供投影构建的单对象 CLI 协议。
def main(list_arguments: list[str] | None = None) -> int:
    """执行投影构建 CLI。

    参数：
        list_arguments: 可选显式参数列表。
    返回：
        成功为 0，配置错误为非零。
    """

    # 解析显式投影构建参数。
    namespace_args = parse_args(list_arguments)  # 当前投影构建请求。

    # 构建成功输出单对象 JSON，便于 registry/脚本调用。
    try:

        # 投影构建器只写调用者指定的三个输出文件。
        dict_result = build_projection(namespace_args)  # 投影构建结果。

    # 领域错误以单对象协议输出，避免回溯污染 stdout。
    except (BundleError, OSError, KeyError) as object_error:

        # 错误结果包含固定 Python 错误前缀。
        print(json.dumps({"status_key": "failed", "message": f"> ERR: [Python] {object_error}"}, ensure_ascii=False))

        # 构建失败返回清单声明的错误码无法读取时的进程失败状态。
        return 1

    # 输出完整但单一的投影构建摘要。
    print(json.dumps(dict_result, ensure_ascii=False, sort_keys=True))

    # 投影构建完成。
    return 0

# 直接执行模块时输出投影构建的最终状态。
if __name__ == "__main__":

    # SystemExit 保留投影构建状态。
    raise SystemExit(main())
