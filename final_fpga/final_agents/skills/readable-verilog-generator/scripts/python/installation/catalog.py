"""解析平台目录并生成单 Harness 目标路径。"""

# 注解延迟求值保持目录模型可在受支持 Python 版本运行。
from __future__ import annotations

# dataclass 表达平台目录的不可变运行时记录。
from dataclasses import dataclass

# os 提供当前进程环境快照。
import os

# pathlib 负责用户根和目标根 containment。
from pathlib import Path

# Any 和 Iterable 描述目录驱动的 JSON 输入。
from typing import Any, Iterable

# CatalogError 统一报告平台目录和路径解析错误。
class CatalogError(ValueError):
    """表示平台目录无法解析为唯一安装目标。"""

# PlatformRecord 把一条平台目录事实收束为不可变值。
@dataclass(frozen=True)
class PlatformRecord:
    """平台目录中的一条不可变 Harness 记录。"""

    # 平台规范 ID 参与显式选择和收据绑定。
    platform_id: str  # 平台规范 ID。

    # 菜单显示名称只用于交互提示。
    display_name: str  # 菜单显示名称。

    # 目录声明的精确别名用于兼容输入。
    aliases: tuple[str, ...]  # 目录声明的精确别名。

    # 根目录解析模式决定环境变量优先级。
    root_mode: str  # 平台根解析模式。

    # 平台根环境变量候选由目录提供。
    environment_names: tuple[str, ...]  # 平台根环境变量候选。

    # 用户目录下的回退根保持平台目录隔离。
    fallback_home_relative: str  # 用户目录下的回退根。

    # 技能安装子目录由 Harness 目录声明。
    skill_install_dir: str  # 技能安装子目录。

    # 当前平台探测规则控制自动候选发现。
    detect_rules: tuple[dict[str, Any], ...]  # 当前平台的检测规则。

# load_platform_records 校验投影并构造平台记录。
def load_platform_records(dict_projection: dict[str, Any]) -> list[PlatformRecord]:
    """把投影中的平台对象转换为类型明确的记录。

    参数：
        dict_projection: 由包内 projection.json 读取的对象。
    返回：
        按目录顺序排列的平台记录。
    异常：
        CatalogError: 平台字段缺失、重复或类型错误。
    """

    # 平台数组由投影提供，代码不复制平台 ID。
    list_platform_values = dict_projection.get("platforms")  # 投影平台数组。

    # 平台数组是展开目录记录的最低结构条件。
    if not isinstance(list_platform_values, list):

        # 非数组投影不能安全展开菜单。
        raise CatalogError("> ERR: [Python] platform projection must contain an array")

    # 记录规范 ID 和别名，后续用于重复检查。
    set_identifiers: set[str] = set()  # 平台 ID 与别名集合。

    # 保存结构化平台记录。
    list_records: list[PlatformRecord] = []  # 已解析的平台记录。

    # 逐项读取目录，不使用平台名称分支。
    for dict_value in list_platform_values:

        # 每项必须是对象。
        if not isinstance(dict_value, dict):

            # 非对象记录不具备可解析字段。
            raise CatalogError("> ERR: [Python] platform record must be an object")

        # 读取目录规范 ID 供后续精确匹配。
        str_platform_id = str(dict_value.get("id", "")).strip()  # 当前目录记录的规范 ID 文本。

        # 读取交互菜单显示名称。
        str_display_name = str(dict_value.get("display_name", "")).strip()  # 当前目录记录的菜单名称。

        # 读取目录声明的精确别名。
        tuple_aliases = tuple(str(value).strip() for value in dict_value.get("aliases", []))  # 平台别名。

        # 读取平台根解析模式。
        str_root_mode = str(dict_value.get("root_mode", "")).strip()  # 根目录解析模式。

        # 读取平台根环境变量候选。
        tuple_environment_names = tuple(str(value).strip() for value in dict_value.get("environment_names", []))  # 环境变量候选。

        # 读取用户目录下的平台根回退路径。
        str_fallback_home = str(dict_value.get("fallback_home_relative", "")).strip()  # 用户目录相对根。

        # 读取技能安装子目录。
        str_skill_install_dir = str(dict_value.get("skill_install_dir", "")).strip()  # 技能安装目录名。

        # 读取当前平台的检测规则集合。
        tuple_detect_rules = tuple(dict_value.get("detect", []))  # 平台探测规则。

        # 任何空身份或空路径字段都必须失败。
        if (
            not str_platform_id
            or not str_display_name
            or not str_root_mode
            or not str_fallback_home
            or not str_skill_install_dir
        ):

            # 不用默认值掩盖目录配置错误。
            raise CatalogError("> ERR: [Python] platform record has an empty required field")

        # 探测规则必须是对象序列，避免字符串被逐字符解释。
        if any(not isinstance(dict_rule, dict) for dict_rule in tuple_detect_rules):

            # 无法解析的探测规则会造成错误的平台选择。
            raise CatalogError("> ERR: [Python] platform detection rules must be objects")

        # 规范 ID 和别名都必须全局唯一。
        for str_identifier in (str_platform_id, *tuple_aliases):

            # 空别名和重复标识不允许进入选择流程。
            if not str_identifier or str_identifier in set_identifiers:

                # 目录本身是运行时权威，重复意味着无法唯一定位。
                raise CatalogError("> ERR: [Python] platform IDs and aliases must be unique")

            # 记录已经占用的标识。
            set_identifiers.add(str_identifier)

        # 保存一条不可变的平台记录。
        obj_platform_record = PlatformRecord(  # 当前平台目录记录。
            platform_id=str_platform_id,  # 目录规范 ID。
            display_name=str_display_name,  # 记录交互菜单使用的名称。

            # aliases 与 root_mode 共同决定平台身份解析。
            aliases=tuple_aliases,  # 精确别名集合.
            root_mode=str_root_mode,  # 根目录解析方式。
            environment_names=tuple_environment_names,  # 记录平台根发现的变量。

            # 用户目录回退根保证平台目标隔离。
            fallback_home_relative=str_fallback_home,  # 用户目录回退根。

            # 技能目录和检测规则决定最终安装行为。
            skill_install_dir=str_skill_install_dir,  # 记录目标所需的技能子目录.
            detect_rules=tuple_detect_rules,  # 当前平台探测规则。
        )

        # 追加到保持目录顺序的结果数组。
        list_records.append(obj_platform_record)

    # 至少要有一条平台记录才能安装。
    if not list_records:

        # 空目录无法提供可用 Harness。
        raise CatalogError("> ERR: [Python] no platform records are configured")

    # 返回动态加载的目录记录。
    return list_records

# find_platform 只接受目录中声明的精确平台身份。
def find_platform(list_records: Iterable[PlatformRecord], str_requested: str) -> PlatformRecord:
    """按规范 ID 或目录别名查找平台。

    参数：
        list_records: 已校验的平台记录。
        str_requested: 调用者传入的 ID 或别名。
    返回：
        唯一匹配的平台记录。
    异常：
        CatalogError: 请求为空或目录没有匹配项。
    """

    # 去除外层空白但不做模糊纠错。
    str_normalized = str_requested.strip()  # 调用者请求的规范标识。

    # 空值没有任何安全选择。
    if not str_normalized:

        # 交给调用方映射为输入错误。
        raise CatalogError("> ERR: [Python] platform selection is empty")

    # 逐条检查规范 ID 和 aliases。
    for obj_platform_record in list_records:

        # 精确匹配才允许选择平台。
        if str_normalized == obj_platform_record.platform_id or str_normalized in obj_platform_record.aliases:

            # 返回目录声明的唯一记录。
            return obj_platform_record

    # 不存在的值必须失败，不能猜测最接近的平台。
    raise CatalogError(f"> ERR: [Python] unknown platform identifier: {str_normalized}")

# detect_platforms 解释环境检测规则并保持目录顺序。
def detect_platforms(
    list_records: Iterable[PlatformRecord],
    path_home: Path,
    dict_environment: dict[str, str],
) -> list[PlatformRecord]:
    """按目录规则探测当前环境中的平台候选。

    参数：
        list_records: 已校验的平台记录。
        path_home: 外部调用者解析出的用户目录。
        dict_environment: 当前进程环境变量快照。
    返回：
        按目录顺序排列的候选记录。
    """

    # 保存命中平台 ID，避免同一平台多个规则重复出现。
    set_detected_ids: set[str] = set()  # 已命中的平台 ID。

    # 保存探测候选。
    list_detected: list[PlatformRecord] = []  # 当前环境的平台候选。

    # 逐条解释目录规则。
    for obj_platform_record in list_records:

        # 每个平台独立计算规则命中。
        bool_matched = False  # 当前平台是否命中。

        # 目录声明的任何命中规则都可以确认候选。
        for dict_rule in obj_platform_record.detect_rules:

            # 读取规则类型，决定采用哪种目录证据。
            str_kind = str(dict_rule.get("kind", "")).strip()  # 当前探测规则类型。

            # 读取环境变量名，供环境证据规则使用。
            str_name = str(dict_rule.get("name", "")).strip()  # 当前探测环境变量名。

            # 读取用户目录相对路径，供目录证据规则使用。
            str_relative = str(dict_rule.get("path", "")).strip()  # 当前探测相对路径。

            # 环境变量规则只检查值是否非空。
            if str_kind == "environment_present" and dict_environment.get(str_name, "").strip():

                # 保留当前平台命中结果。
                bool_matched = True  # 环境变量规则命中当前平台。

            # 用户目录规则只检查目录是否存在。
            if str_kind == "home_relative_exists" and str_relative:

                # 解析规则声明的相对目录。
                path_candidate = (path_home / str_relative).resolve()  # 用户目录下的平台候选根。

                # 只接受仍在用户目录边界内的目录。
                if path_candidate.is_dir() and path_candidate.is_relative_to(path_home.resolve()):

                    # 把用户目录证据记入平台探测状态。
                    bool_matched = True  # 用户目录规则命中当前平台。

        # 只追加一次当前平台。
        if bool_matched and obj_platform_record.platform_id not in set_detected_ids:

            # 记录候选 ID，防止多个规则重复。
            set_detected_ids.add(obj_platform_record.platform_id)

            # 保留目录定义的候选顺序。
            list_detected.append(obj_platform_record)

    # 返回不带重复的平台候选。
    return list_detected

# resolve_user_home 按清单环境候选解析用户根。
def resolve_user_home(dict_manifest: dict[str, Any], dict_environment: dict[str, str], path_fallback: Path) -> Path:
    """按清单声明的环境变量顺序解析用户目录。

    参数：
        dict_manifest: 安装清单对象。
        dict_environment: 当前环境变量快照。
        path_fallback: 运行时平台提供的用户目录候选。
    返回：
        规范化用户目录。
    异常：
        CatalogError: 清单未声明合法环境变量或路径不可用。
    """

    # 清单决定环境变量优先级，代码不复制操作系统变量名。
    list_environment_names = dict_manifest.get("os_home_environment_names", [])  # 用户目录环境变量候选。

    # 依次选择第一个非空环境变量。
    for str_name in list_environment_names:

        # 只有字符串值才允许成为用户根路径。
        str_value = dict_environment.get(str(str_name), "").strip()  # 用户根环境值。

        # 非空环境值才能决定用户根。
        if str_value:

            # 返回规范化的调用者环境根。
            return Path(str_value).expanduser().resolve()

    # 没有环境变量时使用运行时的用户目录回退。
    path_home = path_fallback.expanduser().resolve()  # 系统提供的用户目录回退。

    # 回退必须存在且为目录。
    if not path_home.is_dir():

        # 不猜测不存在的用户目录。
        raise CatalogError("> ERR: [Python] user home directory is unavailable")

    # 返回通过存在性检查的用户目录。
    return path_home

# resolve_platform_root 为选定平台确定唯一根目录。
def resolve_platform_root(
    obj_platform_record: PlatformRecord,
    path_home: Path,
    dict_environment: dict[str, str],
    path_override: Path | None,
) -> Path:
    """解析单个平台根目录。

    参数：
        obj_platform_record: 平台目录记录。
        path_home: 已解析用户目录。
        dict_environment: 当前环境变量快照。
        path_override: 调用者提供的平台根覆盖。
    返回：
        规范化平台根目录。
    异常：
        CatalogError: 覆盖路径或目录模式无效。
    """

    # 显式覆盖优先于目录中的环境发现。
    if path_override is not None:

        # 覆盖路径只做规范化，目录是否存在由事务阶段决定。
        return path_override.expanduser().resolve()

    # 环境优先模式依次读取目录声明的变量。
    if obj_platform_record.root_mode == "environment_or_home_relative":

        # 选择第一个非空平台根环境变量。
        for str_name in obj_platform_record.environment_names:

            # 空环境变量不能提供可信平台根目录。
            str_value = dict_environment.get(str_name, "").strip()  # 平台根环境值。

            # 非空变量值才能成为平台根。
            if str_value:

                # 返回环境变量声明的根。
                return Path(str_value).expanduser().resolve()

    # home_relative 模式和环境回退都使用目录声明的相对根。
    path_root = (path_home / obj_platform_record.fallback_home_relative).resolve()  # 平台根目录。

    # 平台根必须仍在用户目录中，防止配置越界。
    if not path_root.is_relative_to(path_home.resolve()):

        # 越界模板无法安全创建安装目标。
        raise CatalogError("> ERR: [Python] platform root escapes user home")

    # 返回可能尚不存在但边界已确认的平台根。
    return path_root

# resolve_target 将平台模板或显式覆盖转换为最终目标。
def resolve_target(
    obj_platform_record: PlatformRecord,
    path_platform_root: Path,
    str_skill_id: str,
    dict_manifest: dict[str, Any],
    path_override: Path | None,
) -> Path:
    """解析平台目录模板或显式最终目标。

    参数：
        obj_platform_record: 平台目录记录。
        path_platform_root: 已解析平台根。
        str_skill_id: 包元数据提供的技能 ID。
        dict_manifest: 安装清单对象。
        path_override: 调用者提供的最终目标覆盖。
    返回：
        规范化最终技能目录。
    异常：
        CatalogError: 目标模板缺失或结果非法。
    """

    # 显式最终目录覆盖模板计算，但仍需交给事务做边界检查。
    if path_override is not None:

        # 目标目录是用户明确指定的最终写入边界。
        return path_override.expanduser().resolve()

    # 读取清单的唯一目标模板。
    dict_templates = dict_manifest.get("path_templates", {})  # 安装路径模板集合。

    # 目标模板文本决定最终目录如何拼接。
    str_template = str(dict_templates.get("target", "")).strip()  # 目标路径模板。

    # 缺失模板时不构造隐式目标。
    if not str_template:

        # 让清单修复而不是依赖代码默认值。
        raise CatalogError("> ERR: [Python] target path template is missing")

    # 将目录事实填入模板，平台值全部来自目录记录。
    str_target = str_template.format(  # 清单声明的最终目标文本。
        platform_root=str(path_platform_root),  # 模板中的平台根。
        skill_install_dir=obj_platform_record.skill_install_dir,  # 模板中的技能子目录。
        skill_id=str_skill_id,  # 模板中的技能规范 ID。
    )

    # 返回规范化目标目录。
    return Path(str_target).expanduser().resolve()
