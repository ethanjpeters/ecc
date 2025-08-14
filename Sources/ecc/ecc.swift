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
    case internalError = 6
}



// Code Emission

func convert(_ operand: Assembly.Tree.Operand) -> String {
    switch operand {
        case .Immediate(let val):
            return "$\(val)"
        case .Pseudo(let name):
            print("Encountered Pseudo way late in the pipeline: \(name)")
            exit(ExitCode.internalError.rawValue)
        case .Register(let reg):
            switch reg {
                case .AX:
                    return "%eax"
                case .R10:
                    return "%r10d"
            }
        case .Stack(let slot):
            return "\(slot)(%rbp)"
    }
}

func convert(_ op: Assembly.Tree.UnaryOperator) -> String {
    switch op {
        case .Neg:
            return "negl"
        case .Not:
            return "notl"
    }
}

func emitInstructions(_ instructions: [Assembly.Tree.Instruction], out: inout [String]) {
    for instr in instructions {
        switch instr {
            case .AllocateStack(let count):
                if count != 0 { out.append("\tsubq\t$\(count), %rsp") }
            case .Mov(let opSrc, let opDst):
                out.append("\tmovl\t\(convert(opSrc)), \(convert(opDst))")
            case .Ret:
                out.append("\tmovq\t%rbp, %rsp")
                out.append("\tpopq\t%rbp")
                out.append("\tret")
            case .Unary(let unOp, let op):
                out.append("\t\(convert(unOp))\t\(convert(op))")
        }
    }
}

func emitProgram(program: Assembly.Tree.Program) -> [String] {
    var out : [String] = []

    switch program {
        case .Function(let name, let instrs):
            out.append("\t.global _\(name)")
            out.append("_\(name):")
            out.append("\tpushq\t%rbp")
            out.append("\tmovq\t%rsp, %rbp")
            emitInstructions(instrs, out: &out)
    }

    return out
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

        let ast = Parser().parseProgram(tokenStream: &tokenStream)

        if parse {
            if verbose {
                print(ast)
            }
            return
        }

        // tacky IR gen
        let TAC = Tacky().generateTACKYProgram(program: ast)

        if tacky {
            if verbose {
                print(TAC)
            }
            return
        }

        // code gen

        let assembler = Assembly()

        var assembly = assembler.generate(program: TAC)
        assembly = assembler.replacePseudoRegisters(program: assembly)
        assembly = assembler.fixUpMoves(program: assembly)

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