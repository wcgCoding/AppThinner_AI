#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
iOS无用代码扫描器 - 基本使用示例

这个示例展示如何使用iOSUnusedScanner进行基本的代码扫描操作。
"""

import sys
import os

# 添加 skill 根目录到路径，以便 from scripts.scanner 可用
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from scripts.scanner import iOSUnusedScanner


def main():
    """基本使用示例"""

    print("=" * 60)
    print("iOS无用代码扫描器 - 基本使用示例")
    print("=" * 60)
    print()

    # 1. 创建扫描器实例
    print("📱 创建扫描器实例...")
    skill_root = os.path.join(os.path.dirname(__file__), '..')
    default_config = os.path.join(skill_root, 'assets', 'default.json')
    scanner = iOSUnusedScanner(
        project_root=".",  # 当前目录
        config_file=default_config if os.path.isfile(default_config) else None  # skill 默认配置
    )
    print("✅ 扫描器已创建")
    print()

    # 2. 执行扫描
    print("🔍 开始扫描项目...")
    results = scanner.scan(scan_type="all")  # 扫描所有类型
    print("✅ 扫描完成")
    print()

    # 3. 显示扫描结果
    if results.get("success"):
        print("📊 扫描结果汇总:")
        print(f"  - 无用类数量: {len(results.get('unused_classes', []))}")
        print(f"  - 无用方法数量: {len(results.get('unused_methods', []))}")
        print(f"  - 无用资源数量: {len(results.get('unused_resources', []))}")
        print()

        # 显示前5个无用类
        if results.get('unused_classes'):
            print("🔸 前5个无用类:")
            for i, cls in enumerate(results['unused_classes'][:5], 1):
                print(f"  {i}. {cls.get('name')} - {cls.get('file_path')}")
            print()
    else:
        print("❌ 扫描失败:", results.get("error"))
        return

    # 4. 生成报告
    print("📄 生成报告...")
    report_files = scanner.generate_reports(
        output_dir="./unused_scan_results"
    )
    print("✅ 报告已生成:")
    for format_type, file_path in report_files.items():
        print(f"  - {format_type}: {file_path}")
    print()

    # 5. 获取汇总信息
    print("📈 汇总统计:")
    summary = scanner.get_summary()
    print(f"  - 总计无用项: {summary.get('total_unused_items', 0)}")
    print(f"  - 可节省空间: {summary.get('total_size_bytes', 0) / 1024:.2f} KB")
    print(f"  - 扫描用时: {summary.get('scan_duration', 0):.2f} 秒")
    print()

    print("=" * 60)
    print("✅ 示例执行完成!")
    print("=" * 60)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"❌ 执行出错: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
