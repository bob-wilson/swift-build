//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//


import SWBCore
import SWBUtil
import Foundation

public struct TaskDependencyVerification {

    internal static func verifyFiles(
        files: any Sequence<Path>,
        dependencySettings: DependencySettings,
        outputDelegate: any TaskOutputDelegate
    ) throws -> Bool {
        // Group used files by inferred logical dependency name
        var used = Dictionary(
            grouping: files,
            by: { inferDependencyName($0) ?? "" }
        )
            .mapValues { OrderedSet($0)}

        // Remove declared dependencies
        dependencySettings.dependencies.forEach { used.removeValue(forKey: $0) }

        // Remove any where we could not infer the dependency
        let unmapped = used.removeValue(forKey: "") ?? []
        if !unmapped.isEmpty {
            outputDelegate.emitWarning("Could not infer logical dependency for: \(unmapped.map(\.str).joined(separator: ", "))")
        }

        // Any left are undeclared dependencies
        if !used.isEmpty {
            let undeclared = used.map {
                $0.key + "\n  " + $0.value.map { "  - " + $0.str }.joined(separator: "\n  ")
            }

            outputDelegate.error("Undeclared dependencies: \n  " + undeclared.joined(separator: "\n  "))

            return false
        }

        return true
    }

    // The following is a provisional/incomplete mechanism for resolving a logical dependency from a file path.
    // Ultimately, a discrete subsystem will be required that is more sophisticated than just interrogating components of the path.
    // This is currently the minimal viable implementation to satisfy a functional milestone and is not intended for general use.
    private static func inferDependencyName(_ file: Path) -> String? {
        findFrameworkName(file) ?? findLibraryName(file)
    }

    private static func findFrameworkName(_ file: Path) -> String? {
        if file.fileExtension == "framework" {
            return file.basenameWithoutSuffix
        }
        return file.dirname.isEmpty || file.dirname.isRoot ? nil : findFrameworkName(file.dirname)
    }

    private static func findLibraryName(_ file: Path) -> String? {
        if file.fileExtension == "a" && file.basename.starts(with: "lib") {
            return String(file.basenameWithoutSuffix.suffix(from: file.str.index(file.str.startIndex, offsetBy: 3)))
        }
        return nil
    }
}
