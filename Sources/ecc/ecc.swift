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

// exit codes
enum ExitCode: Int32 {
    case ioError = 3
    case lexerError = 4
    case parserError = 5
}

enum Token : Equatable {
    case keywordInt
    case keywordVoid
    case keywordReturn
    case openParen
    case closeParen
    case openBrace
    case closeBrace
    case semicolon
    case complement
    case negate
    case decrement
    case identifier(String)
    case constant(String)
}

func lexFile(sourceFile: String) -> [Token] {
    let sourceFileContent : String
    do {
        sourceFileContent = try String(contentsOfFile: sourceFile, encoding: .utf8)
    } catch {
        print("Error reading source file for lexing: \(error)")
        exit(ExitCode.ioError.rawValue)
    }

    var out : [Token] = []

    let sourceFileCharacters = Array(sourceFileContent)

    var i = 0

    func enforceAscii(index: Int) {
        if !sourceFileCharacters[index].isASCII {
            print("Encountered illegal non-ASCII character \(sourceFileCharacters[i])")
            exit(ExitCode.lexerError.rawValue)
        }
    }

    func matchIdentifier(startingIndex: Int) -> String? {
        var j = startingIndex
        var matchedString : String = ""

        while j < sourceFileCharacters.count {
            let c = sourceFileCharacters[j]
            let ascii = c.asciiValue!
            if !((ascii >= Character("A").asciiValue! && ascii <= Character("Z").asciiValue!) || (ascii >= Character("a").asciiValue! && ascii <= Character("z").asciiValue!) || ascii == Character("_").asciiValue!) {
                break
            }
            matchedString = matchedString + String(c)
            j = j + 1
        }

        return matchedString.count > 0 ? matchedString : nil
    }

    func matchConstant(startingIndex: Int) -> String? {
        var j = startingIndex
        var matchedString: String = ""

        while j < sourceFileCharacters.count {
            let c = sourceFileCharacters[j]
            let ascii = c.asciiValue!

            if !(ascii >= Character("0").asciiValue! && ascii <= Character("9").asciiValue!) {
                break
            }

            matchedString = matchedString + String(c)
            j = j + 1
        }

        return matchedString.count > 0 ? matchedString : nil
    }

    func matchTwoCharacterOperator(startingIndex: Int) -> Token? {
        let c = sourceFileCharacters[startingIndex]
        if c == "-" {
            if startingIndex + 1 < sourceFileCharacters.count {
                if sourceFileCharacters[startingIndex + 1] == "-" {
                    return .decrement
                }
            }
        }
        return nil
    }

    func matchOneCharacterOperator(startingIndex: Int) -> Token? {
        let c = sourceFileCharacters[startingIndex]

        switch c {
            case "~": return .complement
            case "-": return .negate
            default: return nil
        }
    }

    func matchDelimiter(startingIndex: Int) -> Token? {
        let c = sourceFileCharacters[startingIndex]
        switch c {
            case "(": return .openParen
            case ")": return .closeParen
            case "{": return .openBrace
            case "}": return .closeBrace
            case ";": return .semicolon
            default: return nil
        }
    }

    while i < sourceFileCharacters.count {
        enforceAscii(index: i)

        if sourceFileCharacters[i].isWhitespace {
            i = i + 1
        } else if let identifier = matchIdentifier(startingIndex: i) {
            if identifier == "int" {
                out.append(.keywordInt)
            } else if identifier == "void" {
                out.append(.keywordVoid)
            } else if identifier == "return" {
                out.append(.keywordReturn)
            } else {
                out.append(.identifier(identifier))
            }

            i = i + identifier.count
        } else if let constant = matchConstant(startingIndex: i) {
            out.append(.constant(constant))

            i = i + constant.count
        } else if let op = matchTwoCharacterOperator(startingIndex: i) {
            out.append(op)

            i = i + 2
        } else if let op = matchOneCharacterOperator(startingIndex: i) {
            out.append(op)

            i = i + 1
        } else if let del = matchDelimiter(startingIndex: i) {
            out.append(del)

            i = i + 1
        }
    }

    return out
}

// Recursive descent parser

// Parser namespace/scope

struct Parser {
    struct AST {
        enum UnaryOperator {
            case Complement
            case Negate
        }

        indirect enum Expression {
            case Constant(Int)
            case Unary(UnaryOperator, Expression)
        }

        enum Statement {
            case Return(Expression)
        }

        enum Program {
            case Function(String /* name */, Statement /* body */)
        }
    }
}

func expect(_ tok: Token, _ tokenStream: inout [Token]) -> Token {
    if tokenStream.isEmpty {
        print("Expected \(tok) but encountered end of token stream")
        exit(ExitCode.parserError.rawValue)
    }

    let nextToken = tokenStream.removeFirst()
    if nextToken != tok {
        print("Expected \(tok) but encountered \(nextToken)")
        exit(ExitCode.parserError.rawValue)
    }

    return nextToken
}

func parseExpression(tokenStream: inout [Token]) -> Parser.AST.Expression {
    if tokenStream.isEmpty {
        print("Expected integer but encountered end of token stream")
        exit(ExitCode.parserError.rawValue)
    }

    let next = tokenStream.removeFirst()
    switch next {
        // parse an integer constant
        case .constant(let val):
            guard let intVal = Int(val) else {
                print("Integer constant \(val) was not a valid integer")
                exit(ExitCode.parserError.rawValue)
            }
            return .Constant(intVal)
        // expression wrapped in parentheses
        case .openParen:
            let out = parseExpression(tokenStream: &tokenStream)
            let _ = expect(.closeParen, &tokenStream)
            return out
        // <unop> <exp>
        case .complement:
            let child = parseExpression(tokenStream: &tokenStream)
            return .Unary(.Complement, child)
        case .negate:
            let child = parseExpression(tokenStream: &tokenStream)
            return .Unary(.Negate, child)
        default:
            print("Expected expression but encountered \(next)")
            exit(ExitCode.parserError.rawValue)
    }
}

func parseStatement(tokenStream: inout [Token]) -> Parser.AST.Statement {
    let _ = expect(.keywordReturn, &tokenStream)
    let exp = parseExpression(tokenStream: &tokenStream)
    let _ = expect(.semicolon, &tokenStream)

    return .Return(exp)
}

func parseProgram(tokenStream: inout [Token]) -> Parser.AST.Program {
    if tokenStream.isEmpty {
        print("Empty token stream encountered when expecting a program")
        exit(ExitCode.parserError.rawValue)
    }

    let _ = expect(.keywordInt, &tokenStream)

    if tokenStream.isEmpty {
        print("Empty token stream encountered when expecting a function identifier")
        exit(ExitCode.parserError.rawValue)
    }

    let idToken = tokenStream.removeFirst()
    let functionName : String
    switch idToken {
        case .identifier(let name):
            functionName = name
        default:
            print("Expected function identifier but encountered \(idToken)")
            exit(ExitCode.parserError.rawValue)
    }

    let _ = expect(.openParen, &tokenStream)
    let _ = expect(.keywordVoid, &tokenStream)    // currently the only acceptable parameter type
    let _ = expect(.closeParen, &tokenStream)
    let _ = expect(.openBrace, &tokenStream)

    let statement = parseStatement(tokenStream: &tokenStream)

    let _ = expect(.closeBrace, &tokenStream)

    return .Function(functionName, statement)
}

// Assembly Generator

struct Assembly {
    struct Tree {
        enum Operand {
            case Immediate(Int)
            case Register
        }

        enum Instruction {
            case Mov(Operand /* src */, Operand /* dst */)
            case Ret
        }

        enum Program {
            case Function(String, [Instruction])
        }
    }
}


func generateStatement(statement: Parser.AST.Statement) -> [Assembly.Tree.Instruction] {
    switch statement {
        case .Return(let exp):
            let src: Assembly.Tree.Operand
            switch exp {
                case .Constant(let val):
                    src = .Immediate(val)
                default:
                    print("Unsupported expression \(exp)")
                    exit(ExitCode.parserError.rawValue)
            }
            let dst : Assembly.Tree.Operand = .Register
            return [.Mov(src, dst), .Ret]
    }
}

func generateProgram(program: Parser.AST.Program) -> Assembly.Tree.Program {
    switch program {
        case .Function(let name, let stmt):
            let genStmt = generateStatement(statement: stmt)
            return .Function(name, genStmt)
    }
}

// Code Emission

func emitInstruction(instr: Assembly.Tree.Instruction) -> String {
    func emitOperand(op: Assembly.Tree.Operand) -> String {
        switch op {
            case .Immediate(let val):
                return "$\(val)"
            case .Register:
                return "%eax"
        }
    }

    switch instr {
        case .Mov(let opSrc, let opDst):
            return "\tmovl\t\(emitOperand(op: opSrc)), \(emitOperand(op: opDst))"
        case .Ret:
            return "\tret"
    }
}

func emitProgram(program: Assembly.Tree.Program) -> [String] {
    var out : [String] = []

    switch program {
        case .Function(let name, let instrs):
            out.append("\t.global _\(name)")
            out.append("_\(name):")
            for inst in instrs {
                out.append(emitInstruction(instr: inst))
            }
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

        var tokenStream = lexFile(sourceFile: preprocFile)

        if lex {
            if verbose {
                print(tokenStream)
            }
            return
        }

        // parse

        let ast = parseProgram(tokenStream: &tokenStream)

        if parse {
            if verbose {
                print(ast)
            }
            return
        }

        // code gen

        let assembly = generateProgram(program: ast)

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