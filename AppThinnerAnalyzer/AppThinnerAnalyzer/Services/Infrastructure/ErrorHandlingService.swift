import Foundation
import SwiftUI

// MARK: - 错误处理服务
// 全局错误处理中心，负责统一管理和展示应用内各处产生的错误，
// 提供错误分类、恢复建议、历史记录等能力，并通过 @Published 属性驱动 UI 更新。

/// 全局错误处理服务，通过 ObservableObject 将错误状态暴露给 SwiftUI 视图层
class ErrorHandlingService: ObservableObject {
    static let shared = ErrorHandlingService()
    
    @Published var currentError: AppError?
    @Published var errorHistory: [ErrorRecord] = []
    
    private let maxErrorHistoryCount = 100
    
    private init() {}
    
    // MARK: - 错误处理方法
    
    /// 处理错误并自动生成恢复建议
    func handleError(_ error: Error, context: ErrorContext = .general) {
        let appError = convertToAppError(error, context: context)
        
        // Log the error
        logError(appError, context: context)
        
        // Add to error history
        addToErrorHistory(appError, context: context)
        
        // Set current error for UI display
        DispatchQueue.main.async {
            self.currentError = appError
        }
        
        // Attempt automatic recovery if possible
        attemptAutomaticRecovery(for: appError, context: context)
    }
    
    /// Handle an error with custom recovery options
    func handleError(
        _ error: Error,
        context: ErrorContext = .general,
        recoveryOptions: [ErrorRecoveryOption]
    ) {
        let appError = convertToAppError(error, context: context)
        appError.recoveryOptions = recoveryOptions
        
        handleError(appError, context: context)
    }
    
    /// Clear the current error
    func clearCurrentError() {
        DispatchQueue.main.async {
            self.currentError = nil
        }
    }
    
    /// Get user-friendly error message
    func getUserFriendlyMessage(for error: Error) -> String {
        let appError = convertToAppError(error)
        return appError.userFriendlyMessage
    }
    
    /// Get recovery suggestions for an error
    func getRecoverySuggestions(for error: Error) -> [String] {
        let appError = convertToAppError(error)
        return appError.recoverySuggestions
    }
    
    // MARK: - Error Conversion
    
    private func convertToAppError(_ error: Error, context: ErrorContext = .general) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        
        if let analysisError = error as? AnalysisError {
            return convertAnalysisError(analysisError, context: context)
        }
        
        // Handle system errors
        if let nsError = error as NSError? {
            return convertNSError(nsError, context: context)
        }
        
        // Fallback for unknown errors
        return AppError(
            type: .unknown,
            originalError: error,
            userFriendlyMessage: "An unexpected error occurred",
            technicalDetails: error.localizedDescription,
            recoverySuggestions: ["Try the operation again", "Restart the application if the problem persists"],
            context: context
        )
    }
    
    private func convertAnalysisError(_ error: AnalysisError, context: ErrorContext) -> AppError {
        switch error {
        case .invalidFilePath(let path):
            return AppError(
                type: .fileAccess,
                originalError: error,
                userFriendlyMessage: "Cannot access the specified file or directory",
                technicalDetails: "Invalid file path: \(path)",
                recoverySuggestions: [
                    "Check that the file or directory exists",
                    "Verify you have permission to access the file",
                    "Try selecting the file again using the file picker"
                ],
                context: context
            )
            
        case .unsupportedFileFormat(let format):
            return AppError(
                type: .dataProcessing,
                originalError: error,
                userFriendlyMessage: "Unsupported file format",
                technicalDetails: "Unsupported file format: \(format)",
                recoverySuggestions: [
                    "Use a supported file format",
                    "Convert the file to a supported format and try again"
                ],
                context: context
            )
            
        case .corruptedFile(let file):
            return AppError(
                type: .dataProcessing,
                originalError: error,
                userFriendlyMessage: "File appears to be corrupted",
                technicalDetails: "Corrupted file: \(file)",
                recoverySuggestions: [
                    "Try using a different copy of the file",
                    "Verify the file was downloaded or exported correctly"
                ],
                context: context
            )
            
        case .insufficientPermissions(let details):
            return AppError(
                type: .permissions,
                originalError: error,
                userFriendlyMessage: "Permission denied to access required files",
                technicalDetails: details,
                recoverySuggestions: [
                    "Grant file access permission when prompted",
                    "Check System Preferences > Security & Privacy > Files and Folders",
                    "Try dragging the files directly into the application window"
                ],
                context: context
            )
            
        case .pathMappingFailed(let reason):
            return AppError(
                type: .dataProcessing,
                originalError: error,
                userFriendlyMessage: "Failed to map project paths",
                technicalDetails: reason,
                recoverySuggestions: [
                    "Verify the project structure matches the expected layout",
                    "Check custom path mapping settings if any"
                ],
                context: context
            )
            
        case .parsingError(let details):
            return AppError(
                type: .dataProcessing,
                originalError: error,
                userFriendlyMessage: "Unable to parse the selected file",
                technicalDetails: details,
                recoverySuggestions: [
                    "Verify the file format is supported",
                    "Check that the file is not corrupted",
                    "Try using a different version of the file"
                ],
                context: context
            )
            
        case .coreDataError(let details):
            return AppError(
                type: .database,
                originalError: error,
                userFriendlyMessage: "Database operation failed",
                technicalDetails: details,
                recoverySuggestions: [
                    "Try the operation again",
                    "Restart the application",
                    "Check available disk space"
                ],
                context: context
            )
        }
    }
    
    private func convertNSError(_ error: NSError, context: ErrorContext) -> AppError {
        switch error.domain {
        case NSCocoaErrorDomain:
            return convertCocoaError(error, context: context)
        case NSURLErrorDomain:
            return convertURLError(error, context: context)
        default:
            return AppError(
                type: .system,
                originalError: error,
                userFriendlyMessage: "A system error occurred",
                technicalDetails: "\(error.domain): \(error.localizedDescription)",
                recoverySuggestions: ["Try the operation again", "Restart the application"],
                context: context
            )
        }
    }
    
    private func convertCocoaError(_ error: NSError, context: ErrorContext) -> AppError {
        switch error.code {
        case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
            return AppError(
                type: .permissions,
                originalError: error,
                userFriendlyMessage: "Permission denied to access file",
                technicalDetails: error.localizedDescription,
                recoverySuggestions: [
                    "Grant file access permission",
                    "Check file permissions in Finder",
                    "Try running as administrator"
                ],
                context: context
            )
            
        case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
            return AppError(
                type: .fileAccess,
                originalError: error,
                userFriendlyMessage: "File not found",
                technicalDetails: error.localizedDescription,
                recoverySuggestions: [
                    "Check that the file exists",
                    "Verify the file path is correct",
                    "Try selecting the file again"
                ],
                context: context
            )
            
        case NSFileReadCorruptFileError:
            return AppError(
                type: .dataProcessing,
                originalError: error,
                userFriendlyMessage: "File appears to be corrupted",
                technicalDetails: error.localizedDescription,
                recoverySuggestions: [
                    "Try using a different copy of the file",
                    "Verify the file was downloaded completely",
                    "Check the file format is supported"
                ],
                context: context
            )
            
        default:
            return AppError(
                type: .system,
                originalError: error,
                userFriendlyMessage: "File system error",
                technicalDetails: error.localizedDescription,
                recoverySuggestions: ["Try the operation again", "Check available disk space"],
                context: context
            )
        }
    }
    
    private func convertURLError(_ error: NSError, context: ErrorContext) -> AppError {
        return AppError(
            type: .network,
            originalError: error,
            userFriendlyMessage: "Network connection failed",
            technicalDetails: error.localizedDescription,
            recoverySuggestions: [
                "Check your internet connection",
                "Try again in a few moments",
                "Verify the URL is correct"
            ],
            context: context
        )
    }
    
    // MARK: - Error Logging
    
    private func logError(_ error: AppError, context: ErrorContext) {
        let logMessage = """
        [ERROR] \(Date().formatted())
        Context: \(context.rawValue)
        Type: \(error.type.rawValue)
        Message: \(error.userFriendlyMessage)
        Technical: \(error.technicalDetails)
        Original: \(error.originalError?.localizedDescription ?? "N/A")
        """
        
        print(logMessage)
        
        // In a production app, you might want to log to a file or crash reporting service
        #if DEBUG
        NSLog(logMessage)
        #endif
    }
    
    private func addToErrorHistory(_ error: AppError, context: ErrorContext) {
        let record = ErrorRecord(
            error: error,
            context: context,
            timestamp: Date()
        )
        
        DispatchQueue.main.async {
            self.errorHistory.insert(record, at: 0)
            
            // Limit history size
            if self.errorHistory.count > self.maxErrorHistoryCount {
                self.errorHistory = Array(self.errorHistory.prefix(self.maxErrorHistoryCount))
            }
        }
    }
    
    // MARK: - Automatic Recovery
    
    private func attemptAutomaticRecovery(for error: AppError, context: ErrorContext) {
        switch error.type {
        case .permissions:
            // For permission errors, we can't automatically recover
            // The user needs to grant permissions manually
            break
            
        case .network:
            // For network errors, we might retry after a delay
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                // Notify that retry is available
                DispatchQueue.main.async {
                    if let currentError = self.currentError, currentError.id == error.id {
                        self.currentError?.isRetryAvailable = true
                    }
                }
            }
            
        case .fileAccess:
            // For file access errors, check if file exists now
            if case .invalidFilePath(let path) = error.originalError as? AnalysisError {
                if FileManager.default.fileExists(atPath: path) {
                    // File exists now, clear the error
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        if let currentError = self.currentError, currentError.id == error.id {
                            self.clearCurrentError()
                        }
                    }
                }
            }
            
        default:
            break
        }
    }
    
    // MARK: - Recovery Actions
    
    func executeRecoveryOption(_ option: ErrorRecoveryOption, for error: AppError) {
        switch option.type {
        case .retry:
            option.action?()
            clearCurrentError()
            
        case .ignore:
            clearCurrentError()
            
        case .openSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
            
        case .selectDifferentFile:
            // This would typically trigger a file picker
            option.action?()
            clearCurrentError()
            
        case .contactSupport:
            // Open support URL or email
            if let url = URL(string: "mailto:support@example.com?subject=iOS%20App%20Analyzer%20Error") {
                NSWorkspace.shared.open(url)
            }
            
        case .custom:
            option.action?()
            clearCurrentError()
        }
    }
}

// MARK: - Error Types

/// Comprehensive error type for the application
class AppError: Error, Identifiable, ObservableObject {
    let id = UUID()
    let type: ErrorType
    let originalError: Error?
    let userFriendlyMessage: String
    let technicalDetails: String
    let context: ErrorContext
    let timestamp: Date
    
    @Published var recoverySuggestions: [String]
    @Published var recoveryOptions: [ErrorRecoveryOption] = []
    @Published var isRetryAvailable: Bool = false
    
    init(
        type: ErrorType,
        originalError: Error? = nil,
        userFriendlyMessage: String,
        technicalDetails: String,
        recoverySuggestions: [String] = [],
        context: ErrorContext = .general
    ) {
        self.type = type
        self.originalError = originalError
        self.userFriendlyMessage = userFriendlyMessage
        self.technicalDetails = technicalDetails
        self.recoverySuggestions = recoverySuggestions
        self.context = context
        self.timestamp = Date()
        
        // Set default recovery options based on error type
        self.recoveryOptions = generateDefaultRecoveryOptions(for: type)
    }
    
    private func generateDefaultRecoveryOptions(for type: ErrorType) -> [ErrorRecoveryOption] {
        switch type {
        case .fileAccess:
            return [
                ErrorRecoveryOption(type: .selectDifferentFile, title: "Select Different File"),
                ErrorRecoveryOption(type: .retry, title: "Try Again"),
                ErrorRecoveryOption(type: .ignore, title: "Cancel")
            ]
            
        case .permissions:
            return [
                ErrorRecoveryOption(type: .openSettings, title: "Open System Preferences"),
                ErrorRecoveryOption(type: .retry, title: "Try Again"),
                ErrorRecoveryOption(type: .ignore, title: "Cancel")
            ]
            
        case .network:
            return [
                ErrorRecoveryOption(type: .retry, title: "Retry"),
                ErrorRecoveryOption(type: .ignore, title: "Work Offline")
            ]
            
        case .dataProcessing:
            return [
                ErrorRecoveryOption(type: .selectDifferentFile, title: "Select Different File"),
                ErrorRecoveryOption(type: .ignore, title: "Skip This File")
            ]
            
        case .database:
            return [
                ErrorRecoveryOption(type: .retry, title: "Try Again"),
                ErrorRecoveryOption(type: .contactSupport, title: "Contact Support")
            ]
            
        case .system, .unknown:
            return [
                ErrorRecoveryOption(type: .retry, title: "Try Again"),
                ErrorRecoveryOption(type: .contactSupport, title: "Report Issue")
            ]
        }
    }
}

/// Error type categories
enum ErrorType: String, CaseIterable {
    case fileAccess = "File Access"
    case permissions = "Permissions"
    case dataProcessing = "Data Processing"
    case network = "Network"
    case database = "Database"
    case system = "System"
    case unknown = "Unknown"
}

/// Error context for better categorization
enum ErrorContext: String, CaseIterable {
    case general = "General"
    case analysis = "Analysis"
    case fileImport = "File Import"
    case dataExport = "Data Export"
    case optimization = "Optimization"
    case comparison = "Comparison"
    case visualization = "Visualization"
    case systemCompatibility = "System Compatibility"
}

/// Recovery option for errors
struct ErrorRecoveryOption: Identifiable {
    let id = UUID()
    let type: RecoveryType
    let title: String
    let description: String?
    let action: (() -> Void)?
    
    init(type: RecoveryType, title: String, description: String? = nil, action: (() -> Void)? = nil) {
        self.type = type
        self.title = title
        self.description = description
        self.action = action
    }
}

/// Recovery action types
enum RecoveryType {
    case retry
    case ignore
    case openSettings
    case selectDifferentFile
    case contactSupport
    case custom
}

/// Error record for history tracking
struct ErrorRecord: Identifiable {
    let id = UUID()
    let error: AppError
    let context: ErrorContext
    let timestamp: Date
}

// MARK: - Error Presentation Views

/// Error alert view for presenting errors to users
struct ErrorAlertView: View {
    @ObservedObject var error: AppError
    let onRecoveryAction: (ErrorRecoveryOption) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Error header
            HStack {
                Image(systemName: iconForErrorType(error.type))
                    .foregroundColor(colorForErrorType(error.type))
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.type.rawValue)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(error.userFriendlyMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Recovery suggestions
            if !error.recoverySuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggestions:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ForEach(Array(error.recoverySuggestions.enumerated()), id: \.offset) { index, suggestion in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(suggestion)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Technical details (collapsible)
            DisclosureGroup("Technical Details") {
                Text(error.technicalDetails)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            
            // Recovery options
            HStack {
                ForEach(error.recoveryOptions) { option in
                    switch option.type {
                    case .retry:
                        Button(option.title) {
                            onRecoveryAction(option)
                        }
                        .buttonStyle(.borderedProminent)
                    case .openSettings, .selectDifferentFile:
                        Button(option.title) {
                            onRecoveryAction(option)
                        }
                        .buttonStyle(.bordered)
                    default:
                        Button(option.title) {
                            onRecoveryAction(option)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                
                Spacer()
                
                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 8)
    }
    
    private func iconForErrorType(_ type: ErrorType) -> String {
        switch type {
        case .fileAccess: return "doc.badge.exclamationmark"
        case .permissions: return "lock.shield"
        case .dataProcessing: return "exclamationmark.triangle"
        case .network: return "wifi.exclamationmark"
        case .database: return "externaldrive.badge.exclamationmark"
        case .system: return "gear.badge.exclamationmark"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private func colorForErrorType(_ type: ErrorType) -> Color {
        switch type {
        case .fileAccess, .dataProcessing: return .orange
        case .permissions: return .red
        case .network: return .blue
        case .database, .system: return .purple
        case .unknown: return .gray
        }
    }
    
    // No shared buttonStyle helper; styles are applied inline per recovery type for type safety.
}

// MARK: - Error Handling Extensions

extension View {
    /// Modifier to handle errors using the centralized error handling service
    func handleErrors(using errorService: ErrorHandlingService = .shared) -> some View {
        self.overlay(
            Group {
                if let error = errorService.currentError {
                    ErrorAlertView(
                        error: error,
                        onRecoveryAction: { option in
                            errorService.executeRecoveryOption(option, for: error)
                        },
                        onDismiss: {
                            errorService.clearCurrentError()
                        }
                    )
                    .frame(maxWidth: 500)
                    .padding()
                    .transition(.opacity.combined(with: .scale))
                }
            }
        )
    }
}