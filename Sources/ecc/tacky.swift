import Foundation

class Tacky {
    struct IR {
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
        }

        enum Value {
            case Constant(Int)
            case Var(String)
        }

        enum Instruction {
            case Return(Value)
            case Unary(UnaryOperator, Value/* src */, Value /* dst */)
            case Binary(BinaryOperator, Value /* src1 */, Value /* src2 */, Value /* dst */)
        }

        enum Program {
            case Function(String /* identifier */, [Instruction]/* body */)
        }
    }

    private var tempNameCounter : Int = 0

    func makeTemp() -> String {
        let out = "tmp\(tempNameCounter)"
        tempNameCounter = tempNameCounter + 1
        return out
    }

    func generateTACKYExpression(_ exp: Parser.AST.Expression, out: inout [Tacky.IR.Instruction]) -> Tacky.IR.Value {

        func generateTACKYOp(_ op: Parser.AST.UnaryOperator) -> Tacky.IR.UnaryOperator {
            switch op {
                case .Complement:
                    return .Complement
                case .Negate:
                    return .Negate
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
                let v1 = generateTACKYExpression(left, out: &out)
                let v2  = generateTACKYExpression(right, out: &out)
                let dstName = makeTemp()
                let dst : IR.Value = .Var(dstName)
                let tackyOp : IR.BinaryOperator
                switch op {
                    case .Add: tackyOp = .Add
                    case .Subtract: tackyOp = .Subtract
                    case .Multiply: tackyOp = .Multiply
                    case .Divide: tackyOp = .Divide
                    case .Remainder: tackyOp = .Remainder
                }
                out.append(.Binary(tackyOp, v1, v2, dst))
                return dst
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