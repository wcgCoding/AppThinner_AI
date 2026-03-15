import Foundation
import AppKit
import os.log

/// 文件权限服务：负责处理 macOS 沙盒下的文件访问权限，
/// 管理 Security-Scoped Bookmark，确保 IPA/LinkMap 等文件在沙盒内可被正常读取。
class FilePermissionService: ObservableObject {
    static let shared = FilePermissionService()
    
    private let logger = Logger(subsystem: "com.iosappanalyzer.app", category: "FilePermissions")
    
    @Published var hasFileAccessPermission = false
    @Published var permissionStatus: PermissionStatus = .unknown
    
    // MARK: - 初始化
    
    private init() {
        checkInitialPermissions()
    }
    
    // MARK: - 公共接口
    
    /// Requests file access permission for the specified URL
    /// - Parameter url: The file or directory URL to request access for
    /// - Returns: True if permission granted, false otherwise
    func requestFileAccess(for url: URL) async -> Bool {
        logger.info("Requesting file access for: \(url.path)")
        
        // Check if we already have access
        if hasExistingAccess(to: url) {
            logger.info("Already have access to: \(url.path)")
            return true
        }
        
        // Request access through security-scoped bookmark
        return await requestSecurityScopedAccess(for: url)
    }
    
    /// Checks if the app has permission to access the specified URL
    /// - Parameter url: The URL to check access for
    /// - Returns: True if access is available, false otherwise
    func hasPermission(for url: URL) -> Bool {
        return hasExistingAccess(to: url)
    }
    
    /// Handles permission denied scenarios gracefully
    /// - Parameter url: The URL that was denied access
    /// - Returns: User-friendly error message and recovery suggestions
    func handlePermissionDenied(for url: URL) -> PermissionDeniedInfo {
        logger.warning("Permission denied for: \(url.path)")
        
        let info = PermissionDeniedInfo(
            deniedURL: url,
            errorMessage: "Access denied to \(url.lastPathComponent)",
            recoverySuggestion: generateRecoverySuggestion(for: url),
            canRetry: true
        )
        
        permissionStatus = .denied(info)
        return info
    }
    
    /// Validates file access before performing operations
    /// - Parameter urls: Array of URLs to validate
    /// - Returns: ValidationResult with success status and any issues
    func validateFileAccess(for urls: [URL]) async -> FileAccessValidationResult {
        var accessibleURLs: [URL] = []
        var deniedURLs: [URL] = []
        var errors: [FilePermissionError] = []
        
        for url in urls {
            if await requestFileAccess(for: url) {
                accessibleURLs.append(url)
            } else {
                deniedURLs.append(url)
                let error = FilePermissionError.accessDenied(url: url)
                errors.append(error)
            }
        }
        
        let isFullyAccessible = deniedURLs.isEmpty
        permissionStatus = isFullyAccessible ? .granted : .partiallyDenied(deniedURLs)
        
        return FileAccessValidationResult(
            isFullyAccessible: isFullyAccessible,
            accessibleURLs: accessibleURLs,
            deniedURLs: deniedURLs,
            errors: errors
        )
    }
    
    /// Restores security-scoped bookmark access for a cached path
    /// This should be called when loading cached paths to restore access permissions
    /// - Parameter path: The file path that was previously granted access
    /// - Returns: True if bookmark was found and access was restored, false otherwise
    func restoreAccessForCachedPath(_ path: String) -> Bool {
        logger.info("Attempting to restore access for cached path: \(path)")
        
        // Get stored bookmarks
        guard let bookmarks = UserDefaults.standard.dictionary(forKey: "SecurityScopedBookmarks") as? [String: Data] else {
            logger.debug("No stored bookmarks found")
            return false
        }
        
        // Find bookmark for this path
        guard let bookmarkData = bookmarks[path] else {
            logger.debug("No bookmark found for path: \(path)")
            return false
        }
        
        // Resolve bookmark to URL
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                logger.warning("Bookmark is stale for path: \(path)")
                // Remove stale bookmark
                var updatedBookmarks = bookmarks
                updatedBookmarks.removeValue(forKey: path)
                UserDefaults.standard.set(updatedBookmarks, forKey: "SecurityScopedBookmarks")
                return false
            }
            
            // Start accessing the security-scoped resource
            let success = url.startAccessingSecurityScopedResource()
            if success {
                logger.info("Successfully restored access for: \(path)")
                return true
            } else {
                logger.warning("Failed to start accessing security-scoped resource for: \(path)")
                return false
            }
        } catch {
            logger.error("Failed to resolve bookmark for \(path): \(error.localizedDescription)")
            return false
        }
    }
    
    /// 解析 path 对应的 security-scoped bookmark，并开始访问；调用方用完后必须对该 URL 调用 stopAccessingSecurityScopedResource()
    /// 会尝试精确 path、标准化 path、以及按“解析后路径一致”匹配所有已存 bookmark
    /// - Parameter path: 已通过 fileImporter/NSOpenPanel 授权并缓存过 bookmark 的路径
    /// - Returns: 具备 security-scoped 的 URL，若未找到或已过期则返回 nil
    func resolveAndStartAccessingSecurityScopedResource(for path: String) -> URL? {
        guard let bookmarks = UserDefaults.standard.dictionary(forKey: "SecurityScopedBookmarks") as? [String: Data],
              !bookmarks.isEmpty else {
            logger.debug("No bookmarks stored")
            return nil
        }
        let pathNorm = URL(fileURLWithPath: path).standardized.path
        func tryBookmark(_ bookmarkData: Data) -> URL? {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale { return nil }
                let ok = url.startAccessingSecurityScopedResource()
                return ok ? url : nil
            } catch {
                return nil
            }
        }
        if let data = bookmarks[path], let url = tryBookmark(data) {
            logger.info("Started security-scoped access (exact path) for: \(path)")
            return url
        }
        if pathNorm != path, let data = bookmarks[pathNorm], let url = tryBookmark(data) {
            logger.info("Started security-scoped access (normalized path) for: \(path)")
            return url
        }
        for (_, data) in bookmarks {
            guard let url = tryBookmark(data) else { continue }
            let resolvedPath = url.path
            let resolvedNorm = URL(fileURLWithPath: resolvedPath).standardized.path
            url.stopAccessingSecurityScopedResource()
            if resolvedPath == path || resolvedNorm == pathNorm {
                let again = tryBookmark(data)
                if again != nil {
                    logger.info("Started security-scoped access (matched by resolved path) for: \(path)")
                    return again
                }
            }
        }
        logger.debug("No matching bookmark for path: \(path)")
        return nil
    }
    
    // MARK: - Private Methods
    
    /// Checks initial permissions on service initialization
    private func checkInitialPermissions() {
        // Check if we have any stored security-scoped bookmarks
        let hasStoredBookmarks = UserDefaults.standard.object(forKey: "SecurityScopedBookmarks") != nil
        hasFileAccessPermission = hasStoredBookmarks
        permissionStatus = hasStoredBookmarks ? .granted : .unknown
        
        logger.info("Initial permission check: \(hasStoredBookmarks ? "Has stored bookmarks" : "No stored bookmarks")")
    }
    
    /// Checks if we already have access to the specified URL
    /// - Parameter url: The URL to check
    /// - Returns: True if access exists, false otherwise
    private func hasExistingAccess(to url: URL) -> Bool {
        // Check if URL is accessible by attempting to read its attributes
        do {
            _ = try url.resourceValues(forKeys: [.isReadableKey])
            return true
        } catch {
            logger.debug("No existing access to: \(url.path) - \(error.localizedDescription)")
            return false
        }
    }
    
    /// Requests security-scoped access for the URL
    /// - Parameter url: The URL to request access for
    /// - Returns: True if access granted, false otherwise
    private func requestSecurityScopedAccess(for url: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let openPanel = NSOpenPanel()
                openPanel.canChooseFiles = url.hasDirectoryPath ? false : true
                openPanel.canChooseDirectories = url.hasDirectoryPath ? true : false
                openPanel.allowsMultipleSelection = false
                openPanel.directoryURL = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
                
                if url.hasDirectoryPath {
                    openPanel.message = "Grant access to the directory: \(url.lastPathComponent)"
                    openPanel.prompt = "Grant Access"
                } else {
                    openPanel.message = "Grant access to the file: \(url.lastPathComponent)"
                    openPanel.prompt = "Grant Access"
                    openPanel.nameFieldStringValue = url.lastPathComponent
                }
                
                openPanel.begin { response in
                    if response == .OK, let selectedURL = openPanel.url {
                        let granted = self.storeSecurityScopedBookmark(for: selectedURL)
                        self.hasFileAccessPermission = granted
                        self.permissionStatus = granted ? .granted : .denied(
                            PermissionDeniedInfo(
                                deniedURL: url,
                                errorMessage: "Failed to store security bookmark",
                                recoverySuggestion: "Please try selecting the file again",
                                canRetry: true
                            )
                        )
                        continuation.resume(returning: granted)
                    } else {
                        self.permissionStatus = .denied(
                            PermissionDeniedInfo(
                                deniedURL: url,
                                errorMessage: "User cancelled file access request",
                                recoverySuggestion: "Please grant access to continue with analysis",
                                canRetry: true
                            )
                        )
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }
    
    /// Stores a security-scoped bookmark for the URL
    /// This should be called when the user has already granted access (e.g., via fileImporter / NSOpenPanel).
    /// 必须先 startAccessingSecurityScopedResource，否则沙盒下 bookmarkData 会因无权限打开文件而失败。
    /// - Parameter url: The URL to create a bookmark for (应为 fileImporter 返回的 security-scoped URL)
    /// - Returns: True if bookmark created successfully, false otherwise
    func storeSecurityScopedBookmark(for url: URL) -> Bool {
        // 沙盒下：创建 bookmark 时系统会打开文件，必须先“开始访问” fileImporter 授予的 URL，否则 Operation not permitted
        let didStart = url.startAccessingSecurityScopedResource()
        if !didStart {
            logger.warning("startAccessingSecurityScopedResource returned false for: \(url.path)")
        }
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            var bookmarks = UserDefaults.standard.dictionary(forKey: "SecurityScopedBookmarks") ?? [:]
            let pathKey = url.path
            let pathNorm = url.standardized.path
            bookmarks[pathKey] = bookmarkData
            if pathNorm != pathKey {
                bookmarks[pathNorm] = bookmarkData
            }
            UserDefaults.standard.set(bookmarks, forKey: "SecurityScopedBookmarks")
            UserDefaults.standard.synchronize()
            
            logger.info("Stored security-scoped bookmark for: \(url.path)")
            return true
        } catch {
            logger.error("Failed to create security-scoped bookmark: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Generates recovery suggestion for permission denied scenarios
    /// - Parameter url: The URL that was denied
    /// - Returns: User-friendly recovery suggestion
    private func generateRecoverySuggestion(for url: URL) -> String {
        if url.hasDirectoryPath {
            return """
            To analyze this project, the app needs access to the project directory.
            
            Please:
            1. Click 'Grant Access' to open the file picker
            2. Navigate to and select the project folder
            3. Click 'Grant Access' to allow the app to read the files
            
            This permission is required to comply with macOS security requirements.
            """
        } else {
            return """
            To analyze this file, the app needs read access.
            
            Please:
            1. Click 'Grant Access' to open the file picker
            2. Select the file you want to analyze
            3. Click 'Grant Access' to allow the app to read the file
            
            This permission is required to comply with macOS security requirements.
            """
        }
    }
}

// MARK: - Supporting Types

enum PermissionStatus {
    case unknown
    case granted
    case denied(PermissionDeniedInfo)
    case partiallyDenied([URL])
}

struct PermissionDeniedInfo {
    let deniedURL: URL
    let errorMessage: String
    let recoverySuggestion: String
    let canRetry: Bool
}

struct FileAccessValidationResult {
    let isFullyAccessible: Bool
    let accessibleURLs: [URL]
    let deniedURLs: [URL]
    let errors: [FilePermissionError]
}

enum FilePermissionError: LocalizedError {
    case accessDenied(url: URL)
    case bookmarkCreationFailed(url: URL, underlyingError: Error)
    case bookmarkResolutionFailed(url: URL, underlyingError: Error)
    case securityScopeActivationFailed(url: URL)
    
    var errorDescription: String? {
        switch self {
        case .accessDenied(let url):
            return "Access denied to \(url.lastPathComponent)"
        case .bookmarkCreationFailed(let url, _):
            return "Failed to create security bookmark for \(url.lastPathComponent)"
        case .bookmarkResolutionFailed(let url, _):
            return "Failed to resolve security bookmark for \(url.lastPathComponent)"
        case .securityScopeActivationFailed(let url):
            return "Failed to activate security scope for \(url.lastPathComponent)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .accessDenied:
            return "Please grant file access permission to continue"
        case .bookmarkCreationFailed, .bookmarkResolutionFailed, .securityScopeActivationFailed:
            return "Please try selecting the file again"
        }
    }
}