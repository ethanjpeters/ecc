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
            // does this go here?
            case FunctionCall
        }
        
        indirect enum Expression {
            case Constant(Int)
            case Unary(UnaryOperator, Expression)
            case Binary(BinaryOperator, Expression, Expression)
            case Var(String /* identifier */)
            case Assignment(Expression, Expression)
            case CompoundAssignment(BinaryOperator, Expression, Expression)
            case Conditional(Expression /* condition */, Expression, Expression)
            case FunctionCallParameters([Expression])
        }
        
        enum Declaration {
            case Declaration(String /* identifier name */, Expression?)
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
            case Return(Expression)
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
        
        enum ProgramLevelStatement {
            case Function(String /* name */, Block /* body */)
        }

        enum Program {
            case Statement([ProgramLevelStatement])
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
            // DEBUG
            print("REAMAINING TOKEN STREAM: \(tokenStream)")
            // END DEBUG
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
    
    func parseExpression(tokenStream: inout [Lexer.Token], minimumPrecedence: Int) -> Parser.AST.Expression {
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
                    left = .Assignment(left, right)
                } else {
                    switch nextToken {
                    case .plusEqual: left = .CompoundAssignment(.Add, left, right)
                    case .minusEqual: left = .CompoundAssignment(.Subtract, left, right)
                    case .asteriskEqual: left = .CompoundAssignment(.Multiply, left, right)
                    case .slashEqual: left = .CompoundAssignment(.Divide, left, right)
                    case .percentEqual: left = .CompoundAssignment(.Remainder, left, right)
                    case .ampersandEqual: left = .CompoundAssignment(.BitwiseAnd, left, right)
                    case .pipeEqual: left = .CompoundAssignment(.BitwiseOr, left, right)
                    case .carrotEqual: left = .CompoundAssignment(.BitwiseXor, left, right)
                    case .shiftLeftEqual: left = .CompoundAssignment(.BitwiseShiftLeft, left, right)
                    case .shiftRightEqual: left = .CompoundAssignment(.BitwiseShiftRight, left, right)
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
                left = .Conditional(left, middle, right)
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
                left = .Binary(op, left, right)
            }
            nextToken = peek(tokenStream)
        }
        return left
    }
    
    func parseFunctionCallParameters(tokenStream: inout [Lexer.Token]) -> Parser.AST.Expression {
        let _ = expect(.openParen, &tokenStream)
        var expressionList : [Parser.AST.Expression] = []
        var firstPass = true
        while peek(tokenStream) != .closeParen {
            if peek(tokenStream) == .comma {
                if firstPass {
                    print("Found a comma at the beginning of function call parameters")
                    exit(ExitCode.parserError.rawValue)
                }
                let _ = expect(.comma, &tokenStream)
            }
            expressionList.append(parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0))
            firstPass = false
        }
        let _ = expect(.closeParen, &tokenStream)

        return .FunctionCallParameters(expressionList)
    }

    func parseFactor(tokenStream: inout [Lexer.Token]) -> Parser.AST.Expression {
        if tokenStream.isEmpty {
            print("Expected factor but encountered end of token stream")
            exit(ExitCode.parserError.rawValue)
        }
        
        let next = tokenStream.removeFirst()
        var lhs : Parser.AST.Expression
        switch next {
            // parse an integer constant
        case .constant(let val):
            guard let intVal = Int(val) else {
                print("Integer constant \(val) was not a valid integer")
                exit(ExitCode.parserError.rawValue)
            }
            lhs = .Constant(intVal)
            // variable
        case .identifier(let name):
            lhs = .Var(name)
            // expression wrapped in parentheses
        case .openParen:
            let out = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
            let _ = expect(.closeParen, &tokenStream)
            lhs = out
            // <unop> <exp>
        case .complement:
            let child = parseFactor(tokenStream: &tokenStream)
            lhs = .Unary(.Complement, child)
        case .negate:
            let child = parseFactor(tokenStream: &tokenStream)
            lhs = .Unary(.Negate, child)
        case .exclamation:
            let child = parseFactor(tokenStream: &tokenStream)
            lhs = .Unary(.Not, child)
        case .increment:
            let child = parseFactor(tokenStream: &tokenStream)
            lhs = .Unary(.PreIncrement, child)
        case .decrement:
            let child = parseFactor(tokenStream: &tokenStream)
            lhs = .Unary(.PreDecrement, child)
        default:
            print("Expected expression but encountered \(next)")
            exit(ExitCode.parserError.rawValue)
        }
        
        // check for postfix operators
        switch peek(tokenStream) {
            case .increment:
                lhs = .Unary(.PostIncrement, lhs)
                tokenStream.removeFirst()
            case .decrement:
                lhs = .Unary(.PostDecrement, lhs)
                tokenStream.removeFirst()
            case .openParen:
                // function call
                // get paremeters
                let params = parseFunctionCallParameters(tokenStream: &tokenStream)
                lhs = .Binary(.FunctionCall, lhs, params)
            default:
                break
        }
        
        return lhs
    }
    
    func parseLabeledStatement(tokenStream: inout [Lexer.Token]) -> Parser.AST.LabeledStatement {
        func finishParsingLabeledStatement() -> Parser.AST.LabeledStatement {
            switch peek(tokenStream) {
                case .constant(let val):
                    tokenStream.removeFirst()
                    let _ = expect(.colon, &tokenStream)
                    guard let intVal = Int(val) else {
                        print("Integer constant \(val) was not a valid integer")
                        exit(ExitCode.parserError.rawValue)
                    }
                    return .CaseStatement(.Constant(intVal), parseStatement(tokenStream: &tokenStream))
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
    
    func parseStatement(tokenStream: inout [Lexer.Token]) -> Parser.AST.Statement {
        let maybeReturn = peek(tokenStream)
        
        switch maybeReturn {
        case .keywordReturn:
            let _ = expect(.keywordReturn, &tokenStream)
            let exp = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
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
                if tokenStream[1] == .colon {
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
    
    func parseBlockItem(tokenStream: inout [Lexer.Token]) -> Parser.AST.BlockItem {
        // <block-item> = <statement> | <declaration>
        
        // determine if we're lookoing at a statement or a declaration
        // for now we can cheat: declarations all start with a type name and statements do not
        
        if peek(tokenStream) == .keywordInt {
            // declaration
            return .D(parseDeclaration(tokenStream: &tokenStream))
        } else {
            // statement
            return .S(parseStatement(tokenStream: &tokenStream))
        }
    }
    
    func parseBlock(tokenStream: inout [Lexer.Token]) -> Parser.AST.Block {
        let _ = expect(.openBrace, &tokenStream)
        var body : [Parser.AST.BlockItem] = []
        while peek(tokenStream) != .closeBrace {
            body.append(parseBlockItem(tokenStream: &tokenStream))
        }
        let _ = expect(.closeBrace, &tokenStream)
        return .Block(body)
    }
    
    func parseDeclaration(tokenStream: inout [Lexer.Token]) -> Parser.AST.Declaration {
        let _ = expect(.keywordInt, &tokenStream)
        if tokenStream.isEmpty {
            print("Unexpected end of stream hit while parsing declaration")
            exit(ExitCode.parserError.rawValue)
        }
        
        let idToken = tokenStream.removeFirst()
        
        let varName : String
        switch idToken {
        case .identifier(let name):
            varName = name
        default:
            print("Expected identifier in declaration but found \(idToken) instead")
            exit(ExitCode.parserError.rawValue)
        }
        
        let exp : Parser.AST.Expression?
        if peek(tokenStream) == .equal {
            let _ = expect(.equal, &tokenStream)
            exp = parseExpression(tokenStream: &tokenStream, minimumPrecedence: 0)
        } else {
            exp = nil
        }
        
        let _ = expect(.semicolon, &tokenStream)
        
        return .Declaration(varName, exp)
    }
    
    func parseForInit(tokenStream: inout [Lexer.Token]) -> Parser.AST.ForInit {
        if peek(tokenStream) == .keywordInt {
            let out : Parser.AST.ForInit = .InitDecl(parseDeclaration(tokenStream: &tokenStream))
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
    
    func parseFunction(tokenStream: inout [Lexer.Token]) -> Parser.AST.ProgramLevelStatement {
        if tokenStream.isEmpty {
            print("Empty token stream encountered when expecting a function")
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
        
        return .Function(functionName, parseBlock(tokenStream: &tokenStream))
    }

    func parseProgram(tokenStream: inout [Lexer.Token]) -> Parser.AST.Program {
        // right now, only functions
        var functions : [Parser.AST.ProgramLevelStatement] = []
        while !tokenStream.isEmpty {
            functions.append(parseFunction(tokenStream: &tokenStream))
        }
        return .Statement(functions)
    }
    
    func fixUpCompoundAssignments(_ exp: Parser.AST.Expression) -> Parser.AST.Expression {
        switch exp {
        case .CompoundAssignment(let op, let lVal, let rVal):
            return .Assignment(lVal, .Binary(op, lVal, rVal))
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
        case .Return(let exp): return .Return(fixUpCompoundAssignments(exp))
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
    
    func fixUpCompoundAssignments(_ statement: Parser.AST.ProgramLevelStatement) -> Parser.AST.ProgramLevelStatement {
        switch statement {
            case .Function(let name, let body):
                switch body {
                    case .Block(let body):
                        return .Function(name, .Block(body.map { fixUpCompoundAssignments($0) }))
                }
        }
    }

    func fixUpCompoundAssignments(_ program: Parser.AST.Program) -> Parser.AST.Program {
        switch program {
            case .Statement(let stmt):
                return .Statement(stmt.map { fixUpCompoundAssignments($0) })
        }
    }
    
    func parse(tokenStream: inout [Lexer.Token]) -> Parser.AST.Program {
        let initialForm = parseProgram(tokenStream: &tokenStream)
        
        if !tokenStream.isEmpty {
            print("Unexpected tokens found at end of stream: \(tokenStream)")
            exit(ExitCode.parserError.rawValue)
        }
        
        let noCompoundAssignments = fixUpCompoundAssignments(initialForm)
        return noCompoundAssignments
        
    }
}
