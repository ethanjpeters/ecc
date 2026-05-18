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
    // task.standardError = pipe

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

// exit codes
enum ExitCode: Int32 {
    case ioError = 3
    case lexerError = 4
    case parserError = 5
    case semanticError = 6
    case internalError = 7
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

    @Flag(help: "Exit after semantic analysis")
    var validate: Bool = false

    @Flag(help: "Exit after TACKY generation")
    var tacky: Bool = false

    @Flag(help: "Spit out intermediate data structures before exiting")
    var verbose: Bool = false

    @Argument(help: "The file to compile")
    var inputFile: String

    mutating func run() throws {
        let preprocFile = inputFile.fileName() + ".i"
        let assemblyFile = inputFile.fileName() + ".s"
        let outputFile = inputFile.fileName()

        // TODO: this isn't very portable
        guard let _ = runCommand("/usr/bin/gcc", arguments: ["-E", "-P", inputFile, "-o", preprocFile]) else {
            // already printed an error message
            return
        }

        // lex

        var tokenStream = Lexer(withFilepath: preprocFile).lex()

        if lex {
            if verbose {
                print(tokenStream)
            }
            return
        }

        // parse

        let ast = Parser().parse(tokenStream: &tokenStream)

        if parse {
            if verbose {
                print(ast)
            }
            return
        }

        var (validatedAst, symbolTable, typeTable) = SemanticAnalyzer().analyze(ast)

        if validate {
            if verbose {
                print(validatedAst)
            }
            return
        }

        // tacky IR gen
        let (TAC, tackyDefs) = Tacky().generateTACKYProgram(program: validatedAst, symbolTable: &symbolTable, typeTable: typeTable)

        if tacky {
            if verbose {
                print(TAC)
            }
            return
        }

        // code gen

        let assembler = Assembly()

        let (assembly, backendSymbolTable) = assembler.assemble(program: TAC, symbolTable: tackyDefs, typedSymbolTable: symbolTable, typeTable: typeTable)

        if codegen {
            if verbose {
                print(assembly)
            }
            return
        }

        // emit code

        let program = emitProgram(program: assembly)

        do {
            if FileManager.default.fileExists(atPath: assemblyFile) {
                try FileManager.default.removeItem(at: URL(fileURLWithPath: assemblyFile))
            }
            FileManager.default.createFile(atPath: assemblyFile, contents: nil, attributes: nil)

            let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: assemblyFile))
            fileHandle.seekToEndOfFile()

            for line in program {
                if let data = (line + "\n").data(using: .utf8) {
                    fileHandle.write(data)
                }
            }

            fileHandle.closeFile()
        } catch {
            print("Error writing code to file at \(assemblyFile): \(error)")
            return
        }

        // TODO: this isn't very portable
        guard let _ = runCommand("/usr/bin/gcc", arguments: [assemblyFile, "-o", outputFile]) else {
            // already printed an error message
            return
        }
    }
}