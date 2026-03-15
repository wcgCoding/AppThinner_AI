import Foundation
import CryptoKit

// MARK: - CodeDuplicateScanService Protocol

protocol CodeDuplicateScanServiceProtocol {
    /// 扫描工程中的重复代码（基于归一化内容哈希分组）
    /// - Parameters:
    ///   - projectPath: 工程根目录
    ///   - projectFileEntries: 可选，若提供则只扫描其中的源码文件；否则在 projectPath 下枚举 .swift/.m/.mm
    /// - Returns: 重复代码组列表（仅包含 count >= 2 的组）
    func scanDuplicateCode(
        projectPath: String,
        projectFileEntries: [ProjectFileEntry]?
    ) async throws -> [DuplicateCodeGroup]
}

// MARK: - CodeDuplicateScanService Implementation

/// 基于「归一化内容哈希」的代码重复检测：去除注释与多余空白后按哈希分组，相同哈希视为重复。
final class CodeDuplicateScanService: CodeDuplicateScanServiceProtocol {

    private static let codeExtensions = ["swift", "m", "mm"]
    private static let maxFileSize = 512 * 1024 // 512KB，过大文件不参与重复检测以控制耗时

    func scanDuplicateCode(
        projectPath: String,
        projectFileEntries: [ProjectFileEntry]?
    ) async throws -> [DuplicateCodeGroup] {
        let baseURL = URL(fileURLWithPath: projectPath)
        let pathPrefixCount = projectPath.hasSuffix("/") ? projectPath.count : projectPath.count + 1

        let codeFileURLs: [URL]
        if let entries = projectFileEntries {
            codeFileURLs = entries
                .filter { $0.isSourceCode && Self.codeExtensions.contains(($0.relativePath as NSString).pathExtension.lowercased()) }
                .compactMap { entry -> URL? in
                    let url = URL(fileURLWithPath: entry.relativePath, relativeTo: baseURL)
                    return url.path.isEmpty ? nil : url
                }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        } else {
            codeFileURLs = try await enumerateSourceFiles(at: projectPath)
        }

        var hashToPaths: [String: [DuplicateCodeEntry]] = [:]
        let lock = NSLock()

        await withTaskGroup(of: (String, DuplicateCodeEntry)?.self) { group in
            for url in codeFileURLs {
                group.addTask {
                    guard let (fingerprint, entry) = await self.normalizeAndHash(fileURL: url, pathPrefixCount: pathPrefixCount) else { return nil }
                    return (fingerprint, entry)
                }
            }
            for await result in group {
                guard let (fingerprint, entry) = result else { continue }
                lock.lock()
                hashToPaths[fingerprint, default: []].append(entry)
                lock.unlock()
            }
        }

        let groups = hashToPaths
            .filter { $0.value.count >= 2 }
            .map { DuplicateCodeGroup(fingerprint: $0.key, count: $0.value.count, entries: $0.value, similarity: 1.0) }
            .sorted { $0.count > $1.count }

        return groups
    }

    /// 枚举工程目录下的源码文件（.swift / .m / .mm），跳过 Pods、Carthage 等
    private func enumerateSourceFiles(at path: String) async throws -> [URL] {
        let projectURL = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }
        var urls: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: projectURL, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        while let url = enumerator.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let name = url.lastPathComponent.lowercased()
                if name == "pods" || name == "carthage" || name == ".build" { enumerator.skipDescendants() }
                continue
            }
            let ext = url.pathExtension.lowercased()
            if Self.codeExtensions.contains(ext) {
                if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= Self.maxFileSize {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    /// 读取文件、归一化内容并计算指纹，返回 (fingerprint, entry)；失败或空内容返回 nil
    private func normalizeAndHash(fileURL: URL, pathPrefixCount: Int) async -> (String, DuplicateCodeEntry)? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return nil
        }
        guard let content = String(data: data, encoding: .utf8), !content.isEmpty else { return nil }
        let normalized = Self.normalizeSourceContent(content)
        guard !normalized.isEmpty else { return nil }
        let fingerprint = Self.sha256Hex(normalized)
        let relativePath = String(fileURL.path.dropFirst(pathPrefixCount))
        let entry = DuplicateCodeEntry(relativePath: relativePath, startLine: nil, endLine: nil)
        return (fingerprint, entry)
    }

    /// 去除单行/多行注释、归一化空白
    private static func normalizeSourceContent(_ source: String) -> String {
        var result = source
        // 简单移除 // 行尾注释（不处理字符串内的）
        result = result.components(separatedBy: .newlines).map { line in
            if let idx = line.range(of: "//")?.lowerBound {
                return String(line[..<idx])
            }
            return line
        }.joined(separator: "\n")
        // 简单移除 /* ... */（不处理嵌套）
        while let start = result.range(of: "/*"), let end = result.range(of: "*/", range: start.upperBound..<result.endIndex) {
            result.replaceSubrange(start.lowerBound..<end.upperBound, with: " ")
        }
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    private static func sha256Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
