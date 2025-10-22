import Foundation

class Parser {
    struct AST {
        enum UnaryOperator {
            case Complement
            case Negate
            case Not
            case PreIncrement
            case PostIncrement
            case PreDecrement
            case PostDecrement
        }
        
        enum BinaryOperator {
            case Add
            case Subtract
            case Multiply
            case Divide
            case Remainder
            case And
            case Or
            case Equal
            case NotEqual
            case LessThan
            case LessOrEqual
            case GreaterThan
            case GreaterOrEqual
            case BitwiseAnd
            case BitwiseOr
            // these operations do not have non-bitwise counterparts, but
            // grouping makes things easier for me
            case BitwiseXor
            case BitwiseShiftRight
            case BitwiseShiftLeft
        }
        
        enum Constant {
            case ConstInt(Int32)
            case ConstUnsignedInt(UInt32)
            case ConstLong(Int64)
            case ConstUnsignedLong(UInt64)
            case ConstDouble(Double)
        }

        indirect enum Expression {
            case Constant(Constant, CType?)
            case Unary(UnaryOperator, Expression, CType?)
            case Binary(BinaryOperator, Expression, Expression, CType?)
            case Var(String /* identifier */, CType?)
            case Assignment(Expression, Expression, CType?)
            case CompoundAssignment(BinaryOperator, Expression, Expression, CType?)
            case Conditional(Expression /* condition */, Expression, Expression, CType?)
            case FunctionCall(Expression /* "name" */, [Expression] /* parameters */, CType?)
            case Cast(CType, Expression, CType?)
        }
        
        enum BlockItem {
            case S(Statement)
            case D(Declaration)
        }
        
        enum Block {
            case Block([BlockItem])
        }
        
        enum ForInit {
            case InitDecl(Declaration)
            case InitExp(Expression?)
        }
        
        enum LabeledStatement {
            case IdentifiedLine(String /* label */, Statement)
            case CaseStatement(Expression /* label, must be a constant */, Statement)
            case DefaultStatement(Statement)
        }
        
        indirect enum Statement {
            case Return(Expression?)
            case Expression(Expression)
            case If(Expression /* condition */, Statement /* then */, Statement? /* else */)
            case Compound(Block)
            case Null
            case Break(String /* label */)
            case Continue(String /* label */)
            case While(Expression /* condition */, Statement /* body */, String /* label */)
            case DoWhile(Statement /* body */, Expression /* condition */, String /* label */)
            case For(ForInit /* init */, Expression? /* condition */, Expression? /* post */, Statement /* body */, String /* label */)
            case Switch(Expression /* condition */, Statement /* body */, String /* label */)
            case Labeled(LabeledStatement)
        }
        
        enum CType {
            case Int
            case UnsignedInt
            case Long
            case UnsignedLong
            case Void
        }

        enum Parameter {
            case NamedParameter(CType /* type */, String /* identifier name */)
            // it is sometimes technically valid for a parameter to be unnamed, but not in my America
        }

        enum StorageClass {
            case Static
            case Extern
        }

        enum Declaration {
            case VariableDeclaration(CType /* type */, String /* identifier name */, Expression?, StorageClass?)
            case FunctionDeclaration(CType /* return type */, String /* name */, [Parameter] /* type signature */, Block? /* body */, StorageClass?)
        }

        enum Program {
            case Statement([Declaration])
        }
    }
    
    func expect(_ tok: Lexer.Token, _ tokenStream: inout [(Lexer.Token, LexerPosition)]) -> Lexer.Token {
        if tokenStream.isEmpty {
            print("Expected \(tok) but encountered end of token stream")
            exit(ExitCode.parserError.rawValue)
        }
        
        let (nextToken, position) = tokenStream.removeFirst()
        if nextToken != tok {
            let (line, col) = position
            print("Expected \(tok) at line \(line), column \(col) but encountered \(nextToken)")
            exit(ExitCode.parserError.rawValue)
        }
        
        return nextToken
    }

    func expectType(_ tokenStream: inout [(Lexer.Token, LexerPosition)]) -> Lexer.Token {
        if tokenStream.isEmpty {
            print("Expected type but encountered end of token stream")
            exit(ExitCode.parserError.rawValue)
        }

        let (nextToken, position) = tokenStream.removeFirst()
        switch nextToken {
            case .keywordInt: fallthrough
            case .keywordLong: fallthrough
            case .keywordVoid: return nextToken
            default:
                print("Found unexpected token \(nextToken) at line \(position.0), column \(position.1) when looking for type")
                exit(ExitCode.parserError.rawValue)
        }
    }

    func expectStorageClass(_ tokenStream: inout [(Lexer.Token, LexerPosition)]) -> Lexer.Token {
        if tokenStream.isEmpty {
            print("Expected storage class but encountered end of token stream")
            exit(ExitCode.parserError.rawValue)
        }

        let (nextToken, position) = tokenStream.removeFirst()
        switch nextToken {
            case .keywordStatic: fallthrough
            case .keywordExtern: return nextToken
            default:
                print("Found unexpected token \(nextToken) at line \(position.0), column \(position.1) when looking for storage class")
                exit(ExitCode.parserError.rawValue)
        }
    }

    func expectIdentifier(_ tokenStream: inout [(Lexer.Token, LexerPosition)]) -> String /* identifier */ {
        if tokenStream.isEmpty {
            print("Expected identifier but encountered end of token stream")
            exit(ExitCode.parserError.rawValue)
        }

        let (next, position) = tokenStream.removeFirst()
        switch next {
            case .identifier(let name): return name
            default:
                print("Found unexpected token \(next) at line \(position.0), column \(position.1) while looking for identifier")
                exit(ExitCode.parserError.rawValue)
        }
    }

    func convertType(_ token: Lexer.Token) -> Parser.AST.CType {
        switch token {
            case .keywordInt: return .Int
            case .keywordLong: return .Long
            case .keywordVoid: return .Void
            default:
                print("Unreachable not-a-type while converting lexical type to AST")
                exit(ExitCode.internalError.rawValue)
        }
    }

    func convertStorageClass(_ token: Lexer.Token) -> Parser.AST.StorageClass {
        switch token {
            case .keywordStatic: return .Static
            case .keywordExtern: return .Extern
            default:
                print("Unreachable not-a-storage-class while converting lexical storage class to AST")
                exit(ExitCode.internalError.rawValue)
        }
    }

    func peek(_ tokenStream: [(Lexer.Token, LexerPosition)]) -> Lexer.Token {
        if tokenStream.isEmpty {
            print("Expected token but encountered end of token stream")
            exit(ExitCode.parserError.rawValue)
        }
        
        return tokenStream.first!.0
    }
    
    func isType(_ tokenStream: [(Lexer.Token, LexerPosition)]) -> Bool {
        switch peek(tokenStream) {
            case .keywordInt: fallthrough
            case .keywordLong: fallthrough
            case .keywordVoid: return true
            default: return false
        }
    }

    func isTypeSpecifier(_ tokenStream: [(Lexer.Token, LexerPosition)]) -> Bool {
        switch peek(tokenStream) {
            case .keywordStatic: fallthrough
            case .keywordExtern: fallthrough
            case .keywordSigned: fallthrough
            case .keywordUnsigned: return true
            default: return false
        }
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
        case .lessThan: fallthrough
        case .lessThanEqual: fallthrough
        case .greaterThan: fallthrough
        case .greaterThanEqual: return 35
        case .doubleEquals: fallthrough
        case .notEquals: return 30
        case .ampersand: return 25
        case .carrot: return 20
        case .pipe: return 15
        case .doubleAmpersand: return 10
        case .doublePipe: return 5
        case .question: return 3
        case .equal: fallthrough
        case .plusEqual: fallthrough
        case .minusEqual: fallthrough
        case .asteriskEqual: fallthrough
        case .slashEqual: fallthrough
        case .percentEqual: fallthrough
        case .ampersandEqual: fallthrough
        case .pipeEqual: fallthrough
        case .carrotEqual: fallthrough
        case .shiftLeftEqual: fallthrough
        case .shiftRightEqual: return 1
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
        case .doubleAmpersand: fallthrough
        case .doublePipe: fallthrough
        case .doubleEquals: fallthrough
        case .notEquals: fallthrough
        case .lessThan: fallthrough
        case .lessThanEqual: fallthrough
        case .greaterThan: fallthrough
        case .greaterThanEqual: fallthrough
        case .ampersand: fallthrough
        case .pipe: fallthrough
        case .carrot: fallthrough
        case .shiftLeft: fallthrough
        case .shiftRight: fallthrough
        case .equal: fallthrough
        case .plusEqual: fallthrough
        case .minusEqual: fallthrough
        case .asteriskEqual: fallthrough
        case .slashEqual: fallthrough
        case .percentEqual: fallthrough
        case .ampersandEqual: fallthrough
        case .pipeEqual: fallthrough
        case .carrotEqual: fallthrough
        case .shiftLeftEqual: fallthrough
        case .shiftRightEqual: fallthrough
        case .question: return true
        default:
            return false
        }
    }
    
    func isAssignmentOperator(_ token: Lexer.Token) -> Bool {
        switch token {
        case .equal: fallthrough
        case .plusEqual: fallthrough
        case .minusEqual: fallthrough
        case .asteriskEqual: fallthrough
        case .slashEqual: fallthrough
        case .percentEqual: fallthrough
        case .ampersandEqual: fallthrough
        case .pipeEqual: fallthrough
        case .carrotEqual: fallthrough
        case .shiftLeftEqual: fallthrough
        case .shiftRightEqual: return true
        default: return false
        }
    }
    
    func parseExpression(tokenStream: inout [(Lexer.Token, LexerPosition)], minimumPrecedence: Int) -> Parser.AST.Expression {
        if tokenStream.isEmpty {
            print("Expected expression but encountered end of token stream")
            exit(ExitCode.parserError.rawValue)
        }
        
        var left = parseFactor(tokenStream: &tokenStream)
        var nextToken = peek(tokenStream)
        while isBinaryOperator(nextToken) && precedence(nextToken) >= minimumPrecedence {
            if isAssignmentOperator(nextToken) {
                tokenStream.removeFirst()
                let right = parseExpression(tokenStream: &tokenStream, minimumPrecedence: precedence(nextToken))
                if nextToken == .equal {
                    left = .Assignment(left, right, nil)
                } else {
                    switch nextToken {
                    case .plusEqual: left = .CompoundAssignment(.Add, left, right, nil)
                    case .minusEqual: left = .CompoundAssignment(.Subtract, left, right, nil)
                    case .asteriskEqual: left = .CompoundAssignment(.Multiply, left, right, nil)
                    case .slashEqual: left = .CompoundAssignment(.Divide, left, right, nil)
                    case .percentEqual: left = .CompoundAssignment(.Remainder, left, right, nil)
                    case .ampersandEqual: left = .CompoundAssignment(.BitwiseAnd, left, right, nil)
                    case .pipeEqual: left = .CompoundAssignment(.BitwiseOr, left, right, nil)
                    case .carrotEqual: left = .CompoundAssignment(.BitwiseXor, left, right, nil)
                    case .shiftLeftEqual: left = .CompoundAssignment(.BitwiseShiftLeft, left, right, nil)
                    case .shiftRightEqual: left = .CompoundAssignment(.BitwiseShiftRight, left, right, nil)
                    default:
                        print("Unreachable A")
                        exit(ExitCode.internalError.rawValue)
                    }
                }
            } else if nextToken == .question {
                let _ = expect(.question, &tokenStream)
                let middle = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
                let _ = expect(.colon, &tokenStream)
                let right = parseExpression(tokenStream: &tokenStream, minimumPrecedence: precedence(nextToken))
                left = .Conditional(left, middle, right, nil)
            } else {
                let op : AST.BinaryOperator
                switch nextToken {
                case .plus: op = .Add
                case .negate: op = .Subtract
                case .asterisk: op = .Multiply
                case .forwardSlash: op = .Divide
                case .percent: op = .Remainder
                case .doubleAmpersand: op = .And
                case .doublePipe: op = .Or
                case .doubleEquals: op = .Equal
                case .notEquals: op = .NotEqual
                case .lessThan: op = .LessThan
                case .lessThanEqual: op = .LessOrEqual
                case .greaterThan: op = .GreaterThan
                case .greaterThanEqual: op = .GreaterOrEqual
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
                left = .Binary(op, left, right, nil)
            }
            nextToken = peek(tokenStream)
        }
        return left
    }
    
    func parseFunctionCallParameters(tokenStream: inout [(Lexer.Token, LexerPosition)]) -> [Parser.AST.Expression] {
        let _ = expect(.openParen, &tokenStream)
        var expressionList : [Parser.AST.Expression] = []
        if peek(tokenStream) != .closeParen {
            expressionList.append(parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0))
        }
        while peek(tokenStream) != .closeParen {
            let _ = expect(.comma, &tokenStream)
            expressionList.append(parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0))
        }
        let _ = expect(.closeParen, &tokenStream)

        return expressionList
    }

    func parseConstant(token: Lexer.Token) -> Parser.AST.Expression {
        switch token {
            case .constant(let val):
                var trimmedVal : String = val
                var shouldBeLong = false
                var shouldBeUnsigned = false

                while trimmedVal.last!.isLetter {
                    if trimmedVal.last == "l" || trimmedVal.last == "L" {
                        trimmedVal.removeLast()
                        shouldBeLong = true
                    } else if trimmedVal.last == "u" || trimmedVal.last == "U" {
                        trimmedVal.removeLast()
                        shouldBeUnsigned = true
                    }
                }

                if shouldBeUnsigned {
                    guard let longVal = UInt64(trimmedVal) else {
                        print("Integer constant \(trimmedVal) was not a valid integer")
                        exit(ExitCode.parserError.rawValue)
                    }

                    shouldBeLong = shouldBeLong || longVal > UInt32.max

                    if shouldBeLong {
                        return .Constant(.ConstUnsignedLong(longVal), nil)
                    }

                    guard let int32Val = UInt32(trimmedVal) else {
                        print("Integer constant \(trimmedVal) was not a valid integer")
                        exit(ExitCode.parserError.rawValue)
                    }
                    return .Constant(.ConstUnsignedInt(int32Val), nil)
                } else {
                    guard let longVal = Int64(trimmedVal) else {
                        print("Integer constant \(trimmedVal) was not a valid integer")
                        exit(ExitCode.parserError.rawValue)
                    }

                    shouldBeLong = shouldBeLong || longVal > Int32.max

                    if shouldBeLong {
                        return .Constant(.ConstLong(longVal), nil)
                    }
                    guard let int32Val = Int32(trimmedVal) else {
                        print("Integer constant \(trimmedVal) was not a valid integer")
                        exit(ExitCode.parserError.rawValue)
                    }
                    return .Constant(.ConstInt(int32Val), nil)
                }
            case .floatingPointConstant(let val):
                guard let parsedVal = Double(val) else {
                    print("Failed to parse floating point constant \(val)")
                    exit(ExitCode.parserError.rawValue)
                }
                return .Constant(.ConstDouble(parsedVal), nil)
            default:
                print("Unreachable non-constant constant")
                exit(ExitCode.internalError.rawValue)
        }
    }

    func parseFactor(tokenStream: inout [(Lexer.Token, LexerPosition)]) -> Parser.AST.Expression {
        if tokenStream.isEmpty {
            print("Expected factor but encountered end of token stream")
            exit(ExitCode.parserError.rawValue)
        }
        
        let (next, position) = tokenStream.removeFirst()
        var lhs : Parser.AST.Expression
        switch next {
            // parse an integer constant
        case .constant(_): fallthrough
        case .floatingPointConstant(_):
            lhs = parseConstant(token: next)
            // variable
        case .identifier(let name):
            lhs = .Var(name, nil)
            // expression wrapped in parentheses, or cast
        case .openParen:
            if isType(tokenStream) || isTypeSpecifier(tokenStream) {
                // "(" <type> ")" <exp>
                let (tp, storage) = parseType(&tokenStream)
                let _ = expect(.closeParen, &tokenStream)
                let child = parseFactor(tokenStream: &tokenStream)
                if storage != nil {
                    print("Cannot specify storage class when casting type of \(child) to \(tp)")
                }
                lhs = .Cast(tp, child, nil)
            } else {
                // "(" <exp> ")"
                let out = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
                let _ = expect(.closeParen, &tokenStream)
                lhs = out
            }
            // <unop> <exp>
        case .complement:
            let child = parseFactor(tokenStream: &tokenStream)
            lhs = .Unary(.Complement, child, nil)
        case .negate:
            let child = parseFactor(tokenStream: &tokenStream)
            lhs = .Unary(.Negate, child, nil)
        case .exclamation:
            let child = parseFactor(tokenStream: &tokenStream)
            lhs = .Unary(.Not, child, nil)
        case .increment:
            let child = parseFactor(tokenStream: &tokenStream)
            lhs = .Unary(.PreIncrement, child, nil)
        case .decrement:
            let child = parseFactor(tokenStream: &tokenStream)
            lhs = .Unary(.PreDecrement, child, nil)
        default:
            print("Expected expression but encountered \(next) at line \(position.0), column \(position.1)")
            exit(ExitCode.parserError.rawValue)
        }
        
        // check for postfix operators
        switch peek(tokenStream) {
            case .increment:
                lhs = .Unary(.PostIncrement, lhs, nil)
                tokenStream.removeFirst()
            case .decrement:
                lhs = .Unary(.PostDecrement, lhs, nil)
                tokenStream.removeFirst()
            case .openParen:
                // function call
                // get paremeters
                let params = parseFunctionCallParameters(tokenStream: &tokenStream)
                lhs = .FunctionCall(lhs, params, nil)
            default:
                break
        }
        
        return lhs
    }
    
    func parseLabeledStatement(tokenStream: inout [(Lexer.Token, LexerPosition)]) -> Parser.AST.LabeledStatement {
        func finishParsingLabeledStatement() -> Parser.AST.LabeledStatement {
            let next = peek(tokenStream)
            switch next {
                case .constant(_):
                    let c = parseConstant(token: next)
                    tokenStream.removeFirst()
                    let _ = expect(.colon, &tokenStream)
                    return .CaseStatement(c, parseStatement(tokenStream: &tokenStream))
                default:
                    print("Only constant values may be used in case statements")
                    exit(ExitCode.semanticError.rawValue)
            }
        }
        switch peek(tokenStream) {
            case .identifier(let name):
                tokenStream.removeFirst()
                let _ = expect(.colon, &tokenStream)
                let dependentStatement = parseStatement(tokenStream: &tokenStream)
                return .IdentifiedLine(name, dependentStatement)
            case .keywordCase:
                let _ = expect(.keywordCase, &tokenStream)
                return finishParsingLabeledStatement()
            case .keywordDefault:
                let _ = expect(.keywordDefault, &tokenStream)
                let _ = expect(.colon, &tokenStream)
                return .DefaultStatement(parseStatement(tokenStream: &tokenStream))
            default:
                print("Unreachable labeled statement prefix: \(tokenStream[0])")
                exit(ExitCode.internalError.rawValue)
        }
    }
    
    func parseStatement(tokenStream: inout [(Lexer.Token, LexerPosition)]) -> Parser.AST.Statement {
        let maybeReturn = peek(tokenStream)
        
        switch maybeReturn {
        case .keywordReturn:
            let _ = expect(.keywordReturn, &tokenStream)
            let exp : Parser.AST.Expression?
            if peek(tokenStream) != .semicolon {
                exp = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
            } else {
                exp = nil
            }
            let _ = expect(.semicolon, &tokenStream)
            return .Return(exp)
        case .semicolon:
            let _ = expect(.semicolon, &tokenStream)
            return .Null
        case .keywordIf:
            let _ = expect(.keywordIf, &tokenStream)
            let _ = expect(.openParen, &tokenStream)
            let conditional = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
            let _ = expect(.closeParen, &tokenStream)
            let thenStatement = parseStatement(tokenStream: &tokenStream)
            var elseStatement : Parser.AST.Statement? = nil
            if peek(tokenStream) == .keywordElse {
                let _ = expect(.keywordElse, &tokenStream)
                elseStatement = parseStatement(tokenStream: &tokenStream)
            }
            return .If(conditional, thenStatement, elseStatement)
        case .openBrace:
            return .Compound(parseBlock(tokenStream: &tokenStream))
        case .keywordBreak:
            let _ = expect(.keywordBreak, &tokenStream)
            let brk : Parser.AST.Statement = .Break("")
            let _ = expect(.semicolon, &tokenStream)
            return brk
        case .keywordContinue:
            let _ = expect(.keywordContinue, &tokenStream)
            let cont : Parser.AST.Statement = .Continue("")
            let _ = expect(.semicolon, &tokenStream)
            return cont
        case .keywordWhile:
            let _ = expect(.keywordWhile, &tokenStream)
            let _ = expect(.openParen, &tokenStream)
            let cond = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
            let _ = expect(.closeParen, &tokenStream)
            return .While(cond, parseStatement(tokenStream: &tokenStream), "")
        case .keywordDo:
            let _ = expect(.keywordDo, &tokenStream)
            let body = parseStatement(tokenStream: &tokenStream)
            let _ = expect(.keywordWhile, &tokenStream)
            let _ = expect(.openParen, &tokenStream)
            let cond = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
            let _ = expect(.closeParen, &tokenStream)
            let _ = expect(.semicolon, &tokenStream)
            return .DoWhile(body, cond, "")
        case .keywordFor:
            let _ = expect(.keywordFor, &tokenStream)
            let _ = expect(.openParen, &tokenStream)
            let forInit = parseForInit(tokenStream: &tokenStream)
            let cond : Parser.AST.Expression?
            if peek(tokenStream) != .semicolon {
                cond = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
            } else {
                cond = nil
            }
            let _ = expect(.semicolon, &tokenStream)
            let inc : Parser.AST.Expression?
            if peek(tokenStream) != .closeParen {
                inc = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
            } else {
                inc = nil
            }
            let _ = expect(.closeParen, &tokenStream)
            let body = parseStatement(tokenStream: &tokenStream)
            return .For(forInit, cond, inc, body, "")
        case .keywordSwitch:
            let _ = expect(.keywordSwitch, &tokenStream)
            let _ = expect(.openParen, &tokenStream)
            let condition = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
            let _ = expect(.closeParen, &tokenStream)
            let body = parseStatement(tokenStream: &tokenStream)
            return .Switch(condition, body, "")
        case .identifier(_):
            if tokenStream.count > 1 {
                if tokenStream[1].0 == .colon {
                    // labeled statement
                    let out : Parser.AST.Statement = .Labeled(parseLabeledStatement(tokenStream: &tokenStream))
                    let _ = expect(.semicolon, &tokenStream)
                    return out
                } else {
                    // ummmmm.... probably an expression
                    let exp = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
                    let _ = expect(.semicolon, &tokenStream)
                    return .Expression(exp)
                }
            } else {
                print("Unexpected end of stream when parsing labeled statement")
                exit(ExitCode.parserError.rawValue)
            }
        case .keywordCase: fallthrough
        case .keywordDefault:
            let out : Parser.AST.Statement = .Labeled(parseLabeledStatement(tokenStream: &tokenStream))
            return out
        default:
            let exp = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
            let _ = expect(.semicolon, &tokenStream)
            return .Expression(exp)
        }
    }
    
    func parseBlockItem(tokenStream: inout [(Lexer.Token, LexerPosition)]) -> Parser.AST.BlockItem {
        // <block-item> = <statement> | <declaration>
        
        // determine if we're lookoing at a statement or a declaration
        // for now we can cheat: declarations all start with a type name and statements do not
        
        if isType(tokenStream) || isTypeSpecifier(tokenStream) {
            // declaration
            return .D(parseDeclaration(tokenStream: &tokenStream))
        } else {
            // statement
            return .S(parseStatement(tokenStream: &tokenStream))
        }
    }
    
    func parseBlock(tokenStream: inout [(Lexer.Token, LexerPosition)]) -> Parser.AST.Block {
        let _ = expect(.openBrace, &tokenStream)
        var body : [Parser.AST.BlockItem] = []
        while peek(tokenStream) != .closeBrace {
            body.append(parseBlockItem(tokenStream: &tokenStream))
        }
        let _ = expect(.closeBrace, &tokenStream)
        return .Block(body)
    }

    func parseType(_ tokenStream: inout [(Lexer.Token, LexerPosition)]) -> (Parser.AST.CType, Parser.AST.StorageClass?) {
        let _ = peek(tokenStream)
        let startPosition = tokenStream[0].1
        // start by eating all of the specifiers
        var specifierList : [Lexer.Token] = []
        while isType(tokenStream) || isTypeSpecifier(tokenStream) {
            specifierList.append(tokenStream.removeFirst().0)
        }

        // check for empty
        if specifierList.isEmpty {
            print("Type specifier list is empty at line \(startPosition.0), column \(startPosition.1)")
            exit(ExitCode.parserError.rawValue)
        }

        // check for dupes
        if Set(specifierList).count != specifierList.count {
            print("Duplicates found in type/specifier list starting at line \(startPosition.0), column \(startPosition.1)")
            exit(ExitCode.parserError.rawValue)
        }

        // look for conflicting signed-ness
        if specifierList.contains(.keywordSigned) && specifierList.contains(.keywordUnsigned) {
            print("Specifier list at line \(startPosition.0), column \(startPosition.1) specifies both signed and unsigned")
        }

        // pull out storage class specifier
        var storageClass : Parser.AST.StorageClass? = nil
        if specifierList.contains(.keywordStatic) && specifierList.contains(.keywordExtern) {
            print("Conflicting storage types 'static' and 'extern' found in specifier list at line \(startPosition.0), column \(startPosition.1)")
            exit(ExitCode.parserError.rawValue)
        }

        if specifierList.contains(.keywordStatic) { storageClass = .Static }
        else if specifierList.contains(.keywordExtern) { storageClass = .Extern }

        if specifierList.contains(.keywordUnsigned) && specifierList.contains(.keywordLong) {
            return (.UnsignedLong, storageClass)
        }

        if specifierList.contains(.keywordUnsigned) {
            return (.UnsignedInt, storageClass)
        }

        if specifierList.contains(.keywordLong) {
            return (.Long, storageClass)
        }

        if specifierList.contains(.keywordVoid) {
            // probably all kinds of wrong, break elsewhere
            return (.Void, storageClass)
        }

        // nothing specified, must be signed int
        return (.Int, storageClass)
    }

    func parseDeclaration(tokenStream: inout [(Lexer.Token, LexerPosition)]) -> Parser.AST.Declaration {
        // parse a "specifier"

        let (declaredType, storageClass) = parseType(&tokenStream)
        let varName = expectIdentifier(&tokenStream)
        
        if peek(tokenStream) == .openParen {
            // we're looking at a function declaration
            let _ = expect(.openParen, &tokenStream)
            let params : [Parser.AST.Parameter]
            if peek(tokenStream) != .closeParen {
                params = parseFunctionParameters(tokenStream: &tokenStream)
            } else {
                params = []
            }

            let _ = expect(.closeParen, &tokenStream)

            if peek(tokenStream) == .semicolon {
                let _ = expect(.semicolon, &tokenStream)
                return .FunctionDeclaration(declaredType, varName, params, nil, storageClass)
            }

            return .FunctionDeclaration(declaredType, varName, params, parseBlock(tokenStream: &tokenStream), storageClass)
        } else {
            // // does this check belong here?
            if declaredType == .Void {
                print("Variable declaration \(varName) cannot be void")
                exit(ExitCode.semanticError.rawValue)
            }
            let exp : Parser.AST.Expression?
            if peek(tokenStream) == .equal {
                let _ = expect(.equal, &tokenStream)
                exp = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
            } else {
                exp = nil
            }
            
            let _ = expect(.semicolon, &tokenStream)
            
            return .VariableDeclaration(declaredType, varName, exp, storageClass)
        }
    }
    
    func parseForInit(tokenStream: inout [(Lexer.Token, LexerPosition)]) -> Parser.AST.ForInit {
        // NOTE: will need to modify this when we introduce more types
        if isType(tokenStream) || isTypeSpecifier(tokenStream)  {
            let childDecl = parseDeclaration(tokenStream: &tokenStream)
            // weird edge case
            switch childDecl {
                case .FunctionDeclaration(_, let name, _, _, _):
                    print("Can't provide a function as a for loop initializer: \(name)")
                    exit(ExitCode.parserError.rawValue)
                default: ()
            }
            let out : Parser.AST.ForInit = .InitDecl(childDecl)
            return out;
        } else {
            let exp : Parser.AST.Expression?
            if peek(tokenStream) != .semicolon {
                exp = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
            } else { exp = nil }
            let _ = expect(.semicolon, &tokenStream)
            return .InitExp(exp)
        }
    }
    
    func parseFunctionParameters(tokenStream: inout [(Lexer.Token, LexerPosition)]) -> [Parser.AST.Parameter] {
        let pType = expectType(&tokenStream)

        // technically you're allowed not to name "void"
        if pType == .keywordVoid {
            return []
        }

        let pName = expectIdentifier(&tokenStream)
        var params : [Parser.AST.Parameter] = [.NamedParameter(convertType(pType), pName)]

        while peek(tokenStream) == .comma {
            let _ = expect(.comma, &tokenStream)
            let nextType = expectType(&tokenStream)
            let nextName = expectIdentifier(&tokenStream)
            params.append(.NamedParameter(convertType(nextType), nextName))
        }

        return params
    }

    func parseProgram(tokenStream: inout [(Lexer.Token, LexerPosition)]) -> Parser.AST.Program {
        // right now, only functions and function declarations
        var declarations : [Parser.AST.Declaration] = []
        while !tokenStream.isEmpty {
            declarations.append(parseDeclaration(tokenStream: &tokenStream))
        }
        return .Statement(declarations)
    }
    
    func fixUpCompoundAssignments(_ exp: Parser.AST.Expression) -> Parser.AST.Expression {
        switch exp {
        case .CompoundAssignment(let op, let lVal, let rVal, _):
            return .Assignment(lVal, .Binary(op, lVal, rVal, nil), nil)
        default: return exp
        }
    }
    
    func fixUpCompoundAssignments(_ labeledStmt: Parser.AST.LabeledStatement) -> Parser.AST.LabeledStatement {
        return labeledStmt
    }
    
    func fixUpCompoundAssignments(_ statement: Parser.AST.Statement) -> Parser.AST.Statement {
        switch statement {
        case .Expression(let exp): return .Expression(fixUpCompoundAssignments(exp))
        case .Null: return statement
        case .Return(let exp): return .Return(exp == nil ? nil : fixUpCompoundAssignments(exp!))
        case .If(let exp, let thenStatement, let elseStatement):
            return .If(fixUpCompoundAssignments(exp), fixUpCompoundAssignments(thenStatement), elseStatement == nil ? nil : fixUpCompoundAssignments(elseStatement!))
        case .Compound(let block):
            switch block {
            case .Block(let blockItemStar):
                return .Compound(.Block(blockItemStar.map { fixUpCompoundAssignments($0) }))
            }
        case .Break(_): return statement
        case .Continue(_): return statement
        case .While(let condition, let body, _):
            return .While(fixUpCompoundAssignments(condition), fixUpCompoundAssignments(body), "")
        case .DoWhile(let body, let condition, _):
            return .DoWhile(fixUpCompoundAssignments(body), fixUpCompoundAssignments(condition), "")
        case .For(let forInit, let condition, let post, let body, _):
            let fixedUpInit : Parser.AST.ForInit
            switch forInit {
            case .InitDecl(_): fixedUpInit = forInit
            case .InitExp(let exp):
                if let e = exp {
                    fixedUpInit = .InitExp(fixUpCompoundAssignments(e))
                } else {
                    fixedUpInit = forInit
                }
            }
            return .For(
                fixedUpInit,
                condition == nil ? nil : fixUpCompoundAssignments(condition!),
                post == nil ? nil : fixUpCompoundAssignments(post!),
                fixUpCompoundAssignments(body),
                ""
            )
        case .Switch(let toggle, let body, let label):
            return .Switch(fixUpCompoundAssignments(toggle), fixUpCompoundAssignments(body), label)
        case .Labeled(let stmt):
            return .Labeled(fixUpCompoundAssignments(stmt))
        }
    }
        
    func fixUpCompoundAssignments(_ blockItem: Parser.AST.BlockItem) -> Parser.AST.BlockItem {
        switch blockItem {
            case .D(_):
                return blockItem
            case .S(let stmt):
                return .S(fixUpCompoundAssignments(stmt))
        }
    }
    
    func fixUpCompoundAssignments(_ decl: Parser.AST.Declaration) -> Parser.AST.Declaration {
        switch decl {
            case .FunctionDeclaration(let returnType, let name, let params, let body, let storageClass):
                if let b = body {
                    switch b {
                        case .Block(let items):
                            return .FunctionDeclaration(returnType, name, params, .Block(items.map { fixUpCompoundAssignments($0) }), storageClass)
                    }
                } else {
                    return .FunctionDeclaration(returnType, name, params, nil, storageClass)
                }
            case .VariableDeclaration(let tp, let name, let initializer, let storageClass):
                if let e = initializer {
                    return .VariableDeclaration(tp, name, fixUpCompoundAssignments(e), storageClass)
                } else {
                    return .VariableDeclaration(tp, name, nil, storageClass)
                }
        }
    }

    func fixUpCompoundAssignments(_ program: Parser.AST.Program) -> Parser.AST.Program {
        switch program {
            case .Statement(let decls):
                return .Statement(decls.map { fixUpCompoundAssignments($0) })
        }
    }
    
    func parse(tokenStream: inout [(Lexer.Token, LexerPosition)]) -> Parser.AST.Program {
        let initialForm = parseProgram(tokenStream: &tokenStream)
        
        if !tokenStream.isEmpty {
            print("Unexpected tokens found at end of stream: \(tokenStream)")
            exit(ExitCode.parserError.rawValue)
        }
        
        let noCompoundAssignments = fixUpCompoundAssignments(initialForm)
        return noCompoundAssignments
        
    }
}
