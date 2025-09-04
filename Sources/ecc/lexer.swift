import Foundation

class Lexer {
    enum Token : Equatable {
        // types
        case keywordInt
        case keywordVoid
        // control flow
        case keywordReturn
        // braces/brackets
        case openParen
        case closeParen
        case openBrace
        case closeBrace
        // punctuation
        case semicolon
        // one character operators
        case complement
        case negate
        case plus
        case asterisk
        case forwardSlash
        case percent
        case ampersand
        case pipe
        case carrot
        case exclamation
        case lessThan
        case greaterThan
        case equal
        // two character operators
        case decrement
        case shiftLeft
        case shiftRight
        case doubleAmpersand
        case doublePipe
        case doubleEquals
        case notEquals
        case lessThanEqual
        case greaterThanEqual
        // tokens bearing data
        case identifier(String)
        case constant(String)
    }

    private let sourceFileCharacters : [String.Element]

    public init(withFilepath: String) {
       let sourceFileContent : String
        do {
            sourceFileContent = try String(contentsOfFile: withFilepath, encoding: .utf8)
        } catch {
            print("Error reading source file for lexing: \(error)")
            exit(ExitCode.ioError.rawValue)
        }

        sourceFileCharacters = Array(sourceFileContent)
    }

    func enforceAscii(index: Int) {
        if !sourceFileCharacters[index].isASCII {
            print("Encountered illegal non-ASCII character \(sourceFileCharacters[index])")
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
        if c == "<" {
            if startingIndex + 1 < sourceFileCharacters.count {
                if sourceFileCharacters[startingIndex + 1] == "<" {
                    return .shiftLeft
                }
                if sourceFileCharacters[startingIndex + 1] == "=" {
                    return .lessThanEqual
                }
            }
        }
        if c == ">" {
            if startingIndex + 1 < sourceFileCharacters.count {
                if sourceFileCharacters[startingIndex + 1] == ">" {
                    return .shiftRight
                }
                if sourceFileCharacters[startingIndex + 1] == "=" {
                    return .greaterThanEqual
                }
            }
        }
        if c == "&" {
            if startingIndex + 1 < sourceFileCharacters.count {
                if sourceFileCharacters[startingIndex + 1] == "&" {
                    return .doubleAmpersand
                }
            }
        }
        if c == "|" {
            if startingIndex + 1 < sourceFileCharacters.count {
                if sourceFileCharacters[startingIndex + 1] == "|" {
                    return .doublePipe
                }
            }
        }
        if c == "=" {
            if startingIndex + 1 < sourceFileCharacters.count {
                if sourceFileCharacters[startingIndex + 1] == "=" {
                    return .doubleEquals
                }
            }
        }
        if c == "!" {
            if startingIndex + 1 < sourceFileCharacters.count {
                if sourceFileCharacters[startingIndex + 1] == "=" {
                    return .notEquals
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
            case "+": return .plus
            case "*": return .asterisk
            case "/": return .forwardSlash
            case "%": return .percent
            case "&": return .ampersand
            case "|": return .pipe
            case "^": return .carrot
            case "!": return .exclamation
            case "<": return .lessThan
            case ">": return .greaterThan
            case "=": return .equal
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

    func lex() -> [Token] {
        var out : [Token] = []
        var i = 0

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
}