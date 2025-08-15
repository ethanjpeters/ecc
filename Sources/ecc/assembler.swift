import Foundation

class Assembly {
    struct Tree {
        enum Register {
            case AX
            case R10
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

        enum Instruction {
            case Mov(Operand /* src */, Operand /* dst */)
            case Unary(UnaryOperator, Operand)
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
                    out.append(.Mov(convert(src), convert(dst)))
                    out.append(.Unary(convert(op), convert(dst)))
                case .Binary(let op, let src1, let src2, let dst):
                    print("Can not handle binary expressions yet")
                    exit(ExitCode.parserError.rawValue)
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