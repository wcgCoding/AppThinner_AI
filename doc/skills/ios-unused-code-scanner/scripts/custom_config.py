#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
iOS无用代码扫描器 - 自定义配置示例

这个示例展示如何使用自定义配置文件和高级选项。
"""

import sys
import os
import json

# 添加src目录到路径
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from src.scanner import iOSUnusedScanner


def create_custom_config():
    """创建自定义配置"""

    custom_config = {
        "skill": {
            "name": "ios_unused_code_scanner",
            "version": "1.0.0"
        },
        "scan_config": {
            "project_root": ".",
            "output_dir": "custom_scan_results",
            "enable_code_scan": True,
            "enable_resource_scan": True,
            "enable_reference_analysis": True
        },
        "ignore_rules": {
            "ignore_directories": [
                "Pods",
                ".git",
                "build",
                "DerivedData",
                "Carthage",
                ".bundle",
                "fastlane"
            ],
            "ignore_files": [
                "main.m",
                "main.swift",
                "AppDelegate.h",
                "AppDelegate.m",
                "AppDelegate.swift",
                "SceneDelegate.swift"
            ]
        },
        "whitelist": {
            "classes": [
                "AppDelegate",
                "SceneDelegate",
                "ViewController",
                "BaseViewController",
                "BaseTableViewController",
                "BaseCollectionViewController"
            ],
            "methods": [
                "viewDidLoad",
                "viewWillAppear:",
                "viewDidAppear:",
                "viewWillDisappear:",
                "viewDidDisappear:",
                "application:didFinishLaunchingWithOptions:",
                "applicationWillTerminate:",
                "scene:willConnectToSession:options:"
            ]
        },
        "performance": {
            "max_concurrent_scans": 4,
            "chunk_size": 100,
            "timeout_seconds": 300,
            "memory_limit_mb": 1024
        },
        "report_config": {
            "html_template": "default",
            "csv_encoding": "utf-8",
            "json_indent": 2,
            "sort_by": "size",  # size, name, type
            "sort_order": "desc"  # asc, desc
        }
    }

    return custom_config


def main():
    """使用自定义配置的示例"""

    print("=" * 60)
    print("iOS无用代码扫描器 - 自定义配置示例")
    print("=" * 60)
    print()

    # 1. 创建自定义配置
    print("⚙️  创建自定义配置...")
    config = create_custom_config()

    # 保存配置到临时文件
    config_file = "/tmp/custom_scanner_config.json"
    with open(config_file, 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
    print(f"✅ 配置已保存到: {config_file}")
    print()

    # 显示关键配置
    print("📋 关键配置项:")
    print(f"  - 代码扫描: {'启用' if config['scan_config']['enable_code_scan'] else '禁用'}")
    print(f"  - 资源扫描: {'启用' if config['scan_config']['enable_resource_scan'] else '禁用'}")
    print(f"  - 引用分析: {'启用' if config['scan_config']['enable_reference_analysis'] else '禁用'}")
    print(f"  - 最大并发: {config['performance']['max_concurrent_scans']}")
    print(f"  - 忽略目录: {len(config['ignore_rules']['ignore_directories'])} 个")
    print(f"  - 白名单类: {len(config['whitelist']['classes'])} 个")
    print()

    # 2. 使用自定义配置创建扫描器
    print("📱 创建扫描器实例（使用自定义配置）...")
    scanner = iOSUnusedScanner(
        project_root=config['scan_config']['project_root'],
        config_file=config_file
    )
    print("✅ 扫描器已创建")
    print()

    # 3. 执行扫描 - 仅代码扫描
    print("🔍 执行代码扫描（不包括资源）...")
    results = scanner.scan(scan_type="code")

    if results.get("success"):
        print("✅ 代码扫描完成")
        print(f"  - 发现无用类: {len(results.get('unused_classes', []))}")
        print(f"  - 发现无用方法: {len(results.get('unused_methods', []))}")
        print()
    else:
        print(f"❌ 扫描失败: {results.get('error')}")
        return

    # 4. 单独执行资源扫描
    print("🔍 执行资源扫描...")
    resource_results = scanner.scan(scan_type="resources")

    if resource_results.get("success"):
        print("✅ 资源扫描完成")
        print(f"  - 发现无用资源: {len(resource_results.get('unused_resources', []))}")
        print()

    # 5. 生成定制化报告
    print("📄 生成定制化报告...")
    report_files = scanner.generate_reports(
        output_dir=config['scan_config']['output_dir']
    )

    print("✅ 报告已生成:")
    for format_type, file_path in report_files.items():
        print(f"  - {format_type}: {file_path}")
    print()

    # 6. 执行引用分析
    print("🔗 执行引用关系分析...")
    ref_results = scanner.analyze_references(depth=3)

    if ref_results.get("success"):
        print("✅ 引用分析完成")
        print(f"  - 分析的符号数: {ref_results.get('total_symbols', 0)}")
        print(f"  - 引用关系数: {ref_results.get('total_references', 0)}")
        print()

    # 7. 获取详细汇总
    print("📊 详细汇总统计:")
    summary = scanner.get_summary()
    print(f"  - 总计无用项: {summary.get('total_unused_items', 0)}")
    print(f"  - 无用类: {summary.get('unused_classes_count', 0)}")
    print(f"  - 无用方法: {summary.get('unused_methods_count', 0)}")
    print(f"  - 无用资源: {summary.get('unused_resources_count', 0)}")
    print(f"  - 可节省空间: {summary.get('total_size_bytes', 0) / 1024:.2f} KB")
    print(f"  - 扫描用时: {summary.get('scan_duration', 0):.2f} 秒")
    print()

    print("=" * 60)
    print("✅ 自定义配置示例执行完成!")
    print(f"💡 提示: 查看 {config['scan_config']['output_dir']} 目录获取详细报告")
    print("=" * 60)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"❌ 执行出错: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
