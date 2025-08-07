// Tests/WeaverTests/Tags.swift

import Testing

extension Tag {
    // MARK: - Test Scope
    @Tag static var unit: Self
    @Tag static var integration: Self
    @Tag static var performance: Self
    @Tag static var ui: Self
    @Tag static var stress: Self
    
    // MARK: - Component Layers (Updated for new architecture)
    @Tag static var container: Self
    @Tag static var kernel: Self
    @Tag static var inject: Self
    @Tag static var scope: Self
    @Tag static var builder: Self
    @Tag static var swiftui: Self
    @Tag static var core: Self
    
    // MARK: - New Scope System
    @Tag static var startup: Self
    @Tag static var shared: Self
    @Tag static var whenNeeded: Self
    @Tag static var weak: Self
    
    // MARK: - Test Characteristics
    @Tag static var fast: Self
    @Tag static var slow: Self
    @Tag static var concurrency: Self
    @Tag static var memory: Self
    @Tag static var critical: Self
    @Tag static var safety: Self
    @Tag static var lifecycle: Self
    @Tag static var security: Self
    @Tag static var compatibility: Self
    @Tag static var environment: Self
    @Tag static var priority: Self
    
    // MARK: - Platform
    @Tag static var ios: Self
    @Tag static var macos: Self
    @Tag static var watchos: Self
    
    // MARK: - Error Handling
    @Tag static var errorHandling: Self
    @Tag static var resilience: Self
}