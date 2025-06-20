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

public import SWBCore
import Foundation
import SWBUtil

public final class LdTaskAction: TaskAction {
    private let outerTraceFileEnvVar = "LD_TRACE_FILE"
    private static let inherentDependencies = [
        "libSystem.B.tbd",
        "libobjc.A.tbd",
    ]

    public override class var toolIdentifier: String {
        return "ld"
    }

    override public func performTaskAction(
        _ task: any ExecutableTask,
        dynamicExecutionDelegate: any DynamicTaskExecutionDelegate,
        executionDelegate: any TaskExecutionDelegate,
        clientDelegate: any TaskExecutionClientDelegate,
        outputDelegate: any TaskOutputDelegate,
    ) async -> CommandResult {
        do {
            var env = task.environment.bindingsDictionary

            // Check if verifying dependencies from trace data is enabled.
            var taskDependencySettings: TaskDependencySettings? = nil
            var outerTraceFile: Path? = nil
            if let depSettings = (task.payload as? (any TaskDependencySettingsPayload))?.taskDependencySettings {
                if depSettings.dependencySettings.verification {
                    taskDependencySettings = depSettings

                    // Remove the trace output file if it already exists.
                    let traceFile = depSettings.traceFile
                    if executionDelegate.fs.exists(traceFile) {
                        try executionDelegate.fs.remove(traceFile)
                    }

                    // Check if the trace data needs to be merged to "LD_TRACE_FILE".
                    outerTraceFile = env.removeValue(forKey: outerTraceFileEnvVar).map(Path.init)
                }
            }

            let processDelegate = TaskProcessDelegate(outputDelegate: outputDelegate)
            try await spawn(
                commandLine: Array(task.commandLineAsStrings),
                environment: env,
                workingDirectory: task.workingDirectory,
                dynamicExecutionDelegate: dynamicExecutionDelegate,
                clientDelegate: clientDelegate,
                processDelegate: processDelegate,
            )
            if let error = processDelegate.executionError {
                outputDelegate.error(error)
                return .failed
            }
            let execResult = processDelegate.commandResult ?? .failed

            if let taskDependencySettings, execResult == .succeeded {
                // Verify the dependencies from the trace data.
                let traceFile = taskDependencySettings.traceFile
                let fs = executionDelegate.fs
                let traceData: TraceData
                if let outerTraceFile {
                    // TODO: Is this file appending concurrent-targets safe?
                    let traceFileContent = try fs.read(taskDependencySettings.traceFile)
                    try fs.append(outerTraceFile, contents: traceFileContent)
                    traceData = try JSONDecoder().decode(TraceData.self, from: Data(traceFileContent.bytes))
                } else {
                    // Fast path
                    traceData = try JSONDecoder().decode(TraceData.self, from: fs.readMemoryMapped(traceFile))
                }

                let verified = try TaskDependencyVerification.verifyFiles(
                    files: traceData.all().filter { !LdTaskAction.inherentDependencies.contains($0.basename) },
                    dependencySettings: taskDependencySettings.dependencySettings,
                    outputDelegate: outputDelegate
                )
                if !verified {
                    return .failed
                }
            }
            return execResult
        } catch {
            outputDelegate.error(error.localizedDescription)
            return .failed
        }
    }

    private struct TraceData : Decodable {
        let dynamic: [Path]?
        let weak: [Path]?
        let reExports: [Path]?
        let upwardDynamic: [Path]?
        let delayInit: [Path]?
        let archives: [Path]?

        func all() -> Set<Path> {
            var all = Set<Path>()
            [dynamic, weak, reExports, upwardDynamic, delayInit, archives].forEach { all.formUnion($0 ?? []) }
            return all
        }

        enum CodingKeys: String, CodingKey {
            case reExports = "re-exports"
            case dynamic = "dynamic"
            case weak = "weak"
            case upwardDynamic = "upward-dynamic"
            case delayInit = "delay-init"
            case archives = "archives"
        }
    }
}
