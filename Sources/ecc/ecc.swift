import ArgumentParser

import Foundation

/// Executes a system command and returns its output as a String.
/// - Parameters:
///   - executable: The full path to the executable (e.g., "/bin/ls")
///   - arguments: An array of command-line arguments
/// - Returns: A `String?` containing the command output or `nil` on failure
func runCommand(_ executable: String, arguments: [String]) -> String? {
    let task = Process()
    task.launchPath = executable
    task.arguments = arguments

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)
        return output
    } catch {
        print("❌ Failed to execute command: \(error)")
        return nil
    }
}

extension String {
    func fileName() -> String {
        return URL(fileURLWithPath: self).deletingPathExtension().lastPathComponent
    }

    func fileExtension() -> String {
        return URL(fileURLWithPath: self).pathExtension
    }
}


@main
struct ECC : ParsableCommand {

    // TODO: fake mutual exclusion of these flags
    @Flag(help: "Exit after lexing")
    var lex: Bool = false

    @Flag(help: "Exit after parsing")
    var parse: Bool = false
    
    @Flag(help: "Exit after code generation")
    var codegen: Bool = false

    @Argument(help: "The file to compile")
    var inputFile: String

    mutating func run() throws {
        let preprocFile = inputFile.fileName() + ".i"
        let assemblyFile = inputFile.fileName() + ".s"
        let outputFile = inputFile.fileName()

        // TODO: this isn't very portable
        guard let _ = runCommand("/usr/bin/gcc", arguments: ["-E", "-P", inputFile, "-o", preprocFile]) else {
            return
        }

        // TODO: lex

        // TODO: parse

        // TODO: code gen

        // TODO: emit code

        // TODO: this isn't very portable
        guard let _ = runCommand("/usr/bin/gcc", arguments: [assemblyFile, "-o", outputFile]) else {
            return
        }
    }
}