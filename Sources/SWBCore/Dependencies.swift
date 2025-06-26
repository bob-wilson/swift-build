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

public import SWBUtil

import Foundation
import SWBMacro

public struct FixItContext: Sendable, SerializableCodable {
    public var insertionPoint: InsertionPoint
    public var modificationStyle: ModificationStyle

    public init(insertionPoint: InsertionPoint, modificationStyle: ModificationStyle) {
        self.insertionPoint = insertionPoint
        self.modificationStyle = modificationStyle
    }

    public struct InsertionPoint: Sendable, SerializableCodable {
        public var path: Path
        public var line: Int
        public var column: Int

        public init(path: Path, line: Int, column: Int) {
            self.path = path
            self.line = line
            self.column = column
        }

        public static func eof(fs: any FSProxy, path: Path) throws -> FixItContext.InsertionPoint {
            guard let s = try fs.read(path).stringValue else { throw StubError.error("could not decode utf8 from \(path.str)") }
            let lines = s.components(separatedBy: CharacterSet.newlines)
            // We always get at least one line
            let endLine = lines.count - 1
            let endColumn = lines.last!.count
            return .init(path: path, line: endLine, column: endColumn)
        }
    }

    public enum ModificationStyle: Sendable, SerializableCodable {
        case appendToExistingAssignment
        case insertNewAssignment(targetNameCondition: String?)
    }

    public func makeFixIt(newModules: [Settings.ModuleDependencyInfo]) -> Diagnostic.FixIt {
        let stringValue = newModules.map { $0.asBuildSettingEntry }.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.sorted().joined(separator: " ")
        let newText: String
        switch modificationStyle {
        case .appendToExistingAssignment:
            newText = " \(stringValue)"
        case .insertNewAssignment(let targetNameCondition):
            let targetCondition = targetNameCondition.map { "[target=\($0)]" } ?? ""
            newText = "\n\(BuiltinMacros.MODULE_DEPENDENCIES.name)\(targetCondition) = $(inherited) \(stringValue)\n"
        }

        return Diagnostic.FixIt(sourceRange: Diagnostic.SourceRange(path: insertionPoint.path, startLine: insertionPoint.line, startColumn: insertionPoint.column, endLine: insertionPoint.line, endColumn: insertionPoint.column), newText: newText)
    }
}

public struct ModuleDependenciesContext: Sendable, SerializableCodable {
    public var validate: BooleanWarningLevel
    public var settingsModuleDependencyInfos: [Settings.ModuleDependencyInfo]
    public var fixItContext: FixItContext?

    public init(validate: BooleanWarningLevel, settingsModuleDependencyInfos: [Settings.ModuleDependencyInfo], fixItContext: FixItContext? = nil) {
        self.validate = validate
        self.settingsModuleDependencyInfos = settingsModuleDependencyInfos
        self.fixItContext = fixItContext
    }

    func signatureData() -> String {
        let moduleNames = settingsModuleDependencyInfos.map { $0.name }
        return "validate:\(validate),modules:\(moduleNames.joined(separator: ":"))"
    }
}

public struct LinkDependenciesContext: Sendable, SerializableCodable {
    public var validate: BooleanWarningLevel
    public var settingsModuleDependencyInfos: [Settings.ModuleDependencyInfo]

    public init(validate: BooleanWarningLevel, settingsModuleDependencyInfos: [Settings.ModuleDependencyInfo]) {
        self.validate = validate
        self.settingsModuleDependencyInfos = settingsModuleDependencyInfos
    }

    func signatureData() -> String {
        let moduleNames = settingsModuleDependencyInfos.map { $0.name }
        return "validate:\(validate),modules:\(moduleNames.joined(separator: ":"))"
    }

}
