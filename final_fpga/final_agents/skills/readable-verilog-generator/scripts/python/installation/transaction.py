"""执行单目标安装事务并保留可恢复证据。"""

# 注解延迟求值保持事务模型兼容受支持 Python 版本。
from __future__ import annotations

# dataclass 表达单事务的不可变请求。
from dataclasses import dataclass

# datetime 和 uuid 生成不依赖 case 的事务身份。
from datetime import datetime, timezone
import uuid

# json 只写入锁和安装收据摘要。
import json

# os 提供原子替换和文件操作。
import os

# pathlib 统一表达事务目录边界。
from pathlib import Path

# shutil 负责受控的目录复制与暂存清理。
import shutil

# Any 描述清单和收据映射。
from typing import Any

# 复用包摘要和安装后目录摘要实现。
from .bundle import BundleError, canonical_json_bytes, sha256_bytes
from .receipt import tree_digest

# TransactionError 将事务失败转换为配置驱动的恢复边界错误。
class TransactionError(BundleError):
    """表示安装事务需要回滚或人工恢复。"""

    # __init__ 保存失败状态键，避免调用方复制协议文本。
    def __init__(self, str_message: str, str_status_key: str = "rolled_back") -> None:
        """保存事务错误和状态键。

        参数：
            str_message: 已带 Python 错误前缀的摘要。
            str_status_key: 清单状态键。
        返回：
            无。
        """

        # 状态键由上层清单解析为输出文本和退出码。
        self.str_status_key = str_status_key  # 当前事务错误的清单状态键。

        # 保留原始错误文本供恢复诊断。
        super().__init__(str_message)

# _make_recovery_error 集中构造需要人工恢复的事务错误。
def _make_recovery_error(str_message: str) -> TransactionError:
    """创建需要人工恢复的事务错误。

    参数：
        str_message: 已带 Python 错误前缀的摘要。
    返回：
        标记为人工恢复的事务错误。
    """

    # 状态键只在事务错误对象中保存，输出文本由清单解析。
    return TransactionError(str_message, "recovery_required")

# _status_value 读取事务结果需要的清单状态文本。
def _status_value(dict_manifest: dict[str, Any], str_status_key: str) -> str:
    """读取清单声明的事务状态文本。

    参数：
        dict_manifest: 安装清单对象。
        str_status_key: 状态键。
    返回：
        清单声明的状态文本。
    异常：
        TransactionError: 状态键缺失或值为空。
    """

    # 安装事务不维护状态值备用常量。
    dict_status_values = dict_manifest.get("status_values", {})  # 清单状态键到机器文本的映射。

    # 清单缺字段时拒绝伪造成功结果。
    str_value = dict_status_values.get(str_status_key)  # 当前状态键对应的清单文本。

    # 只有清单提供非空文本时才允许生成事务结果。
    if not isinstance(str_value, str) or not str_value.strip():

        # 配置缺失必须在文件写入前终止。
        raise TransactionError(
            f"> ERR: [Python] status value is missing: {str_status_key}",
            "recovery_required",
        )

    # 返回规范化的清单状态文本。
    return str_value.strip()

# InstallRequest 保存一个 Harness 和一个目标的完整写入意图。
@dataclass(frozen=True)
class InstallRequest:
    """单次安装事务的规范化输入。"""

    # 目录声明的平台规范 ID绑定本次事务身份。
    platform_id: str  # 目录声明的平台规范 ID。

    # 已验证的版本化发布源只读参与复制。
    source_root: Path  # 已验证的版本化发布源。

    # 解析后的平台根用于目标模板计算。
    platform_root: Path  # 解析后的平台根。

    # 最终安装目标是本次唯一写入边界。
    target_dir: Path  # 最终安装目标。

    # 覆盖意图必须由调用者显式声明。
    replace: bool  # 是否允许替换现有目标。

    # 非交互写入确认不能由默认值推断。
    assume_yes: bool  # 是否已获得非交互确认。

    # 只读预演不创建锁、暂存和收据。
    dry_run: bool  # 是否只做只读预演。

# _transaction_id 为暂存、备份和收据提供唯一关联键。
def _transaction_id() -> str:
    """生成不依赖当前 case 或服务器的事务身份。

    参数：
        无；身份由运行时 UTC 时间和随机尾缀产生。
    返回：
        UTC 时间和随机尾缀组成的目录安全 ID。
    """

    # 时间提供可读排序，随机尾缀避免同一秒碰撞。
    str_identifier = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:8]  # 事务身份。

    # 返回只用于备份、暂存和收据关联的身份。
    return str_identifier

# _ensure_no_symlink 在复制和替换前阻断链接逃逸。
def _ensure_no_symlink(path_root: Path) -> None:
    """确认目录树不含符号链接。

    参数：
        path_root: 待检查目录。
    返回：
        无。
    异常：
        TransactionError: 发现符号链接。
    """

    # 目录不存在时由调用方决定是否允许创建。
    if not path_root.exists():

        # 没有目录就没有链接可检查。
        return

    # 逐项检查目录树，拒绝可能逃逸的链接。
    for path_entry in path_root.rglob("*"):

        # 任何层级符号链接都不允许进入覆盖或保留流程。
        if path_entry.is_symlink():

            # 保留失败原因但不跟随该链接。
            raise TransactionError("> ERR: [Python] target tree contains a symbolic link")

# _copy_file_or_directory 复制已经通过链接检查的载荷项。
def _copy_file_or_directory(path_source: Path, path_target: Path) -> None:
    """复制一个普通文件或目录，不跟随符号链接。

    参数：
        path_source: 已通过链接检查的源路径。
        path_target: 目标路径。
    返回：
        无。
    异常：
        OSError: 复制失败。
    """

    # 目录先创建，再递归复制其内容。
    if path_source.is_dir():

        # 目录复制保持内容边界，禁止链接跟随。
        shutil.copytree(path_source, path_target, symlinks=False, dirs_exist_ok=True)

        # 目录复制结束后不再执行文件分支。
        return

    # 普通文件复制同时保留基本元数据。
    path_target.parent.mkdir(parents=True, exist_ok=True)

    # 将普通文件复制到已经确认的暂存路径。
    shutil.copy2(path_source, path_target)

# _preserve_unlisted_files 把用户额外文件并入新暂存目录。
def _preserve_unlisted_files(path_target: Path, path_staging: Path, set_source_files: set[str]) -> list[str]:
    """把目标中未被发布载荷声明的文件复制到暂存目录。

    参数：
        path_target: 已存在的用户目标目录。
        path_staging: 新发布载荷的暂存目录。
        set_source_files: 发布收据声明的相对文件集合。
    返回：
        已保留的相对文件列表。
    异常：
        TransactionError: 目标含链接或路径越界。
    """

    # 先确认目标树没有会改变复制语义的链接。
    _ensure_no_symlink(path_target)

    # 记录实际复制的用户文件，供安装收据复核。
    list_preserved = []  # 保留文件相对路径。

    # 遍历全部用户文件，目录仅作为父路径存在。
    for path_file in sorted(path_target.rglob("*")):

        # 目录不需要单独复制，文件复制会创建父目录。
        if not path_file.is_file():

            # 跳过目录项和特殊项。
            continue

        # 统一为包内相对路径。
        str_relative = path_file.relative_to(path_target).as_posix()  # 用户文件相对路径。

        # 发布载荷已经提供的文件不能被用户副本覆盖。
        if str_relative in set_source_files:

            # 保留发布文件的内容权威。
            continue

        # 将未声明文件复制到暂存目录。
        path_destination = path_staging / str_relative  # 保留文件目标路径。

        # 复制用户文件并保持其相对路径。
        _copy_file_or_directory(path_file, path_destination)

        # 保存收据使用的相对身份。
        list_preserved.append(str_relative)

    # 返回排序后的保留文件列表。
    return sorted(list_preserved)

# _write_lock 以独占文件创建方式取得目标级事务锁。
def _write_lock(path_lock: Path, dict_payload: dict[str, Any]) -> None:
    """以独占创建方式取得目标级锁。

    参数：
        path_lock: 目标级锁路径。
        dict_payload: 写入锁文件的诊断摘要。
    返回：
        无。
    异常：
        TransactionError: 锁已存在或无法写入。
    """

    # 锁父目录必须先存在，且只创建清单确定的父目录。
    path_lock.parent.mkdir(parents=True, exist_ok=True)

    # x 模式保证并发事务不会互相覆盖锁内容。
    try:

        # 写入最小 JSON 摘要，便于恢复诊断。
        with path_lock.open("x", encoding="utf-8") as file_lock:

            # 锁内容不含凭据或完整环境变量。
            file_lock.write(json.dumps(dict_payload, ensure_ascii=False, sort_keys=True))

    # 文件已存在或权限不足都属于锁失败。
    except FileExistsError as object_error:

        # 调用方将锁冲突映射为输入或事务失败。
        raise TransactionError("> ERR: [Python] target transaction lock already exists") from object_error

    # 其他文件系统错误都阻止事务开始。
    except OSError as object_error:

        # 锁无法写入时不能继续复制。
        raise TransactionError(
            f"> ERR: [Python] cannot create target transaction lock: {object_error}"
        ) from object_error

# _remove_tree 只清理由本次事务创建的暂存或隔离目录。
def _remove_tree(path_root: Path) -> None:
    """删除当前事务自己创建的目录。

    参数：
        path_root: 事务拥有的目录。
    返回：
        无。
    异常：
        OSError: 删除失败。
    """

    # 只清理存在且已确认属于事务的目录。
    if path_root.exists():

        # 暂存和隔离目录统一递归清理。
        shutil.rmtree(path_root)

# _path_from_template 统一渲染清单声明的事务路径。
def _path_from_template(dict_manifest: dict[str, Any], str_key: str, dict_values: dict[str, str]) -> Path:
    """使用清单模板构造事务路径。

    参数：
        dict_manifest: 安装清单对象。
        str_key: path_templates 中的模板键。
        dict_values: 模板变量。
    返回：
        规范化路径。
    异常：
        TransactionError: 模板缺失或渲染越界。
    """

    # 路径模板必须来自清单，代码不维护备用命名规则。
    dict_templates = dict_manifest.get("path_templates", {})  # 安装路径模板集合。

    # 当前模板键决定本次事务资源的相对位置。
    str_template = str(dict_templates.get(str_key, "")).strip()  # 当前事务路径模板。

    # 空模板不能生成隐式事务目录。
    if not str_template:

        # 缺失模板时不创建隐式目录。
        raise TransactionError("> ERR: [Python] transaction path template is missing")

    # 渲染后交给调用方继续执行 containment 校验。
    try:

        # 模板变量全部来自已规范化的事务路径。
        str_rendered = str_template.format(**dict_values)  # 当前事务路径文本。

    # 缺少模板变量时保留配置错误边界。
    except (KeyError, ValueError) as object_error:

        # 不用默认值修补清单错误。
        raise TransactionError("> ERR: [Python] transaction path template is invalid") from object_error

    # 返回绝对规范路径。
    return Path(str_rendered).expanduser().resolve()

# _write_install_receipt 原子写入安装后目录的收据。
def _write_install_receipt(
    path_target: Path,
    dict_manifest: dict[str, Any],
    dict_request: dict[str, Any],
    dict_source_receipt: dict[str, Any],
    list_preserved: list[str],
    path_backup: Path | None,
) -> Path:
    """原子写入安装完成收据。

    参数：
        path_target: 已切换的新目标目录。
        dict_manifest: 安装清单对象。
        dict_request: 规范化请求摘要。
        dict_source_receipt: 源发布收据对象。
        list_preserved: 目标侧保留文件。
        path_backup: 旧目标备份路径。
    返回：
        新收据路径。
    异常：
        OSError: 收据无法写入。
    """

    # 收据文件名从清单读取，避免复制协议常量。
    str_receipt_name = str(dict_manifest.get("install_receipt_filename", "")).strip()  # 安装收据文件名。

    # 收据记录安装前后的受管目录摘要。
    dict_payload = {  # 安装投影收据。
        "schema_version": dict_manifest.get("schema_version"),  # 收据结构版本。
        "skill_id": dict_request["skill_id"],  # 安装技能规范 ID。
        "version": dict_request["version"],  # 发布版本来源。
        "platform_id": dict_request["platform_id"],  # 目录平台 ID。
        "source_receipt_sha256": sha256_bytes(canonical_json_bytes(dict_source_receipt)),  # 源收据摘要。
        "installed_tree_sha256": tree_digest(path_target),  # 安装后目录摘要。
        "preserved_files": list_preserved,  # 受保护用户文件。
        "backup_relative_path": str(path_backup.relative_to(path_target.parent)) if path_backup else None,  # 旧目标备份身份。
        "transaction_status": _status_value(dict_manifest, "installed"),  # 事务完成状态。
    }

    # 临时收据后缀由清单声明，避免业务代码复制命名规则。
    str_receipt_suffix = str(dict_manifest["transaction"].get("receipt_temp_suffix", "")).strip()  # 临时收据后缀。

    # 临时收据放在目标目录同级，写完后再原子替换进目标。
    path_temporary = path_target.parent / (path_target.name + str_receipt_suffix)  # 临时收据路径。

    # 先写完整 JSON，再用替换避免半份收据可见。
    path_temporary.write_bytes(canonical_json_bytes(dict_payload))

    # 收据文件进入新目标目录。
    path_receipt = path_target / str_receipt_name  # 最终安装收据路径。

    # 原子替换保证收据不会暴露半份内容。
    os.replace(path_temporary, path_receipt)

    # 返回收据位置供 CLI 输出摘要。
    return path_receipt

# _commit_transaction 在目标级锁内完成复制、替换、收据和恢复。
def _commit_transaction(dict_context: dict[str, Any]) -> dict[str, Any]:
    """执行已经完成只读校验的复制和回滚事务。

    参数：
        dict_context: 由调用方整理的事务路径、身份、源文件和锁状态。
    返回：
        安装成功摘要。
    异常：
        TransactionError: 复制、替换或恢复失败。
    """

    # 创建目标级锁，阻止同一目标的并发替换。
    try:

        # 锁只在所有只读检查后创建。
        _write_lock(dict_context["path_lock"], dict_context["dict_lock_payload"])

        # 标记本次事务已经拥有目标锁。
        dict_context["bool_lock_created"] = True  # 锁生命周期状态。

        # 创建目标父目录，确保暂存与目标位于同一卷。
        dict_context["path_parent"].mkdir(parents=True, exist_ok=True)

        # 创建本次事务独占的暂存目录。
        dict_context["path_staging"].mkdir(parents=False, exist_ok=False)

        # 将源发布载荷复制到新暂存目录。
        for str_relative, path_source_file in sorted(dict_context["dict_source_files"].items()):

            # 每个目标文件都通过相对路径回到暂存根。
            path_destination = dict_context["path_staging"] / str_relative  # 暂存文件路径。

            # 把通过收据校验的文件写入暂存树。
            _copy_file_or_directory(path_source_file, path_destination)

        # 目标存在时保留不在发布收据中的用户文件。
        list_preserved = []  # 用户保留文件清单。

        # 只有原目标存在时才需要计算保护文件。
        if dict_context["object_request"].target_dir.exists():

            # 将目标侧未声明文件复制到新载荷中。
            list_preserved = _preserve_unlisted_files(  # 保留用户文件。
                dict_context["object_request"].target_dir,  # 当前旧目标。
                dict_context["path_staging"],  # 新发布暂存目录。
                dict_context["set_source_files"],  # 发布载荷的受管相对路径集合。
            )

        # 已有目标先移动到受管备份，再切换新暂存目录。
        if dict_context["object_request"].target_dir.exists():

            # 备份父目录由清单控制，避免散落到用户根目录。
            dict_context["path_backup_parent"].mkdir(parents=True, exist_ok=True)

            # 原子移动旧目标，保留失败时的恢复入口。
            os.replace(dict_context["object_request"].target_dir, dict_context["path_backup"])

            # 记录旧目标已经进入受管备份。
            dict_context["bool_target_moved"] = True  # 备份完成状态。

        # 新暂存目录原子成为正式目标。
        os.replace(dict_context["path_staging"], dict_context["object_request"].target_dir)

        # 安装收据记录切换后的实际目录摘要。
        dict_request = {  # 收据中的规范化请求。
            "skill_id": dict_context["str_skill_id"],  # 收据技能身份。
            "version": dict_context["str_version"],  # 收据发布版本。
            "platform_id": dict_context["object_request"].platform_id,  # 收据平台身份。
        }

        # 将收据字段写入新目标并返回路径。
        path_receipt = _write_install_receipt(  # 安装完成收据。
            dict_context["object_request"].target_dir,  # 新安装目标。
            dict_context["dict_manifest"],  # 安装清单。
            dict_request,  # 规范化请求摘要。
            dict_context["dict_source_receipt"],  # 源发布收据。
            list_preserved,  # 用户保留文件。
            dict_context["path_backup"] if dict_context["bool_target_moved"] else None,  # 旧目标备份。
        )

        # 成功后释放事务锁，锁清理失败仍需返回错误。
        dict_context["path_lock"].unlink()

        # 标记锁已经释放，异常路径不再重复清理。
        dict_context["bool_lock_created"] = False  # 成功路径的锁占用状态。

        # 只返回机器可序列化的安装事实。
        return {
            "status": _status_value(dict_context["dict_manifest"], "installed"),
            "platform_id": dict_context["object_request"].platform_id,
            "target_dir": str(dict_context["object_request"].target_dir),
            "receipt": str(path_receipt),
            "preserved_files": list_preserved,
            "backup_dir": str(dict_context["path_backup"]) if dict_context["bool_target_moved"] else None,
        }

    # 任何事务异常都进入受管恢复分支。
    except Exception as transaction_error_object_error:

        # 暂存目录不能成为下一次事务的隐形输入。
        try:

            # 暂存尚未切换时直接清理；切换后它已经不存在。
            _remove_tree(dict_context["path_staging"])

        # 清理失败本身必须保留到恢复错误。
        except OSError as cleanup_error:

            # 转换为带上下文的事务异常供下方统一处理。
            str_cleanup_error_message = f"> ERR: [Python] staging cleanup failed: {cleanup_error}"  # 暂存清理失败摘要。

            # 将清理摘要绑定到人工恢复状态。
            transaction_error_object_error = _make_recovery_error(str_cleanup_error_message)  # 暂存清理失败需要人工恢复。

        # 旧目标已经备份时尝试恢复原位置。
        if (
        dict_context["bool_target_moved"]
        and not dict_context["object_request"].target_dir.exists()
        and dict_context["path_backup"].exists()
        ):

            # 原子移回旧目标，恢复原安装状态。
            try:

                # 备份存在时恢复原目标目录。
                os.replace(dict_context["path_backup"], dict_context["object_request"].target_dir)

                # 标记旧目标已经恢复到原位置。
                dict_context["bool_target_moved"] = False  # 备份恢复状态。

            # 恢复失败必须转为人工恢复状态。
            except OSError as restore_error:

                # 保留原始失败和恢复失败摘要。
                str_restore_error_message = f"> ERR: [Python] rollback failed: {restore_error}"  # 回滚失败摘要。

                # 将恢复摘要绑定到人工恢复状态。
                transaction_error_object_error = _make_recovery_error(str_restore_error_message)  # 回滚失败需要人工恢复。

        # 锁释放失败时不能伪造事务完成。
        if dict_context["bool_lock_created"]:

            # 只删除本次创建且路径已派生的锁。
            try:

                # 锁不存在时忽略已完成的外部清理。
                if dict_context["path_lock"].exists():

                    # 释放本次事务锁。
                    dict_context["path_lock"].unlink()

            # 锁残留需要人工恢复。
            except OSError as lock_error:

                # 保留最危险的恢复边界。
                str_lock_error_message = f"> ERR: [Python] transaction lock cleanup failed: {lock_error}"  # 锁清理失败摘要。

                # 锁释放边界失效时保留人工恢复标记。
                transaction_error_object_error = _make_recovery_error(str_lock_error_message)  # 锁清理失败需要人工恢复。

        # 任何未知异常都以事务错误形式向 CLI 传播。
        if isinstance(transaction_error_object_error, TransactionError):

            # 维持已经分类的恢复语义。
            raise

        # 其他异常只保留稳定错误前缀。
        raise TransactionError(
            f"> ERR: [Python] installation transaction failed: {transaction_error_object_error}"
        ) from transaction_error_object_error

# execute_transaction 先整理路径和身份，再调用受控提交事务。
def execute_transaction(
    object_request: InstallRequest,
    dict_bundle: dict[str, Any],
    dict_source_receipt: dict[str, Any],
    dict_source_files: dict[str, Path],
) -> dict[str, Any]:
    """执行一次目标级原子安装。

    参数：
        object_request: 已规范化的单 Harness 请求。
        dict_bundle: 已验证的包上下文。
        dict_source_receipt: 源发布收据对象。
        dict_source_files: 源发布文件索引。
    返回：
        安装结果摘要。
    异常：
        TransactionError: 事务失败或恢复失败。
    """

    # 读取本次事务的安装清单。
    dict_manifest = dict_bundle["manifest"]  # 安装清单对象。

    # 读取收据使用的技能规范 ID。
    str_skill_id = dict_bundle["skill_id"]  # 技能规范 ID。

    # 读取收据使用的发布版本。
    str_version = dict_bundle["version"]  # 发布版本。

    # 每次真实事务使用独立身份，避免暂存和备份碰撞。
    str_transaction_id = _transaction_id()  # 本次事务身份。

    # 目标父目录用于锁、暂存、备份和原子移动。
    path_parent = object_request.target_dir.parent  # 最终目标父目录。

    # 目标目录名进入清单模板和锁身份。
    str_target_name = object_request.target_dir.name  # 最终目标目录名。

    # 清单模板使用的字符串变量集中在一个映射中。
    dict_template_values = {  # 事务模板变量。
        "target_parent": str(path_parent),  # 目标父目录。
        "target_name": str_target_name,  # 目标目录名。
        "target": str(object_request.target_dir),  # 目标绝对路径。
        "skill_id": str_skill_id,  # 模板中的技能规范 ID。
        "platform_id": object_request.platform_id,  # 平台规范 ID。
        "transaction_id": str_transaction_id,  # 事务关联 ID。
        "lock_file_name": str(dict_manifest["transaction"]["lock_file_name"]),  # 锁文件名。
        "backup_directory_name": str(dict_manifest["transaction"]["backup_directory_name"]),  # 备份目录名。
        "quarantine_directory_name": str(dict_manifest["transaction"]["quarantine_directory_name"]),  # 隔离目录名。
    }

    # 清单模板决定目标级锁的位置。
    path_lock = _path_from_template(dict_manifest, "lock", dict_template_values)  # 目标级锁路径。

    # 清单模板决定历史备份的父目录。
    path_backup_parent = _path_from_template(dict_manifest, "backup_parent", dict_template_values)  # 历史目标的受管备份父目录。

    # 清单模板决定失败证据的隔离父目录。
    path_quarantine_parent = _path_from_template(dict_manifest, "quarantine_parent", dict_template_values)  # 失败暂存的隔离证据父目录。

    # 暂存目录前缀由清单声明。
    str_staging_prefix = str(dict_manifest["transaction"]["staging_prefix"])  # 暂存目录前缀。

    # 暂存目录把清单前缀和本次事务身份组合起来。
    path_staging = path_parent / f"{str_staging_prefix}{str_transaction_id}"  # 本次暂存目录。

    # 备份名称来自清单模板，旧目标不会覆盖历史备份。
    str_backup_name = str(dict_manifest["transaction"]["backup_name_template"]).format(  # 备份目录名称。
        skill_id=str_skill_id,  # 备份名中的技能身份。
        transaction_id=str_transaction_id,  # 备份名中的事务身份。
    )

    # 备份根和名称组合为本次旧目标的唯一位置。
    path_backup = path_backup_parent / str_backup_name  # 旧目标备份路径。

    # 记录旧目标是否已经安全移动到备份。
    bool_target_moved = False  # 旧目标是否已移入备份。

    # 记录本次事务是否创建了锁文件。
    bool_lock_created = False  # 事务锁是否已创建。

    # 源和目标不能互相包含，避免复制时把新目录写入源载荷。
    path_source_root = object_request.source_root.resolve()  # 已规范化发布源根。

    # 目标规范路径用于 containment 比较。
    path_target_root = object_request.target_dir.resolve()  # 已规范化安装目标。

    # 源目标包含关系会破坏发布和回滚边界。
    if (
        path_source_root == path_target_root
        or path_source_root.is_relative_to(path_target_root)
        or path_target_root.is_relative_to(path_source_root)
    ):

        # 该关系会让收据摘要覆盖正在写入的目录。
        raise TransactionError("> ERR: [Python] source and target directories overlap")

    # 受管锁内容只保存恢复所需的相对身份。
    dict_lock_payload = {  # 目标级锁诊断摘要。
        "skill_id": str_skill_id,  # 锁关联的技能身份。
        "platform_id": object_request.platform_id,  # 锁关联的平台身份。
        "transaction_id": str_transaction_id,  # 锁关联的事务身份。
    }

    # 发布文件集合用于保护目标侧额外内容。
    set_source_files = set(dict_source_files)  # 发布文件相对路径集合。

    # 安装器自己的收据由本次事务重新生成，不作为用户额外内容保留。
    str_install_receipt = str(dict_manifest.get("install_receipt_filename", "")).strip()  # 事务重写的收据文件名。

    # 将安装器收据从用户额外文件集合排除。
    set_source_files.add(str_install_receipt)

    # 事务开始前确认目标树和源载荷都没有符号链接。
    _ensure_no_symlink(object_request.target_dir)

    # 源发布树也必须保持普通文件边界。
    _ensure_no_symlink(object_request.source_root)

    # 将只读阶段收集的事实集中交给事务执行器。
    dict_context: dict[str, Any] = {
        "object_request": object_request,  # 单 Harness 安装请求。
        "dict_manifest": dict_manifest,  # 当前安装清单。
        "str_skill_id": str_skill_id,  # 技能规范身份。
        "str_version": str_version,  # 发布版本身份。
        "path_parent": path_parent,  # 传入事务目标父目录。
        "path_staging": path_staging,  # 当前暂存目录。
        "path_backup_parent": path_backup_parent,  # 受管备份父目录。
        "path_backup": path_backup,  # 传入旧目标备份路径。
        "path_lock": path_lock,  # 传入目标锁路径。
        "dict_lock_payload": dict_lock_payload,  # 锁摘要内容。
        "bool_target_moved": bool_target_moved,  # 旧目标移动状态。
        "bool_lock_created": bool_lock_created,  # 锁创建状态。
        "set_source_files": set_source_files,  # 发布文件集合。
        "dict_source_receipt": dict_source_receipt,  # 传入发布收据对象。
        "dict_source_files": dict_source_files,  # 源文件索引。
    }

    # 只读检查完成后进入唯一的写入事务。
    return _commit_transaction(dict_context)
