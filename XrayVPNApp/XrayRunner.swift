import Foundation
import os.log

enum XrayRunnerError: LocalizedError {
    case binaryNotFound
    case stagingFailed
    case configWriteFailed
    case launchFailed(Error)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "xray binary not found in app resources."
        case .stagingFailed:
            return "Could not prepare xray runtime files."
        case .configWriteFailed:
            return "Could not write xray config file."
        case .launchFailed(let error):
            return "Could not start xray: \(error.localizedDescription)"
        }
    }
}

final class XrayRunner {
    var onTermination: ((Int32) -> Void)?

    private let logger = Logger(subsystem: "com.henryswisvip.xrayvpn", category: "XrayRunner")
    private let fileManager = FileManager.default

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    func start(withConfigJSON json: String) throws {
        stop()

        let runtimeDirectory = try prepareRuntimeDirectory()
        let binaryURL = runtimeDirectory.appendingPathComponent("xray")
        let configURL = runtimeDirectory.appendingPathComponent("config.json")

        guard let configData = json.data(using: .utf8) else {
            throw XrayRunnerError.configWriteFailed
        }
        do {
            try configData.write(to: configURL, options: [.atomic])
        } catch {
            throw XrayRunnerError.configWriteFailed
        }

        let stdout = Pipe()
        let stderr = Pipe()

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["run", "-config", configURL.path]
        process.environment = ["XRAY_LOCATION_ASSET": runtimeDirectory.path]
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw XrayRunnerError.launchFailed(error)
        }

        process.terminationHandler = { [weak self] process in
            self?.logger.error("xray exited with status \(process.terminationStatus)")
            self?.onTermination?(process.terminationStatus)
        }

        attachPipeLogging(stdout: stdout, stderr: stderr)

        self.process = process
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
    }

    func stop() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if let process {
            process.terminationHandler = nil
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        process = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    private func prepareRuntimeDirectory() throws -> URL {
        guard let bundledXray = Bundle.main.url(forResource: "xray", withExtension: nil) else {
            throw XrayRunnerError.binaryNotFound
        }

        let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let runtimeDirectory = (appSupportDirectory ?? fileManager.temporaryDirectory)
            .appendingPathComponent("XrayVPN", isDirectory: true)

        do {
            try fileManager.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
            try stageResource(named: "xray", from: bundledXray, into: runtimeDirectory)
            try stageOptionalResource(named: "geoip.dat", into: runtimeDirectory)
            try stageOptionalResource(named: "geosite.dat", into: runtimeDirectory)
            return runtimeDirectory
        } catch {
            throw XrayRunnerError.stagingFailed
        }
    }

    private func stageOptionalResource(named fileName: String, into runtimeDirectory: URL) throws {
        guard let bundledFile = Bundle.main.url(forResource: fileName, withExtension: nil) else {
            return
        }

        try stageResource(named: fileName, from: bundledFile, into: runtimeDirectory)
    }

    private func stageResource(named fileName: String, from sourceURL: URL, into runtimeDirectory: URL) throws {
        let destinationURL = runtimeDirectory.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        if fileName == "xray" {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
        }
    }

    private func attachPipeLogging(stdout: Pipe, stderr: Pipe) {
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.logger.debug("xray stdout: \(text, privacy: .public)")
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.logger.error("xray stderr: \(text, privacy: .public)")
        }
    }
}
