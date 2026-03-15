#!/usr/bin/env python3
# -*- coding: utf-8 -*-                 
"""
iOS无用代码及资源扫描器 - Agent Skill核心模块

功能：
1. 无用代码检测（类、方法、属性等）
2. 无用资源检测（图片、xib/storyboard等资源文件）
3. 精确引用关系分析
4. 多格式报告生成
5. Agent Skill标准接口支持

支持：Swift/Objective-C混合项目，CocoaPods依赖管理
"""

import os
import re
import json
import argparse
import fnmatch
import subprocess
import shutil
from pathlib import Path
from typing import List, Dict, Set, Tuple, Optional, Any
import html as html_module
import csv
from datetime import datetime
import logging

# 设置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class iOSUnusedScanner:
    """iOS无用代码及资源扫描器 - Agent Skill核心类"""
    
    def __init__(self, project_root: str = ".", config_file: Optional[str] = None):
        """
        初始化扫描器
        
        Args:
            project_root: iOS项目根目录路径
            config_file: 配置文件路径
        """
        self.project_root = Path(project_root).resolve()
        self.config_file = self._resolve_config_file(config_file)
        self.config = self._load_config()
        
        # 扫描结果存储
        self.unused_classes: List[Dict] = []
        self.unused_methods: List[Dict] = []
        self.unused_properties: List[Dict] = []
        self.unused_files: List[Dict] = []  # 新增：整个文件无用
        self.unused_images: List[Dict] = []
        self.unused_xibs: List[Dict] = []
        self.unused_storyboards: List[Dict] = []
        
        # 定义位置映射 (name -> file_path)
        self.class_definitions: Dict[str, Path] = {}
        self.method_definitions: Dict[str, List[Path]] = {}
        self.property_definitions: Dict[str, List[Path]] = {}
        
        # 文件级别的类定义映射
        self.file_class_definitions: Dict[Path, Set[str]] = {}
        
        # 引用关系存储
        self.class_references: Dict[str, Set[str]] = {}
        self.method_references: Dict[str, Set[str]] = {}
        self.resource_references: Dict[str, Set[str]] = {}
        
        # 父类映射（子类 -> 父类），用于引用传递闭包
        self.superclass_map: Dict[str, str] = {}
        # 引用类集合（含闭包后），供 _scan_unused_files 复用
        self.referenced_classes: Set[str] = set()
        
        # 扫描统计
        self.scan_stats = {
            'total_files_scanned': 0,
            'total_classes_found': 0,
            'total_methods_found': 0,
            'total_resources_found': 0,
            'scan_start_time': None,
            'scan_end_time': None,
            'scan_duration': 0
        }
        
        logger.info(f"iOSUnusedScanner初始化完成，项目根目录: {self.project_root}")
    
    def _resolve_config_file(self, config_file: Optional[str]) -> Optional[Path]:
        """解析配置文件路径：支持绝对/相对 cwd；为 None 时尝试 skill 根目录 assets/default.json"""
        skill_root = Path(__file__).resolve().parent.parent
        if config_file:
            p = Path(config_file)
            if p.exists():
                return p.resolve()
            if not p.is_absolute():
                alt = skill_root / p
                if alt.exists():
                    return alt.resolve()
            return None
        default_path = skill_root / 'assets' / 'default.json'
        return default_path if default_path.exists() else None
    
    def _is_class_whitelisted(self, class_name: str) -> bool:
        """判断类名是否在白名单中（精确匹配或 class_name_patterns 通配）"""
        if class_name in self.config['whitelist'].get('classes', []):
            return True
        patterns = self.config['whitelist'].get('class_name_patterns', [])
        for pat in patterns:
            if fnmatch.fnmatch(class_name, pat):
                return True
        return False
    
    def _load_config(self) -> Dict[str, Any]:
        """加载配置文件"""
        default_config = {
            'scan_config': {
                'project_root': str(self.project_root),
                'output_dir': 'unused_scan_results',
                'enable_code_scan': True,
                'enable_resource_scan': True,
                'enable_reference_analysis': True,
                'enable_method_scan': False,  # 默认关闭方法扫描
                'generate_html_report': True,
                'generate_csv_report': True,
                'sort_by_size': True,
                'min_file_size_bytes': 1024,
                'max_scan_depth': 10,
                # 文件数据源: "directory"=目录遍历, "xcodeproj"=从 .xcodeproj 引用
                'file_source': 'directory',
                'xcodeproj_path': None,  # 为 None 时在 project_root 下自动查找 .xcodeproj
            },
            'ignore_rules': {
                'ignore_directories': ['Pods', '.git', 'build', 'DerivedData', 'Carthage', '.clangd'],
                'ignore_files': ['main.m', 'AppDelegate.h', 'AppDelegate.m', 'main.swift', 'Podfile', 'Podfile.lock'],
                'ignore_file_patterns': ['*Test*.{h,m,swift}', '*Mock*.{h,m,swift}', '*Spec*.{h,m,swift}']
            },
            'whitelist': {
                # 仅保留通用 iOS/UIKit 基类；项目专属类请放在 assets/default.json 中
                'classes': [
                    'AppDelegate', 'ViewController', 'BaseViewController', 'UIViewController', 'UIView',
                    'BaseTableViewCell', 'BaseUICollectionViewCell', 'UITableViewCell', 'UICollectionViewCell',
                    'NSObject'
                ],
                'class_name_patterns': [
                    '*Base*ViewController', '*Base*VC', '*Base*Cell', '*Base*View',
                    'Base*', '*Base'
                ],
                'methods': ['viewDidLoad', 'viewWillAppear:', 'viewDidAppear:', 'application:didFinishLaunchingWithOptions:'],
                'properties': ['view', 'navigationController', 'title']
            },
            'code_extensions': ['.h', '.m', '.mm', '.c', '.cpp'],  # 默认不扫描 .swift，可在配置中加回
            'resource_extensions': ['.png', '.jpg', '.jpeg', '.gif', '.bmp', '.tiff', '.xib', '.storyboard', '.xcassets', '.strings', '.json']
        }
        
        if self.config_file and self.config_file.exists():
            try:
                with open(self.config_file, 'r', encoding='utf-8') as f:
                    user_config = json.load(f)
                    # 合并配置
                    self._merge_configs(default_config, user_config)
                    logger.info(f"已加载配置文件: {self.config_file}")
            except Exception as e:
                logger.warning(f"配置文件加载失败，使用默认配置: {e}")
        
        return default_config
    
    def _merge_configs(self, default: Dict, user: Dict) -> None:
        """合并配置"""
        for key, value in user.items():
            if key in default and isinstance(default[key], dict) and isinstance(value, dict):
                self._merge_configs(default[key], value)
            else:
                default[key] = value
    
    def scan(self, scan_type: str = "all") -> Dict[str, Any]:
        """
        执行扫描
        
        Args:
            scan_type: 扫描类型 ('all', 'code', 'resources')
            
        Returns:
            扫描结果字典
        """
        self.scan_stats['scan_start_time'] = datetime.now()
        logger.info(f"开始扫描，类型: {scan_type}")
        
        try:
            # 创建输出目录
            output_dir = Path(self.config['scan_config']['output_dir'])
            output_dir.mkdir(exist_ok=True)
            
            # 执行扫描
            if scan_type in ['all', 'code']:
                self._scan_unused_code()
                # 扫描整个文件无用的文件
                self._scan_unused_files()
            
            if scan_type in ['all', 'resources']:
                self._scan_unused_resources()
            
            # 分析引用关系
            if self.config['scan_config']['enable_reference_analysis']:
                self._analyze_reference_graph()
            
            self.scan_stats['scan_end_time'] = datetime.now()
            self.scan_stats['scan_duration'] = (
                self.scan_stats['scan_end_time'] - self.scan_stats['scan_start_time']
            ).total_seconds()
            
            # 生成结果
            results = self._generate_results()
            logger.info(f"扫描完成，耗时: {self.scan_stats['scan_duration']:.2f}秒")
            
            return results
            
        except Exception as e:
            logger.error(f"扫描过程中出现错误: {e}")
            return {
                'success': False,
                'error': str(e),
                'scan_stats': self.scan_stats
            }
    
    def _scan_unused_code(self) -> None:
        """扫描无用代码"""
        logger.info("开始扫描无用代码...")
        
        code_files = self._collect_files(self.config['code_extensions'])
        self.scan_stats['total_files_scanned'] += len(code_files)
        
        defined_classes = set()
        defined_methods = set()
        defined_properties = set()
        
        # 分析定义
        for file_path in code_files:
            self._analyze_code_file(file_path, defined_classes, defined_methods, defined_properties, file_path)
        
        self.scan_stats['total_classes_found'] = len(defined_classes)
        self.scan_stats['total_methods_found'] = len(defined_methods)
        
        # 分析引用
        referenced_classes = set()
        referenced_methods = set()
        referenced_properties = set()
        
        for file_path in code_files:
            self._analyze_references(file_path, referenced_classes, referenced_methods, referenced_properties)
        
        # 引用传递闭包：被引用类的所有父类也视为被引用（避免基类如 JXSubPageViewController 被误判）
        self._closure_referenced_classes_by_superclass(referenced_classes)
        self.referenced_classes = referenced_classes
        
        # 找出无用项（方法扫描改为可选）
        self._find_unused_items(defined_classes, referenced_classes, self.unused_classes, "class")
        if self.config['scan_config'].get('enable_method_scan', False):
            self._find_unused_items(defined_methods, referenced_methods, self.unused_methods, "method")
        self._find_unused_items(defined_properties, referenced_properties, self.unused_properties, "property")
        
        logger.info(f"代码扫描完成: 类={len(defined_classes)}, 方法={len(defined_methods)}, 无用类={len(self.unused_classes)}, 无用方法={len(self.unused_methods)}")
    
    def _scan_unused_files(self) -> None:
        """扫描整个文件无用的文件；OC 仅以 .m/.mm 实现文件形式列出一条，不单独列出 .h"""
        logger.info("开始扫描整个文件无用的文件...")
        
        code_files = self._collect_files(self.config['code_extensions'])
        
        # 使用与无用类一致的引用集合（含父类闭包），避免基类所在文件被误判为无用文件
        referenced_classes = self.referenced_classes
        
        # OC：已按“实现文件”合并过的路径，避免 .h 与 .m 重复列出
        added_impl_paths: Set[Path] = set()
        
        # 检查每个文件中的类是否都被引用
        for file_path, classes in self.file_class_definitions.items():
            if not classes:
                continue
            
            # 如果文件中的所有类都没有被引用，则整个文件无用
            if all(cls not in referenced_classes for cls in classes):
                try:
                    # OC：报告统一用实现文件 .m/.mm；若当前是 .h 且对应 .m 已加入则跳过
                    display_path = self._prefer_impl_path_for_oc(file_path)
                    if display_path in added_impl_paths:
                        continue
                    if file_path.suffix.lower() == '.h' and display_path != file_path:
                        added_impl_paths.add(display_path)
                        file_path = display_path
                    elif file_path.suffix.lower() in ('.m', '.mm'):
                        added_impl_paths.add(file_path)
                    
                    file_size = file_path.stat().st_size
                    relative_path = str(file_path.relative_to(self.project_root))
                    
                    self.unused_files.append({
                        'name': file_path.name,
                        'type': 'file',
                        'size': file_size,
                        'path': relative_path,
                        'full_path': str(file_path),
                        'classes_count': len(classes)
                    })
                    added_impl_paths.add(file_path)
                except Exception as e:
                    logger.warning(f"无法获取文件信息 {file_path}: {e}")
    
    def _scan_unused_resources(self) -> None:
        """扫描无用资源"""
        logger.info("开始扫描无用资源...")
        
        resource_files = self._collect_files(self.config['resource_extensions'])
        self.scan_stats['total_files_scanned'] += len(resource_files)
        self.scan_stats['total_resources_found'] = len(resource_files)
        
        code_files = self._collect_files(self.config['code_extensions'])
        referenced_resources = set()
        
        # 分析资源引用
        for file_path in code_files:
            self._analyze_resource_references(file_path, referenced_resources)
        
        # 找出无用资源
        for resource_path in resource_files:
            resource_name = resource_path.name
            relative_path = str(resource_path.relative_to(self.project_root))
            
            is_referenced = False
            for referenced in referenced_resources:
                if referenced in resource_name or resource_name in referenced:
                    is_referenced = True
                    break
            
            if not is_referenced:
                file_size = resource_path.stat().st_size
                
                resource_info = {
                    'name': resource_name,
                    'path': relative_path,
                    'size': file_size,
                    'type': self._get_resource_type(resource_path),
                    'full_path': str(resource_path)
                }
                
                if resource_path.suffix == '.xcassets':
                    self.unused_images.append(resource_info)
                elif resource_path.suffix == '.xib':
                    self.unused_xibs.append(resource_info)
                elif resource_path.suffix == '.storyboard':
                    self.unused_storyboards.append(resource_info)
        
        logger.info(f"资源扫描完成: 资源文件={len(resource_files)}, 无用图片={len(self.unused_images)}, 无用界面文件={len(self.unused_xibs) + len(self.unused_storyboards)}")
    
    def _get_xcodeproj_files(self) -> Tuple[List[Path], List[Path]]:
        """从 .xcodeproj 获取代码与资源文件列表（带缓存）。"""
        if getattr(self, '_xcodeproj_cache', None) is not None:
            return self._xcodeproj_cache
        try:
            try:
                from scripts.xcodeproj_parser import get_files_from_xcodeproj, find_xcodeproj_in_dir
            except ImportError:
                from xcodeproj_parser import get_files_from_xcodeproj, find_xcodeproj_in_dir
            xcodeproj_path = self.config['scan_config'].get('xcodeproj_path')
            if not xcodeproj_path:
                xcodeproj_path = find_xcodeproj_in_dir(str(self.project_root))
                if not xcodeproj_path:
                    logger.warning("file_source=xcodeproj 但未找到 .xcodeproj，回退为目录扫描")
                    self._xcodeproj_cache = ([], [])
                    return self._xcodeproj_cache
                xcodeproj_path = str(xcodeproj_path)
            code_files, resource_files = get_files_from_xcodeproj(xcodeproj_path, str(self.project_root))
            self._xcodeproj_cache = (code_files, resource_files)
            logger.info(f"从 xcodeproj 加载: 代码文件 {len(code_files)}, 资源文件 {len(resource_files)}")
            return self._xcodeproj_cache
        except Exception as e:
            logger.warning(f"xcodeproj 解析失败，回退为目录扫描: {e}")
            self._xcodeproj_cache = ([], [])
            return self._xcodeproj_cache
    
    def _collect_files(self, extensions: List[str]) -> List[Path]:
        """收集指定扩展名的文件。数据源由 scan_config.file_source 决定：directory=目录遍历，xcodeproj=工程引用。"""
        file_source = self.config['scan_config'].get('file_source', 'directory')
        ignore_files = self.config['ignore_rules']['ignore_files']
        
        if file_source == 'xcodeproj':
            code_files, resource_files = self._get_xcodeproj_files()
            code_ext = set(self.config.get('code_extensions', ['.h', '.m', '.mm', '.c', '.cpp']))
            ext_set = {e.lower() for e in extensions}
            if ext_set & code_ext:
                files = [p for p in code_files if p.suffix.lower() in ext_set]
            else:
                files = [p for p in resource_files if p.suffix.lower() in ext_set]
            ignore_patterns = self._expand_ignore_patterns(
                self.config['ignore_rules'].get('ignore_file_patterns', [])
            )
            def skip(name): return name in ignore_files or any(fnmatch.fnmatch(name, pat) for pat in ignore_patterns)
            files = [p for p in files if not skip(p.name)]
            return files
        
        # 展开 ignore_file_patterns 中的 {a,b,c} 为多条 pattern
        ignore_patterns = self._expand_ignore_patterns(
            self.config['ignore_rules'].get('ignore_file_patterns', [])
        )
        
        def should_ignore_file(name: str) -> bool:
            if name in ignore_files:
                return True
            for pat in ignore_patterns:
                if fnmatch.fnmatch(name, pat):
                    return True
            return False
        
        files = []
        ignore_dirs = self.config['ignore_rules']['ignore_directories']
        for root, dirs, filenames in os.walk(self.project_root):
            dirs[:] = [d for d in dirs if d not in ignore_dirs]
            for filename in filenames:
                file_path = Path(root) / filename
                if file_path.suffix.lower() in extensions:
                    if not should_ignore_file(filename):
                        files.append(file_path)
        return files
    
    def _expand_ignore_patterns(self, patterns: List[str]) -> List[str]:
        """将 *Test*.{h,m,swift} 展开为 *Test*.h, *Test*.m, *Test*.swift 等，供 fnmatch 使用"""
        result = []
        for p in patterns:
            m = re.search(r'\{([^}]+)\}', p)
            if m:
                for part in m.group(1).split(','):
                    part = part.strip()
                    result.append(re.sub(r'\{[^}]+\}', part, p, count=1))
            else:
                result.append(p)
        return result
    
    def _analyze_code_file(self, file_path: Path, 
                          defined_classes: Set[str], 
                          defined_methods: Set[str], 
                          defined_properties: Set[str],
                          source_file: Path) -> None:
        """分析代码文件中的定义"""
        try:
            content = file_path.read_text(encoding='utf-8', errors='ignore')
            
            if file_path.suffix in {'.h', '.m', '.mm'}:
                self._analyze_objc_definitions(content, file_path, defined_classes, defined_methods, defined_properties, source_file)
            elif file_path.suffix == '.swift':
                self._analyze_swift_definitions(content, file_path, defined_classes, defined_methods, defined_properties, source_file)
                
        except Exception as e:
            logger.warning(f"无法分析文件 {file_path}: {e}")
    
    def _analyze_objc_definitions(self, content: str, file_path: Path,
                                 defined_classes: Set[str], 
                                 defined_methods: Set[str], 
                                 defined_properties: Set[str],
                                 source_file: Path) -> None:
        """分析Objective-C定义"""
        # 初始化文件类定义集合
        if source_file not in self.file_class_definitions:
            self.file_class_definitions[source_file] = set()
        
        # 类定义匹配
        class_patterns = [
            r'@interface\s+(\w+)\s*:',
            r'@implementation\s+(\w+)',
        ]
        
        for pattern in class_patterns:
            for match in re.finditer(pattern, content):
                class_name = match.group(1)
                if not self._is_class_whitelisted(class_name):
                    defined_classes.add(class_name)
                    self.class_definitions[class_name] = source_file
                    self.file_class_definitions[source_file].add(class_name)
        
        # 父类映射：@interface ChildClass : ParentClass（仅主接口声明，不含 () 扩展）
        objc_super_pattern = r'@interface\s+(\w+)\s*:\s*(\w+)'
        for match in re.finditer(objc_super_pattern, content):
            child, parent = match.group(1), match.group(2)
            self.superclass_map[child] = parent
        
        # 方法定义匹配
        method_patterns = [
            r'[-+]\s*\([^)]+\)\s*(\w+)',
        ]
        
        for pattern in method_patterns:
            for match in re.finditer(pattern, content):
                method_name = match.group(1)
                if method_name not in self.config['whitelist']['methods']:
                    defined_methods.add(method_name)
                    if method_name not in self.method_definitions:
                        self.method_definitions[method_name] = []
                    self.method_definitions[method_name].append(source_file)
        
        # 属性定义匹配
        property_pattern = r'@property\s*\([^)]+\)\s*[^\s]+\s*\*?\s*(\w+)\s*;'
        for match in re.finditer(property_pattern, content):
            property_name = match.group(1)
            defined_properties.add(property_name)
            if property_name not in self.property_definitions:
                self.property_definitions[property_name] = []
            self.property_definitions[property_name].append(source_file)
    
    def _analyze_swift_definitions(self, content: str, file_path: Path,
                                  defined_classes: Set[str], 
                                  defined_methods: Set[str], 
                                  defined_properties: Set[str],
                                  source_file: Path) -> None:
        """分析Swift定义"""
        # 初始化文件类定义集合
        if source_file not in self.file_class_definitions:
            self.file_class_definitions[source_file] = set()
        
        # 类定义匹配
        class_patterns = [
            r'class\s+(\w+)\s*[:{]',
            r'struct\s+(\w+)\s*[:{]',
            r'enum\s+(\w+)\s*[:{]',
        ]
        
        for pattern in class_patterns:
            for match in re.finditer(pattern, content):
                class_name = match.group(1)
                if not self._is_class_whitelisted(class_name):
                    defined_classes.add(class_name)
                    self.class_definitions[class_name] = source_file
                    self.file_class_definitions[source_file].add(class_name)
        
        # 父类映射：class/struct Name : SuperClassOrProtocol
        swift_super_pattern = r'(?:class|struct)\s+(\w+)\s*:\s*(\w+)'
        for match in re.finditer(swift_super_pattern, content):
            child, parent = match.group(1), match.group(2)
            self.superclass_map[child] = parent
        
        # 方法定义匹配
        method_pattern = r'func\s+(\w+)\s*\('
        for match in re.finditer(method_pattern, content):
            method_name = match.group(1)
            if method_name not in self.config['whitelist']['methods']:
                defined_methods.add(method_name)
                if method_name not in self.method_definitions:
                    self.method_definitions[method_name] = []
                self.method_definitions[method_name].append(source_file)
        
        # 属性定义匹配
        property_patterns = [
            r'var\s+(\w+)\s*[:=]',
            r'let\s+(\w+)\s*[:=]',
        ]
        
        for pattern in property_patterns:
            for match in re.finditer(pattern, content):
                property_name = match.group(1)
                defined_properties.add(property_name)
                if property_name not in self.property_definitions:
                    self.property_definitions[property_name] = []
                self.property_definitions[property_name].append(source_file)
    
    def _closure_referenced_classes_by_superclass(self, referenced_classes: Set[str]) -> None:
        """引用传递闭包：被引用类的所有父类也视为被引用（子类被 alloc 则父类不应判为无用）"""
        changed = True
        while changed:
            changed = False
            for cls in list(referenced_classes):
                parent = self.superclass_map.get(cls)
                if parent and parent not in referenced_classes:
                    referenced_classes.add(parent)
                    changed = True
                    logger.debug(f"引用闭包: {cls} -> 父类 {parent} 视为已引用")
    
    def _analyze_references(self, file_path: Path, 
                           referenced_classes: Set[str], 
                           referenced_methods: Set[str], 
                           referenced_properties: Set[str]) -> None:
        """分析代码文件中的引用"""
        try:
            content = file_path.read_text(encoding='utf-8', errors='ignore')
            
            # 移除注释的代码（简单处理）
            content = self._remove_comments(content, file_path.suffix)
            
            # 1. 类引用 - Objective-C消息发送 [[ClassName ...]
            class_ref_pattern = r'\[\s*(\w+)\s+[^]]+\]'
            for match in re.finditer(class_ref_pattern, content):
                referenced_classes.add(match.group(1))
            
            # 2. 类方法调用 - [ClassName methodName]
            class_method_pattern = r'\[\s*(\w+)\s+(\w+)'
            for match in re.finditer(class_method_pattern, content):
                referenced_classes.add(match.group(1))
            
            # 3. alloc/new 方式 - [[ClassName alloc] init]
            alloc_pattern = r'\[\[\s*(\w+)\s+alloc\s*\]'
            for match in re.finditer(alloc_pattern, content):
                referenced_classes.add(match.group(1))
            
            # 4. new 方式 - [ClassName new]
            new_pattern = r'\[\s*(\w+)\s+new\s*\]'
            for match in re.finditer(new_pattern, content):
                referenced_classes.add(match.group(1))
            
            # 5. 点语法类方法调用 - ClassName.alloc / A.alloc / ClassName.new / ClassName.shared 等
            dot_class_method_pattern = r'\b(\w+)\.(?:alloc|new|shared|sharedInstance|allocWithZone)\b'
            for match in re.finditer(dot_class_method_pattern, content):
                referenced_classes.add(match.group(1))
            
            # 6. NSStringFromClass 方式 - NSStringFromClass(ClassName.class)
            nsstringfromclass_pattern = r'NSStringFromClass\s*\(\s*(\w+)\s*\.\s*class\s*\)'
            for match in re.finditer(nsstringfromclass_pattern, content):
                referenced_classes.add(match.group(1))
            
            # 7. 类型转换 - (ClassName *)
            typecast_pattern = r'\(\s*(\w+)\s*\*\s*\)'
            for match in re.finditer(typecast_pattern, content):
                # 过滤掉基本类型
                class_name = match.group(1)
                if class_name not in {'void', 'int', 'float', 'double', 'char', 'bool', 'long', 'short', 'unsigned', 'signed'}:
                    referenced_classes.add(class_name)
            
            # 8. 属性声明中的类型 - @property (nonatomic, strong) ClassName *property
            property_type_pattern = r'@property\s*\([^)]+\)\s*(\w+)\s*\*'
            for match in re.finditer(property_type_pattern, content):
                referenced_classes.add(match.group(1))
            
            # 9. 方法参数类型 - (void)methodName:(ClassName *)param
            method_param_pattern = r':\s*\(\s*(\w+)\s*\*\s*\)'
            for match in re.finditer(method_param_pattern, content):
                class_name = match.group(1)
                if class_name not in {'void', 'int', 'float', 'double', 'char', 'bool', 'long', 'short', 'unsigned', 'signed'}:
                    referenced_classes.add(class_name)
            
            # 10. 方法调用
            method_call_pattern = r'\[\s*[^\s]+\s+(\w+)\]'
            for match in re.finditer(method_call_pattern, content):
                referenced_methods.add(match.group(1))
            
            # 11. 点语法方法调用（实例/类方法）
            swift_method_pattern = r'\.\s*(\w+)\s*\('
            for match in re.finditer(swift_method_pattern, content):
                referenced_methods.add(match.group(1))
            
            # 12. 父类引用 - @interface ChildClass : ParentClass（ObjC）
            objc_superclass_pattern = r'@interface\s+\w+\s*:\s*(\w+)'
            for match in re.finditer(objc_superclass_pattern, content):
                referenced_classes.add(match.group(1))
            
            # 13. 父类/协议引用 - class/struct Name : SuperClassOrProtocol（Swift）
            swift_superclass_pattern = r'(?:class|struct)\s+\w+\s*:\s*(\w+)'
            for match in re.finditer(swift_superclass_pattern, content):
                referenced_classes.add(match.group(1))
                
        except Exception as e:
            logger.warning(f"无法分析引用 {file_path}: {e}")
    
    def _analyze_resource_references(self, file_path: Path, referenced_resources: Set[str]) -> None:
        """分析资源文件引用"""
        try:
            content = file_path.read_text(encoding='utf-8', errors='ignore')
            
            # 图片引用匹配
            image_patterns = [
                r'UIImage\s*imageNamed:\s*@"([^"]+)"',
                r'UIImage\(named:\s*"([^"]+)"\)',
                r'image\s*=\s*"([^"]+)"',
            ]
            
            for pattern in image_patterns:
                for match in re.finditer(pattern, content):
                    referenced_resources.add(match.group(1))
            
            # xib/storyboard引用
            xib_patterns = [
                r'UINib\s*nibWithNibName:\s*@"([^"]+)"',
                r'UIStoryboard\s*storyboardWithName:\s*@"([^"]+)"',
            ]
            
            for pattern in xib_patterns:
                for match in re.finditer(pattern, content):
                    referenced_resources.add(match.group(1))
                    
        except Exception as e:
            logger.warning(f"无法分析资源引用 {file_path}: {e}")
    
    def _prefer_impl_path_for_oc(self, file_path: Path) -> Path:
        """OC 报告优先使用实现文件：.h 对应为同名的 .m 或 .mm（若存在），否则保持原路径"""
        if file_path.suffix.lower() != '.h':
            return file_path
        stem = file_path.stem
        parent = file_path.parent
        for ext in ('.m', '.mm'):
            impl = parent / (stem + ext)
            if impl.exists():
                return impl
        return file_path
    
    def _find_unused_items(self, defined: Set[str], referenced: Set[str], 
                          result_list: List[Dict], item_type: str) -> None:
        """找出未使用的项目"""
        unused_items = defined - referenced
        
        for item in unused_items:
            # 类：白名单基类不视为无用（双重保护）
            if item_type == 'class' and self._is_class_whitelisted(item):
                continue
            # 获取定义位置
            file_path = None
            file_size = 0
            relative_path = f"Unknown ({item_type})"
            full_path = f"Unknown ({item_type})"
            
            if item_type == 'class' and item in self.class_definitions:
                file_path = self.class_definitions[item]
            elif item_type == 'method' and item in self.method_definitions:
                file_path = self.method_definitions[item][0] if self.method_definitions[item] else None
            elif item_type == 'property' and item in self.property_definitions:
                file_path = self.property_definitions[item][0] if self.property_definitions[item] else None
            
            if file_path and file_path.exists():
                try:
                    # OC 类/方法/属性：报告路径优先使用 .m/.mm 实现文件
                    display_path = self._prefer_impl_path_for_oc(file_path)
                    # 对于类和方法，大小设为0；只有文件类型才显示大小
                    if item_type in ['class', 'method', 'property']:
                        file_size = 0
                    else:
                        file_size = file_path.stat().st_size
                    
                    relative_path = str(display_path.relative_to(self.project_root))
                    full_path = str(display_path)
                except Exception as e:
                    logger.warning(f"无法获取文件信息 {file_path}: {e}")
            
            result_list.append({
                'name': item,
                'type': item_type,
                'size': file_size,
                'path': relative_path,
                'full_path': full_path
            })
    
    def _remove_comments(self, content: str, file_suffix: str) -> str:
        """移除代码中的注释"""
        if file_suffix in {'.h', '.m', '.mm', '.c', '.cpp'}:
            # 移除单行注释 //
            content = re.sub(r'//.*?$', '', content, flags=re.MULTILINE)
            # 移除多行注释 /* ... */
            content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
        elif file_suffix == '.swift':
            # 移除单行注释 //
            content = re.sub(r'//.*?$', '', content, flags=re.MULTILINE)
            # 移除多行注释 /* ... */
            content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
        
        return content
    
    def _get_resource_type(self, file_path: Path) -> str:
        """获取资源类型"""
        suffix = file_path.suffix.lower()
        if suffix in {'.png', '.jpg', '.jpeg', '.gif', '.bmp', '.tiff'}:
            return 'image'
        elif suffix == '.xib':
            return 'xib'
        elif suffix == '.storyboard':
            return 'storyboard'
        elif suffix == '.xcassets':
            return 'asset catalog'
        elif suffix == '.strings':
            return 'localization'
        else:
            return 'other'
    
    def _analyze_reference_graph(self) -> None:
        """分析引用关系图"""
        logger.info("分析引用关系图...")
        # 这里可以集成更专业的静态分析工具
        pass
    
    def _generate_results(self) -> Dict[str, Any]:
        """生成扫描结果"""
        return {
            'success': True,
            'scan_stats': self.scan_stats,
            'unused_classes': self.unused_classes,
            'unused_methods': self.unused_methods,
            'unused_properties': self.unused_properties,
            'unused_files': self.unused_files,
            'unused_images': self.unused_images,
            'unused_xibs': self.unused_xibs,
            'unused_storyboards': self.unused_storyboards,
            'total_unused_items': (
                len(self.unused_classes) + len(self.unused_methods) + len(self.unused_properties) +
                len(self.unused_files) + len(self.unused_images) + len(self.unused_xibs) + len(self.unused_storyboards)
            )
        }
    
    def generate_reports(self, output_dir: Optional[str] = None, 
                        formats: List[str] = None) -> Dict[str, str]:
        """
        生成报告
        
        Args:
            output_dir: 输出目录
            formats: 报告格式列表
            
        Returns:
            报告文件路径字典
        """
        if formats is None:
            formats = ['html', 'csv', 'json']
        if 'all' in formats:
            formats = ['html', 'csv', 'json']
        
        if output_dir is None:
            output_dir = self.config['scan_config']['output_dir']
        
        output_path = Path(output_dir)
        output_path.mkdir(exist_ok=True)
        
        report_files = {}
        
        if 'html' in formats:
            html_file = output_path / "unused_scan_report.html"
            self._generate_html_report(html_file)
            report_files['html'] = str(html_file)
        
        if 'csv' in formats:
            csv_file = output_path / "unused_scan_report.csv"
            self._generate_csv_report(csv_file)
            report_files['csv'] = str(csv_file)
        
        if 'json' in formats:
            json_file = output_path / "scan_summary.json"
            self._generate_json_summary(json_file)
            report_files['json'] = str(json_file)
        
        logger.info(f"报告生成完成: {report_files}")
        return report_files
    
    def _generate_html_report(self, output_file: Path) -> None:
        """生成HTML报告"""
        # 按目录组织数据
        directory_tree = self._build_directory_tree()
        
        # 计算总大小
        total_size = sum(item.get('size', 0) for item in 
                        self.unused_classes + self.unused_methods + self.unused_properties +
                        self.unused_files + self.unused_images + self.unused_xibs + self.unused_storyboards)
        
        # 生成HTML
        html_content = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>iOS无用代码及资源扫描报告</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{ 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;
            background: #f5f7fa;
            padding: 20px;
            line-height: 1.6;
        }}
        .container {{ max-width: 1400px; margin: 0 auto; }}
        .header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }}
        .header h1 {{ font-size: 32px; margin-bottom: 10px; }}
        .header p {{ opacity: 0.9; font-size: 14px; }}
        .stats {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }}
        .stat-card {{
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            border-left: 4px solid #667eea;
        }}
        .stat-card h3 {{ color: #666; font-size: 14px; margin-bottom: 10px; }}
        .stat-card .number {{ font-size: 32px; font-weight: bold; color: #333; }}
        .stat-card .label {{ color: #999; font-size: 12px; margin-top: 5px; }}
        .section {{
            background: white;
            padding: 25px;
            border-radius: 8px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        .section h2 {{
            font-size: 20px;
            margin-bottom: 20px;
            color: #333;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }}
        .directory-tree {{
            font-family: 'Monaco', 'Menlo', 'Courier New', monospace;
            font-size: 13px;
        }}
        .directory {{
            margin-left: 20px;
            border-left: 1px solid #e0e0e0;
            padding-left: 15px;
            margin-top: 5px;
        }}
        .directory-name {{
            color: #667eea;
            font-weight: bold;
            cursor: pointer;
            padding: 5px 0;
            display: flex;
            align-items: center;
        }}
        .directory-name:hover {{ background: #f5f7fa; }}
        .directory-name::before {{
            content: '📁';
            margin-right: 8px;
        }}
        .file-item {{
            padding: 8px 0;
            border-bottom: 1px solid #f0f0f0;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }}
        .file-item:hover {{ background: #f9f9f9; }}
        .file-name {{
            flex: 1;
            color: #333;
            display: flex;
            align-items: center;
        }}
        .file-name::before {{
            content: '📄';
            margin-right: 8px;
        }}
        .file-type {{
            display: inline-block;
            padding: 2px 8px;
            border-radius: 3px;
            font-size: 11px;
            margin-left: 10px;
            font-weight: 500;
        }}
        .type-class {{ background: #e3f2fd; color: #1976d2; }}
        .type-method {{ background: #f3e5f5; color: #7b1fa2; }}
        .type-property {{ background: #fff3e0; color: #f57c00; }}
        .type-resource {{ background: #e8f5e9; color: #388e3c; }}
        .file-size {{
            color: #999;
            font-size: 12px;
            margin-left: 15px;
            min-width: 80px;
            text-align: right;
        }}
        .toggle {{
            cursor: pointer;
            user-select: none;
            margin-right: 5px;
            display: inline-block;
            width: 16px;
            text-align: center;
        }}
        .collapsed {{ display: none; }}
        .hidden {{ display: none !important; }}
        .directory.hidden {{ display: none !important; }}
        .search-highlight {{ background-color: #fff3cd; }}
        .type-file {{ background: #e8f5e9; color: #388e3c; }}
        .filter-controls {{ 
            display: flex; 
            gap: 15px; 
            flex-wrap: wrap; 
            margin-bottom: 15px;
        }}
        .filter-controls label {{
            display: flex;
            align-items: center;
            cursor: pointer;
            padding: 5px 10px;
            background: #f5f7fa;
            border-radius: 4px;
        }}
        .filter-controls input {{ margin-right: 5px; }}
        .summary-table {{
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }}
        .summary-table th, .summary-table td {{
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #e0e0e0;
        }}
        .summary-table th {{
            background: #f5f7fa;
            font-weight: 600;
            color: #666;
        }}
        .summary-table tr:hover {{ background: #f9f9f9; }}
        .badge {{
            display: inline-block;
            padding: 4px 10px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: 500;
        }}
        .badge-danger {{ background: #ffebee; color: #c62828; }}
        .badge-warning {{ background: #fff3e0; color: #ef6c00; }}
        .badge-info {{ background: #e3f2fd; color: #1565c0; }}
    </style>
    <script>
        function toggleDirectory(id) {{
            const element = document.getElementById(id);
            const toggle = document.getElementById('toggle-' + id);
            if (element.classList.contains('collapsed')) {{
                element.classList.remove('collapsed');
                toggle.textContent = '▼';
            }} else {{
                element.classList.add('collapsed');
                toggle.textContent = '▶';
            }}
        }}
        
        function sortDirectoryTree(sortBy) {{
            document.querySelectorAll('.directory-tree .directory > div[id]').forEach(contentDiv => {{
                const children = Array.from(contentDiv.children).filter(el =>
                    el.classList.contains('directory') || el.classList.contains('file-item'));
                if (children.length === 0) return;
                const sorted = children.slice().sort((a, b) => {{
                    const aName = (a.dataset.name || '').toLowerCase();
                    const bName = (b.dataset.name || '').toLowerCase();
                    const aSize = parseInt(a.dataset.size || '0', 10);
                    const bSize = parseInt(b.dataset.size || '0', 10);
                    if (sortBy === 'name') return aName.localeCompare(bName, 'zh-CN');
                    return bSize - aSize;
                }});
                sorted.forEach(el => contentDiv.appendChild(el));
            }});
        }}
        
        function performSearch() {{
            const searchTerm = document.getElementById('searchInput').value.toLowerCase();
            const filterFile = document.getElementById('filterFile').checked;
            const filterResource = document.getElementById('filterResource').checked;
            
            const fileItems = document.querySelectorAll('.file-item');
            let visibleCount = 0;
            
            fileItems.forEach(item => {{
                const itemType = item.getAttribute('data-type');
                const itemName = (item.getAttribute('data-name') || '').toLowerCase();
                const itemPath = (item.getAttribute('data-path') || '').toLowerCase();
                
                let typeVisible = false;
                if (itemType === 'file' && filterFile) typeVisible = true;
                if (['image', 'xib', 'storyboard', 'resource'].includes(itemType) && filterResource) typeVisible = true;
                
                const matchesSearch = searchTerm === '' || 
                    itemName.includes(searchTerm) || 
                    itemPath.includes(searchTerm);
                
                const shouldShow = typeVisible && matchesSearch;
                
                if (shouldShow) {{
                    item.classList.remove('hidden');
                    visibleCount++;
                }} else {{
                    item.classList.add('hidden');
                }}
            }});
            
            // 从叶到根隐藏“空节点”：无可见文件且无可见子目录的目录不展示
            const dirs = Array.from(document.querySelectorAll('.directory-tree .directory'));
            dirs.reverse().forEach(dir => {{
                const content = dir.querySelector('div[id]');
                if (!content) return;
                const hasVisibleFile = content.querySelector('.file-item:not(.hidden)');
                const hasVisibleChildDir = content.querySelector('.directory:not(.hidden)');
                if (!hasVisibleFile && !hasVisibleChildDir) {{
                    dir.classList.add('hidden');
                }} else {{
                    dir.classList.remove('hidden');
                }}
            }});
            
            const searchStats = document.getElementById('searchStats');
            if (searchStats) {{
                searchStats.textContent = searchTerm ? '找到 ' + visibleCount + ' 个匹配项' : '';
            }}
        }}
        
        // 初始化搜索功能
        document.addEventListener('DOMContentLoaded', function() {{
            const searchInput = document.getElementById('searchInput');
            const filters = document.querySelectorAll('input[type="checkbox"]');
            
            if (searchInput) {{
                searchInput.addEventListener('input', performSearch);
            }}
            filters.forEach(filter => {{
                filter.addEventListener('change', performSearch);
            }});
        }});
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 iOS无用代码及资源扫描报告</h1>
            <p>扫描时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} | 项目路径: {self.project_root}</p>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <h3>无用类</h3>
                <div class="number">{len(self.unused_classes)}</div>
                <div class="label">Classes</div>
            </div>
            <div class="stat-card">
                <h3>无用文件</h3>
                <div class="number">{len(self.unused_files)}</div>
                <div class="label">Files</div>
            </div>
            <div class="stat-card">
                <h3>无用资源</h3>
                <div class="number">{len(self.unused_images) + len(self.unused_xibs) + len(self.unused_storyboards)}</div>
                <div class="label">Resources</div>
            </div>
            <div class="stat-card">
                <h3>总计</h3>
                <div class="number">{len(self.unused_classes) + len(self.unused_methods) + len(self.unused_files) + len(self.unused_images) + len(self.unused_xibs) + len(self.unused_storyboards)}</div>
                <div class="label">Total Items</div>
            </div>
            <div class="stat-card">
                <h3>文件大小</h3>
                <div class="number">{self._format_size(total_size)}</div>
                <div class="label">Total Size</div>
            </div>
        </div>
        
        <div class="section">
            <h2>🔍 搜索与筛选</h2>
            <div style="margin-bottom: 20px;">
                <input type="text" id="searchInput" placeholder="搜索文件名、类名或路径..." style="
                    width: 100%;
                    padding: 12px;
                    border: 1px solid #ddd;
                    border-radius: 6px;
                    font-size: 14px;
                    margin-bottom: 10px;
                ">
                <div style="display: flex; gap: 10px; flex-wrap: wrap;">
                    <label style="display: flex; align-items: center; cursor: pointer;">
                        <input type="checkbox" id="filterFile" checked> 文件
                    </label>
                    <label style="display: flex; align-items: center; cursor: pointer;">
                        <input type="checkbox" id="filterResource" checked> 资源
                    </label>
                </div>
                <div id="searchStats" style="color: #666; font-size: 14px; margin-top: 10px;"></div>
            </div>
        </div>
        
        <div class="section">
            <h2>📁 按目录结构查看</h2>
            <div class="sort-control" style="margin-bottom: 16px;">
                <label>排序：</label>
                <select id="treeSort" onchange="sortDirectoryTree(this.value)">
                    <option value="size">按大小（大到小）</option>
                    <option value="name">按名称</option>
                </select>
            </div>
            <div class="directory-tree">
                {self._generate_directory_tree_html(directory_tree)}
            </div>
        </div>
        
        <div class="section">
            <h2>📋 详细列表</h2>
            {self._generate_detailed_tables_html()}
        </div>
    </div>
</body>
</html>"""
        
        output_file.write_text(html_content, encoding='utf-8')
    
    def _build_directory_tree(self) -> Dict:
        """构建目录树结构，包含文件夹大小汇总"""
        tree = {}
        
        # 仅包含文件和资源，不包含类、方法、属性
        all_items = (self.unused_files + self.unused_images + self.unused_xibs + self.unused_storyboards)
        
        for item in all_items:
            path = item.get('path', '')
            if path.startswith('Unknown'):
                continue
            
            parts = Path(path).parts
            if len(parts) == 1:
                if '_root' not in tree:
                    tree['_root'] = {
                        '_dirs': {}, '_files': [], '_total_size': 0, '_file_count': 0
                    }
                tree['_root']['_files'].append(item)
                tree['_root']['_total_size'] += item.get('size', 0)
                tree['_root']['_file_count'] += 1
                continue
            
            current = tree
            for i, part in enumerate(parts[:-1]):
                if part not in current:
                    current[part] = {
                        '_dirs': {}, '_files': [], '_total_size': 0, '_file_count': 0
                    }
                current[part]['_total_size'] += item.get('size', 0)
                current[part]['_file_count'] += 1
                # 最后一级目录：文件挂到该目录下，避免再建同名空节点
                if i == len(parts[:-1]) - 1:
                    current[part]['_files'].append(item)
                current = current[part]['_dirs']
        
        return tree
    
    def _generate_directory_tree_html(self, tree: Dict, level: int = 0, parent_id: str = '') -> str:
        """生成目录树HTML，包含文件夹大小汇总"""
        html = []
        dir_counter = 0
        
        for key, value in sorted(tree.items()):
            if key.startswith('_'):
                continue
            
            dir_id = f"{parent_id}_{key}_{level}_{dir_counter}"
            dir_counter += 1
            
            # 获取文件夹统计信息
            total_size = value.get('_total_size', 0)
            file_count = value.get('_file_count', 0)
            
            # 目录名（包含大小信息）；data-name/data-size 供前端排序
            html.append(f'<div class="directory" data-name="{html_module.escape(key)}" data-size="{total_size}">')
            html.append(f'<div class="directory-name" onclick="toggleDirectory(\'{dir_id}\')">')
            html.append(f'<span class="toggle" id="toggle-{dir_id}">▼</span>')
            html.append(f'<span style="flex: 1;">{key}/</span>')
            html.append(f'<span style="color: #999; font-size: 12px; margin-left: 10px;">')
            html.append(f'{file_count} 项, {self._format_size(total_size)}')
            html.append(f'</span>')
            html.append(f'</div>')
            
            # 目录内容
            html.append(f'<div id="{dir_id}">')
            
            # 递归处理子目录
            if '_dirs' in value and value['_dirs']:
                html.append(self._generate_directory_tree_html(value['_dirs'], level + 1, dir_id))
            
            # 文件列表
            if '_files' in value and value['_files']:
                for file_item in sorted(value['_files'], key=lambda x: x.get('size', 0), reverse=True):
                    item_type = file_item.get('type', 'unknown')
                    type_class = f'type-{item_type}' if item_type in ['class', 'method', 'property', 'file'] else 'type-resource'
                    
                    # 对于文件类型，显示包含的类数量
                    classes_count = file_item.get('classes_count', '')
                    classes_info = f" ({classes_count}个类)" if classes_count else ""
                    
                    html.append(f'<div class="file-item" data-type="{item_type}" data-name="{html_module.escape(file_item.get("name", ""))}" data-path="{html_module.escape(file_item.get("path", ""))}" data-size="{file_item.get("size", 0)}">')
                    html.append(f'<div class="file-name">')
                    html.append(f'{file_item.get("name", "Unknown")}{classes_info}')
                    html.append(f'<span class="file-type {type_class}">{item_type}</span>')
                    html.append(f'</div>')
                    html.append(f'<div class="file-size">{self._format_size(file_item.get("size", 0))}</div>')
                    html.append(f'</div>')
            
            html.append(f'</div>')
            html.append(f'</div>')
        
        return ''.join(html)
    
    def _generate_detailed_tables_html(self) -> str:
        """生成详细表格HTML"""
        html = []
        
        # 仅显示文件和资源，不显示类、方法、属性
        sections = [
            ('无用文件 (Files)', self.unused_files, 'danger'),
            ('无用资源 (Resources)', self.unused_images + self.unused_xibs + self.unused_storyboards, 'info')
        ]
        
        for title, items, badge_type in sections:
            if not items:
                continue
            
            html.append(f'<h3>{title} <span class="badge badge-{badge_type}">{len(items)}</span></h3>')
            html.append('<table class="summary-table">')
            html.append('<thead><tr><th>名称</th><th>类型</th><th>路径</th><th>大小</th></tr></thead>')
            html.append('<tbody>')
            
            for item in sorted(items[:100], key=lambda x: x.get('size', 0), reverse=True):  # 只显示前100个
                html.append('<tr>')
                html.append(f'<td>{html_module.escape(item.get("name", "Unknown"))}</td>')
                html.append(f'<td><span class="file-type type-{item.get("type", "unknown")}">{item.get("type", "unknown")}</span></td>')
                html.append(f'<td style="font-size:12px;color:#666;">{html_module.escape(item.get("path", "Unknown"))}</td>')
                html.append(f'<td>{self._format_size(item.get("size", 0))}</td>')
                html.append('</tr>')
            
            if len(items) > 100:
                html.append(f'<tr><td colspan="4" style="text-align:center;color:#999;">... 还有 {len(items) - 100} 项，请查看CSV报告获取完整列表</td></tr>')
            
            html.append('</tbody></table><br>')
        
        return ''.join(html)
    
    def _format_size(self, size_bytes: int) -> str:
        """格式化文件大小"""
        if size_bytes == 0:
            return '-'
        
        for unit in ['B', 'KB', 'MB', 'GB']:
            if size_bytes < 1024.0:
                return f"{size_bytes:.1f} {unit}"
            size_bytes /= 1024.0
        return f"{size_bytes:.1f} TB"
    
    def _generate_csv_report(self, output_file: Path) -> None:
        """生成CSV报告"""
        with open(output_file, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(['类型', '名称', '路径', '大小', '完整路径', '类数量'])
            
            all_items = (self.unused_classes + self.unused_methods + self.unused_properties + 
                        self.unused_files + self.unused_images + self.unused_xibs + self.unused_storyboards)
            
            for item in all_items:
                writer.writerow([
                    item.get('type', ''),
                    item.get('name', ''),
                    item.get('path', ''),
                    item.get('size', 0),
                    item.get('full_path', ''),
                    item.get('classes_count', '')  # 文件类型显示类数量
                ])
    
    def _generate_json_summary(self, output_file: Path) -> None:
        """生成JSON汇总"""
        # 转换scan_stats中的datetime对象为字符串
        scan_stats_serializable = {}
        for key, value in self.scan_stats.items():
            if isinstance(value, datetime):
                scan_stats_serializable[key] = value.isoformat()
            else:
                scan_stats_serializable[key] = value
        
        summary = {
            'scan_time': datetime.now().isoformat(),
            'project_path': str(self.project_root),
            'total_unused_items': (
                len(self.unused_classes) + len(self.unused_methods) + len(self.unused_properties) +
                len(self.unused_files) + len(self.unused_images) + len(self.unused_xibs) + len(self.unused_storyboards)
            ),
            'unused_classes': len(self.unused_classes),
            'unused_methods': len(self.unused_methods),
            'unused_properties': len(self.unused_properties),
            'unused_files': len(self.unused_files),
            'unused_images': len(self.unused_images),
            'unused_xibs': len(self.unused_xibs),
            'unused_storyboards': len(self.unused_storyboards),
            'scan_stats': scan_stats_serializable
        }
        
        output_file.write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding='utf-8')
    
    def get_summary(self) -> Dict[str, Any]:
        """获取扫描汇总信息"""
        return {
            'total_unused_items': (
                len(self.unused_classes) + len(self.unused_methods) + len(self.unused_properties) +
                len(self.unused_files) + len(self.unused_images) + len(self.unused_xibs) + len(self.unused_storyboards)
            ),
            'scan_stats': self.scan_stats,
            'scan_time': datetime.now().isoformat()
        }


def main():
    """命令行入口点"""
    parser = argparse.ArgumentParser(description='iOS无用代码及资源扫描工具')
    parser.add_argument('project_path', nargs='?', default='.', 
                       help='iOS项目根目录路径（默认当前目录）')
    parser.add_argument('-c', '--config', help='配置文件路径')
    parser.add_argument('-o', '--output', default='unused_scan_results',
                       help='输出目录路径（默认: unused_scan_results）')
    parser.add_argument('--scan-type', choices=['all', 'code', 'resources'], 
                       default='all', help='扫描类型')
    parser.add_argument('--formats', nargs='+', choices=['html', 'csv', 'json', 'all'],
                       default=['html', 'csv', 'json'], help='报告格式（all=全部）')
    
    args = parser.parse_args()
    
    # 创建扫描器并执行扫描
    scanner = iOSUnusedScanner(args.project_path, args.config)
    results = scanner.scan(args.scan_type)
    
    if results['success']:
        # 生成报告
        report_files = scanner.generate_reports(args.output, args.formats)
        
        print("\n🎉 扫描报告已生成！")
        for format_name, file_path in report_files.items():
            print(f"📄 {format_name.upper()}报告: {file_path}")
        
        summary = scanner.get_summary()
        print(f"📊 汇总统计: 无用项总数={summary['total_unused_items']}")
    else:
        print(f"\n❌ 扫描失败: {results['error']}")
    
    exit(0 if results['success'] else 1)


if __name__ == "__main__":
    main()