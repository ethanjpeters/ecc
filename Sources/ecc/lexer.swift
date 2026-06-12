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
        case keywordDouble
        case keywordChar
        case keywordStruct
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
        case openBracket
        case closeBracket
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
        case dot
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
        case arrow
        // three chracter operators
        case shiftLeftEqual
        case shiftRightEqual
        // whole word operator
        case keywordSizeOf
        // tokens bearing data
        case identifier(String)
        case constant(String)
        case floatingPointConstant(String)
        case stringLiteral(String)
        case charLiteral(Int32)
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

    public init(withString: String) {
        sourceFileCharacters = Array(withString)
    }

    func enforceAscii(index: Int) {
        if !sourceFileCharacters[index].isASCII {
            print("Encountered illegal non-ASCII character \(sourceFileCharacters[index])")
            exit(ExitCode.lexerError.rawValue)
        }
    }

    func isInRange(_ c: Character, _ lower: String, _ higher: String) -> Bool {
        let t = c.asciiValue!
        return t >= Character(lower).asciiValue! && t <= Character(higher).asciiValue!
    }

    func isWord(_ c: Character) -> Bool {
        return isInRange(c, "A", "Z") || isInRange(c, "a", "z") || isInRange(c, "0", "9") || c == "_"
    }

    func isWordBoundary(_ index: Int) -> Bool {
        if index >= sourceFileCharacters.count { return true }

        return !isWord(sourceFileCharacters[index])
    }

    func matchIdentifier(startingIndex: Int) -> String? {
        var j = startingIndex
        var matchedString : String = ""

        if j >= sourceFileCharacters.count { return nil }
        if !(isInRange(sourceFileCharacters[j], "A", "Z") || isInRange(sourceFileCharacters[j], "a", "z") || sourceFileCharacters[j] == "_") {
            return nil
        }
        matchedString = matchedString + String(sourceFileCharacters[j])
        j = j + 1
        while j < sourceFileCharacters.count {
            let c = sourceFileCharacters[j]
            if !isWord(c) { break }
            matchedString = matchedString + String(c)
            j = j + 1
        }

        return matchedString
    }

    func matchConstant(startingIndex: Int) -> String? {
        var j = startingIndex
        var matchedString: String = ""

        while j < sourceFileCharacters.count {
            let c = sourceFileCharacters[j]

            if c == "l" || c == "L" {
                matchedString = matchedString + String(c)
                j = j + 1
                if j < sourceFileCharacters.count && (sourceFileCharacters[j] == "u" || sourceFileCharacters[j] == "U") {
                    matchedString = matchedString + String(sourceFileCharacters[j])
                    j = j + 1
                }
                break
            }

            if c == "u" || c == "U" {
                matchedString = matchedString + String(c)
                j = j + 1
                if j < sourceFileCharacters.count && (sourceFileCharacters[j] == "l" || sourceFileCharacters[j] == "L") {
                    matchedString = matchedString + String(sourceFileCharacters[j])
                    j = j + 1
                }
                break
            }

            if !isInRange(c, "0", "9") {
                break
            }

            matchedString = matchedString + String(c)
            j = j + 1
        }

        return isWordBoundary(j) ? (matchedString.count > 0 ? matchedString : nil) : nil
    }

    func matchStringConstant(startingIndex: Int) -> (String, UInt)? {
        // exit early if this is obviously not a string
        if sourceFileCharacters[startingIndex] != "\"" {
            return nil
        }

        // eat the quote
        var j = startingIndex + 1

        var matchedString = ""

        while j < sourceFileCharacters.count {
            let c = sourceFileCharacters[j]

            if c == "\\" {
                j = j + 1
                if j < sourceFileCharacters.count {
                    let d = sourceFileCharacters[j]
                    let e : String
                    switch d {
                        case "'": e = "'"
                        case "\"": e = "\""
                        case "?": e = "?"
                        case "\\": e = "\\"
                        case "a": e = String(UnicodeScalar(UInt8(7)))
                        case "b": e = String(UnicodeScalar(UInt8(8)))
                        case "f": e = String(UnicodeScalar(UInt8(12)))
                        case "n": e = "\n"
                        case "r": e = "\r"
                        case "t": e = "\t"
                        case "v": e = String(UnicodeScalar(UInt8(11)))
                        default:
                            print("Unrecognized escape sequence \\\(d)")
                            exit(ExitCode.lexerError.rawValue)
                    }

                    matchedString = matchedString + e
                } else {
                    print("Reached end of source stream while trying to lex string")
                    exit(ExitCode.lexerError.rawValue)
                }
            } else if c == "\"" {
                return (matchedString, UInt(j - startingIndex + 1))
            } else if c.isNewline {
                print("Unexpected line break found in string literal")
                exit(ExitCode.lexerError.rawValue)
            } else {
                matchedString = matchedString + String(c)
            }

            j = j + 1
        }

        print("Unexpected end of file found while parsing string constant")
        exit(ExitCode.lexerError.rawValue)
    }

    func matchCharConstant(startingIndex: Int) -> (Int32, UInt)? {
        // exit early if this is obviously not a character
        if sourceFileCharacters[startingIndex] != "\'" {
            return nil
        }

        // eat the quote
        var j = startingIndex + 1

        let c = sourceFileCharacters[j]

        if c == "\\" {
            j = j + 1
            if j < sourceFileCharacters.count {
                let d = sourceFileCharacters[j]
                let e : Int32
                switch d {
                    case "'": e = 39
                    case "\"": e = 34
                    case "?": e = 63
                    case "\\": e = 92
                    case "a": e = 7
                    case "b": e = 8
                    case "f": e = 12
                    case "n": e = 10
                    case "r": e = 13
                    case "t": e = 9
                    case "v": e = 11
                    default:
                        print("Unrecognized escape sequence \\\(d)")
                        exit(ExitCode.lexerError.rawValue)
                }
                j = j + 1
                if j < sourceFileCharacters.count {
                    let f = sourceFileCharacters[j]
                    if f == "'" {
                        return (e, 4)
                    }
                } else {
                    print("Reached end of source stream while trying to lex string")
                    exit(ExitCode.lexerError.rawValue)
                }
            } else {
                print("Reached end of source stream while trying to lex string")
                exit(ExitCode.lexerError.rawValue)
            }
        } else if c == "\'" {
            print("Empty character literal found")
            exit(ExitCode.lexerError.rawValue)
        } else if c.isNewline {
            print("Unexpected line break found in character literal")
            exit(ExitCode.lexerError.rawValue)
        } else {
            return (Int32(c.asciiValue!), 3)
        }

        print("Unexpected end of file found while parsing character constant")
        exit(ExitCode.lexerError.rawValue)
    }

    func matchFloatingPointConstant(startingIndex: Int) -> String? {
        var j = startingIndex
        var matchedString = ""
        var hasWholePart = false
        var hasFractionalPart = false
        var hasExponentPart = false
        var hasDecimalPoint = false

        // match the part before decimal point
        while j < sourceFileCharacters.count {
            let c = sourceFileCharacters[j]

            if !isInRange(c, "0", "9") {
                break
            }

            hasWholePart = true

            matchedString = matchedString + String(c)

            j = j + 1
        }
        if j >= sourceFileCharacters.count { return nil }
        // match the decimal point
        if sourceFileCharacters[j] == "." {
            matchedString = matchedString + "."
            j = j + 1
            hasDecimalPoint = true
            // match the fractional part
            while j < sourceFileCharacters.count {
                let c = sourceFileCharacters[j]

                if !isInRange(c, "0", "9") { break }

                hasFractionalPart = true

                matchedString = matchedString + String(c)

                j = j + 1
            }
        }
        if !(hasFractionalPart || hasWholePart) { return nil }
        // match the exponent
        if sourceFileCharacters[j] == "e" || sourceFileCharacters[j] == "E" {
            matchedString = matchedString + "E"
            j = j + 1
            if j >= sourceFileCharacters.count { return nil }
            if sourceFileCharacters[j] == "+" || sourceFileCharacters[j] == "-" {
                matchedString = matchedString + String(sourceFileCharacters[j])
                j = j + 1
                if j >= sourceFileCharacters.count { return nil }
            }
            if !isInRange(sourceFileCharacters[j], "0", "9") { return nil }
            while j < sourceFileCharacters.count {
                let c = sourceFileCharacters[j]
                if !isInRange(c, "0", "9") {
                    break
                }
                matchedString = matchedString + String(c)
                j = j + 1
            }
            hasExponentPart = true
        }
        if !(hasFractionalPart || hasExponentPart || hasDecimalPoint) { return nil }

        return isWordBoundary(j) ? (matchedString.count > 0 ? matchedString : nil) : nil
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
                if sourceFileCharacters[startingIndex + 1] == ">" {
                    return .arrow
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
            case ".": return .dot
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
            case "[": return .openBracket
            case "]": return .closeBracket
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
            case "double": return .keywordDouble
            case "char" : return .keywordChar
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
            case "sizeof" : return .keywordSizeOf
            case "struct" : return .keywordStruct
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
            } else if let (stringConstant, stringLength) = matchStringConstant(startingIndex: i) {
                out.append((.stringLiteral(stringConstant), (lineCounter, columnCounter)))

                i = i + Int(stringLength)   // add 1 for the closing "
                columnCounter = columnCounter + Int(stringLength)
            } else if let (charConstant, charLength) = matchCharConstant(startingIndex: i) {
                out.append((.charLiteral(charConstant), (lineCounter, columnCounter)))

                i = i + Int(charLength)
                columnCounter = columnCounter + Int(charLength)
            } else if let constant = matchFloatingPointConstant(startingIndex: i) {
                out.append((.floatingPointConstant(constant), (lineCounter, columnCounter)))

                i = i + constant.count
                columnCounter = columnCounter + constant.count
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
            } else {
                print("Unrecognized character \(sourceFileCharacters[i]) at line \(lineCounter), column \(columnCounter)")
                exit(ExitCode.lexerError.rawValue)
            }
        }

        return out
    }
}