#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
解析 .xcodeproj 中的 project.pbxproj，提取 Sources 与 Resources 引用的文件路径。
用于将扫描数据源从「目录遍历」切换为「工程引用」。
"""

import re
from pathlib import Path
from typing import List, Tuple, Dict, Set, Optional


def _parse_pbxproj_content(content: str) -> Tuple[Dict[str, str], Dict[str, dict], str, Dict[str, str], Dict[str, str]]:
    """
    解析 pbxproj 内容。
    Returns:
        file_refs: ref_id -> path (from PBXFileReference)
        groups: group_id -> {path, children: [id, ...]}
        main_group_id: 根 group id
        build_file_to_ref: build_file_id -> file_ref_id (from PBXBuildFile, in Sources)
        build_file_to_ref_res: build_file_id -> file_ref_id (from PBXBuildFile, in Resources)
    """
    file_refs: Dict[str, str] = {}
    groups: Dict[str, dict] = {}
    main_group_id: Optional[str] = None
    build_file_to_ref: Dict[str, str] = {}
    build_file_to_ref_res: Dict[str, str] = {}

    # PBXFileReference: 单行形式 path = xxx;
    # 例: \t\t009DE21A159D5B5100EC8B6F /* DirectCluster.m */ = {isa = PBXFileReference; ... path = DirectCluster.m; sourceTree = "<group>"; };
    ref_id_re = re.compile(r'^\s*([A-F0-9]+)\s+/\*.*?\*/\s*=\s*\{\s*isa = PBXFileReference;', re.MULTILINE)
    path_re = re.compile(r'path\s*=\s*([^;]+);')
    for m in ref_id_re.finditer(content):
        ref_id = m.group(1)
        block_start = m.start()
        block_end = content.find('};', block_start) + 2
        block = content[block_start:block_end]
        path_m = path_re.search(block)
        if path_m:
            path_val = path_m.group(1).strip().strip('"')
            file_refs[ref_id] = path_val

    # mainGroup
    main_m = re.search(r'mainGroup\s*=\s*([A-F0-9]+)\s*;', content)
    if main_m:
        main_group_id = main_m.group(1)

    # PBXGroup: 多行块，提取 group id, path, children
    # 块格式: \t\tHEXID /* name */ = { isa = PBXGroup; 或 \t\tHEXID = { isa = PBXGroup;
    group_begin = re.compile(r'^\s*([A-F0-9]+)\s+(?:/\*.*?\*/\s*)?=\s*\{\s*isa = PBXGroup;', re.MULTILINE)
    for m in group_begin.finditer(content):
        group_id = m.group(1)
        block_start = m.start()
        # 找匹配的 };
        depth = 0
        i = content.index('{', block_start)
        while i < len(content):
            if content[i] == '{':
                depth += 1
            elif content[i] == '}':
                depth -= 1
                if depth == 0:
                    block_end = i + 1
                    break
            i += 1
        else:
            continue
        block = content[block_start:block_end]
        path_m = path_re.search(block)
        path_val = path_m.group(1).strip().strip('"') if path_m else ''
        # children = ( id1, id2, ... ); 用括号平衡找闭合，避免注释内 ) 截断
        children = []
        idx = block.find('children = (')
        if idx >= 0:
            start = block.index('(', idx) + 1
            depth = 1
            i = start
            while i < len(block) and depth > 0:
                if block[i] == '(':
                    depth += 1
                elif block[i] == ')':
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            child_str = block[start:i]
            for part in re.finditer(r'([A-F0-9]+)\s+/\*', child_str):
                children.append(part.group(1))
        groups[group_id] = {'path': path_val, 'children': children}

    # PBXBuildFile: 单行，注释里 " in Sources */" 或 " in Resources */"，行首 build_id，中间 fileRef = HEXID
    # 例: \t\t009DE21B... /* DirectCluster.m in Sources */ = {isa = PBXBuildFile; fileRef = 009DE21A... /* ... */; };
    build_id_re = re.compile(r'^\s*([A-F0-9]+)\s+/\*')
    file_ref_re = re.compile(r'fileRef = ([A-F0-9]+)')
    for line in content.splitlines():
        if ' in Sources */' in line and 'fileRef = ' in line:
            bid = build_id_re.search(line)
            fid = file_ref_re.search(line)
            if bid and fid:
                build_file_to_ref[bid.group(1)] = fid.group(1)
        elif ' in Resources */' in line and 'fileRef = ' in line:
            bid = build_id_re.search(line)
            fid = file_ref_re.search(line)
            if bid and fid:
                build_file_to_ref_res[bid.group(1)] = fid.group(1)

    return file_refs, groups, main_group_id or '', build_file_to_ref, build_file_to_ref_res


def _resolve_paths(
    file_refs: Dict[str, str],
    groups: Dict[str, dict],
    main_group_id: str,
    project_dir: Path,
) -> Dict[str, str]:
    """将 file_ref id 解析为相对 project_dir 的路径。"""
    ref_to_full_path: Dict[str, str] = {}
    # 每个 ref 属于哪个 group（直接父 group）
    ref_to_group: Dict[str, str] = {}
    for gid, g in groups.items():
        for cid in g.get('children', []):
            if cid in file_refs:
                ref_to_group[cid] = gid
    # 每个 group 从根起的路径
    group_to_prefix: Dict[str, str] = {}

    def set_group_prefix(gid: str, prefix: str) -> None:
        if gid not in groups:
            return
        g = groups[gid]
        p = (g.get('path') or '').strip()
        here = f"{prefix}/{p}" if prefix else (p or '')
        here = here.strip('/')
        group_to_prefix[gid] = here
        for cid in g.get('children', []):
            if cid in groups:
                set_group_prefix(cid, here)

    set_group_prefix(main_group_id, '')

    for ref_id, file_path in file_refs.items():
        parent_gid = ref_to_group.get(ref_id)
        prefix = group_to_prefix.get(parent_gid, '') if parent_gid else ''
        full = f"{prefix}/{file_path}".strip('/') if prefix else file_path
        ref_to_full_path[ref_id] = full

    return ref_to_full_path


def get_files_from_xcodeproj(
    xcodeproj_path: str,
    project_root: Optional[str] = None,
) -> Tuple[List[Path], List[Path]]:
    """
    从 .xcodeproj 中读取被引用的源文件与资源文件路径。

    Args:
        xcodeproj_path: .xcodeproj 目录路径或 project.pbxproj 文件路径
        project_root: 项目根目录（用于解析相对路径），默认取 xcodeproj 父目录

    Returns:
        (code_files, resource_files) 均为绝对路径 Path 列表
    """
    path = Path(xcodeproj_path).resolve()
    if path.is_dir():
        pbxproj = path / "project.pbxproj"
    else:
        pbxproj = path
    if not pbxproj.exists():
        return [], []

    project_dir = Path(project_root).resolve() if project_root else pbxproj.parent.parent
    content = pbxproj.read_text(encoding='utf-8', errors='ignore')

    file_refs, groups, main_group_id, source_refs, resource_refs = _parse_pbxproj_content(content)
    ref_to_path = _resolve_paths(file_refs, groups, main_group_id, project_dir)

    code_extensions = {'.h', '.m', '.mm', '.swift', '.c', '.cpp'}
    resource_extensions = {'.png', '.jpg', '.jpeg', '.gif', '.bmp', '.tiff', '.xib', '.storyboard', '.xcassets', '.strings', '.json', '.pag', '.ttf'}

    code_files: List[Path] = []
    resource_files: List[Path] = []

    for ref_id in source_refs.values():
        rel = ref_to_path.get(ref_id) or file_refs.get(ref_id, '')
        if not rel:
            continue
        full = project_dir / rel
        if full.suffix.lower() in code_extensions and full.exists():
            code_files.append(full)

    for ref_id in resource_refs.values():
        rel = ref_to_path.get(ref_id) or file_refs.get(ref_id, '')
        if not rel:
            continue
        full = project_dir / rel
        suf = full.suffix.lower()
        if suf in resource_extensions or full.name.endswith('.xcassets') or (suf == '' and rel.endswith('.xcassets')):
            if full.exists():
                resource_files.append(full)
            elif full.suffix.lower() == '.xcassets':
                resource_files.append(full)

    # 去重并保持顺序
    seen_code: Set[Path] = set()
    code_files = [p for p in code_files if p not in seen_code and not seen_code.add(p)]
    seen_res: Set[Path] = set()
    resource_files = [p for p in resource_files if p not in seen_res and not seen_res.add(p)]

    return code_files, resource_files


def find_xcodeproj_in_dir(dir_path: str) -> Optional[Path]:
    """在目录下查找第一个 .xcodeproj。"""
    root = Path(dir_path)
    if not root.is_dir():
        return None
    for p in root.iterdir():
        if p.suffix == '.xcodeproj' and p.is_dir():
            return p.resolve()
    return None
