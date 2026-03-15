import Foundation
import CryptoKit

// MARK: - 资源重复扫描服务协议
// 基于文件内容 SHA256 哈希检测工程中的重复资源文件，
// 相同哈希的文件视为重复，可安全删除其中一份以节省包体积。

protocol ResourceDuplicateScanServiceProtocol {
    /// 扫描工程中的重复资源（基于文件内容哈希分组）
    func scanDuplicateResources(
        projectPath: String,
        projectFileEntries: [ProjectFileEntry]?
    ) async throws -> [DuplicateResourceGroup]
}

// MARK: - 资源重复扫描服务实现

/// 基于文件内容 SHA256 的资源重复检测：相同哈希视为重复。
final class ResourceDuplicateScanService: ResourceDuplicateScanServiceProtocol {

    private static let maxFileSize = 5 * 1024 * 1024 // 5MB，过大文件不参与以控制耗时

    func scanDuplicateResources(
        projectPath: String,
        projectFileEntries: [ProjectFileEntry]?
    ) async throws -> [DuplicateResourceGroup] {
        let baseURL = URL(fileURLWithPath: projectPath)
        let resourceEntries: [ProjectFileEntry]
        if let entries = projectFileEntries {
            resourceEntries = entries.filter { $0.resourceType != nil && $0.resourceType != .other }
        } else {
            let all = try await ProjectResourceScanner().scanProjectDirectory(at: projectPath)
            resourceEntries = all
        }
        let fileURLs: [(URL, Int64)] = resourceEntries
            .filter { $0.size > 0 && $0.size <= Self.maxFileSize }
            .compactMap { entry -> (URL, Int64)? in
                let url = URL(fileURLWithPath: entry.relativePath, relativeTo: baseURL)
                return FileManager.default.fileExists(atPath: url.path) ? (url, entry.size) : nil
            }

        var hashToEntries: [String: [DuplicateResourceEntry]] = [:]
        let lock = NSLock()

        await withTaskGroup(of: (String, DuplicateResourceEntry)?.self) { group in
            for (url, size) in fileURLs {
                group.addTask {
                    guard let (fingerprint, entry) = await self.hashAndEntry(fileURL: url, size: size, baseURL: baseURL) else { return nil }
                    return (fingerprint, entry)
                }
            }
            for await result in group {
                guard let (fingerprint, entry) = result else { continue }
                lock.lock()
                hashToEntries[fingerprint, default: []].append(entry)
                lock.unlock()
            }
        }

        let groups = hashToEntries
            .filter { $0.value.count >= 2 }
            .map { key, list in
                DuplicateResourceGroup(
                    fingerprint: key,
                    count: list.count,
                    entries: list,
                    totalSize: list.reduce(0) { $0 + $1.size },
                    similarity: 1.0
                )
            }
            .sorted { $0.totalSize > $1.totalSize }

        return groups
    }

    private func hashAndEntry(fileURL: URL, size: Int64, baseURL: URL) async -> (String, DuplicateResourceEntry)? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return nil
        }
        let fingerprint = Self.sha256Hex(data)
        let basePath = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"
        let relativePath = fileURL.path.hasPrefix(basePath)
            ? String(fileURL.path.dropFirst(basePath.count))
            : (fileURL.path.hasPrefix(baseURL.path) ? String(fileURL.path.dropFirst(baseURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : fileURL.lastPathComponent)
        let safeRelative = relativePath.isEmpty ? fileURL.lastPathComponent : relativePath
        let entry = DuplicateResourceEntry(relativePath: safeRelative, size: size)
        return (fingerprint, entry)
    }

    private static func sha256Hex(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
