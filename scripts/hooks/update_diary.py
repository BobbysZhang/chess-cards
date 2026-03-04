#!/usr/bin/env python3
"""根据最近一次 git 提交，自动在开发者日记中追加一条记录。由 post-commit 钩子调用。"""
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Tuple

# 约定式提交前缀 -> 类型
TYPE_MAP = {
    "docs": "文档",
    "feat": "功能",
    "fix": "修复",
    "refactor": "重构",
    "style": "样式",
    "chore": "杂项",
    "test": "测试",
}


def get_repo_root() -> Path:
    out = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=False,
    )
    if out.returncode != 0:
        sys.exit(1)
    return Path(out.stdout.strip())


def get_last_commit_date() -> str:
    """获取最近一次提交的日期 YYYY-MM-DD。"""
    out = subprocess.run(
        ["git", "log", "-1", "--format=%ci"],
        capture_output=True,
        text=True,
        check=True,
        cwd=get_repo_root(),
    )
    # %ci: 2026-03-04 16:45:55 +0800
    return out.stdout.strip().split()[0]


def get_commits_for_date(date: str, root: Path) -> List[Tuple[str, str, str]]:
    """获取指定日期当天的所有提交，按时间从早到晚排序。返回 [(HH:MM, subject, short_hash), ...]。"""
    out = subprocess.run(
        ["git", "log", "--format=%ci%n%s%n%h", "--reverse", "-100"],
        capture_output=True,
        text=True,
        check=True,
        cwd=root,
    )
    result: List[Tuple[str, str, str]] = []
    lines = out.stdout.strip().split("\n") if out.stdout.strip() else []
    i = 0
    while i + 2 < len(lines):
        date_time = lines[i].split()
        if len(date_time) < 2:
            i += 1
            continue
        commit_date = date_time[0]
        time_str = date_time[1][:5]
        subject = lines[i + 1]
        short_hash = lines[i + 2] if i + 2 < len(lines) else ""
        if commit_date == date:
            result.append((time_str, subject, short_hash))
        i += 3
    return result


def type_from_subject(subject: str) -> str:
    for prefix, label in TYPE_MAP.items():
        if subject.strip().lower().startswith(prefix + ":"):
            return label
    return "提交"


def weekday_cn(date_str: str) -> str:
    """2026-03-04 -> 周三"""
    d = datetime.strptime(date_str, "%Y-%m-%d")
    w = ["一", "二", "三", "四", "五", "六", "日"][d.weekday()]
    return f"周{w}"


def escape_cell(text: str) -> str:
    """表格单元格内不保留 | 和换行"""
    return text.replace("|", "，").replace("\n", " ").strip() or "—"


def extract_desc_from_table_row(line: str) -> Optional[str]:
    """从表格行中提取简述（第三列），仅处理数据行。"""
    if not re.match(r"^\| \d{2}:\d{2}\s+\| .+ \| .+ \|$", line):
        return None
    parts = [p.strip() for p in line.split("|")]
    # parts[0]='', parts[1]=时间, parts[2]=类型, parts[3]=简述, parts[4]=''
    if len(parts) >= 4 and parts[3]:
        return parts[3]
    return None


# 简述末尾可带提交 hash，如 "feat: xxx (49c79eb)"，用于去重
_HASH_SUFFIX_RE = re.compile(r"\s+\([0-9a-f]{7}\)$")


def _desc_without_hash(desc: str) -> str:
    """去掉简述末尾的 (short_hash)，便于与旧行（无 hash）比对。"""
    return _HASH_SUFFIX_RE.sub("", desc).strip()


def get_existing_for_date(text: str, section_header: str) -> Tuple[set, set]:
    """返回 (已有 short_hash 集合, 已有简述集合（去掉 hash 后）)，用于去重。"""
    existing_hashes: set = set()
    existing_descs: set = set()
    lines = text.split("\n")
    in_section = False
    for line in lines:
        if line.strip() == section_header:
            in_section = True
            continue
        if in_section:
            if line.strip().startswith("## "):
                break
            desc = extract_desc_from_table_row(line)
            if desc:
                existing_descs.add(_desc_without_hash(desc))
                m = _HASH_SUFFIX_RE.search(desc)
                if m:
                    # "(e527920)" -> "e527920"
                    existing_hashes.add(m.group(0).strip()[1:-1])
    return existing_hashes, existing_descs


def fill_pending_summaries(text: str) -> str:
    """将文中所有「当日小结：待补充。」根据当日表格内容自动生成一句小结并替换。"""
    table_row_re = re.compile(r"^\| \d{2}:\d{2}\s+\| .+ \| .+ \|$")
    pending_marker = "**当日小结**：待补充。"
    if pending_marker not in text:
        return text

    lines = text.split("\n")
    result: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        result.append(line)
        # 遇到待补充的当日小结行：向前收集本节的表格数据行以生成小结
        if pending_marker in line and line.strip().startswith("**当日小结**"):
            # 从当前 section 的表格里收集简述（从后往前直到表头）
            descs: list[str] = []
            j = len(result) - 2  # 上一行
            while j >= 0:
                row = result[j]
                if table_row_re.match(row):
                    desc = extract_desc_from_table_row(row)
                    if desc:
                        descs.append(desc)
                elif row.strip().startswith("|") and "---" in row:
                    break  # 表头分隔行，再往前是表头
                elif row.strip().startswith("## "):
                    break
                j -= 1
            descs.reverse()
            if descs:
                summary = "本日完成：" + "、".join(descs) + "。"
                result[-1] = line.replace("待补充。", summary)
            # 若 descs 为空则保留「待补充。」
        i += 1
    return "\n".join(result)


def main() -> None:
    root = get_repo_root()
    diary_path = root / "docs" / "DEVELOPER_DIARY.md"
    if not diary_path.exists():
        return

    date = get_last_commit_date()
    weekday = weekday_cn(date)
    commits = get_commits_for_date(date, root)
    if not commits:
        return

    text = diary_path.read_text(encoding="utf-8")
    section_header = f"## {date}（{weekday}）"
    table_row_re = re.compile(r"^\| \d{2}:\d{2}\s+\| .+ \| .+ \|$")
    existing_hashes, existing_descs = (
        get_existing_for_date(text, section_header) if section_header in text else (set(), set())
    )

    # 收集当日尚未出现在日记中的提交（按 hash 或简述去重），按时间顺序
    rows_to_add: List[Tuple[str, str, str]] = []
    for time_str, subject, short_hash in commits:
        desc_normalized = _desc_without_hash(escape_cell(subject))
        if short_hash not in existing_hashes and desc_normalized not in existing_descs:
            type_label = type_from_subject(subject)
            desc_cell = escape_cell(subject) + " (" + short_hash + ")"
            rows_to_add.append((time_str, type_label, desc_cell))
            existing_hashes.add(short_hash)
            existing_descs.add(desc_normalized)

    if not rows_to_add:
        text = fill_pending_summaries(text)
        diary_path.write_text(text, encoding="utf-8")
        return

    new_rows_str = "\n".join(f"| {t}  | {tl:<10} | {d} |" for t, tl, d in rows_to_add)

    if section_header not in text:
        # 新日期：在最后一个日期区块与「安装」说明之间插入新区块
        block = (
            f"\n{section_header}\n\n"
            "| 时间   | 类型       | 简述 |\n"
            "|--------|------------|------|\n"
            f"{new_rows_str}\n\n"
            "**当日小结**：待补充。"
        )
        if "\n---\n\n安装" in text:
            text = text.replace("\n---\n\n安装", "\n\n" + block + "\n\n---\n\n安装", 1)
        else:
            text = text.rstrip() + "\n\n" + block + "\n\n---\n"
    else:
        # 已有该日期：在当日最后一个表格数据行后一次性插入所有新行
        lines = text.split("\n")
        insert_after = None
        in_section = False
        for i, line in enumerate(lines):
            if line.strip() == section_header:
                in_section = True
                continue
            if in_section:
                if line.strip().startswith("## "):
                    break
                if table_row_re.match(line):
                    insert_after = i
        if insert_after is not None:
            for row in new_rows_str.split("\n"):
                lines.insert(insert_after + 1, row)
                insert_after += 1
            text = "\n".join(lines)
        else:
            for i, line in enumerate(lines):
                if line.strip() == section_header:
                    for j in range(i + 1, min(i + 5, len(lines))):
                        if re.match(r"^\|[-]+\|", lines[j]):
                            for row in new_rows_str.split("\n"):
                                lines.insert(j + 1, row)
                                j += 1
                            text = "\n".join(lines)
                            break
                    break

    text = fill_pending_summaries(text)
    diary_path.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
