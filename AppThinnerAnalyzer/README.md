# AppThinner Analyzer

A professional macOS application for analyzing iOS app package sizes, detecting unused resources and code, and providing optimization recommendations.

## Features

- **Multi-source Data Analysis**: Parse .ipa/.app files, linkmap.txt files, and project directories
- **Interactive Treemap Visualization**: Project directory-based size distribution visualization
- **Unused Content Detection**: Identify unused resources and code with external data import support
- **Optimization Tools**: Image compression and safe file deletion with backup functionality
- **Professional Reports**: Generate HTML reports with embedded visualizations
- **Project Comparison**: Compare different versions and track size trends
- **Data Persistence**: CoreData-based storage with analysis history

## System Requirements

- macOS 14.0 or later
- Apple Silicon or Intel processor
- Xcode 15.0 or later (for development)

## Architecture

The application follows MVVM (Model-View-ViewModel) architecture with:

- **SwiftUI**: Declarative user interface
- **CoreData**: Data persistence and management
- **Swift Testing**: Unit and integration testing
- **SwiftCheck**: Property-based testing framework

## Project Structure

```
AppThinnerAnalyzer/
├── AppThinnerAnalyzer/
│   ├── Models/                 # Data models and structures
│   ├── ViewModels/            # MVVM view models
│   ├── Views/                 # SwiftUI views
│   ├── CoreData/              # CoreData stack and entities
│   └── Assets.xcassets        # App assets and resources
├── AppThinnerAnalyzerTests/   # Test suite
└── README.md                  # This file
```

## Core Components

### Data Models
- **AnalysisProject**: CoreData entity for analysis projects
- **AnalysisResult**: CoreData entity for file analysis results
- **ExternalUnusedData**: CoreData entity for imported external data
- **TreemapNode**: Value type for treemap visualization

### ViewModels
- **MainViewModel**: Main application state and analysis coordination
- **TreemapViewModel**: Treemap visualization and navigation
- **OptimizationViewModel**: Optimization operations and selection
- **ComparisonViewModel**: Project comparison functionality

### Views
- **MainView**: Primary application interface with navigation
- **AnalysisView**: File input and analysis configuration
- **TreemapView**: Interactive treemap visualization
- **OptimizationView**: Optimization tools and operations
- **ComparisonView**: Project comparison interface

## Development Setup

1. Open `AppThinnerAnalyzer.xcodeproj` in Xcode
2. Ensure macOS 14.0+ deployment target
3. Build and run the project
4. Swift package dependencies will be resolved automatically

## Testing

The project includes comprehensive testing with:

- **Swift Testing Framework**: Modern testing with `@Test` attributes
- **SwiftCheck Integration**: Property-based testing capabilities
- **Unit Tests**: Core functionality validation
- **Integration Tests**: Component interaction testing

Run tests using:
```bash
xcodebuild test -scheme AppThinnerAnalyzer
```

## Property-Based Testing

The application uses property-based testing to validate correctness properties:

- **Data Persistence Round-trip Integrity**
- **Multi-source Data Parsing Completeness**
- **Path Mapping Conflict Resolution**
- **Treemap Generation Consistency**
- **Interactive Navigation Correctness**

## Contributing

1. Follow the MVVM architecture pattern
2. Add appropriate tests for new functionality
3. Update documentation for API changes
4. Ensure compatibility with macOS 14.0+

## License

This project is part of the AppThinner specification implementation.