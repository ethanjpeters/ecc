import Foundation

class Tacky {
    struct IR {
        enum UnaryOperator {
            case Complement
            case Negate
            case Not
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

        enum Value {
            case Constant(Int)
            case Var(String)
        }

        enum Instruction {
            case Return(Value)
            case Unary(UnaryOperator, Value/* src */, Value /* dst */)
            case Binary(BinaryOperator, Value /* src1 */, Value /* src2 */, Value /* dst */)
            case Copy(Value /* src */, Value /* dst */)
            case Jump(String /* identifier target */)
            case JumpIfZero(Value /* condition */, String /* identifier target */)
            case JumpIfNotZero(Value /* condition */, String /* identifier target */)
            case Label(String /* identifier */)
        }

        enum Program {
            case Function(String /* identifier */, [Instruction]/* body */)
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
        let out = "\(descriptor)label.\(tempLabelCounter)"
        tempLabelCounter = tempLabelCounter + 1
        return out
    }

    func convert(_ op : Parser.AST.BinaryOperator) -> IR.BinaryOperator {
        switch op {
            case .Add: return .Add
            case .Subtract: return .Subtract
            case .Multiply: return .Multiply
            case .Divide: return .Divide
            case .And: return .And
            case .Or: return .Or
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
        }
    }

    func generateTACKYExpression(_ exp: Parser.AST.Expression, out: inout [Tacky.IR.Instruction]) -> Tacky.IR.Value {

        func generateTACKYOp(_ op: Parser.AST.UnaryOperator) -> Tacky.IR.UnaryOperator {
            switch op {
                case .Complement:
                    return .Complement
                case .Negate:
                    return .Negate
                case .Not:
                    return .Not
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