#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
iOS无用代码及资源扫描Agent Skill - API接口模块

提供标准的Agent Skill接口，支持：
1. 标准化的Skill调用接口
2. 参数验证和错误处理
3. 统一的响应格式
4. 插件化集成支持
"""

import os
import json
import logging
from pathlib import Path
from typing import Dict, List, Any, Optional, Union
from datetime import datetime
from scanner import iOSUnusedScanner

# 设置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class iOSUnusedScannerAPI:
    """iOS无用代码及资源扫描Agent Skill API接口"""
    
    def __init__(self, skill_config: Optional[Dict[str, Any]] = None):
        """
        初始化API接口
        
        Args:
            skill_config: Skill配置信息
        """
        self.skill_config = skill_config or {}
        self.scanner = None
        self.api_version = "1.0.0"
        self.supported_actions = [
            "scan_unused_code",
            "scan_unused_resources", 
            "generate_reports",
            "analyze_references",
            "get_summary"
        ]
        
        logger.info(f"iOSUnusedScannerAPI初始化完成，版本: {self.api_version}")
    
    def execute(self, action: str, parameters: Dict[str, Any] = None) -> Dict[str, Any]:
        """
        执行Skill动作
        
        Args:
            action: 动作名称
            parameters: 动作参数
            
        Returns:
            执行结果
        """
        logger.info(f"执行Skill动作: {action}")
        
        # 验证动作
        if action not in self.supported_actions:
            return self._error_response(f"不支持的动作: {action}")
        
        # 验证参数
        validation_result = self._validate_parameters(action, parameters or {})
        if not validation_result["valid"]:
            return self._error_response(f"参数验证失败: {validation_result['message']}")
        
        try:
            # 执行动作
            if action == "scan_unused_code":
                result = self._scan_unused_code(parameters)
            elif action == "scan_unused_resources":
                result = self._scan_unused_resources(parameters)
            elif action == "generate_reports":
                result = self._generate_reports(parameters)
            elif action == "analyze_references":
                result = self._analyze_references(parameters)
            elif action == "get_summary":
                result = self._get_summary(parameters)
            else:
                result = self._error_response(f"未实现的动作: {action}")
            
            # 添加元数据
            result["metadata"] = {
                "skill_name": "ios_unused_code_scanner",
                "api_version": self.api_version,
                "action": action,
                "execution_time": datetime.now().isoformat(),
                "success": result.get("success", False)
            }
            
            return result
            
        except Exception as e:
            logger.error(f"执行动作 {action} 时出现错误: {e}")
            return self._error_response(f"执行错误: {str(e)}")
    
    def _scan_unused_code(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """扫描无用代码"""
        project_root = parameters.get("project_root", ".")
        scan_type = parameters.get("scan_type", "all")
        config_file = parameters.get("config_file")
        
        # 初始化扫描器
        self.scanner = iOSUnusedScanner(project_root, config_file)
        
        # 执行扫描
        results = self.scanner.scan(scan_type)
        
        return {
            "success": True,
            "action": "scan_unused_code",
            "results": results,
            "scan_type": scan_type,
            "project_root": project_root
        }
    
    def _scan_unused_resources(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """扫描无用资源"""
        project_root = parameters.get("project_root", ".")
        resource_types = parameters.get("resource_types", ["all"])
        config_file = parameters.get("config_file")
        
        # 初始化扫描器
        self.scanner = iOSUnusedScanner(project_root, config_file)
        
        # 执行资源扫描
        results = self.scanner.scan("resources")
        
        return {
            "success": True,
            "action": "scan_unused_resources",
            "results": results,
            "resource_types": resource_types,
            "project_root": project_root
        }
    
    def _generate_reports(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """生成报告"""
        if not self.scanner:
            return self._error_response("请先执行扫描操作")
        
        output_dir = parameters.get("output_dir", "unused_scan_results")
        formats = parameters.get("formats", ["all"])
        
        # 生成报告
        report_files = self.scanner.generate_reports(output_dir, formats)
        
        return {
            "success": True,
            "action": "generate_reports",
            "report_files": report_files,
            "output_dir": output_dir,
            "formats": formats
        }
    
    def _analyze_references(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """分析引用关系"""
        project_root = parameters.get("project_root", ".")
        depth = parameters.get("depth", 3)
        config_file = parameters.get("config_file")
        
        # 初始化扫描器
        self.scanner = iOSUnusedScanner(project_root, config_file)
        
        # 执行引用分析
        # 这里可以调用更复杂的引用分析逻辑
        results = self.scanner.scan("all")
        
        return {
            "success": True,
            "action": "analyze_references",
            "results": results,
            "depth": depth,
            "project_root": project_root
        }
    
    def _get_summary(self, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """获取汇总信息"""
        if not self.scanner:
            return self._error_response("请先执行扫描操作")
        
        summary = self.scanner.get_summary()
        
        return {
            "success": True,
            "action": "get_summary",
            "summary": summary
        }
    
    def _validate_parameters(self, action: str, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """验证参数"""
        validation_rules = {
            "scan_unused_code": {
                "project_root": {"type": str, "required": True, "default": "."},
                "scan_type": {"type": str, "required": False, "enum": ["all", "code", "resources"], "default": "all"},
                "config_file": {"type": str, "required": False, "default": None}
            },
            "scan_unused_resources": {
                "project_root": {"type": str, "required": True, "default": "."},
                "resource_types": {"type": list, "required": False, "default": ["all"]},
                "config_file": {"type": str, "required": False, "default": None}
            },
            "generate_reports": {
                "output_dir": {"type": str, "required": False, "default": "unused_scan_results"},
                "formats": {"type": list, "required": False, "default": ["all"]}
            },
            "analyze_references": {
                "project_root": {"type": str, "required": True, "default": "."},
                "depth": {"type": int, "required": False, "min": 1, "max": 5, "default": 3},
                "config_file": {"type": str, "required": False, "default": None}
            },
            "get_summary": {
                # 无参数
            }
        }
        
        rules = validation_rules.get(action, {})
        
        for param_name, rule in rules.items():
            # 检查必需参数
            if rule.get("required", False) and param_name not in parameters:
                return {
                    "valid": False,
                    "message": f"必需参数缺失: {param_name}"
                }
            
            # 检查参数类型
            if param_name in parameters:
                param_value = parameters[param_name]
                expected_type = rule.get("type")
                
                if expected_type and not isinstance(param_value, expected_type):
                    return {
                        "valid": False,
                        "message": f"参数 {param_name} 类型错误，期望 {expected_type.__name__}，实际 {type(param_value).__name__}"
                    }
                
                # 检查枚举值
                if "enum" in rule and param_value not in rule["enum"]:
                    return {
                        "valid": False,
                        "message": f"参数 {param_name} 值无效，有效值: {rule['enum']}"
                    }
                
                # 检查数值范围
                if "min" in rule and isinstance(param_value, (int, float)):
                    if param_value < rule["min"]:
                        return {
                            "valid": False,
                            "message": f"参数 {param_name} 值过小，最小值: {rule['min']}"
                        }
                
                if "max" in rule and isinstance(param_value, (int, float)):
                    if param_value > rule["max"]:
                        return {
                            "valid": False,
                            "message": f"参数 {param_name} 值过大，最大值: {rule['max']}"
                        }
        
        return {"valid": True, "message": "参数验证通过"}
    
    def _error_response(self, message: str) -> Dict[str, Any]:
        """生成错误响应"""
        return {
            "success": False,
            "error": message,
            "metadata": {
                "skill_name": "ios_unused_code_scanner",
                "api_version": self.api_version,
                "execution_time": datetime.now().isoformat(),
                "success": False
            }
        }
    
    def get_capabilities(self) -> Dict[str, Any]:
        """获取Skill能力信息"""
        return {
            "skill_name": "ios_unused_code_scanner",
            "version": self.api_version,
            "description": "iOS无用代码及资源扫描Agent Skill",
            "supported_actions": self.supported_actions,
            "config_schema": self._get_config_schema(),
            "requirements": {
                "python": ">=3.6",
                "system": "macOS 10.15+（可选，用于 xcodebuild）",
                "dependencies": []
            }
        }
    
    def _get_config_schema(self) -> Dict[str, Any]:
        """获取配置架构"""
        return {
            "scan_config": {
                "project_root": {"type": "string", "default": "."},
                "output_dir": {"type": "string", "default": "unused_scan_results"},
                "enable_code_scan": {"type": "boolean", "default": True},
                "enable_resource_scan": {"type": "boolean", "default": True},
                "enable_reference_analysis": {"type": "boolean", "default": True},
                "file_source": {"type": "string", "default": "directory", "enum": ["directory", "xcodeproj"]},
                "xcodeproj_path": {"type": "string", "default": None}
            },
            "ignore_rules": {
                "ignore_directories": {"type": "array", "default": ["Pods", ".git", "build"]},
                "ignore_files": {"type": "array", "default": ["main.m", "AppDelegate.h"]},
                "ignore_file_patterns": {"type": "array", "default": ["*Test*.{h,m,swift}", "*Mock*", "*Spec*"]}
            }
        }
    
    def health_check(self) -> Dict[str, Any]:
        """健康检查：仅校验 Python 版本与可选系统工具，无第三方依赖"""
        try:
            import sys
            deps = {"python": f"{sys.version_info.major}.{sys.version_info.minor}"}
            if sys.version_info < (3, 6):
                return {
                    "status": "unhealthy",
                    "message": "需要 Python 3.6+",
                    "error": "python_version"
                }
            try:
                import subprocess
                subprocess.run(["xcodebuild", "-version"], capture_output=True, check=True, timeout=5)
                deps["xcodebuild"] = "正常"
            except (FileNotFoundError, subprocess.CalledProcessError, Exception):
                deps["xcodebuild"] = "未检测（可选）"
            try:
                import subprocess
                subprocess.run(["git", "--version"], capture_output=True, check=True, timeout=2)
                deps["git"] = "正常"
            except (FileNotFoundError, subprocess.CalledProcessError, Exception):
                deps["git"] = "未检测（可选）"
            return {
                "status": "healthy",
                "message": "依赖检查通过",
                "dependencies": deps
            }
        except Exception as e:
            return {
                "status": "unhealthy",
                "message": f"健康检查失败: {str(e)}",
                "error": str(e)
            }


# Agent Skill标准接口
def skill_main(action: str, parameters: Dict[str, Any] = None) -> Dict[str, Any]:
    """
    Agent Skill标准入口点
    
    Args:
        action: 动作名称
        parameters: 动作参数
        
    Returns:
        标准化的Skill响应
    """
    api = iOSUnusedScannerAPI()
    return api.execute(action, parameters or {})


def skill_info() -> Dict[str, Any]:
    """获取Skill信息"""
    api = iOSUnusedScannerAPI()
    return api.get_capabilities()


def skill_health() -> Dict[str, Any]:
    """Skill健康检查"""
    api = iOSUnusedScannerAPI()
    return api.health_check()


# 命令行接口
def main():
    """命令行入口点"""
    import argparse
    
    parser = argparse.ArgumentParser(description='iOS无用代码扫描Agent Skill API')
    parser.add_argument('action', help='动作名称')
    parser.add_argument('-p', '--parameters', type=json.loads, help='JSON格式的参数')
    parser.add_argument('--info', action='store_true', help='显示Skill信息')
    parser.add_argument('--health', action='store_true', help='健康检查')
    
    args = parser.parse_args()
    
    if args.info:
        result = skill_info()
        print(json.dumps(result, indent=2, ensure_ascii=False))
    elif args.health:
        result = skill_health()
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        parameters = args.parameters or {}
        result = skill_main(args.action, parameters)
        print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()