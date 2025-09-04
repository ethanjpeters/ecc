import Foundation

class Assembly {
    struct Tree {
        enum ConditionCode {
            case E
            case NE
            case G
            case GE
            case L
            case LE
        }

        enum Register {
            case AX
            case CL
            case CX
            case DX
            case R10
            case R11
        }

        enum Operand {
            case Immediate(Int)
            case Register(Register)
            case Pseudo(String)
            case Stack(Int)
        }

        enum UnaryOperator {
            case Neg
            case Not
        }

        enum BinaryOperator {
            case Add
            case Sub
            case Mult
            case And
            case Or
            case Xor
            case Sar
            case Shl
        }

        enum Instruction {
            case Mov(Operand /* src */, Operand /* dst */)
            case Unary(UnaryOperator, Operand)
            case Binary(BinaryOperator, Operand, Operand)
            case Cmp(Operand, Operand)
            case Idiv(Operand)
            case Cdq
            case Jmp(String /* identifier */)
            case JmpCC(ConditionCode, String /* identifier */)
            case SetCC(ConditionCode, Operand)
            case Label(String /* identifier */)
            case AllocateStack(Int)
            case Ret
        }

        enum Program {
            case Function(String, [Instruction])
        }
    }

    func convert(_ val: Tacky.IR.Value) -> Tree.Operand {
        switch val {
            case .Constant(let c):
                return .Immediate(c)
            case .Var(let name):
                return .Pseudo(name)
        }
    }

    func convert(_ op: Tacky.IR.UnaryOperator) -> Tree.UnaryOperator {
        switch op {
            case .Complement:
                return .Not
            case .Negate:
                return .Neg
            default:
                print("Unreachable 3")
                exit(ExitCode.parserError.rawValue)
        }
    }

    func generate(_ instructions: [Tacky.IR.Instruction]) -> [Tree.Instruction] {
        var out : [Tree.Instruction] = []

        for instr in instructions {
            switch instr {
                case .Return(let val):
                    out.append(.Mov(convert(val), .Register(.AX)))
                    out.append(.Ret)
                case .Unary(let op, let src, let dst):
                    if op == .Not {
                        out.append(.Cmp(.Immediate(0), convert(src)))
                        out.append(.Mov(.Immediate(0), convert(dst)))
                        out.append(.SetCC(.E, convert(dst)))
                    } else {
                        out.append(.Mov(convert(src), convert(dst)))
                        out.append(.Unary(convert(op), convert(dst)))
                    }
                case .Binary(let op, let src1, let src2, let dst):
                    switch op {
                        case .Add:
                            out.append(.Mov(convert(src1), convert(dst)))
                            out.append(.Binary(.Add, convert(src2), convert(dst)))
                        case .Subtract:
                            out.append(.Mov(convert(src1), convert(dst)))
                            out.append(.Binary(.Sub, convert(src2), convert(dst)))
                        case .Multiply:
                            out.append(.Mov(convert(src1), convert(dst)))
                            out.append(.Binary(.Mult, convert(src2), convert(dst)))
                        case .Divide:
                            out.append(.Mov(convert(src1), .Register(.AX)))
                            out.append(.Cdq)
                            out.append(.Idiv(convert(src2)))
                            out.append(.Mov(.Register(.AX), convert(dst)))
                        case .Remainder:
                            out.append(.Mov(convert(src1), .Register(.AX)))
                            out.append(.Cdq)
                            out.append(.Idiv(convert(src2)))
                            out.append(.Mov(.Register(.DX), convert(dst)))
                        case .Equal:
                            out.append(.Cmp(convert(src2), convert(src1)))
                            out.append(.Mov(.Immediate(0), convert(dst)))
                            out.append(.SetCC(.E, convert(dst)))
                        case .NotEqual:
                            out.append(.Cmp(convert(src2), convert(src1)))
                            out.append(.Mov(.Immediate(0), convert(dst)))
                            out.append(.SetCC(.NE, convert(dst)))
                        case .LessThan:
                            out.append(.Cmp(convert(src2), convert(src1)))
                            out.append(.Mov(.Immediate(0), convert(dst)))
                            out.append(.SetCC(.L, convert(dst)))
                        case .LessOrEqual:
                            out.append(.Cmp(convert(src2), convert(src1)))
                            out.append(.Mov(.Immediate(0), convert(dst)))
                            out.append(.SetCC(.LE, convert(dst)))
                        case .GreaterThan: 
                            out.append(.Cmp(convert(src2), convert(src1)))
                            out.append(.Mov(.Immediate(0), convert(dst)))
                            out.append(.SetCC(.G, convert(dst)))
                        case .GreaterOrEqual:
                            out.append(.Cmp(convert(src2), convert(src1)))
                            out.append(.Mov(.Immediate(0), convert(dst)))
                            out.append(.SetCC(.GE, convert(dst)))
                        case .BitwiseAnd:
                            out.append(.Mov(convert(src1), convert(dst)))
                            out.append(.Binary(.And, convert(src2), convert(dst)))
                        case .BitwiseOr:
                            out.append(.Mov(convert(src1), convert(dst)))
                            out.append(.Binary(.Or, convert(src2), convert(dst)))
                        case .BitwiseXor:
                            out.append(.Mov(convert(src1), convert(dst)))
                            out.append(.Binary(.Xor, convert(src2), convert(dst)))
                        case .BitwiseShiftRight:
                            out.append(.Mov(convert(src1), convert(dst)))
                            out.append(.Binary(.Sar, convert(src2), convert(dst)))
                        case .BitwiseShiftLeft:
                            out.append(.Mov(convert(src1), convert(dst)))
                            out.append(.Binary(.Shl, convert(src2), convert(dst)))
                    }
                case .Copy(let src, let dst):
                    out.append(.Mov(convert(src), convert(dst)))
                case .Jump(let label):
                    out.append(.Jmp(label))
                case .JumpIfZero(let val, let label):
                    out.append(.Cmp(.Immediate(0), convert(val)))
                    out.append(.JmpCC(.E, label))
                case .JumpIfNotZero(let val, let label):
                    out.append(.Cmp(.Immediate(0), convert(val)))
                    out.append(.JmpCC(.NE, label))
                case .Label(let name):
                    out.append(.Label(name))
            }
        }

        return out
    }

    func generate(program: Tacky.IR.Program) -> Tree.Program {
        switch program {
            case .Function(let name, let instrs):
                return .Function(name, generate(instrs))
        }
    }

    func replacePseudoRegisters(_ op: Tree.Operand, _ stackSlotCounter: inout Int, _ nameStackMapping: inout [String: Int]) -> Tree.Operand {
        switch op {
            case .Immediate(_):
                return op
            case .Register(_):
                return op
            case .Pseudo(let name):
                if let slot = nameStackMapping[name] {
                    return .Stack((slot+1) * -4)
                }
                let tmp = stackSlotCounter
                stackSlotCounter = stackSlotCounter + 1
                nameStackMapping[name] = tmp
                return .Stack((tmp+1) * -4)
            case .Stack(_):
                return op
        }
    }

    func replacePseudoRegisters(_ instructions: [Tree.Instruction]) -> [Tree.Instruction] {
        var out : [Tree.Instruction] = []

        var stackSlotCounter : Int = 0
        var nameStackMapping : [String: Int] = [:]

        for instr: Assembly.Tree.Instruction in instructions {
            switch instr {
                case .AllocateStack(_):
                    out.append(instr)
                case .Mov(let op1, let op2):
                    out.append(.Mov(replacePseudoRegisters(op1, &stackSlotCounter, &nameStackMapping),
                                    replacePseudoRegisters(op2, &stackSlotCounter, &nameStackMapping)))
                case .Ret:
                    out.append(instr)
                case .Unary(let unOp, let op):
                    out.append(.Unary(unOp, replacePseudoRegisters(op, &stackSlotCounter, &nameStackMapping)))
                case .Binary(let binOp, let left, let right):
                    out.append(.Binary(binOp, replacePseudoRegisters(left, &stackSlotCounter, &nameStackMapping), replacePseudoRegisters(right, &stackSlotCounter, &nameStackMapping)))
                case .Cdq: out.append(.Cdq)
                case .Idiv(let op): out.append(.Idiv(replacePseudoRegisters(op, &stackSlotCounter, &nameStackMapping)))
                case .Cmp(let left, let right):
                    out.append(.Cmp(replacePseudoRegisters(left, &stackSlotCounter, &nameStackMapping),
                                    replacePseudoRegisters(right, &stackSlotCounter, &nameStackMapping)))
                case .Jmp(_): out.append(instr)
                case .JmpCC(_, _): out.append(instr)
                case .SetCC(_, _): out.append(instr)
                case .Label(_): out.append(instr)
            }
        }

        out.insert(.AllocateStack(stackSlotCounter * 4), at: 0)

        return out
    }

    func replacePseudoRegisters(program: Tree.Program) -> Tree.Program {
        switch program {
            case .Function(let name, let instrs):
                return .Function(name, replacePseudoRegisters(instrs))
        }
    }

    func fixUpMoves(_ instrs: [Tree.Instruction]) -> [Tree.Instruction] {
        var out : [Tree.Instruction] = []
        for instr in instrs {
            switch instr {
                case .AllocateStack(_): out.append(instr)
                case .Mov(let opSrc, let opDst):
                    switch opSrc {
                        case .Stack(let srcSlot):
                            switch opDst {
                                case .Stack(let dstSlot):
                                    out.append(.Mov(.Stack(srcSlot), .Register(.R10)))
                                    out.append(.Mov(.Register(.R10), .Stack(dstSlot)))
                                default:
                                    out.append(instr)
                            }
                        default:
                            out.append(instr)
                    }
                case .Ret: out.append(instr)
                case .Unary(_, _): out.append(instr)
                case .Binary(let op, let src, let dst):
                    switch op {
                        case .Add: fallthrough
                        case .Sub: fallthrough
                        case .And:
                            switch src {
                                case .Stack(let srcSlot):
                                switch dst {
                                    case .Stack(let dstSlot):
                                        out.append(.Mov(.Stack(srcSlot), .Register(.R10)))
                                        out.append(.Binary(op, .Register(.R10), .Stack(dstSlot)))
                                    default: out.append(instr)
                                }
                                default: out.append(instr)
                            }
                        case .Mult: fallthrough
                        case .Or: fallthrough
                        case .Xor:
                            switch dst {
                                case .Stack(let val):
                                    out.append(.Mov(.Stack(val), .Register(.R11)))
                                    out.append(.Binary(op, src, .Register(.R11)))
                                    out.append(.Mov(.Register(.R11), .Stack(val)))
                                default:
                                    out.append(instr)
                            }
                        case .Sar: fallthrough
                        case .Shl:
                            switch src {
                                case .Stack(let val):
                                    // move the value off of the stack and into CL, which is currently never used otherwise
                                    // and is in no danger of being overwritten
                                    out.append(.Mov(.Stack(val), .Register(.CX)))
                                    out.append(.Binary(op, .Register(.CL), dst))
                                default:
                                    out.append(instr)
                            }
                    }
                case .Cdq: out.append(instr)
                case .Idiv(let op):
                    switch op {
                        case .Immediate(let val):
                            out.append(.Mov(.Immediate(val), .Register(.R10)))
                            out.append(.Idiv(.Register(.R10)))
                        default: out.append(instr)
                    }
                case .Cmp(let left, let right):
                    switch left {
                        case .Stack(let srcSlot):
                            switch right {
                                case .Stack(_):
                                    out.append(.Mov(.Stack(srcSlot), .Register(.R10)))
                                    out.append(.Cmp(.Register(.R10), right))
                                case .Immediate(_):
                                    out.append(.Mov(right, .Register(.R11)))
                                    out.append(.Cmp(left, .Register(.R11)))
                                default:
                                    out.append(instr)
                            }
                        default:
                            out.append(instr)
                    }
                case .Jmp(_): out.append(instr)
                case .JmpCC(_, _): out.append(instr)
                case .SetCC(_, _): out.append(instr)
                case .Label(_): out.append(instr)
            }
        }
        return out
    }

    func fixUpMoves(program: Tree.Program) -> Tree.Program {
        switch program {
            case .Function(let name, let instrs):
                return .Function(name, fixUpMoves(instrs))
        }
    }
}