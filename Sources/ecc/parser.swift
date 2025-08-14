import Foundation

class Parser {
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

    func parseExpression(tokenStream: inout [Lexer.Token]) -> Parser.AST.Expression {
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

    func parseStatement(tokenStream: inout [Lexer.Token]) -> Parser.AST.Statement {
        let _ = expect(.keywordReturn, &tokenStream)
        let exp = parseExpression(tokenStream: &tokenStream)
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