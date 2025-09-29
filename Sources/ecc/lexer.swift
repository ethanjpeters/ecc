import Foundation

typealias LexerPosition = (Int /* line */, Int /* column */)

class Lexer {
    enum Token : Equatable, Hashable {
        // types
        case keywordInt
        case keywordLong
        case keywordVoid
        case keywordUnsigned
        case keywordSigned
        // storage specifiers
        case keywordStatic
        case keywordExtern
        // control flow
        case keywordReturn
        case keywordIf
        case keywordElse
        case keywordDo
        case keywordWhile
        case keywordFor
        case keywordBreak
        case keywordContinue
        case keywordSwitch
        case keywordCase
        case keywordDefault
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
        case question
        case colon
        case comma
        // two character operators
        case decrement
        case increment
        case shiftLeft
        case shiftRight
        case doubleAmpersand
        case doublePipe
        case doubleEquals
        case notEquals
        case lessThanEqual
        case greaterThanEqual
        case plusEqual
        case minusEqual
        case asteriskEqual
        case slashEqual
        case percentEqual
        case ampersandEqual
        case pipeEqual
        case carrotEqual
        // three chracter operators
        case shiftLeftEqual
        case shiftRightEqual
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

            if c == "l" || c == "L" {
                matchedString = matchedString + String(c)
                if j + 1 < sourceFileCharacters.count && (sourceFileCharacters[j+1] == "u" || sourceFileCharacters[j+1] == "U") {
                    matchedString = matchedString + String(sourceFileCharacters[j+1])
                }
                break
            }

            if c == "u" || c == "U" {
                matchedString = matchedString + String(c)
                if j + 1 < sourceFileCharacters.count && (sourceFileCharacters[j+1] == "l" || sourceFileCharacters[j+1] == "L") {
                    matchedString = matchedString + String(sourceFileCharacters[j+1])
                }
                break
            }

            if !(ascii >= Character("0").asciiValue! && ascii <= Character("9").asciiValue!) {
                break
            }

            matchedString = matchedString + String(c)
            j = j + 1
        }

        return matchedString.count > 0 ? matchedString : nil
    }

    func matchThreeCharacterOperator(startingIndex: Int) -> Token? {
        let c = sourceFileCharacters[startingIndex]
        if c == "<" {
            if startingIndex + 1 < sourceFileCharacters.count {
                if sourceFileCharacters[startingIndex + 1] == "<" {
                    if startingIndex + 2 < sourceFileCharacters.count {
                        if sourceFileCharacters[startingIndex + 2] == "=" {
                            return .shiftLeftEqual
                        }
                    }
                }
            }
        }
        if c == ">" {
            if startingIndex + 1 < sourceFileCharacters.count {
                if sourceFileCharacters[startingIndex + 1] == ">" {
                    if startingIndex + 2 < sourceFileCharacters.count {
                        if sourceFileCharacters[startingIndex + 2] == "=" {
                            return .shiftRightEqual
                        }
                    }
                }
            }
        }
        return nil
    }

    func matchTwoCharacterOperator(startingIndex: Int) -> Token? {
        let c = sourceFileCharacters[startingIndex]
        if c == "-" {
            if startingIndex + 1 < sourceFileCharacters.count {
                if sourceFileCharacters[startingIndex + 1] == "-" {
                    return .decrement
                }
                if sourceFileCharacters[startingIndex + 1] == "=" {
                    return .minusEqual
                }
            }
        }
        if c == "+" {
            if startingIndex + 1 < sourceFileCharacters.count {
                if sourceFileCharacters[startingIndex + 1] == "=" {
                    return .plusEqual
                }
                if sourceFileCharacters[startingIndex + 1] == "+" {
                    return .increment
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
                if sourceFileCharacters[startingIndex + 1] == "=" {
                    return .ampersandEqual
                }
            }
        }
        if c == "|" {
            if startingIndex + 1 < sourceFileCharacters.count {
                if sourceFileCharacters[startingIndex + 1] == "|" {
                    return .doublePipe
                }
                if sourceFileCharacters[startingIndex + 1] == "=" {
                    return .pipeEqual
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
        if c == "*" {
            if startingIndex + 1 < sourceFileCharacters.count {
                if sourceFileCharacters[startingIndex + 1] == "=" {
                    return .asteriskEqual
                }
            }
        }
        if c == "/" {
            if startingIndex + 1 < sourceFileCharacters.count {
                if sourceFileCharacters[startingIndex + 1] == "=" {
                    return .slashEqual
                }
            }
        }
        if c == "%" {
            if startingIndex + 1 < sourceFileCharacters.count {
                if sourceFileCharacters[startingIndex + 1] == "=" {
                    return .percentEqual
                }
            }
        }
        if c == "^" {
            if startingIndex + 1 < sourceFileCharacters.count {
                if sourceFileCharacters[startingIndex + 1] == "=" {
                    return .carrotEqual
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
            case ":": return .colon
            case "?": return .question
            case ",": return .comma
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

    func matchKeyword(identifier: String) -> Token? {
        switch identifier {
            case "int": return .keywordInt
            case "long": return .keywordLong
            case "void": return .keywordVoid
            case "unsigned": return .keywordUnsigned
            case "signed": return .keywordSigned
            case "static": return .keywordStatic
            case "extern": return .keywordExtern
            case "return": return .keywordReturn
            case "if": return .keywordIf
            case "else": return .keywordElse
            case "do": return .keywordDo
            case "while": return .keywordWhile
            case "for": return .keywordFor
            case "break": return .keywordBreak
            case "continue": return .keywordContinue
            case "switch": return .keywordSwitch
            case "case": return .keywordCase
            case "default" : return .keywordDefault
            default: return nil
        }
    }

    func lex() -> [(Token, LexerPosition)] {
        var out : [(Token, LexerPosition)] = []
        var i = 0

        var lineCounter : Int = 1
        var columnCounter : Int = 1

        while i < sourceFileCharacters.count {
            enforceAscii(index: i)

            if sourceFileCharacters[i].isWhitespace {
                if sourceFileCharacters[i].isNewline {
                    columnCounter = 1
                    lineCounter = lineCounter + 1
                } else {
                    columnCounter = columnCounter + 1
                }
                i = i + 1
            } else if let identifier = matchIdentifier(startingIndex: i) {
                if let kw = matchKeyword(identifier: identifier) {
                    out.append((kw, (lineCounter, columnCounter)))
                } else {
                    out.append((.identifier(identifier), (lineCounter, columnCounter)))
                }

                i = i + identifier.count
                columnCounter = columnCounter + identifier.count
            } else if let constant = matchConstant(startingIndex: i) {
                out.append((.constant(constant), (lineCounter, columnCounter)))

                i = i + constant.count
                columnCounter = columnCounter + constant.count
            } else if let op = matchThreeCharacterOperator(startingIndex: i) {
                out.append((op, (lineCounter, columnCounter)))

                i = i + 3
                columnCounter = columnCounter + 3
            } else if let op = matchTwoCharacterOperator(startingIndex: i) {
                out.append((op, (lineCounter, columnCounter)))

                i = i + 2
                columnCounter = columnCounter + 2
            } else if let op = matchOneCharacterOperator(startingIndex: i) {
                out.append((op, (lineCounter, columnCounter)))

                i = i + 1
                columnCounter = columnCounter + 1
            } else if let del = matchDelimiter(startingIndex: i) {
                out.append((del, (lineCounter, columnCounter)))

                i = i + 1
                columnCounter = columnCounter + 1
            }
        }

        return out
    }
}