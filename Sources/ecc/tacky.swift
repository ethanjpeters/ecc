import Foundation

class Tacky {
    struct IR {
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

        enum Value {
            case Constant(Int)
            case Var(String)
        }

        enum Instruction {
            case Return(Value?)
            case Unary(UnaryOperator, Value/* src */, Value /* dst */)
            case Binary(BinaryOperator, Value /* src1 */, Value /* src2 */, Value /* dst */)
            case Copy(Value /* src */, Value /* dst */)
            case Jump(String /* identifier target */)
            case JumpIfZero(Value /* condition */, String /* identifier target */)
            case JumpIfNotZero(Value /* condition */, String /* identifier target */)
            case Label(String /* identifier */)
            case Call(String /* function name */, [Value] /* parameters */, Value /* result */)
        }

        enum Declaration {
            case Function(String /* name */, Bool /* is global */, [String] /* params */, [Instruction] /* body */)
            case StaticVariable(String /* name */, Bool /* is global */, Int /* init */)
        }

        enum Program {
            case Statement([Declaration])
        }
    }

    private var tempNameCounter : Int = 0
    private var tempLabelCounter : Int = 0

    func makeTemp() -> String {
        let out = "tmp.\(tempNameCounter)"
        tempNameCounter = tempNameCounter + 1
        return out
    }

    func makeLabel(_ descriptor: String = "") -> String {
        let out = ".L\(descriptor)label.\(tempLabelCounter)"
        tempLabelCounter = tempLabelCounter + 1
        return out
    }

    func makeLoopLabel(_ descriptor: String) -> String {
        return ".L.loop.\(descriptor)label.inf"
    }

    func makeSwitchLabel(_ descriptor: String) -> String {
        return ".L.switch.\(descriptor)label.inf"
    }

    func transformUserLabel(_ userLabel: String) -> String {
        let out = ".L.user.\(userLabel).eps"
        return out
    }

    func convert(_ op : Parser.AST.BinaryOperator) -> IR.BinaryOperator {
        switch op {
            case .Add: return .Add
            case .Subtract: return .Subtract
            case .Multiply: return .Multiply
            case .Divide: return .Divide
            case .Equal: return .Equal
            case .NotEqual: return .NotEqual
            case .LessThan: return .LessThan
            case .LessOrEqual: return .LessOrEqual
            case .GreaterThan: return .GreaterThan
            case .GreaterOrEqual: return .GreaterOrEqual
            case .Remainder: return .Remainder
            case .BitwiseAnd: return .BitwiseAnd
            case .BitwiseOr: return .BitwiseOr
            case .BitwiseXor: return .BitwiseXor
            case .BitwiseShiftLeft: return .BitwiseShiftLeft
            case .BitwiseShiftRight: return .BitwiseShiftRight
            case .And: fallthrough
            case .Or:
                print("Unreachable 4")
                exit(ExitCode.internalError.rawValue)
        }
    }

    func generateTACKYExpression(_ exp: Parser.AST.Expression, out: inout [Tacky.IR.Instruction]) -> Tacky.IR.Value {

        func generateTACKYOp(_ op: Parser.AST.UnaryOperator) -> Tacky.IR.UnaryOperator {
            switch op {
                case .Complement: return .Complement
                case .Negate: return .Negate
                case .Not: return .Not
                case .PreIncrement: return .PreIncrement
                case .PreDecrement: return .PreDecrement
                case .PostIncrement: return .PostIncrement
                case .PostDecrement: return .PostDecrement
            }
        }

        func isIncOrDec(_ op: Parser.AST.UnaryOperator) -> Bool {
            switch op {
                case .PreIncrement: fallthrough
                case .PreDecrement: fallthrough
                case .PostIncrement: fallthrough
                case .PostDecrement: return true
                default: return false
            }
        }

        switch exp {
            case .ConstInt(let val):
                return .Constant(Int(val))
            case .ConstLong(let val):
                return .Constant(Int(val))
            case .Unary(let op, let exp):
                if isIncOrDec(op) {
                    let src = generateTACKYExpression(exp, out: &out)
                    let dstName = makeTemp()
                    let dst : Tacky.IR.Value = .Var(dstName)
                    switch op {
                        case .PreIncrement:
                            out.append(.Binary(.Add, .Constant(1), src, dst))
                            out.append(.Copy(dst, src))
                            return src
                        case .PreDecrement:
                            out.append(.Binary(.Subtract, src, .Constant(1), dst))
                            out.append(.Copy(dst, src))
                            return src
                        case .PostIncrement:
                            let tmpName = makeTemp()
                            let tmp : Tacky.IR.Value = .Var(tmpName)
                            out.append(.Copy(src, tmp))
                            out.append(.Binary(.Add, .Constant(1), src, dst))
                            out.append(.Copy(dst, src))
                            return tmp
                        case .PostDecrement:
                            let tmpName = makeTemp()
                            let tmp : Tacky.IR.Value = .Var(tmpName)
                            out.append(.Copy(src, tmp))
                            out.append(.Binary(.Subtract, src, .Constant(1), dst))
                            out.append(.Copy(dst, src))
                            return tmp
                        default:
                            print("Unreachable B")
                            exit(ExitCode.internalError.rawValue)
                    }
                } else {
                    let src = generateTACKYExpression(exp, out: &out)
                    let dstName = makeTemp()
                    let dst : Tacky.IR.Value = .Var(dstName)
                    let tackyOp = generateTACKYOp(op)
                    out.append(.Unary(tackyOp, src, dst))
                    return dst
                }
            case .Binary(let op, let left, let right):
                if op == .And {
                    let v1 = generateTACKYExpression(left, out: &out)
                    let falseLabel = makeLabel("and_false")
                    out.append(.JumpIfZero(v1, falseLabel))
                    let v2 = generateTACKYExpression(right, out: &out)
                    out.append(.JumpIfZero(v2, falseLabel))
                    let resultName = makeTemp()
                    let result : Tacky.IR.Value = .Var(resultName)
                    // result = 1
                    out.append(.Copy(.Constant(1), result))
                    let endLabel = makeLabel()
                    out.append(.Jump(endLabel))
                    out.append(.Label(falseLabel))
                    // result = 0
                    out.append(.Copy(.Constant(0), result))
                    out.append(.Label(endLabel))
                    return result
                } else if op == .Or {
                    let v1: Tacky.IR.Value = generateTACKYExpression(left, out: &out)
                    let trueLabel = makeLabel("or_true")
                    out.append(.JumpIfNotZero(v1, trueLabel))
                    let v2 = generateTACKYExpression(right, out: &out)
                    out.append(.JumpIfNotZero(v2, trueLabel))
                    let resultName = makeTemp()
                    let result : Tacky.IR.Value = .Var(resultName)
                    // result = 0
                    out.append(.Copy(.Constant(0), result))
                    let endLabel = makeLabel()
                    out.append(.Jump(endLabel))
                    out.append(.Label(trueLabel))
                    // result = 1
                    out.append(.Copy(.Constant(1), result))
                    out.append(.Label(endLabel))
                    return result
                } else {
                    let v1 = generateTACKYExpression(left, out: &out)
                    let v2  = generateTACKYExpression(right, out: &out)
                    let dstName = makeTemp()
                    let dst : IR.Value = .Var(dstName)
                    let tackyOp = convert(op)
                    out.append(.Binary(tackyOp, v1, v2, dst))
                    return dst
                }
            case .Var(let name):
                return .Var(name)
            case .Assignment(let lVal, let rVal):
                let result = generateTACKYExpression(rVal, out: &out)
                switch lVal {
                    case .Var(let name):
                        out.append(.Copy(result, .Var(name)))
                        return .Var(name)
                    default:
                        print("Unreachable non-variable lValue")
                        exit(ExitCode.internalError.rawValue)
                }
            case .CompoundAssignment(_,_,_):
                print("Unreachable compound assignment")
                exit(ExitCode.internalError.rawValue)
            case .Conditional(let cond, let left, let right):
                let condValue = generateTACKYExpression(cond, out: &out)
                let dstName = makeTemp()
                let dst : Tacky.IR.Value = .Var(dstName)
                let e2Label = makeLabel("right")
                let endLabel = makeLabel("end")
                out.append(.JumpIfZero(condValue, e2Label))
                let e1Value = generateTACKYExpression(left, out: &out)
                out.append(.Copy(e1Value, dst))
                out.append(.Jump(endLabel))
                out.append(.Label(e2Label))
                let e2Value = generateTACKYExpression(right, out: &out)
                out.append(.Copy(e2Value, dst))
                out.append(.Label(endLabel))
                return dst
            case .FunctionCall(let fun, let params):
                // fun has already been constrained to an lValue, currently just a name
                let funName : String
                switch fun {
                    case .Var(let fnNm):
                        funName = fnNm
                    default:
                        print("Unreachable non-lValue function \(fun)")
                        exit(ExitCode.internalError.rawValue)
                }
                var paramValues : [Tacky.IR.Value] = []
                for p in params {
                    paramValues.append(generateTACKYExpression(p, out: &out))
                }
                let dstName = makeTemp()
                let dst : Tacky.IR.Value = .Var(dstName)
                out.append(.Call(funName, paramValues, dst))
                return dst
        }
    }

    func generateTACKYStatement(statement: Parser.AST.Statement, out : inout [Tacky.IR.Instruction], switchValue: Tacky.IR.Value?, fallthroughValue: Tacky.IR.Value?) {
        switch statement {
            case .Return(let exp):
                let child : Tacky.IR.Value?
                if let e = exp {
                    child = generateTACKYExpression(e, out: &out)
                } else {
                    child = nil
                }
                out.append(.Return(child))
            case .Expression(let exp):
                let _ = generateTACKYExpression(exp, out: &out)
            case .If(let cond, let thenStatement, let elseStatement):
                let condValue = generateTACKYExpression(cond, out: &out)
                let elseLabel = makeLabel("ifelse")
                let endLabel = makeLabel("ifend")
                out.append(.JumpIfZero(condValue, elseLabel))
                generateTACKYStatement(statement: thenStatement, out: &out, switchValue: switchValue, fallthroughValue: fallthroughValue)
                out.append(.Jump(endLabel))
                out.append(.Label(elseLabel))
                if let es = elseStatement {
                    generateTACKYStatement(statement: es, out: &out, switchValue: switchValue, fallthroughValue: fallthroughValue)
                }
                out.append(.Label(endLabel))
            case .Null: ()
            case .Compound(let block):
                switch block {
                    case .Block(let items):
                        for itm in items {
                            switch itm {
                                case .S(let stmt):
                                    generateTACKYStatement(statement: stmt, out: &out, switchValue: switchValue, fallthroughValue: fallthroughValue)
                                case .D(let decl):
                                    let _ = generateTACKYDeclaration(decl: decl, out: &out)
                            }
                        }
                }
            case .Break(let label):
                out.append(.Jump(makeLoopLabel("\(label).break")))
            case .Continue(let label):
                out.append(.Jump(makeLoopLabel("\(label).continue")))
            case .While(let condition, let body, let label):
                let startLabel = makeLoopLabel("\(label).start")
                out.append(.Label(startLabel))  // for debugging purposes
                let continueLabel = makeLoopLabel("\(label).continue")
                out.append(.Label(continueLabel))
                let condValue = generateTACKYExpression(condition, out: &out)
                let breakLabel = makeLoopLabel("\(label).break")
                out.append(.JumpIfZero(condValue, breakLabel))
                generateTACKYStatement(statement: body, out: &out, switchValue: switchValue, fallthroughValue: fallthroughValue)
                out.append(.Jump(continueLabel))
                out.append(.Label(breakLabel))
            case .DoWhile(let body, let condition, let label):
                let startLabel = makeLoopLabel("\(label).start")
                out.append(.Label(startLabel))
                generateTACKYStatement(statement: body, out: &out, switchValue: switchValue, fallthroughValue: fallthroughValue)
                let continueLabel = makeLoopLabel("\(label).continue")
                out.append(.Label(continueLabel))
                let condValue = generateTACKYExpression(condition, out: &out)
                out.append(.JumpIfNotZero(condValue, startLabel))
                out.append(.Label(makeLoopLabel("\(label).break")))
            case .For(let forInit, let condition, let increment, let body, let label):
                switch forInit {
                    case .InitDecl(let decl):
                        let _ = generateTACKYDeclaration(decl: decl, out: &out)
                    case .InitExp(let exp):
                        if let e = exp {
                            let _ = generateTACKYExpression(e, out: &out)
                        }
                }
                let startLabel = makeLoopLabel("\(label).start")
                out.append(.Label(startLabel))
                let condValue : Tacky.IR.Value
                if let c = condition {
                    condValue = generateTACKYExpression(c, out: &out)
                } else {
                    condValue = .Constant(1)
                }
                let breakLabel = makeLoopLabel("\(label).break")
                out.append(.JumpIfZero(condValue, breakLabel))
                generateTACKYStatement(statement: body, out: &out, switchValue: switchValue, fallthroughValue: fallthroughValue)
                out.append(.Label(makeLoopLabel("\(label).continue")))
                if let inc = increment {
                    let _ = generateTACKYExpression(inc, out: &out)
                }
                out.append(.Jump(startLabel))
                out.append(.Label(breakLabel))
            case .Switch(let toggle, let stmt, let label):
                // NOTE: something here is broken, duff's device does not function properly
                let breakLabel = makeLoopLabel("\(label).break")
                let toggleVal = generateTACKYExpression(toggle, out: &out)
                let fallthroughTmpName = makeTemp()
                let ftVal : Tacky.IR.Value = .Var(fallthroughTmpName)
                out.append(.Copy(.Constant(0), ftVal))
                generateTACKYStatement(statement: stmt, out: &out, switchValue: toggleVal, fallthroughValue: ftVal)
                out.append(.Label(breakLabel))
            case .Labeled(let ls):
                switch ls {
                    case .CaseStatement(let labelExp, let line):
                        // check if we're falling through
                        let ftLabel = makeLabel("case.fallthrough")
                        let ftCmpTmpName = makeTemp()
                        let ftCmpTmp : Tacky.IR.Value = .Var(ftCmpTmpName)
                        out.append(.Binary(.Equal, fallthroughValue!, .Constant(1), ftCmpTmp))
                        out.append(.JumpIfNotZero(ftCmpTmp, ftLabel))
                        let labelVal = generateTACKYExpression(labelExp, out: &out)
                        let tmpName = makeTemp()
                        let tmp : Tacky.IR.Value = .Var(tmpName)
                        // semantic analyzer catches when we're not in a switch statement
                        // and switchValue would be nil
                        out.append(.Binary(.Equal, labelVal, switchValue!, tmp))
                        let skipLabel = makeLabel("case.skip")
                        out.append(.JumpIfZero(tmp, skipLabel))
                        out.append(.Copy(tmp, fallthroughValue!))
                        out.append(.Label(ftLabel))
                        generateTACKYStatement(statement: line, out: &out, switchValue: switchValue, fallthroughValue: fallthroughValue)
                        out.append(.Label(skipLabel))
                    case .IdentifiedLine(let label, let line):
                        out.append(.Label(transformUserLabel(label)))
                        generateTACKYStatement(statement: line, out: &out, switchValue: switchValue, fallthroughValue: fallthroughValue)
                    case .DefaultStatement(let stmt):
                        // unconditionally execute this statement
                        out.append(.Label(makeLabel("case.default")))
                        generateTACKYStatement(statement: stmt, out: &out, switchValue: nil, fallthroughValue: nil)
                }
        }
    }

    func generateTACKYDeclaration(decl: Parser.AST.Declaration, out : inout [Tacky.IR.Instruction]) -> Tacky.IR.Declaration? {
        switch decl {
            // TODO: use type information to determine size of parameters
            case .VariableDeclaration(_, let name, let exp, let storageClass):
                if exp != nil {
                    let child = generateTACKYExpression(exp!, out: &out)
                    out.append(.Copy(child, .Var(name)))
                }
                return nil
            case .FunctionDeclaration(_, let name, let parameters, let body, let storageClass):
                if let b = body {
                    switch b {
                        case .Block(let items):
                            var instrs : [Tacky.IR.Instruction] = []
                            for blockItem in items {
                                switch blockItem {
                                    case .S(let stmt):
                                        generateTACKYStatement(statement: stmt, out: &instrs, switchValue: nil, fallthroughValue: nil)
                                    case .D(let decl):
                                        let _ = generateTACKYDeclaration(decl: decl, out: &instrs)
                                }
                            }
                            instrs.append(.Return(.Constant(0)))
                            var tackyIds : [String] = []
                            for p in parameters {
                                switch p {
                                    case .NamedParameter(_, let name):
                                        tackyIds.append(name)
                                }
                            }
                            return .Function(name, storageClass != .Static, tackyIds, instrs)
                    }
                } else {
                    // no code for undefined functions
                    return nil
                }
        }
    }

    func generateTACKYSymbolTable(symbolTable: [String : (SemanticAnalyzer.TypeChecker.CheckerType, SemanticAnalyzer.TypeChecker.IdentifierAttributes)]) -> [Tacky.IR.Declaration] {
        var tackyDefs : [Tacky.IR.Declaration] = []
        for (name, entry) in symbolTable {
            let (_, attrs) = entry
            switch attrs {
                case .StaticAttr(let initVal, let isGlobal):
                    switch initVal {
                        case .Initial(let i):
                            tackyDefs.append(.StaticVariable(name, isGlobal, i))
                        case .Tentative:
                            tackyDefs.append(.StaticVariable(name, isGlobal, 0))
                        case .NoInitializer: ()
                    }
                default: ()
            }
        }
        return tackyDefs
    }

    func generateTACKYProgram(program: Parser.AST.Program, symbolTable: [String : (SemanticAnalyzer.TypeChecker.CheckerType, SemanticAnalyzer.TypeChecker.IdentifierAttributes)]) -> (Tacky.IR.Program, [Tacky.IR.Declaration]) {
        var out : [Tacky.IR.Instruction] = []
        switch program {
            case .Statement(let declarations):
                var tackyDecls : [Tacky.IR.Declaration] = []
                for decl in declarations {
                    if let d = generateTACKYDeclaration(decl: decl, out: &out) {
                        tackyDecls.append(d)
                    }
                }
                return (.Statement(tackyDecls), generateTACKYSymbolTable(symbolTable: symbolTable))
        }
    }

}