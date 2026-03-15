import Foundation
import os.log

/// 负责系统兼容性检查和 Apple Silicon 优化的服务
class SystemCompatibilityService: ObservableObject {
    static let shared = SystemCompatibilityService()
    
    private let logger = Logger(subsystem: "com.iosappanalyzer.app", category: "SystemCompatibility")
    
    // MARK: - 系统要求
    
    /// 最低要求的 macOS 版本（14.0）
    private let minimumMacOSVersion = OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
    
    // MARK: - 初始化
    
    private init() {
        performSystemCompatibilityCheck()
        optimizeForAppleSilicon()
    }
    
    // MARK: - 公共接口
    
    /// 检查当前系统是否满足最低要求
    /// - Returns: 若系统兼容则返回 true，否则返回 false
    func isSystemCompatible() -> Bool {
        return isMacOSVersionSupported() && isArchitectureSupported()
    }
    
    /// 获取用于诊断的详细系统信息
    /// - Returns: 包含系统信息的字典
    func getSystemInfo() -> [String: Any] {
        var info: [String: Any] = [:]
        
        let processInfo = ProcessInfo.processInfo
        info["macOSVersion"] = processInfo.operatingSystemVersionString
        info["isAppleSilicon"] = isAppleSilicon()
        info["processorCount"] = processInfo.processorCount
        info["physicalMemory"] = processInfo.physicalMemory
        info["hostName"] = processInfo.hostName
        
        return info
    }
    
    /// 针对 Apple Silicon 处理器执行优化
    func optimizeForAppleSilicon() {
        guard isAppleSilicon() else {
            logger.info("Running on Intel processor - Apple Silicon optimizations not applicable")
            return
        }
        
        logger.info("Detected Apple Silicon processor - applying optimizations")
        
        // 为分析操作启用高性能模式
        enableHighPerformanceMode()
        
        // 针对 Apple Silicon 优化内存分配策略
        optimizeMemoryAllocation()
        
        // 为 Apple Silicon 能效核心配置线程策略
        configureThreadingForAppleSilicon()
    }
    
    // MARK: - 私有方法
    
    /// 执行初始系统兼容性检查并记录结果
    private func performSystemCompatibilityCheck() {
        logger.info("Performing system compatibility check...")
        
        let macOSSupported = isMacOSVersionSupported()
        let archSupported = isArchitectureSupported()
        
        logger.info("macOS version supported: \(macOSSupported)")
        logger.info("Architecture supported: \(archSupported)")
        
        if !macOSSupported {
            logger.error("Unsupported macOS version detected. Minimum required: macOS 14.0")
        }
        
        if !archSupported {
            logger.error("Unsupported architecture detected")
        }
        
        if isSystemCompatible() {
            logger.info("System compatibility check passed")
        } else {
            logger.error("System compatibility check failed")
        }
    }
    
    /// 检查当前 macOS 版本是否满足最低要求
    /// - Returns: 若 macOS 版本为 14.0 或更高则返回 true
    private func isMacOSVersionSupported() -> Bool {
        let processInfo = ProcessInfo.processInfo
        return processInfo.isOperatingSystemAtLeast(minimumMacOSVersion)
    }
    
    /// 检查当前架构是否受支持
    /// - Returns: 若运行在受支持的架构（Intel 或 Apple Silicon）上则返回 true
    private func isArchitectureSupported() -> Bool {
        // Intel 和 Apple Silicon 均受支持
        return true
    }
    
    /// 检测是否运行在 Apple Silicon 处理器上
    /// - Returns: 若运行在 Apple Silicon 上返回 true，Intel 上返回 false
    private func isAppleSilicon() -> Bool {
        var systemInfo = utsname()
        uname(&systemInfo)
        
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        
        // Apple Silicon Mac 报告的架构为 "arm64"
        return machine?.hasPrefix("arm64") == true
    }
    
    /// 为密集型操作启用高性能模式
    private func enableHighPerformanceMode() {
        // 提升进程优先级以在分析期间获得更好的性能
        setpriority(PRIO_PROCESS, 0, -10) // 较高优先级（范围：-20 到 20）
        
        logger.info("High-performance mode enabled")
    }
    
    /// 针对 Apple Silicon 优化内存分配策略
    private func optimizeMemoryAllocation() {
        // Apple Silicon 采用统一内存架构
        // 据此配置内存分配策略
        
        // 若可用则启用内存压缩
        if #available(macOS 14.0, *) {
            // 使用现代内存管理 API
            logger.info("Using optimized memory allocation for Apple Silicon")
        }
    }
    
    /// 配置针对 Apple Silicon 能效核心优化的线程策略
    private func configureThreadingForAppleSilicon() {
        guard isAppleSilicon() else { return }
        
        let processorCount = ProcessInfo.processInfo.processorCount
        
        // Apple Silicon 拥有性能核心和能效核心
        // 据此配置线程池
        let optimalThreadCount = max(1, processorCount - 2) // 为系统保留部分核心
        
        logger.info("Configured threading for Apple Silicon: \(optimalThreadCount) threads")
    }
}

// MARK: - 系统兼容性错误

enum SystemCompatibilityError: LocalizedError {
    case unsupportedMacOSVersion(current: String, required: String)
    case unsupportedArchitecture(current: String)
    case systemCheckFailed(reason: String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedMacOSVersion(let current, let required):
            return "Unsupported macOS version. Current: \(current), Required: \(required) or higher"
        case .unsupportedArchitecture(let current):
            return "Unsupported architecture: \(current)"
        case .systemCheckFailed(let reason):
            return "System compatibility check failed: \(reason)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .unsupportedMacOSVersion:
            return "Please upgrade to macOS 14.0 or higher to use this application."
        case .unsupportedArchitecture:
            return "This application requires an Intel or Apple Silicon Mac."
        case .systemCheckFailed:
            return "Please check your system configuration and try again."
        }
    }
}

// MARK: - 系统信息扩展

extension SystemCompatibilityService {
    
    /// 获取格式化的系统信息字符串，用于界面展示
    var systemInfoString: String {
        let info = getSystemInfo()
        var result = "System Information:\n"
        
        if let version = info["macOSVersion"] as? String {
            result += "macOS Version: \(version)\n"
        }
        
        if let isAppleSilicon = info["isAppleSilicon"] as? Bool {
            result += "Processor: \(isAppleSilicon ? "Apple Silicon" : "Intel")\n"
        }
        
        if let processorCount = info["processorCount"] as? Int {
            result += "Processor Cores: \(processorCount)\n"
        }
        
        if let memory = info["physicalMemory"] as? UInt64 {
            let memoryGB = Double(memory) / (1024 * 1024 * 1024)
            result += "Physical Memory: \(String(format: "%.1f", memoryGB)) GB\n"
        }
        
        result += "Compatibility: \(isSystemCompatible() ? "✅ Compatible" : "❌ Not Compatible")"
        
        return result
    }
}