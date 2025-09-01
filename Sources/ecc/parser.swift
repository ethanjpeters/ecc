import Foundation

class Parser {
    struct AST {
        enum UnaryOperator {
            case Complement
            case Negate
        }

        enum BinaryOperator {
            case Add
            case Subtract
            case Multiply
            case Divide
            case Remainder
            case BitwiseAnd
            case BitwiseOr
            // these operations do not have non-bitwise counterparts, but
            // grouping makes things easier for me
            case BitwiseXor
            case BitwiseShiftRight
            case BitwiseShiftLeft
        }

        indirect enum Expression {
            case Constant(Int)
            case Unary(UnaryOperator, Expression)
            case Binary(BinaryOperator, Expression, Expression)
        }

        enum Statement {
            case Return(Expression)
        }

        enum Program {
            case Function(String /* name */, Statement /* body */)
        }
    }

    func expect(_ tok: Lexer.Token, _ tokenStream: inout [Lexer.Token]) -> Lexer.Token {
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

    func peek(_ tokenStream: [Lexer.Token]) -> Lexer.Token {
        if tokenStream.isEmpty {
            print("Expected token but encountered end of token stream")
            exit(ExitCode.parserError.rawValue)
        }

        return tokenStream.first!
    }

    func precedence(_ token: Lexer.Token) -> Int {
        switch token {
            case .asterisk: return 50
            case .forwardSlash: return 50
            case .percent: return 50
            case .plus: return 45
            case .negate: return 45
            case .shiftLeft: return 40
            case .shiftRight: return 40
            case .ampersand: return 35
            case .pipe: return 30
            case .carrot: return 25
            default:
                print("Unreachable 2")
                exit(ExitCode.parserError.rawValue)
        }
    }

    func isBinaryOperator(_ token: Lexer.Token) -> Bool {
        switch token {
            case .plus: fallthrough
            case .negate: fallthrough
            case .asterisk: fallthrough
            case .forwardSlash: fallthrough
            case .percent: fallthrough
            case .ampersand: fallthrough
            case .pipe: fallthrough
            case .carrot: fallthrough
            case .shiftLeft: fallthrough
            case .shiftRight: return true
            default:
                return false
        }
    }

    func parseExpression(tokenStream: inout [Lexer.Token], minimumPrecedence: Int) -> Parser.AST.Expression {
        if tokenStream.isEmpty {
            print("Expected expression but encountered end of token stream")
            exit(ExitCode.parserError.rawValue)
        }

        var left = parseFactor(tokenStream: &tokenStream)
        var nextToken = peek(tokenStream)
        while isBinaryOperator(nextToken) && precedence(nextToken) >= minimumPrecedence {
            let op : AST.BinaryOperator
            switch nextToken {
                case .plus: op = .Add
                case .negate: op = .Subtract
                case .asterisk: op = .Multiply
                case .forwardSlash: op = .Divide
                case .percent: op = .Remainder
                case .ampersand: op = .BitwiseAnd
                case .pipe: op = .BitwiseOr
                case .carrot: op = .BitwiseXor
                case .shiftLeft: op = .BitwiseShiftLeft
                case .shiftRight: op = .BitwiseShiftRight
                default:
                    print("Unreachable")
                    exit(ExitCode.parserError.rawValue)
            }
            tokenStream.removeFirst()

            let right = parseExpression(tokenStream: &tokenStream, minimumPrecedence: precedence(nextToken) + 1)
            left = .Binary(op, left, right)
            nextToken = peek(tokenStream)
        }
        return left
    }

    func parseFactor(tokenStream: inout [Lexer.Token]) -> Parser.AST.Expression {
        if tokenStream.isEmpty {
            print("Expected factor but encountered end of token stream")
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
                let out = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
                let _ = expect(.closeParen, &tokenStream)
                return out
            // <unop> <exp>
            case .complement:
                let child = parseFactor(tokenStream: &tokenStream)
                return .Unary(.Complement, child)
            case .negate:
                let child = parseFactor(tokenStream: &tokenStream)
                return .Unary(.Negate, child)
            default:
                print("Expected expression but encountered \(next)")
                exit(ExitCode.parserError.rawValue)
        }
    }

    func parseStatement(tokenStream: inout [Lexer.Token]) -> Parser.AST.Statement {
        let _ = expect(.keywordReturn, &tokenStream)
        let exp = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
        let _ = expect(.semicolon, &tokenStream)

        return .Return(exp)
    }

    func parseProgram(tokenStream: inout [Lexer.Token]) -> Parser.AST.Program {
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
}