//
//  DebugOnly.swift
//  Rise & Move
//
//  Created by Joshua Costanza on 1/13/26.
//
//  Debug-only gates that MUST NOT affect Release/TestFlight behavior.
//

import Foundation

/// Centralized debug gate.
/// In Release builds, all `DebugOnly.*` helpers become safe no-ops.
enum DebugOnly {

    /// True only in DEBUG builds.
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Run code only in DEBUG builds.
    static func run(_ work: () -> Void) {
        #if DEBUG
        work()
        #else
        // no-op in Release
        #endif
    }

    /// Run code only in DEBUG builds, on the main thread.
    @MainActor
    static func runMain(_ work: @MainActor () -> Void) {
        #if DEBUG
        work()
        #else
        // no-op in Release
        #endif
    }

    /// Returns the provided value in DEBUG builds; otherwise returns the fallback.
    static func value<T>(debug: @autoclosure () -> T, release: @autoclosure () -> T) -> T {
        #if DEBUG
        return debug()
        #else
        return release()
        #endif
    }

    /// Debug-only assertion.
    /// In Release/TestFlight, this is a no-op so it can never affect production behavior.
    static func assertDebugOnly(
        _ message: String = "Debug-only code path executed in Release build.",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        #if DEBUG
        assertionFailure(message, file: file, line: line)
        #else
        // no-op in Release
        #endif
    }
}
