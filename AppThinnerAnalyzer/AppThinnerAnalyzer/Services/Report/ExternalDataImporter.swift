import Foundation

// MARK: - 外部数据导入器协议
// 负责从外部文件（如 txt/csv）导入无用资源列表和无用类列表，
// 并将外部数据与本地静态分析结果合并，同时支持将分析结果导出为外部格式。

protocol ExternalDataImporterProtocol {
    func importUnusedResourcesList(from filePath: String) async throws -> [String]
    func importUnusedClassesList(from filePath: String) async throws -> [String]
    func mergeWithLocalAnalysis(
        externalUnusedResources: [String],
        localUnusedResources: [UnusedResource]
    ) -> [UnusedResource]
    func mergeWithLocalAnalysis(
        externalUnusedClasses: [String],
        localUnusedCode: [UnusedCode]
    ) -> [UnusedCode]
    func validateImportedData(
        _ data: [String],
        type: ImportedDataType
    ) throws -> ValidationResult
    func exportUnusedData(
        resources: [UnusedResource],
        code: [UnusedCode],
        format: ExportFormat,
        to filePath: String
    ) async throws
}

// MARK: - ExternalDataImporter Implementation

class ExternalDataImporter: ExternalDataImporterProtocol {
    
    // MARK: - Public Methods
    
    func importUnusedResourcesList(from filePath: String) async throws -> [String] {
        let fileURL = URL(fileURLWithPath: filePath)
        
        // Validate file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ImportError.fileNotFound(filePath)
        }
        
        let fileExtension = fileURL.pathExtension.lowercased()
        
        switch fileExtension {
        case "json":
            return try await parseJSONResourceList(from: filePath)
        case "csv":
            return try await parseCSVResourceList(from: filePath)
        case "txt":
            return try await parseTextResourceList(from: filePath)
        case "plist":
            return try await parsePlistResourceList(from: filePath)
        default:
            throw ImportError.unsupportedFormat(fileExtension)
        }
    }
    
    func importUnusedClassesList(from filePath: String) async throws -> [String] {
        let fileURL = URL(fileURLWithPath: filePath)
        
        // Validate file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ImportError.fileNotFound(filePath)
        }
        
        let fileExtension = fileURL.pathExtension.lowercased()
        
        switch fileExtension {
        case "json":
            return try await parseJSONClassList(from: filePath)
        case "csv":
            return try await parseCSVClassList(from: filePath)
        case "txt":
            return try await parseTextClassList(from: filePath)
        case "plist":
            return try await parsePlistClassList(from: filePath)
        default:
            throw ImportError.unsupportedFormat(fileExtension)
        }
    }
    
    func mergeWithLocalAnalysis(
        externalUnusedResources: [String],
        localUnusedResources: [UnusedResource]
    ) -> [UnusedResource] {
        var mergedResources: [UnusedResource] = []
        
        // Add all local analysis results
        mergedResources.append(contentsOf: localUnusedResources)
        
        // Create set of local resource paths for efficient lookup
        let localResourcePaths = Set(localUnusedResources.map { $0.relativePath })
        
        // Add external resources that weren't found by local analysis
        for externalResourcePath in externalUnusedResources {
            if !localResourcePaths.contains(externalResourcePath) {
                // Create UnusedResource from external data
                let fileName = URL(fileURLWithPath: externalResourcePath).lastPathComponent
                let resourceType = determineResourceType(from: fileName)
                
                let externalUnusedResource = UnusedResource(
                    relativePath: externalResourcePath,
                    fileName: fileName,
                    size: 0, // Size unknown from external data
                    resourceType: resourceType,
                    detectionMethod: .externalData,
                    recommendedAction: .reviewRequired
                )
                
                mergedResources.append(externalUnusedResource)
            } else {
                // Update existing resource to indicate it was also found externally
                if let index = mergedResources.firstIndex(where: { $0.relativePath == externalResourcePath }) {
                    let existingResource = mergedResources[index]
                    let updatedResource = UnusedResource(
                        relativePath: existingResource.relativePath,
                        fileName: existingResource.fileName,
                        size: existingResource.size,
                        resourceType: existingResource.resourceType,
                        detectionMethod: .externalData, // Mark as confirmed by external data
                        recommendedAction: .safeToDelete // Higher confidence when confirmed externally
                    )
                    mergedResources[index] = updatedResource
                }
            }
        }
        
        return mergedResources
    }
    
    func mergeWithLocalAnalysis(
        externalUnusedClasses: [String],
        localUnusedCode: [UnusedCode]
    ) -> [UnusedCode] {
        var mergedCode: [UnusedCode] = []
        
        // Add all local analysis results
        mergedCode.append(contentsOf: localUnusedCode)
        
        // Create set of local class names for efficient lookup
        let localClassNames = Set(localUnusedCode.map { $0.className })
        
        // Add external classes that weren't found by local analysis
        for externalClassName in externalUnusedClasses {
            if !localClassNames.contains(externalClassName) {
                let externalUnusedCode = UnusedCode(
                    className: externalClassName,
                    filePath: "Unknown", // Path unknown from external data
                    estimatedSize: 0, // Size unknown from external data
                    detectionMethod: .externalData,
                    dependencies: [], // Dependencies unknown from external data
                    riskLevel: .medium // Default to medium risk for external data
                )
                
                mergedCode.append(externalUnusedCode)
            } else {
                // Update existing code to indicate it was also found externally
                if let index = mergedCode.firstIndex(where: { $0.className == externalClassName }) {
                    let existingCode = mergedCode[index]
                    let updatedCode = UnusedCode(
                        className: existingCode.className,
                        filePath: existingCode.filePath,
                        estimatedSize: existingCode.estimatedSize,
                        detectionMethod: .externalData, // Mark as confirmed by external data
                        dependencies: existingCode.dependencies,
                        riskLevel: .low // Lower risk when confirmed externally
                    )
                    mergedCode[index] = updatedCode
                }
            }
        }
        
        return mergedCode
    }
    
    func validateImportedData(
        _ data: [String],
        type: ImportedDataType
    ) throws -> ValidationResult {
        var validItems: [String] = []
        var invalidItems: [InvalidItem] = []
        var warnings: [String] = []
        
        for item in data {
            let trimmedItem = item.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty items
            if trimmedItem.isEmpty {
                continue
            }
            
            switch type {
            case .resourcePaths:
                let validation = validateResourcePath(trimmedItem)
                if validation.isValid {
                    validItems.append(trimmedItem)
                } else {
                    invalidItems.append(InvalidItem(
                        item: trimmedItem,
                        reason: validation.reason
                    ))
                }
                
            case .classNames:
                let validation = validateClassName(trimmedItem)
                if validation.isValid {
                    validItems.append(trimmedItem)
                } else {
                    invalidItems.append(InvalidItem(
                        item: trimmedItem,
                        reason: validation.reason
                    ))
                }
            }
        }
        
        // Generate warnings for common issues
        if invalidItems.count > validItems.count {
            warnings.append("More than half of the imported items are invalid")
        }
        
        if validItems.isEmpty {
            warnings.append("No valid items found in imported data")
        }
        
        return ValidationResult(
            validItems: validItems,
            invalidItems: invalidItems,
            warnings: warnings,
            totalProcessed: data.count
        )
    }
    
    func exportUnusedData(
        resources: [UnusedResource],
        code: [UnusedCode],
        format: ExportFormat,
        to filePath: String
    ) async throws {
        let fileURL = URL(fileURLWithPath: filePath)
        
        switch format {
        case .json:
            try await exportAsJSON(resources: resources, code: code, to: fileURL)
        case .csv:
            try await exportAsCSV(resources: resources, code: code, to: fileURL)
        case .txt:
            try await exportAsText(resources: resources, code: code, to: fileURL)
        case .plist:
            try await exportAsPlist(resources: resources, code: code, to: fileURL)
        }
    }
    
    // MARK: - Private JSON Parsing Methods
    
    private func parseJSONResourceList(from filePath: String) async throws -> [String] {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        
        do {
            // Try to parse as array of strings
            if let resourceArray = try JSONSerialization.jsonObject(with: data) as? [String] {
                return resourceArray
            }
            
            // Try to parse as object with resources array
            if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let resourceArray = jsonObject["unusedResources"] as? [String] {
                return resourceArray
            }
            
            // Try to parse as array of objects with path property
            if let objectArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return objectArray.compactMap { $0["path"] as? String }
            }
            
            throw ImportError.invalidData("JSON format not recognized")
            
        } catch {
            throw ImportError.invalidData("Invalid JSON: \(error.localizedDescription)")
        }
    }
    
    private func parseJSONClassList(from filePath: String) async throws -> [String] {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        
        do {
            // Try to parse as array of strings
            if let classArray = try JSONSerialization.jsonObject(with: data) as? [String] {
                return classArray
            }
            
            // Try to parse as object with classes array
            if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let classArray = jsonObject["unusedClasses"] as? [String] {
                return classArray
            }
            
            // Try to parse as array of objects with className property
            if let objectArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return objectArray.compactMap { $0["className"] as? String }
            }
            
            throw ImportError.invalidData("JSON format not recognized")
            
        } catch {
            throw ImportError.invalidData("Invalid JSON: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private CSV Parsing Methods
    
    private func parseCSVResourceList(from filePath: String) async throws -> [String] {
        let content = try String(contentsOf: URL(fileURLWithPath: filePath), encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var resources: [String] = []
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines and potential header
            if trimmedLine.isEmpty || (index == 0 && trimmedLine.lowercased().contains("path")) {
                continue
            }
            
            // Parse CSV line (handle quoted values)
            let columns = parseCSVLine(trimmedLine)
            
            if let resourcePath = columns.first {
                resources.append(resourcePath)
            }
        }
        
        return resources
    }
    
    private func parseCSVClassList(from filePath: String) async throws -> [String] {
        let content = try String(contentsOf: URL(fileURLWithPath: filePath), encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var classes: [String] = []
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines and potential header
            if trimmedLine.isEmpty || (index == 0 && trimmedLine.lowercased().contains("class")) {
                continue
            }
            
            // Parse CSV line
            let columns = parseCSVLine(trimmedLine)
            
            if let className = columns.first {
                classes.append(className)
            }
        }
        
        return classes
    }
    
    // MARK: - Private Text Parsing Methods
    
    private func parseTextResourceList(from filePath: String) async throws -> [String] {
        let content = try String(contentsOf: URL(fileURLWithPath: filePath), encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("//") }
    }
    
    private func parseTextClassList(from filePath: String) async throws -> [String] {
        let content = try String(contentsOf: URL(fileURLWithPath: filePath), encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("//") }
    }
    
    // MARK: - Private Plist Parsing Methods
    
    private func parsePlistResourceList(from filePath: String) async throws -> [String] {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        
        do {
            if let plistArray = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String] {
                return plistArray
            }
            
            if let plistDict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let resourceArray = plistDict["UnusedResources"] as? [String] {
                return resourceArray
            }
            
            throw ImportError.invalidData("Plist format not recognized")
            
        } catch {
            throw ImportError.invalidData("Invalid Plist: \(error.localizedDescription)")
        }
    }
    
    private func parsePlistClassList(from filePath: String) async throws -> [String] {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        
        do {
            if let plistArray = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String] {
                return plistArray
            }
            
            if let plistDict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let classArray = plistDict["UnusedClasses"] as? [String] {
                return classArray
            }
            
            throw ImportError.invalidData("Plist format not recognized")
            
        } catch {
            throw ImportError.invalidData("Invalid Plist: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Export Methods
    
    private func exportAsJSON(
        resources: [UnusedResource],
        code: [UnusedCode],
        to fileURL: URL
    ) async throws {
        let exportData: [String: Any] = [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "unusedResources": resources.map { resource in
                [
                    "path": resource.relativePath,
                    "fileName": resource.fileName,
                    "size": resource.size,
                    "type": resource.resourceType.rawValue,
                    "detectionMethod": resource.detectionMethod.rawValue,
                    "recommendedAction": "\(resource.recommendedAction)"
                ]
            },
            "unusedClasses": code.map { codeItem in
                [
                    "className": codeItem.className,
                    "filePath": codeItem.filePath,
                    "estimatedSize": codeItem.estimatedSize,
                    "detectionMethod": codeItem.detectionMethod.rawValue,
                    "riskLevel": "\(codeItem.riskLevel)",
                    "dependencies": codeItem.dependencies
                ]
            }
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
        try jsonData.write(to: fileURL)
    }
    
    private func exportAsCSV(
        resources: [UnusedResource],
        code: [UnusedCode],
        to fileURL: URL
    ) async throws {
        var csvContent = ""
        
        // Export resources
        csvContent += "# Unused Resources\n"
        csvContent += "Path,FileName,Size,Type,DetectionMethod,RecommendedAction\n"
        
        for resource in resources {
            let line = [
                escapeCSVField(resource.relativePath),
                escapeCSVField(resource.fileName),
                "\(resource.size)",
                escapeCSVField(resource.resourceType.rawValue),
                escapeCSVField(resource.detectionMethod.rawValue),
                escapeCSVField("\(resource.recommendedAction)")
            ].joined(separator: ",")
            
            csvContent += line + "\n"
        }
        
        csvContent += "\n# Unused Classes\n"
        csvContent += "ClassName,FilePath,EstimatedSize,DetectionMethod,RiskLevel,Dependencies\n"
        
        for codeItem in code {
            let line = [
                escapeCSVField(codeItem.className),
                escapeCSVField(codeItem.filePath),
                "\(codeItem.estimatedSize)",
                escapeCSVField(codeItem.detectionMethod.rawValue),
                escapeCSVField("\(codeItem.riskLevel)"),
                escapeCSVField(codeItem.dependencies.joined(separator: ";"))
            ].joined(separator: ",")
            
            csvContent += line + "\n"
        }
        
        try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func exportAsText(
        resources: [UnusedResource],
        code: [UnusedCode],
        to fileURL: URL
    ) async throws {
        var textContent = ""
        
        textContent += "# iOS App Analyzer - Unused Content Report\n"
        textContent += "# Generated: \(Date())\n\n"
        
        textContent += "## Unused Resources (\(resources.count) items)\n\n"
        for resource in resources {
            textContent += "\(resource.relativePath)\n"
        }
        
        textContent += "\n## Unused Classes (\(code.count) items)\n\n"
        for codeItem in code {
            textContent += "\(codeItem.className)\n"
        }
        
        try textContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func exportAsPlist(
        resources: [UnusedResource],
        code: [UnusedCode],
        to fileURL: URL
    ) async throws {
        let plistData: [String: Any] = [
            "ExportDate": Date(),
            "UnusedResources": resources.map { $0.relativePath },
            "UnusedClasses": code.map { $0.className }
        ]
        
        let data = try PropertyListSerialization.data(fromPropertyList: plistData, format: .xml, options: 0)
        try data.write(to: fileURL)
    }
    
    // MARK: - Private Helper Methods
    
    private func parseCSVLine(_ line: String) -> [String] {
        var columns: [String] = []
        var currentColumn = ""
        var insideQuotes = false
        
        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                columns.append(currentColumn.trimmingCharacters(in: .whitespacesAndNewlines))
                currentColumn = ""
            } else {
                currentColumn.append(char)
            }
        }
        
        // Add the last column
        columns.append(currentColumn.trimmingCharacters(in: .whitespacesAndNewlines))
        
        return columns
    }
    
    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let escapedField = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escapedField)\""
        }
        return field
    }
    
    private func determineResourceType(from fileName: String) -> ResourceType {
        let pathExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        
        switch pathExtension {
        case "png", "jpg", "jpeg", "gif", "svg", "pdf", "tiff", "bmp", "webp", "heic", "heif":
            return .image
        case "mp3", "wav", "aac", "m4a", "flac", "ogg", "wma":
            return .audio
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm":
            return .video
        case "json", "plist", "xml", "txt", "strings", "stringsdict", "csv", "yaml", "yml":
            return .data
        default:
            return .other
        }
    }
    
    private func validateResourcePath(_ path: String) -> (isValid: Bool, reason: String) {
        // Check for valid path format
        if path.isEmpty {
            return (false, "Empty path")
        }
        
        // Check for invalid characters
        let invalidChars = CharacterSet(charactersIn: "<>:\"|?*")
        if path.rangeOfCharacter(from: invalidChars) != nil {
            return (false, "Contains invalid characters")
        }
        
        // Check for reasonable path length
        if path.count > 260 {
            return (false, "Path too long")
        }
        
        return (true, "")
    }
    
    private func validateClassName(_ className: String) -> (isValid: Bool, reason: String) {
        // Check for valid Swift class name format
        if className.isEmpty {
            return (false, "Empty class name")
        }
        
        // Check if starts with letter or underscore
        guard let firstChar = className.first,
              firstChar.isLetter || firstChar == "_" else {
            return (false, "Must start with letter or underscore")
        }
        
        // Check if contains only valid characters
        let validCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if className.rangeOfCharacter(from: validCharacterSet.inverted) != nil {
            return (false, "Contains invalid characters")
        }
        
        // Check for reasonable length
        if className.count > 100 {
            return (false, "Class name too long")
        }
        
        return (true, "")
    }
}

// MARK: - Supporting Types

enum ImportedDataType {
    case resourcePaths
    case classNames
}

enum ExportFormat {
    case json
    case csv
    case txt
    case plist
}

struct ValidationResult {
    let validItems: [String]
    let invalidItems: [InvalidItem]
    let warnings: [String]
    let totalProcessed: Int
    
    var isValid: Bool {
        return !validItems.isEmpty && invalidItems.count < validItems.count
    }
    
    var validationSummary: String {
        return "Processed \(totalProcessed) items: \(validItems.count) valid, \(invalidItems.count) invalid"
    }
}

struct InvalidItem {
    let item: String
    let reason: String
}