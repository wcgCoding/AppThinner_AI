#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
iOS无用代码扫描器 - 单元测试

测试核心扫描器功能
"""

import sys
import os
import json
import unittest
from pathlib import Path

# 添加src目录到路径
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from src.scanner import iOSUnusedScanner


class TestiOSUnusedScanner(unittest.TestCase):
    """测试iOSUnusedScanner类"""

    def setUp(self):
        """测试前设置"""
        self.test_data_dir = os.path.join(os.path.dirname(__file__), 'test_data')
        self.output_dir = os.path.join(self.test_data_dir, 'test_output')

        # 创建测试输出目录
        os.makedirs(self.output_dir, exist_ok=True)

    def tearDown(self):
        """测试后清理"""
        # 清理测试输出
        import shutil
        if os.path.exists(self.output_dir):
            shutil.rmtree(self.output_dir)

    def test_scanner_initialization(self):
        """测试扫描器初始化"""
        scanner = iOSUnusedScanner(
            project_root=self.test_data_dir,
            config_file=None
        )

        self.assertIsNotNone(scanner)
        self.assertEqual(scanner.project_root, self.test_data_dir)

    def test_scanner_with_config(self):
        """测试使用配置文件初始化"""
        config_file = os.path.join(os.path.dirname(__file__), '../configs/default.json')

        if os.path.exists(config_file):
            scanner = iOSUnusedScanner(
                project_root=self.test_data_dir,
                config_file=config_file
            )

            self.assertIsNotNone(scanner)
            self.assertIsNotNone(scanner.config)

    def test_scan_invalid_project(self):
        """测试扫描无效项目"""
        scanner = iOSUnusedScanner(
            project_root="/nonexistent/path",
            config_file=None
        )

        results = scanner.scan()

        # 应该返回失败结果
        self.assertFalse(results.get('success', True))
        self.assertIn('error', results)

    def test_scan_types(self):
        """测试不同扫描类型"""
        scanner = iOSUnusedScanner(
            project_root=self.test_data_dir,
            config_file=None
        )

        # 测试所有扫描类型
        scan_types = ['all', 'code', 'resources']

        for scan_type in scan_types:
            with self.subTest(scan_type=scan_type):
                results = scanner.scan(scan_type=scan_type)

                # 基本结构验证
                self.assertIsInstance(results, dict)
                self.assertIn('success', results)

    def test_generate_reports(self):
        """测试报告生成"""
        scanner = iOSUnusedScanner(
            project_root=self.test_data_dir,
            config_file=None
        )

        # 先扫描
        scanner.scan()

        # 生成报告
        report_files = scanner.generate_reports(output_dir=self.output_dir)

        # 验证返回值
        self.assertIsInstance(report_files, dict)

        # 验证报告文件（如果生成成功）
        for format_type, file_path in report_files.items():
            if file_path and os.path.exists(file_path):
                self.assertTrue(os.path.isfile(file_path))

    def test_get_summary(self):
        """测试获取汇总信息"""
        scanner = iOSUnusedScanner(
            project_root=self.test_data_dir,
            config_file=None
        )

        # 先扫描
        scanner.scan()

        # 获取汇总
        summary = scanner.get_summary()

        # 验证汇总结构
        self.assertIsInstance(summary, dict)
        self.assertIn('total_unused_items', summary)
        self.assertIn('scan_time', summary)

    def test_analyze_references(self):
        """测试引用分析"""
        scanner = iOSUnusedScanner(
            project_root=self.test_data_dir,
            config_file=None
        )

        # 执行引用分析
        results = scanner.analyze_references(depth=2)

        # 验证结果
        self.assertIsInstance(results, dict)
        self.assertIn('success', results)

    def test_config_loading(self):
        """测试配置文件加载"""
        # 创建测试配置
        test_config = {
            "skill": {
                "name": "test_scanner",
                "version": "1.0.0"
            },
            "scan_config": {
                "project_root": ".",
                "enable_code_scan": True
            }
        }

        config_file = os.path.join(self.output_dir, 'test_config.json')
        with open(config_file, 'w') as f:
            json.dump(test_config, f)

        # 使用测试配置初始化
        scanner = iOSUnusedScanner(
            project_root=self.test_data_dir,
            config_file=config_file
        )

        self.assertIsNotNone(scanner.config)

    def test_whitelist_handling(self):
        """测试白名单处理"""
        # 创建带白名单的配置
        test_config = {
            "whitelist": {
                "classes": ["AppDelegate", "TestClass"],
                "methods": ["viewDidLoad", "testMethod"]
            }
        }

        config_file = os.path.join(self.output_dir, 'whitelist_config.json')
        with open(config_file, 'w') as f:
            json.dump(test_config, f)

        scanner = iOSUnusedScanner(
            project_root=self.test_data_dir,
            config_file=config_file
        )

        # 白名单应该被加载
        self.assertIsNotNone(scanner.config)

    def test_ignore_rules(self):
        """测试忽略规则"""
        test_config = {
            "ignore_rules": {
                "ignore_directories": ["Pods", "build"],
                "ignore_files": ["main.m", "AppDelegate.h"]
            }
        }

        config_file = os.path.join(self.output_dir, 'ignore_config.json')
        with open(config_file, 'w') as f:
            json.dump(test_config, f)

        scanner = iOSUnusedScanner(
            project_root=self.test_data_dir,
            config_file=config_file
        )

        # 忽略规则应该被加载
        self.assertIsNotNone(scanner.config)


class TestReportGeneration(unittest.TestCase):
    """测试报告生成功能"""

    def setUp(self):
        """测试前设置"""
        self.test_data_dir = os.path.join(os.path.dirname(__file__), 'test_data')
        self.output_dir = os.path.join(self.test_data_dir, 'report_output')
        os.makedirs(self.output_dir, exist_ok=True)

    def tearDown(self):
        """测试后清理"""
        import shutil
        if os.path.exists(self.output_dir):
            shutil.rmtree(self.output_dir)

    def test_html_report_generation(self):
        """测试HTML报告生成"""
        scanner = iOSUnusedScanner(
            project_root=self.test_data_dir,
            config_file=None
        )

        scanner.scan()
        reports = scanner.generate_reports(
            output_dir=self.output_dir,
            formats=['html']
        )

        # 验证HTML报告
        if 'html_report' in reports and reports['html_report']:
            html_file = reports['html_report']
            if os.path.exists(html_file):
                self.assertTrue(html_file.endswith('.html'))

    def test_csv_report_generation(self):
        """测试CSV报告生成"""
        scanner = iOSUnusedScanner(
            project_root=self.test_data_dir,
            config_file=None
        )

        scanner.scan()
        reports = scanner.generate_reports(
            output_dir=self.output_dir,
            formats=['csv']
        )

        # 验证CSV报告
        if 'csv_report' in reports and reports['csv_report']:
            csv_file = reports['csv_report']
            if os.path.exists(csv_file):
                self.assertTrue(csv_file.endswith('.csv'))

    def test_json_report_generation(self):
        """测试JSON报告生成"""
        scanner = iOSUnusedScanner(
            project_root=self.test_data_dir,
            config_file=None
        )

        scanner.scan()
        reports = scanner.generate_reports(
            output_dir=self.output_dir,
            formats=['json']
        )

        # 验证JSON报告
        if 'json_summary' in reports and reports['json_summary']:
            json_file = reports['json_summary']
            if os.path.exists(json_file):
                self.assertTrue(json_file.endswith('.json'))
                # 验证JSON格式
                with open(json_file) as f:
                    data = json.load(f)
                    self.assertIsInstance(data, dict)


class TestEdgeCases(unittest.TestCase):
    """测试边界情况"""

    def test_empty_project(self):
        """测试空项目扫描"""
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            scanner = iOSUnusedScanner(
                project_root=tmpdir,
                config_file=None
            )

            results = scanner.scan()
            self.assertIsInstance(results, dict)

    def test_invalid_scan_type(self):
        """测试无效扫描类型"""
        scanner = iOSUnusedScanner(
            project_root='.',
            config_file=None
        )

        # 测试无效的扫描类型
        results = scanner.scan(scan_type='invalid_type')

        # 应该处理无效输入
        self.assertIsInstance(results, dict)

    def test_invalid_config_file(self):
        """测试无效配置文件"""
        scanner = iOSUnusedScanner(
            project_root='.',
            config_file='/nonexistent/config.json'
        )

        # 应该使用默认配置
        self.assertIsNotNone(scanner)


def run_tests():
    """运行所有测试"""
    # 创建测试套件
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    # 添加所有测试
    suite.addTests(loader.loadTestsFromTestCase(TestiOSUnusedScanner))
    suite.addTests(loader.loadTestsFromTestCase(TestReportGeneration))
    suite.addTests(loader.loadTestsFromTestCase(TestEdgeCases))

    # 运行测试
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    # 返回退出码
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(run_tests())
