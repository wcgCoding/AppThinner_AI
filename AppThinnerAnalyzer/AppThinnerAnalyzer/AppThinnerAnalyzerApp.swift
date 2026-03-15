import SwiftUI
import CoreData

@main
struct AppThinnerAnalyzerApp: App {
    let dependencyContainer = DependencyContainer.shared
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(\.managedObjectContext, dependencyContainer.coreDataManager.container.viewContext)
                .onAppear {
                    performSystemCompatibilityCheck()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
    
    private func performSystemCompatibilityCheck() {
        let systemCompatibility = dependencyContainer.systemCompatibilityService
        
        if !systemCompatibility.isSystemCompatible() {
            // Log system compatibility issues
            print("⚠️ System compatibility issues detected")
            print(systemCompatibility.systemInfoString)
        } else {
            print("✅ System compatibility check passed")
            print(systemCompatibility.systemInfoString)
        }
    }
}