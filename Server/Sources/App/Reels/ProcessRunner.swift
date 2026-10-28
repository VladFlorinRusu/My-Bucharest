import Foundation

/// Rulează unelte externe (ffmpeg, ffprobe, say) căutate în PATH.
enum ProcessRunner {
    struct Failure: Error, CustomStringConvertible {
        let tool: String
        let status: Int32
        let output: String

        var description: String {
            "\(tool) a eșuat cu codul \(status): \(output.suffix(1_500))"
        }
    }

    /// Întoarce doar stdout; stderr (avertismente, progres) merge într-un fișier temporar
    /// și apare doar în mesajul de eroare.
    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments

        let stdout = Pipe()
        let stderrURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mybucharest-\(UUID().uuidString).stderr")
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stderr.close()
            try? FileManager.default.removeItem(at: stderrURL)
        }
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        // Citim până la EOF înainte de wait, ca procesul să nu se blocheze cu buffer-ul plin.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let errors = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
            throw Failure(tool: tool, status: process.terminationStatus, output: errors.isEmpty ? output : errors)
        }
        return output
    }

    static func isAvailable(_ tool: String) -> Bool {
        (try? run("which", [tool])) != nil
    }
}
