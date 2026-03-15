#!/usr/bin/env swift

import Foundation

/// 包体积验证：对比「期望」与「实际」分析结果 JSON，用于 Cursor 或 CI 校验对齐。
/// 用法: swift compare_analysis.swift <expected.json> <actual.json> [--tolerance-pct 1]
/// 退出码: 0 通过, 1 失败

func loadJSON(path: String) -> [String: Any]? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    return json
}

func int64(_ value: Any?) -> Int64 {
    if let n = value as? Int64 { return n }
    if let n = value as? Int { return Int64(n) }
    if let n = value as? NSNumber { return n.int64Value }
    return 0
}

func main() {
    let args = CommandLine.arguments.dropFirst()
    guard args.count >= 2 else {
        fputs("Usage: swift compare_analysis.swift <expected.json> <actual.json> [--tolerance-pct 1]\n", stderr)
        exit(1)
    }
    let expectedPath = args.first!
    let actualPath = args[args.index(after: args.startIndex)]
    var tolerancePct: Double = 1.0
    if let i = args.firstIndex(of: "--tolerance-pct"), args.count > i + 1, let p = Double(args[i + 1]) {
        tolerancePct = p
    }

    guard let expected = loadJSON(path: expectedPath) else {
        fputs("ERROR: Could not load expected JSON: \(expectedPath)\n", stderr)
        exit(1)
    }
    guard let actual = loadJSON(path: actualPath) else {
        fputs("ERROR: Could not load actual JSON: \(actualPath)\n", stderr)
        exit(1)
    }

    let keys = ["totalSize", "summaryCodeSize", "summaryResourceSize", "summaryFrameworkSize"]
    var failed = false
    for key in keys {
        let exp = int64(expected[key])
        let act = int64(actual[key])
        let allowDelta: Int64
        if key == "summaryCodeSize" {
            allowDelta = 0
        } else {
            allowDelta = exp == 0 ? 0 : Int64(Double(exp) * tolerancePct / 100.0)
        }
        let delta = abs(act - exp)
        if delta > allowDelta {
            fputs("MISMATCH \(key): expected \(exp), actual \(act) (delta \(delta), allowed \(allowDelta))\n", stderr)
            failed = true
        } else {
            print("OK \(key): \(act)")
        }
    }
    if failed {
        fputs("VERIFICATION FAILED\n", stderr)
        exit(1)
    }
    print("VERIFICATION PASSED")
    exit(0)
}

main()
