#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
iOS无用代码扫描器 - CI/CD集成示例

这个示例展示如何在CI/CD流程中集成无用代码扫描功能。
适用于GitHub Actions、Jenkins、GitLab CI等。
"""

import sys
import os
import json

# 添加 skill 根目录到路径，以便 from scripts.scanner 可用
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from scripts.scanner import iOSUnusedScanner


def ci_integration_scan(project_path, threshold=100):
    """
    CI/CD集成扫描函数

    Args:
        project_path: iOS项目路径
        threshold: 无用项阈值，超过此值将返回非零退出码

    Returns:
        退出码: 0表示成功，1表示超过阈值
    """

    print("🚀 CI/CD环境检测...")
    ci_env = os.environ.get('CI', 'false')
    print(f"  - CI环境: {ci_env}")
    print(f"  - 项目路径: {project_path}")
    print(f"  - 阈值: {threshold} 个无用项")
    print()

    # 创建扫描器
    print("📱 初始化扫描器...")
    skill_root = os.path.join(os.path.dirname(__file__), '..')
    default_config = os.path.join(skill_root, 'assets', 'default.json')
    scanner = iOSUnusedScanner(
        project_root=project_path,
        config_file=default_config if os.path.isfile(default_config) else None
    )
    print("✅ 扫描器初始化完成")
    print()

    # 执行快速扫描（适合CI环境）
    print("🔍 执行快速扫描...")
    results = scanner.scan(scan_type="all")

    if not results.get("success"):
        print(f"❌ 扫描失败: {results.get('error')}")
        return 1

    print("✅ 扫描完成")
    print()

    # 生成报告
    print("📄 生成CI报告...")
    output_dir = os.environ.get('CI_REPORT_DIR', './unused_scan_results')
    report_files = scanner.generate_reports(output_dir=output_dir)
    print(f"✅ 报告已保存到: {output_dir}")
    print()

    # 获取汇总信息
    summary = scanner.get_summary()
    total_unused = summary.get('total_unused_items', 0)

    # 输出统计信息
    print("=" * 60)
    print("📊 CI扫描结果汇总")
    print("=" * 60)
    print(f"无用类数量:   {len(results.get('unused_classes', []))}")
    print(f"无用方法数量: {len(results.get('unused_methods', []))}")
    print(f"无用资源数量: {len(results.get('unused_resources', []))}")
    print(f"总计:         {total_unused}")
    print(f"可节省空间:   {summary.get('total_size_bytes', 0) / 1024:.2f} KB")
    print("=" * 60)
    print()

    # 保存CI元数据
    ci_metadata = {
        "scan_result": "success",
        "total_unused_items": total_unused,
        "threshold": threshold,
        "passed": total_unused <= threshold,
        "unused_classes": len(results.get('unused_classes', [])),
        "unused_methods": len(results.get('unused_methods', [])),
        "unused_resources": len(results.get('unused_resources', [])),
        "report_files": report_files,
        "scan_time": summary.get('scan_time'),
        "scan_duration": summary.get('scan_duration')
    }

    # 保存到JSON文件供CI系统读取
    metadata_file = os.path.join(output_dir, 'ci_metadata.json')
    with open(metadata_file, 'w', encoding='utf-8') as f:
        json.dump(ci_metadata, f, indent=2, ensure_ascii=False)
    print(f"💾 CI元数据已保存: {metadata_file}")
    print()

    # 检查是否超过阈值
    if total_unused > threshold:
        print(f"⚠️  警告: 发现 {total_unused} 个无用项，超过阈值 {threshold}")
        print("   建议清理无用代码和资源以提高代码质量")
        return 1
    else:
        print(f"✅ 通过: 发现 {total_unused} 个无用项，在阈值 {threshold} 范围内")
        return 0


def main():
    """主函数"""

    # 从环境变量或命令行参数获取配置
    project_path = os.environ.get('PROJECT_PATH', '.')
    threshold = int(os.environ.get('UNUSED_THRESHOLD', '100'))

    if len(sys.argv) > 1:
        project_path = sys.argv[1]
    if len(sys.argv) > 2:
        threshold = int(sys.argv[2])

    # 执行CI集成扫描
    exit_code = ci_integration_scan(project_path, threshold)
    sys.exit(exit_code)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n⚠️  扫描被用户中断")
        sys.exit(1)
    except Exception as e:
        print(f"❌ 执行出错: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
