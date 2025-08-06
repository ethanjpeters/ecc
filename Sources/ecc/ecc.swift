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
}

enum Token {
    case keywordInt
    case keywordVoid
    case keywordReturn
    case openParen
    case closeParen
    case openBrace
    case closeBrace
    case semicolon
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

    var sourceFileCharacters = Array(sourceFileContent)

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
        } else if let del = matchDelimiter(startingIndex: i) {
            out.append(del)

            i = i + 1
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

        let tokenStream = lexFile(sourceFile: preprocFile)

        // DEBUG
        tokenStream.forEach { tkn in
            print(tkn)
        }
        // END DEBUG

        if lex {
            return
        }

        // TODO: parse

        // TODO: code gen

        // TODO: emit code

        // TODO: this isn't very portable
        guard let _ = runCommand("/usr/bin/gcc", arguments: [assemblyFile, "-o", outputFile]) else {
            // already printed an error message
            return
        }
    }
}