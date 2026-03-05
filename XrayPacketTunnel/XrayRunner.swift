import Foundation
import os.log

enum XrayRunnerError: LocalizedError {
    case binaryNotFound
    case configWriteFailed
    case launchFailed(Error)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "xray binary not found in extension resources."
        case .configWriteFailed:
            return "Could not write Xray config file."
        case .launchFailed(let error):
            return "Could not start Xray: \(error.localizedDescription)"
        }
    }
}

final class XrayRunner {
    private let logger = Logger(subsystem: "com.example.xrayvpn", category: "XrayRunner")

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var configURL: URL?

    func start(withConfigJSON json: String) throws {
        stop()

        let binaryURL = try locateBinary()
        let configURL = try writeConfig(json)

        let stdout = Pipe()
        let stderr = Pipe()

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["run", "-config", configURL.path]
        process.environment = [
            "XRAY_LOCATION_ASSET": binaryURL.deletingLastPathComponent().path
        ]
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw XrayRunnerError.launchFailed(error)
        }

        process.terminationHandler = { [weak self] process in
            self?.logger.error("xray exited with status \(process.terminationStatus)")
        }

        attachPipeLogging(stdout: stdout, stderr: stderr)

        self.process = process
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.configURL = configURL
    }

    func stop() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        process = nil
        stdoutPipe = nil
        stderrPipe = nil

        if let configURL {
            try? FileManager.default.removeItem(at: configURL)
        }
        configURL = nil
    }

    private func locateBinary() throws -> URL {
        let fileManager = FileManager.default
        guard let binaryURL = Bundle.main.url(forResource: "xray", withExtension: nil) else {
            throw XrayRunnerError.binaryNotFound
        }

        guard fileManager.isExecutableFile(atPath: binaryURL.path) else {
            throw XrayRunnerError.binaryNotFound
        }

        return binaryURL
    }

    private func writeConfig(_ json: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xray-vpn", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("config.json")
        guard let data = json.data(using: .utf8) else {
            throw XrayRunnerError.configWriteFailed
        }

        do {
            try data.write(to: fileURL, options: [.atomic])
            return fileURL
        } catch {
            throw XrayRunnerError.configWriteFailed
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
