import Foundation

// MARK: - CodeAnalyzer Protocol

protocol CodeAnalyzerProtocol {
    func analyzeUnusedCode(
        from linkmapData: [SymbolInfo],
        projectPath: String
    ) async throws -> [UnusedCode]
    
    func detectUnusedClasses(
        in projectPath: String
    ) async throws -> [String]
    
    func estimateCodeSize(
        for className: String,
        in symbols: [SymbolInfo]
    ) -> Int64
    
    func buildCallGraph(
        from projectPath: String
    ) async throws -> CallGraph
    
    func analyzeMethodUsage(
        in projectPath: String,
        using callGraph: CallGraph
    ) async throws -> [UnusedMethod]
}

// MARK: - CodeAnalyzer Implementation

class CodeAnalyzer: CodeAnalyzerProtocol {
    
    private let sourceCodeParser: SourceCodeParserProtocol
    private let dependencyAnalyzer: DependencyAnalyzerProtocol
    
    init(
        sourceCodeParser: SourceCodeParserProtocol = SourceCodeParser(),
        dependencyAnalyzer: DependencyAnalyzerProtocol = DependencyAnalyzer()
    ) {
        self.sourceCodeParser = sourceCodeParser
        self.dependencyAnalyzer = dependencyAnalyzer
    }
    
    // MARK: - Public Methods
    
    func analyzeUnusedCode(
        from linkmapData: [SymbolInfo],
        projectPath: String
    ) async throws -> [UnusedCode] {
        // Parse all source files in the project
        let sourceFiles = try await sourceCodeParser.parseProject(at: projectPath)
        
        // Build dependency graph
        let dependencyGraph = try await dependencyAnalyzer.buildDependencyGraph(from: sourceFiles)
        
        // Find unused classes
        let unusedClasses = try await identifyUnusedClasses(
            from: sourceFiles,
            dependencyGraph: dependencyGraph,
            linkmapData: linkmapData
        )
        
        var unusedCode: [UnusedCode] = []
        
        for className in unusedClasses {
            let estimatedSize = estimateCodeSize(for: className, in: linkmapData)
            let dependencies = dependencyGraph.getDependencies(for: className)
            let riskLevel = calculateRiskLevel(for: className, dependencies: dependencies)
            
            if let sourceFile = sourceFiles.first(where: { $0.classes.contains(where: { $0.name == className }) }) {
                let unusedCodeItem = UnusedCode(
                    className: className,
                    filePath: sourceFile.filePath,
                    estimatedSize: estimatedSize,
                    detectionMethod: .staticAnalysis,
                    dependencies: dependencies,
                    riskLevel: riskLevel
                )
                
                unusedCode.append(unusedCodeItem)
            }
        }
        
        return unusedCode
    }
    
    func detectUnusedClasses(in projectPath: String) async throws -> [String] {
        let sourceFiles = try await sourceCodeParser.parseProject(at: projectPath)
        let dependencyGraph = try await dependencyAnalyzer.buildDependencyGraph(from: sourceFiles)
        
        return try await identifyUnusedClasses(
            from: sourceFiles,
            dependencyGraph: dependencyGraph,
            linkmapData: []
        )
    }
    
    func estimateCodeSize(for className: String, in symbols: [SymbolInfo]) -> Int64 {
        // Find symbols related to this class
        let classSymbols = symbols.filter { symbol in
            symbol.symbolName.contains(className) ||
            symbol.fileName.contains(className)
        }
        
        return classSymbols.reduce(0) { $0 + $1.size }
    }
    
    func buildCallGraph(from projectPath: String) async throws -> CallGraph {
        let sourceFiles = try await sourceCodeParser.parseProject(at: projectPath)
        return try await dependencyAnalyzer.buildCallGraph(from: sourceFiles)
    }
    
    func analyzeMethodUsage(
        in projectPath: String,
        using callGraph: CallGraph
    ) async throws -> [UnusedMethod] {
        let sourceFiles = try await sourceCodeParser.parseProject(at: projectPath)
        var unusedMethods: [UnusedMethod] = []
        
        for sourceFile in sourceFiles {
            for classInfo in sourceFile.classes {
                for method in classInfo.methods {
                    let methodSignature = "\(classInfo.name).\(method.name)"
                    
                    if !callGraph.isMethodCalled(methodSignature) && !isEntryPoint(method) {
                        let unusedMethod = UnusedMethod(
                            className: classInfo.name,
                            methodName: method.name,
                            filePath: sourceFile.filePath,
                            lineNumber: method.lineNumber,
                            estimatedSize: method.estimatedSize
                        )
                        
                        unusedMethods.append(unusedMethod)
                    }
                }
            }
        }
        
        return unusedMethods
    }
    
    // MARK: - Private Methods
    
    private func identifyUnusedClasses(
        from sourceFiles: [SourceFileInfo],
        dependencyGraph: DependencyGraph,
        linkmapData: [SymbolInfo]
    ) async throws -> [String] {
        // 获取所有类名
        let allClasses = sourceFiles.flatMap { $0.classes.map { $0.name } }
        
        // 使用并行任务组处理类检测
        return await withTaskGroup(of: String?.self) { group in
            var unusedClasses: [String] = []
            
            for className in allClasses {
                group.addTask {
                    // Skip certain types of classes that are likely to be used
                    if self.shouldSkipClass(className) {
                        return nil
                    }
                    
                    // Check if class is referenced by other classes
                    let isReferenced = dependencyGraph.isClassReferenced(className)
                    
                    // Check if class appears in linkmap (indicating it's compiled and potentially used)
                    let appearsInLinkmap = linkmapData.contains { symbol in
                        symbol.symbolName.contains(className) || symbol.fileName.contains(className)
                    }
                    
                    // Check if class is an entry point (AppDelegate, SceneDelegate, etc.)
                    let isEntryPoint = self.isEntryPointClass(className)
                    
                    // 优化：对于大型项目，跳过Interface Builder检查（通常耗时且结果有限）
                    let isUsedInIB = false // 性能优化：跳过Interface Builder检查
                    
                    if !isReferenced && !appearsInLinkmap && !isEntryPoint && !isUsedInIB {
                        return className
                    }
                    
                    return nil
                }
            }
            
            for await className in group {
                if let className = className {
                    unusedClasses.append(className)
                }
            }
            
            return unusedClasses
        }
    }
    
    private func shouldSkipClass(_ className: String) -> Bool {
        // Skip system classes and common patterns
        let skipPatterns = [
            "AppDelegate",
            "SceneDelegate",
            "ViewController",
            "TableViewController",
            "CollectionViewController",
            "NavigationController",
            "TabBarController"
        ]
        
        return skipPatterns.contains { className.contains($0) }
    }
    
    private func isEntryPointClass(_ className: String) -> Bool {
        let entryPointPatterns = [
            "AppDelegate",
            "SceneDelegate",
            "main",
            "App" // SwiftUI App protocol
        ]
        
        return entryPointPatterns.contains { className.contains($0) }
    }
    
    private func isClassUsedInInterfaceBuilder(
        _ className: String,
        in projectPath: String
    ) async throws -> Bool {
        let projectURL = URL(fileURLWithPath: projectPath)
        
        // Find all storyboard and xib files
        let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            let pathExtension = fileURL.pathExtension.lowercased()
            
            if pathExtension == "storyboard" || pathExtension == "xib" {
                do {
                    let content = try String(contentsOf: fileURL, encoding: .utf8)
                    if content.contains(className) {
                        return true
                    }
                } catch {
                    // Skip files that can't be read
                    continue
                }
            }
        }
        
        return false
    }
    
    private func calculateRiskLevel(for className: String, dependencies: [String]) -> RiskLevel {
        // Calculate risk based on various factors
        
        // High risk if class has many dependencies
        if dependencies.count > 10 {
            return .high
        }
        
        // Medium risk if class has some dependencies
        if dependencies.count > 3 {
            return .medium
        }
        
        // Low risk for classes with few or no dependencies
        return .low
    }
    
    private func isEntryPoint(_ method: MethodInfo) -> Bool {
        let entryPointMethods = [
            "main",
            "applicationDidFinishLaunching",
            "sceneDidBecomeActive",
            "viewDidLoad",
            "viewWillAppear",
            "viewDidAppear"
        ]
        
        return entryPointMethods.contains { method.name.contains($0) }
    }
}

// MARK: - SourceCodeParser Protocol and Implementation

protocol SourceCodeParserProtocol {
    func parseProject(at path: String) async throws -> [SourceFileInfo]
    func parseSourceFile(at path: String) async throws -> SourceFileInfo
}

class SourceCodeParser: SourceCodeParserProtocol {
    
    func parseProject(at path: String) async throws -> [SourceFileInfo] {
        let projectURL = URL(fileURLWithPath: path)
        
        // 使用并行任务组处理文件枚举和解析，大幅提升大工程处理性能
        return await withTaskGroup(of: [SourceFileInfo].self) { group in
            var allSourceFiles: [SourceFileInfo] = []
            
            // 分批处理文件，避免内存峰值
            let batchSize = 100
            var currentBatch: [URL] = []
            
            let enumerator = FileManager.default.enumerator(
                at: projectURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            while let fileURL = enumerator?.nextObject() as? URL {
                let pathExtension = fileURL.pathExtension.lowercased()
                
                if pathExtension == "swift" && !shouldSkipFile(fileURL) {
                    currentBatch.append(fileURL)
                    
                    if currentBatch.count >= batchSize {
                        let batch = currentBatch
                        currentBatch = []
                        
                        group.addTask {
                            return await self.processSourceFileBatch(batch)
                        }
                    }
                }
            }
            
            // 处理最后一批
            if !currentBatch.isEmpty {
                group.addTask {
                    return await self.processSourceFileBatch(currentBatch)
                }
            }
            
            // 收集所有结果
            for await batchResult in group {
                allSourceFiles.append(contentsOf: batchResult)
            }
            
            return allSourceFiles
        }
    }
    
    /// 并行处理源文件批次
    private func processSourceFileBatch(_ fileURLs: [URL]) async -> [SourceFileInfo] {
        return await withTaskGroup(of: SourceFileInfo?.self) { group in
            var sourceFiles: [SourceFileInfo] = []
            
            for fileURL in fileURLs {
                group.addTask {
                    do {
                        return try await self.parseSourceFile(at: fileURL.path)
                    } catch {
                        print("Warning: Could not parse source file \(fileURL.path): \(error)")
                        return nil
                    }
                }
            }
            
            for await sourceFile in group {
                if let sourceFile = sourceFile {
                    sourceFiles.append(sourceFile)
                }
            }
            
            return sourceFiles
        }
    }
    
    func parseSourceFile(at path: String) async throws -> SourceFileInfo {
        let fileURL = URL(fileURLWithPath: path)
        let sourceCode = try String(contentsOf: fileURL, encoding: .utf8)
        
        // 使用并行任务组同时解析类和导入，提升解析效率
        return await withTaskGroup(of: (classes: [ClassInfo], imports: [String]).self) { group in
            group.addTask {
                let classes = self.parseClasses(from: sourceCode)
                return (classes: classes, imports: [])
            }
            
            group.addTask {
                let imports = self.parseImports(from: sourceCode)
                return (classes: [], imports: imports)
            }
            
            var allClasses: [ClassInfo] = []
            var allImports: [String] = []
            
            for await result in group {
                allClasses.append(contentsOf: result.classes)
                allImports.append(contentsOf: result.imports)
            }
            
            return SourceFileInfo(
                filePath: path,
                projectPath: extractProjectPath(from: path),
                classes: allClasses,
                imports: allImports
            )
        }
    }
    
    private func parseClasses(from sourceCode: String) -> [ClassInfo] {
        let lines = sourceCode.components(separatedBy: .newlines)
        var classDeclarations: [(lineNumber: Int, line: String)] = []
        
        // 第一阶段：快速扫描找到所有类声明行
        for (lineNumber, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // 快速检测类声明（避免正则表达式开销）
            if trimmedLine.hasPrefix("class ") || 
               trimmedLine.contains(" class ") ||
               trimmedLine.hasPrefix("struct ") ||
               trimmedLine.contains(" struct ") ||
               trimmedLine.hasPrefix("enum ") ||
               trimmedLine.contains(" enum ") {
                
                classDeclarations.append((lineNumber: lineNumber, line: line))
            }
        }
        
        // 第二阶段：并行处理每个类声明
        return classDeclarations.map { declaration in
            let lineNumber = declaration.lineNumber
            let line = declaration.line
            
            let className = extractClassName(from: line)
            let superclass = extractSuperclass(from: line)
            let protocols = extractProtocols(from: line)
            
            // 优化：只扫描类范围内的代码，避免全文件扫描
            let classContent = extractClassContent(from: sourceCode, startingAt: lineNumber)
            let methods = extractMethods(from: classContent)
            let properties = extractProperties(from: classContent)
            let dependencies = extractClassDependencies(from: classContent, className: className)
            
            return ClassInfo(
                name: className,
                superclass: superclass,
                protocols: protocols,
                methods: methods,
                properties: properties,
                dependencies: dependencies,
                lineNumber: lineNumber + 1
            )
        }
    }
    
    /// 提取类范围内的代码内容（从类声明到下一个类声明或文件结束）
    private func extractClassContent(from sourceCode: String, startingAt lineNumber: Int) -> String {
        let lines = sourceCode.components(separatedBy: .newlines)
        var classContent: [String] = []
        var braceCount = 0
        var inClass = false
        
        for i in lineNumber..<lines.count {
            let line = lines[i]
            
            if !inClass {
                // 开始类内容
                classContent.append(line)
                inClass = true
            } else {
                // 检查是否遇到下一个类声明
                if i > lineNumber {
                    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                    if (trimmedLine.hasPrefix("class ") || trimmedLine.hasPrefix("struct ") || trimmedLine.hasPrefix("enum ")) && braceCount == 0 {
                        break
                    }
                }
                
                classContent.append(line)
            }
            
            // 跟踪大括号计数来检测类结束
            braceCount += line.filter { $0 == "{" }.count
            braceCount -= line.filter { $0 == "}" }.count
            
            if braceCount <= 0 && i > lineNumber {
                break
            }
        }
        
        return classContent.joined(separator: "\n")
    }
    
    private func parseImports(from sourceCode: String) -> [String] {
        var imports: [String] = []
        let lines = sourceCode.components(separatedBy: .newlines)
        
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("import ") {
                let importStatement = line.trimmingCharacters(in: .whitespaces)
                let importName = String(importStatement.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                imports.append(importName)
            }
        }
        
        return imports
    }
    
    private func extractClassName(from line: String) -> String {
        let pattern = #"class\s+(\w+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            if let range = Range(match.range(at: 1), in: line) {
                return String(line[range])
            }
        }
        return "UnknownClass"
    }
    
    private func extractSuperclass(from line: String) -> String? {
        let pattern = #"class\s+\w+\s*:\s*(\w+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            if let range = Range(match.range(at: 1), in: line) {
                return String(line[range])
            }
        }
        return nil
    }
    
    private func extractProtocols(from line: String) -> [String] {
        // Simplified protocol extraction
        if line.contains(":") {
            let parts = line.components(separatedBy: ":")
            if parts.count > 1 {
                let protocolPart = parts[1].trimmingCharacters(in: .whitespaces)
                let protocols = protocolPart.components(separatedBy: ",")
                return protocols.map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }
        return []
    }
    
    private func extractMethods(from classContent: String) -> [MethodInfo] {
        let lines = classContent.components(separatedBy: .newlines)
        var methods: [MethodInfo] = []
        
        // 快速扫描方法声明，避免复杂的正则表达式
        for (i, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // 快速检测方法声明（func关键字 + 非注释行）
            if trimmedLine.hasPrefix("func ") && !trimmedLine.hasPrefix("//") {
                let methodName = extractMethodName(from: line)
                let parameters = extractParameters(from: line)
                let returnType = extractReturnType(from: line)
                let isPublic = line.contains("public") || line.contains("open")
                let isStatic = line.contains("static") || line.contains("class")
                
                // 简化：不提取被调用的方法，大幅提升性能
                let methodInfo = MethodInfo(
                    name: methodName,
                    parameters: parameters,
                    returnType: returnType,
                    isPublic: isPublic,
                    isStatic: isStatic,
                    calledMethods: [], // 性能优化：跳过方法调用分析
                    lineNumber: i + 1,
                    estimatedSize: 50 // 粗略估计
                )
                
                methods.append(methodInfo)
            }
        }
        
        return methods
    }
    
    private func extractProperties(from classContent: String) -> [PropertyInfo] {
        let lines = classContent.components(separatedBy: .newlines)
        var properties: [PropertyInfo] = []
        
        // 快速扫描属性声明
        for (i, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // 快速检测属性声明（var/let关键字 + 非注释行 + 非方法内）
            if (trimmedLine.hasPrefix("var ") || trimmedLine.hasPrefix("let ")) && 
                !trimmedLine.hasPrefix("//") && 
                !trimmedLine.contains("func ") {
                
                let propertyName = extractPropertyName(from: line)
                let type = extractPropertyType(from: line)
                let isPublic = line.contains("public") || line.contains("open")
                let isStatic = line.contains("static") || line.contains("class")
                
                let propertyInfo = PropertyInfo(
                    name: propertyName,
                    type: type,
                    isPublic: isPublic,
                    isStatic: isStatic,
                    lineNumber: i + 1
                )
                
                properties.append(propertyInfo)
            }
        }
        
        return properties
    }
    
    private func extractClassDependencies(from classContent: String, className: String) -> [String] {
        var dependencies: Set<String> = []
        
        // 使用更高效的依赖检测：基于类型声明和初始化模式
        let lines = classContent.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // 跳过注释和空行
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("//") || trimmedLine.hasPrefix("/*") {
                continue
            }
            
            // 快速检测类型声明模式
            if trimmedLine.contains(":") {
                // 类型注解模式：var/let name: Type
                let parts = trimmedLine.components(separatedBy: ":")
                if parts.count > 1 {
                    let typePart = parts[1].trimmingCharacters(in: .whitespaces)
                    // 提取类型名称（去除泛型等）
                    if let typeName = extractTypeName(from: typePart) {
                        if typeName.count > 1 && typeName.first?.isUppercase == true && typeName != className {
                            dependencies.insert(typeName)
                        }
                    }
                }
            }
            
            // 检测初始化模式：Type()
            if trimmedLine.contains("(") && trimmedLine.contains(")") {
                let words = trimmedLine.components(separatedBy: CharacterSet.alphanumerics.inverted)
                for word in words {
                    if word.count > 1 && word.first?.isUppercase == true && word != className {
                        dependencies.insert(word)
                    }
                }
            }
        }
        
        return Array(dependencies)
    }
    
    /// 从类型声明中提取纯类型名称（去除泛型、可选等修饰）
    private func extractTypeName(from typeDeclaration: String) -> String? {
        var typeName = typeDeclaration
        
        // 去除泛型部分：Array<String> -> Array
        if let genericStart = typeName.firstIndex(of: "<") {
            typeName = String(typeName[..<genericStart])
        }
        
        // 去除可选标记：String? -> String
        if typeName.hasSuffix("?") {
            typeName = String(typeName.dropLast())
        }
        
        // 去除协议约束：Type & Protocol -> Type
        if let protocolSeparator = typeName.firstIndex(of: "&") {
            typeName = String(typeName[..<protocolSeparator]).trimmingCharacters(in: .whitespaces)
        }
        
        return typeName.trimmingCharacters(in: .whitespaces)
    }
    
    private func extractMethodName(from line: String) -> String {
        let pattern = #"func\s+(\w+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            if let range = Range(match.range(at: 1), in: line) {
                return String(line[range])
            }
        }
        return "unknownMethod"
    }
    
    private func extractParameters(from line: String) -> [String] {
        // Simplified parameter extraction
        if let startParen = line.firstIndex(of: "("),
           let endParen = line.firstIndex(of: ")") {
            let paramString = String(line[line.index(after: startParen)..<endParen])
            if paramString.isEmpty {
                return []
            }
            return paramString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return []
    }
    
    private func extractReturnType(from line: String) -> String? {
        if line.contains("->") {
            let parts = line.components(separatedBy: "->")
            if parts.count > 1 {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    
    private func extractPropertyName(from line: String) -> String {
        let pattern = #"(?:var|let)\s+(\w+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            if let range = Range(match.range(at: 1), in: line) {
                return String(line[range])
            }
        }
        return "unknownProperty"
    }
    
    private func extractPropertyType(from line: String) -> String {
        if line.contains(":") {
            let parts = line.components(separatedBy: ":")
            if parts.count > 1 {
                let typePart = parts[1].trimmingCharacters(in: .whitespaces)
                // Remove any assignment part
                if let equalIndex = typePart.firstIndex(of: "=") {
                    return String(typePart[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                }
                return typePart
            }
        }
        return "Unknown"
    }
    
    private func shouldSkipFile(_ url: URL) -> Bool {
        let path = url.path
        
        // Skip build directories and generated files
        let skipPatterns = [
            "/build/",
            "/DerivedData/",
            "/.git/",
            "/Pods/",
            ".generated.swift",
            ".pb.swift"
        ]
        
        return skipPatterns.contains { path.contains($0) }
    }
    
    private func extractProjectPath(from filePath: String) -> String {
        // Extract project root path (simplified heuristic)
        if let range = filePath.range(of: ".xcodeproj") {
            return String(filePath[..<range.lowerBound])
        }
        
        // Fallback to parent directory
        return URL(fileURLWithPath: filePath).deletingLastPathComponent().path
    }
}

// MARK: - DependencyAnalyzer Protocol and Implementation

protocol DependencyAnalyzerProtocol {
    func buildDependencyGraph(from sourceFiles: [SourceFileInfo]) async throws -> DependencyGraph
    func buildCallGraph(from sourceFiles: [SourceFileInfo]) async throws -> CallGraph
}

class DependencyAnalyzer: DependencyAnalyzerProtocol {
    
    func buildDependencyGraph(from sourceFiles: [SourceFileInfo]) async throws -> DependencyGraph {
        var dependencies: [String: Set<String>] = [:]
        var references: [String: Set<String>] = [:]
        
        // Build class dependency map
        for sourceFile in sourceFiles {
            for classInfo in sourceFile.classes {
                let className = classInfo.name
                dependencies[className] = Set(classInfo.dependencies)
                
                // Track which classes reference this class
                for dependency in classInfo.dependencies {
                    if references[dependency] == nil {
                        references[dependency] = Set<String>()
                    }
                    references[dependency]?.insert(className)
                }
            }
        }
        
        return DependencyGraph(
            dependencies: dependencies,
            references: references
        )
    }
    
    func buildCallGraph(from sourceFiles: [SourceFileInfo]) async throws -> CallGraph {
        var methodCalls: [String: Set<String>] = [:]
        
        for sourceFile in sourceFiles {
            for classInfo in sourceFile.classes {
                for method in classInfo.methods {
                    let methodSignature = "\(classInfo.name).\(method.name)"
                    methodCalls[methodSignature] = Set(method.calledMethods)
                }
            }
        }
        
        return CallGraph(methodCalls: methodCalls)
    }
}

// MARK: - Supporting Data Structures

struct SourceFileInfo {
    let filePath: String
    let projectPath: String
    let classes: [ClassInfo]
    let imports: [String]
}

struct ClassInfo {
    let name: String
    let superclass: String?
    let protocols: [String]
    let methods: [MethodInfo]
    let properties: [PropertyInfo]
    let dependencies: [String] // Classes this class depends on
    let lineNumber: Int
}

struct MethodInfo {
    let name: String
    let parameters: [String]
    let returnType: String?
    let isPublic: Bool
    let isStatic: Bool
    let calledMethods: [String] // Methods called within this method
    let lineNumber: Int
    let estimatedSize: Int64 // Rough estimate based on lines of code
}

struct PropertyInfo {
    let name: String
    let type: String
    let isPublic: Bool
    let isStatic: Bool
    let lineNumber: Int
}

struct UnusedMethod {
    let className: String
    let methodName: String
    let filePath: String
    let lineNumber: Int
    let estimatedSize: Int64
}

struct DependencyGraph {
    let dependencies: [String: Set<String>] // class -> dependencies
    let references: [String: Set<String>]   // class -> classes that reference it
    
    func isClassReferenced(_ className: String) -> Bool {
        return references[className]?.isEmpty == false
    }
    
    func getDependencies(for className: String) -> [String] {
        return Array(dependencies[className] ?? [])
    }
}

struct CallGraph {
    let methodCalls: [String: Set<String>] // method -> called methods
    
    func isMethodCalled(_ methodSignature: String) -> Bool {
        // Check if any method calls this method
        return methodCalls.values.contains { $0.contains(methodSignature) }
    }
}