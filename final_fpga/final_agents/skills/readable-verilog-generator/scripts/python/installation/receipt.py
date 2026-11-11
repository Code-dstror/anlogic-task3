"""校验发布收据并生成安装事务摘要。"""

# 注解延迟求值保持收据模块运行时兼容性。
from __future__ import annotations

# JSON 负责读取发布收据对象。
import json

# pathlib 统一表达发布根和相对文件身份。
from pathlib import Path

# Any 描述发布收据的可扩展字段。
from typing import Any

# 复用包投影的规范 JSON 和摘要实现。
from .bundle import BundleError, canonical_json_bytes, sha256_bytes, sha256_file

# _relative_file_map 收集收据覆盖范围内的普通载荷。
def _relative_file_map(path_root: Path, path_receipt: Path) -> dict[str, Path]:
    """收集发布根中的普通文件。

    参数：
        path_root: 发布目录根。
        path_receipt: 发布收据路径。
    返回：
        相对路径到普通文件的映射。
    异常：
        BundleError: 发现符号链接或越界路径。
    """

    # 保存发布载荷的相对路径索引。
    dict_files: dict[str, Path] = {}  # 发布文件索引。

    # 递归遍历发布目录，收据自身不参与自引用摘要。
    for path_file in path_root.rglob("*"):

        # 符号链接不能成为可安装载荷。
        if path_file.is_symlink():

            # 立即阻止链接逃逸或链接语义差异。
            raise BundleError("> ERR: [Python] release payload contains a symbolic link")

        # 只把普通文件放入摘要索引。
        if not path_file.is_file():

            # 目录由其内部文件间接表达，不单独记录。
            continue

        # 收据文件不加入自身文件摘要清单。
        if path_file.resolve() == path_receipt.resolve():

            # 保留收据外部存在性检查。
            continue

        # 将路径转换为使用正斜杠的包内相对身份。
        str_relative = path_file.relative_to(path_root).as_posix()  # 发布文件相对路径。

        # 路径重复意味着平台大小写或目录结构发生歧义。
        if str_relative in dict_files:

            # 不接受同一路径被不同实体覆盖。
            raise BundleError("> ERR: [Python] release payload contains duplicate relative paths")

        # 记录相对路径和文件对象。
        dict_files[str_relative] = path_file  # 相对路径到普通文件的索引。

    # 返回文件索引供收据校验和复制流程共享。
    return dict_files

# _is_valid_receipt_size 判断可选大小字段是否满足兼容合同。
def _is_valid_receipt_size(obj_expected_size: object, bool_size_declared: bool) -> bool:
    """判断发布 receipt 的可选文件大小字段是否有效。

    参数：
        obj_expected_size: 收据声明的文件大小对象。
        bool_size_declared: 收据是否显式包含 ``size`` 字段。
    返回：
        缺失大小或显式非负整数时返回 True。
    """

    # 外部 agents-md receipt 可以只绑定路径和文件摘要。
    if not bool_size_declared:

        # 缺失大小不削弱路径和 SHA-256 校验。
        return True

    # 显式大小必须是非布尔的非负整数。
    return (
        isinstance(obj_expected_size, int)
        and not isinstance(obj_expected_size, bool)
        and obj_expected_size >= 0
    )

# _validate_receipt_files 逐项比对收据文件与源载荷摘要。
def _validate_receipt_files(
    dict_receipt: dict[str, Any],
    str_receipt_name: str,
    dict_source_files: dict[str, Path],
) -> dict[str, dict[str, Any]]:
    """验证收据文件项并返回已确认条目。

    参数：
        dict_receipt: 发布收据对象。
        str_receipt_name: 清单声明的收据文件名。
        dict_source_files: 发布源文件索引。
    返回：
        相对路径到收据条目的映射。
    异常：
        BundleError: 任一条目路径、重复项或摘要不一致。
    """

    # 保存收据列出的相对路径，检查重复和额外文件。
    dict_declared_files: dict[str, dict[str, Any]] = {}  # 收据文件清单。

    # 逐条校验收据中的路径和摘要。
    for dict_entry in dict_receipt["files"]:

        # 文件条目必须是对象。
        if not isinstance(dict_entry, dict):

            # 非对象条目无法验证文件身份。
            raise BundleError("> ERR: [Python] release receipt file entry is invalid")

        # 收据路径统一使用正斜杠。
        str_relative = str(dict_entry.get("path", "")).replace("\\", "/").strip()  # 收据相对路径。

        # 收据摘要字段决定逐文件完整性比较。
        str_expected_hash = str(dict_entry.get("sha256", "")).strip()  # 收据文件摘要。

        # 收据大小字段存在时绑定复制前的字节级载荷事实。
        bool_size_declared = "size" in dict_entry  # 当前收据是否声明文件大小。

        # agents-md release receipt 可只声明路径和摘要，缺失大小由 backend 兼容接受。
        obj_expected_size: object = dict_entry.get("size")  # 收据文件大小。

        # 缺失大小表示外部 receipt 合同，显式大小仍必须是非负整数。
        bool_size_valid = _is_valid_receipt_size(obj_expected_size, bool_size_declared)  # 当前收据大小字段合法性。

        # 空路径、绝对路径、缺摘要或非法显式大小均失败。
        bool_path_valid = bool(str_relative) and not Path(str_relative).is_absolute()  # 当前收据路径合法性。

        # 路径、摘要和大小必须同时满足当前 receipt 兼容合同。
        if not bool_path_valid or not str_expected_hash or not bool_size_valid:

            # 不允许收据把摘要指向包外。
            raise BundleError("> ERR: [Python] release receipt contains an invalid file path")

        # 收据不允许自引用，否则无法稳定生成摘要。
        if str_relative == str_receipt_name.replace("\\", "/"):

            # 保持收据和载荷摘要的单向关系。
            raise BundleError("> ERR: [Python] release receipt must not list itself")

        # 重复路径会让摘要语义不唯一。
        if str_relative in dict_declared_files:

            # 立即拒绝重复收据项。
            raise BundleError("> ERR: [Python] release receipt repeats a file path")

        # 收据路径必须能在源索引中找到。
        path_file = dict_source_files.get(str_relative)  # 收据条目对应的真实文件。

        # 缺失文件不能由收据条目虚构。
        if path_file is None:

            # 不接受声明不存在的文件。
            raise BundleError("> ERR: [Python] release receipt lists a missing file")

        # 计算文件真实摘要并比较。
        str_actual_hash = sha256_file(path_file)  # 发布文件真实摘要。

        # 真实摘要必须与发布收据逐项一致。
        if str_actual_hash != str_expected_hash:

            # 任何单文件失配都阻止复制。
            raise BundleError("> ERR: [Python] release file hash mismatch")

        # 显式声明大小时必须与源文件真实字节数一致。
        if bool_size_declared and path_file.stat().st_size != int(obj_expected_size):

            # 大小失配表示收据和载荷不是同一发布身份。
            raise BundleError("> ERR: [Python] release file size mismatch")

        # 保存通过校验的收据条目。
        dict_declared_files[str_relative] = dict_entry  # 已校验的收据条目。

    # 返回逐文件校验完成的收据条目集合。
    return dict_declared_files

# load_release_receipt 验证发布收据与实际载荷逐项一致。
def load_release_receipt(path_source: Path, dict_manifest: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Path]]:
    """校验版本化发布目录的收据和逐文件摘要。

    参数：
        path_source: 待安装的版本化发布目录。
        dict_manifest: 安装器清单。
    返回：
        收据对象以及发布文件相对路径索引。
    异常：
        BundleError: 收据缺失、身份不匹配、文件清单失配或摘要错误。
    """

    # 收据文件名必须来自安装清单。
    str_receipt_name = str(dict_manifest.get("release_receipt_filename", "")).strip()  # 发布收据文件名。

    # 没有收据名就无法锁定发布身份。
    if not str_receipt_name:

        # 清单没有收据名时不能验证发布来源。
        raise BundleError("> ERR: [Python] release receipt filename is not configured")

    # 发布根必须是目录且不允许符号链接。
    path_root = path_source.expanduser().resolve()  # 发布目录根。

    # 源目录必须是真实可读目录。
    if not path_root.is_dir() or path_root.is_symlink():

        # 源路径不满足目录载荷合同。
        raise BundleError("> ERR: [Python] release source is not a directory")

    # 收据只能位于发布根的直接子项。
    path_receipt = (path_root / str_receipt_name).resolve()  # 发布收据路径。

    # 收据越界或缺失时拒绝源码安装。
    if not path_receipt.is_file() or not path_receipt.is_relative_to(path_root):

        # 缺收据时拒绝把源码目录当发布包。
        raise BundleError("> ERR: [Python] release receipt is missing")

    # 读取收据 JSON，保持其自描述内容不执行。
    try:

        # 收据必须使用 UTF-8 对象格式。
        dict_receipt = json.loads(path_receipt.read_text(encoding="utf-8"))  # 发布收据对象。

    # 读取或解析失败都属于完整性错误。
    except (OSError, json.JSONDecodeError) as object_error:

        # 统一返回收据不可用的诊断。
        raise BundleError(f"> ERR: [Python] release receipt is unreadable: {object_error}") from object_error

    # 顶层和文件数组必须满足最小收据结构。
    if not isinstance(dict_receipt, dict) or not isinstance(dict_receipt.get("files"), list):

        # 不接受没有逐文件证据的自制收据。
        raise BundleError("> ERR: [Python] release receipt has no file manifest")

    # 读取收据声明的技能身份。
    str_expected_skill = str(dict_receipt.get("skill_name", "")).strip()  # 收据技能身份。

    # 读取收据声明的发布版本。
    str_expected_version = str(dict_receipt.get("version", "")).strip()  # 收据发布版本。

    # 读取当前包的运行时技能身份。
    str_actual_skill = str(dict_manifest.get("_runtime_skill_id", "")).strip()  # 当前包技能身份。

    # 读取当前包的运行时发布版本。
    str_actual_version = str(dict_manifest.get("_runtime_version", "")).strip()  # 当前包发布版本。

    # 只有身份和版本同时一致才允许继续校验文件。
    if str_expected_skill != str_actual_skill or str_expected_version != str_actual_version:

        # 收据与运行时身份不一致时阻止安装。
        raise BundleError("> ERR: [Python] release receipt identity does not match package metadata")

    # 建立源文件索引并跳过收据自引用。
    dict_source_files = _relative_file_map(path_root, path_receipt)  # 收据校验使用的源文件索引。

    # 读取清单声明的禁止载荷名称，防止缓存或临时目录进入安装包。
    list_forbidden_names = dict_manifest.get("source_policy", {}).get("forbidden_names", [])  # 清单禁止名称列表。

    # 将禁止名称规范化为集合。
    set_forbidden_names = {str(value).strip() for value in list_forbidden_names if str(value).strip()}  # 禁止源名称集合。

    # 逐项检查源相对路径的每一层目录。
    for str_relative in dict_source_files:

        # 路径命中禁止名称时在复制前拒绝载荷。
        if any(str_part in set_forbidden_names for str_part in Path(str_relative).parts):

            # 保留清单驱动的源策略错误边界。
            raise BundleError("> ERR: [Python] release source contains a forbidden path")

    # 逐项校验收据声明的源文件。
    dict_declared_files = _validate_receipt_files(  # 已确认的收据条目。
        dict_receipt,  # 当前发布收据。
        str_receipt_name,  # 收据文件名。
        dict_source_files,  # 源文件索引。
    )

    # 收据清单必须覆盖全部普通载荷文件。
    if set(dict_declared_files) != set(dict_source_files):

        # 额外或遗漏文件都意味着发布包被篡改或收据过期。
        raise BundleError("> ERR: [Python] release receipt file set does not match source payload")

    # 返回收据和已校验的文件索引。
    return dict_receipt, dict_source_files

# tree_digest 为安装收据生成排序稳定的目录摘要。
def tree_digest(path_root: Path) -> str:
    """计算目录中文件路径和摘要的规范化摘要。

    参数：
        path_root: 待摘要目录。
    返回：
        规范化 JSON 的 SHA-256 摘要。
    异常：
        OSError: 目录内容不可读。
    """

    # 文件身份和内容摘要共同决定目录摘要。
    dict_files = _relative_file_map(path_root, path_root / "__never__")  # 安装后目录文件索引。

    # 使用排序列表保证不同遍历顺序得到相同摘要。
    list_entries = [  # 目录摘要条目。
        {"path": str_relative, "sha256": sha256_file(path_file)}  # 当前文件摘要条目。
        for str_relative, path_file in sorted(dict_files.items())  # 以路径顺序生成摘要。
    ]

    # 将目录摘要条目编码为稳定字节。
    bytes_payload = canonical_json_bytes({"files": list_entries})  # 目录摘要 JSON。

    # 返回目录级摘要供安装收据绑定。
    return sha256_bytes(bytes_payload)
