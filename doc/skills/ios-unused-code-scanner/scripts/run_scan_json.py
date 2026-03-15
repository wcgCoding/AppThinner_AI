#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
供 AppThinnerAnalyzer 调用的无用代码/资源扫描入口。
用法: python3 run_scan_json.py <project_root>
输出: 标准输出为 JSON，包含 unused_classes, unused_files, unused_images, unused_xibs, unused_storyboards。
"""

import json
import sys
import os

# 确保可导入同目录下的 scanner / api
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

def main():
    project_root = sys.argv[1] if len(sys.argv) > 1 else "."
    if not os.path.isdir(project_root):
        out = {"success": False, "error": "project_root is not a directory: " + project_root}
        print(json.dumps(out, ensure_ascii=False))
        sys.exit(1)
    try:
        from api import iOSUnusedScannerAPI
        api = iOSUnusedScannerAPI()
        result = api.execute("scan_unused_code", {"project_root": project_root, "scan_type": "all"})
        if not result.get("success"):
            print(json.dumps({"success": False, "error": result.get("error", "scan failed")}, ensure_ascii=False))
            sys.exit(1)
        results = result.get("results", {})
        out = {
            "success": True,
            "unused_classes": results.get("unused_classes", []),
            "unused_files": results.get("unused_files", []),
            "unused_images": results.get("unused_images", []),
            "unused_xibs": results.get("unused_xibs", []),
            "unused_storyboards": results.get("unused_storyboards", []),
        }
        print(json.dumps(out, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}, ensure_ascii=False))
        sys.exit(1)

if __name__ == "__main__":
    main()
