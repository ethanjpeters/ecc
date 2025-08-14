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
    case internalError = 6
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

// TACKY IR
class Tacky {
    struct IR {
        enum UnaryOperator {
            case Complement
            case Negate
        }

        enum Value {
            case Constant(Int)
            case Var(String)
        }

        enum Instruction {
            case Return(Value)
            case Unary(UnaryOperator, Value/* src */, Value /* dst */)
        }

        enum Program {
            case Function(String /* identifier */, [Instruction]/* body */)
        }
    }

    private var tempNameCounter : Int = 0

    func makeTemp() -> String {
        let out = "tmp\(tempNameCounter)"
        tempNameCounter = tempNameCounter + 1
        return out
    }

    func generateTACKYExpression(_ exp: Parser.AST.Expression, out: inout [Tacky.IR.Instruction]) -> Tacky.IR.Value {

        func generateTACKYOp(_ op: Parser.AST.UnaryOperator) -> Tacky.IR.UnaryOperator {
            switch op {
                case .Complement:
                    return .Complement
                case .Negate:
                    return .Negate
            }
        }

        switch exp {
            case .Constant(let val):
                return .Constant(val)
            case .Unary(let op, let exp):
                let src = generateTACKYExpression(exp, out: &out)
                let dstName = makeTemp()
                let dst : Tacky.IR.Value = .Var(dstName)
                let tackyOp = generateTACKYOp(op)
                out.append(.Unary(tackyOp, src, dst))
                return dst
        }
    }

    func generateTACKYStatement(statement: Parser.AST.Statement) -> [Tacky.IR.Instruction] {
        switch statement {
            case .Return(let exp):
                var out : [Tacky.IR.Instruction] = []
                let child = generateTACKYExpression(exp, out: &out)
                out.append(.Return(child))
                return out
        }
    }

    func generateTACKYProgram(program: Parser.AST.Program) -> Tacky.IR.Program {
        switch program {
            case .Function(let name, let stmt):
                let tackyInstrs = generateTACKYStatement(statement: stmt)
                return .Function(name, tackyInstrs)
        }
    }

}

// Assembly Generator

class Assembly {
    struct Tree {
        enum Register {
            case AX
            case R10
        }

        enum Operand {
            case Immediate(Int)
            case Register(Register)
            case Pseudo(String)
            case Stack(Int)
        }

        enum UnaryOperator {
            case Neg
            case Not
        }

        enum Instruction {
            case Mov(Operand /* src */, Operand /* dst */)
            case Unary(UnaryOperator, Operand)
            case AllocateStack(Int)
            case Ret
        }

        enum Program {
            case Function(String, [Instruction])
        }
    }

    func convert(_ val: Tacky.IR.Value) -> Tree.Operand {
        switch val {
            case .Constant(let c):
                return .Immediate(c)
            case .Var(let name):
                return .Pseudo(name)
        }
    }

    func convert(_ op: Tacky.IR.UnaryOperator) -> Tree.UnaryOperator {
        switch op {
            case .Complement:
                return .Not
            case .Negate:
                return .Neg
        }
    }

    func generate(_ instructions: [Tacky.IR.Instruction]) -> [Tree.Instruction] {
        var out : [Tree.Instruction] = []

        for instr in instructions {
            switch instr {
                case .Return(let val):
                    out.append(.Mov(convert(val), .Register(.AX)))
                    out.append(.Ret)
                case .Unary(let op, let src, let dst):
                    out.append(.Mov(convert(src), convert(dst)))
                    out.append(.Unary(convert(op), convert(dst)))
            }
        }

        return out
    }

    func generate(program: Tacky.IR.Program) -> Tree.Program {
        switch program {
            case .Function(let name, let instrs):
                return .Function(name, generate(instrs))
        }
    }

    func replacePseudoRegisters(_ op: Tree.Operand, _ stackSlotCounter: inout Int, _ nameStackMapping: inout [String: Int]) -> Tree.Operand {
        switch op {
            case .Immediate(_):
                return op
            case .Register(_):
                return op
            case .Pseudo(let name):
                if let slot = nameStackMapping[name] {
                    return .Stack((slot+1) * -4)
                }
                let tmp = stackSlotCounter
                stackSlotCounter = stackSlotCounter + 1
                nameStackMapping[name] = tmp
                return .Stack((tmp+1) * -4)
            case .Stack(_):
                return op
        }
    }

    func replacePseudoRegisters(_ instructions: [Tree.Instruction]) -> [Tree.Instruction] {
        var out : [Tree.Instruction] = []

        var stackSlotCounter : Int = 0
        var nameStackMapping : [String: Int] = [:]

        for instr: Assembly.Tree.Instruction in instructions {
            switch instr {
                case .AllocateStack(_):
                    out.append(instr)
                case .Mov(let op1, let op2):
                    out.append(.Mov(replacePseudoRegisters(op1, &stackSlotCounter, &nameStackMapping),
                                    replacePseudoRegisters(op2, &stackSlotCounter, &nameStackMapping)))
                case .Ret:
                    out.append(instr)
                case .Unary(let unOp, let op):
                    out.append(.Unary(unOp, replacePseudoRegisters(op, &stackSlotCounter, &nameStackMapping)))
            }
        }

        out.insert(.AllocateStack(stackSlotCounter), at: 0)

        return out
    }

    func replacePseudoRegisters(program: Tree.Program) -> Tree.Program {
        switch program {
            case .Function(let name, let instrs):
                return .Function(name, replacePseudoRegisters(instrs))
        }
    }

    func fixUpMoves(_ instrs: [Tree.Instruction]) -> [Tree.Instruction] {
        var out : [Tree.Instruction] = []
        for instr in instrs {
            switch instr {
                case .AllocateStack(_): out.append(instr)
                case .Mov(let opSrc, let opDst):
                    switch opSrc {
                        case .Stack(let srcSlot):
                            switch opDst {
                                case .Stack(let dstSlot):
                                    out.append(.Mov(.Stack(srcSlot), .Register(.R10)))
                                    out.append(.Mov(.Register(.R10), .Stack(dstSlot)))
                                default:
                                    out.append(instr)
                            }
                        default:
                            out.append(instr)
                    }
                case .Ret: out.append(instr)
                case .Unary(_, _): out.append(instr)
            }
        }
        return out
    }

    func fixUpMoves(program: Tree.Program) -> Tree.Program {
        switch program {
            case .Function(let name, let instrs):
                return .Function(name, fixUpMoves(instrs))
        }
    }


}

// Code Emission

func convert(_ operand: Assembly.Tree.Operand) -> String {
    switch operand {
        case .Immediate(let val):
            return "\(val)"
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