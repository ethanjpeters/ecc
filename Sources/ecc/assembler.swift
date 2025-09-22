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
            case DI
            case SI
            case R8
            case R9
            case R10
            case R11
        }

        enum Operand {
            case Immediate(Int)
            case Register(Register)
            case Pseudo(String)
            case Stack(Int)
            case Data(String /* identifier */)
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
            case DeallocateStack(Int)
            case Push(Operand)
            case Call(String /* identifier */)
            case Ret
        }

        enum Declaration {
            case Function(String, Bool /* is global */, [Instruction])
            case StaticVariable(String /* name */, Bool /* is global */, Int /* initial value */)
        }

        enum Program {
            case Statement([Declaration])
        }
    }

    func convert(_ val: Tacky.IR.Value, _ symbolTable: [String : Assembly.Tree.Declaration]) -> Tree.Operand {
        switch val {
            case .Constant(let c):
                return .Immediate(c)
            case .Var(let name):
                if let _ = symbolTable[name] {
                    return .Data(name)
                }
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
                exit(ExitCode.internalError.rawValue)
        }
    }

    func generate(_ instructions: [Tacky.IR.Instruction], _ symbolTable: [String : Assembly.Tree.Declaration], _ out: inout [Tree.Instruction]) {
        for instr in instructions {
            switch instr {
                case .Return(let val):
                    let v : Tacky.IR.Value = (val == nil ? .Constant(0) : val!)
                    out.append(.Mov(convert(v, symbolTable), .Register(.AX)))
                    out.append(.Ret)
                case .Unary(let op, let src, let dst):
                    if op == .Not {
                        out.append(.Cmp(.Immediate(0), convert(src, symbolTable)))
                        out.append(.Mov(.Immediate(0), convert(dst, symbolTable)))
                        out.append(.SetCC(.E, convert(dst, symbolTable)))
                    } else {
                        out.append(.Mov(convert(src, symbolTable), convert(dst, symbolTable)))
                        out.append(.Unary(convert(op), convert(dst, symbolTable)))
                    }
                case .Binary(let op, let src1, let src2, let dst):
                    let src1Conv = convert(src1, symbolTable)
                    let src2Conv = convert(src2, symbolTable)
                    let dstConv = convert(dst, symbolTable)
                    switch op {
                        case .Add:
                            out.append(.Mov(src1Conv, dstConv))
                            out.append(.Binary(.Add, src2Conv, dstConv))
                        case .Subtract:
                            out.append(.Mov(src1Conv, dstConv))
                            out.append(.Binary(.Sub, src2Conv, dstConv))
                        case .Multiply:
                            out.append(.Mov(src1Conv, dstConv))
                            out.append(.Binary(.Mult, src2Conv, dstConv))
                        case .Divide:
                            out.append(.Mov(src1Conv, .Register(.AX)))
                            out.append(.Cdq)
                            out.append(.Idiv(src2Conv))
                            out.append(.Mov(.Register(.AX), dstConv))
                        case .Remainder:
                            out.append(.Mov(src1Conv, .Register(.AX)))
                            out.append(.Cdq)
                            out.append(.Idiv(src2Conv))
                            out.append(.Mov(.Register(.DX), dstConv))
                        case .Equal:
                            out.append(.Cmp(src2Conv, src1Conv))
                            out.append(.Mov(.Immediate(0), dstConv))
                            out.append(.SetCC(.E, dstConv))
                        case .NotEqual:
                            out.append(.Cmp(src2Conv, src1Conv))
                            out.append(.Mov(.Immediate(0), dstConv))
                            out.append(.SetCC(.NE, dstConv))
                        case .LessThan:
                            out.append(.Cmp(src2Conv, src1Conv))
                            out.append(.Mov(.Immediate(0), dstConv))
                            out.append(.SetCC(.L, dstConv))
                        case .LessOrEqual:
                            out.append(.Cmp(src2Conv, src1Conv))
                            out.append(.Mov(.Immediate(0), dstConv))
                            out.append(.SetCC(.LE, dstConv))
                        case .GreaterThan: 
                            out.append(.Cmp(src2Conv, src1Conv))
                            out.append(.Mov(.Immediate(0), dstConv))
                            out.append(.SetCC(.G, dstConv))
                        case .GreaterOrEqual:
                            out.append(.Cmp(src2Conv, src1Conv))
                            out.append(.Mov(.Immediate(0), dstConv))
                            out.append(.SetCC(.GE, dstConv))
                        case .BitwiseAnd:
                            out.append(.Mov(src1Conv, dstConv))
                            out.append(.Binary(.And, src2Conv, dstConv))
                        case .BitwiseOr:
                            out.append(.Mov(src1Conv, dstConv))
                            out.append(.Binary(.Or, src2Conv, dstConv))
                        case .BitwiseXor:
                            out.append(.Mov(src1Conv, dstConv))
                            out.append(.Binary(.Xor, src2Conv, dstConv))
                        case .BitwiseShiftRight:
                            out.append(.Mov(src1Conv, dstConv))
                            out.append(.Binary(.Sar, src2Conv, dstConv))
                        case .BitwiseShiftLeft:
                            out.append(.Mov(src1Conv, dstConv))
                            out.append(.Binary(.Shl, src2Conv, dstConv))
                    }
                case .Copy(let src, let dst):
                    out.append(.Mov(convert(src, symbolTable), convert(dst, symbolTable)))
                case .Jump(let label):
                    out.append(.Jmp(label))
                case .JumpIfZero(let val, let label):
                    out.append(.Cmp(.Immediate(0), convert(val, symbolTable)))
                    out.append(.JmpCC(.E, label))
                case .JumpIfNotZero(let val, let label):
                    out.append(.Cmp(.Immediate(0), convert(val, symbolTable)))
                    out.append(.JmpCC(.NE, label))
                case .Label(let name):
                    out.append(.Label(name))
                case .Call(let name, let params, let result):
                    // save context (currently not an issue because we only use scratch registers)
                    // move parameters into place
                    var copiedParams = params
                    if !copiedParams.isEmpty {
                        let p = copiedParams.removeFirst()
                        out.append(.Mov(convert(p, symbolTable), .Register(.DI)))
                    }
                    if !copiedParams.isEmpty {
                        let p = copiedParams.removeFirst()
                        out.append(.Mov(convert(p, symbolTable), .Register(.SI)))
                    }
                    if !copiedParams.isEmpty {
                        let p = copiedParams.removeFirst()
                        out.append(.Mov(convert(p, symbolTable), .Register(.CX)))
                    }
                    if !copiedParams.isEmpty {
                        let p = copiedParams.removeFirst()
                        out.append(.Mov(convert(p, symbolTable), .Register(.R8)))
                    }
                    if !copiedParams.isEmpty {
                        let p = copiedParams.removeFirst()
                        out.append(.Mov(convert(p, symbolTable), .Register(.R9)))
                    }

                    // the System V ABI requires the stack to be 16-byte aligned
                    let stackPadding = copiedParams.count % 2 == 0 ? 0 : 8

                    if stackPadding != 0 {
                        out.append(.AllocateStack(stackPadding))
                    }

                    copiedParams.reverse()
                    for p in copiedParams {
                        let src = convert(p, symbolTable)
                        switch src {
                            case .Register(_): fallthrough
                            case .Immediate(_):
                                out.append(.Push(src))
                            default:
                                out.append(.Mov(src, .Register(.AX)))
                                out.append(.Push(.Register(.AX)))
                        }
                    }
                    // call the function
                    out.append(.Call(name))

                    let bytesToRemove = 8 * copiedParams.count + stackPadding
                    if bytesToRemove != 0 {
                        out.append(.DeallocateStack(bytesToRemove))
                    }

                    // move the result
                    out.append(.Mov(.Register(.AX), convert(result, symbolTable)))
            }
        }
    }

    func generate(_ pls: Tacky.IR.Declaration, _ symbolTable: [String : Assembly.Tree.Declaration]) -> Tree.Declaration {
        switch pls {
            case .Function(let name, let isGlobal, let params, let instrs):
                var out : [Tree.Instruction] = []
                var copiedParams = params
                if !copiedParams.isEmpty {
                    let p = copiedParams.removeFirst()
                    out.append(.Mov(.Register(.DI), .Pseudo(p)))
                }
                if !copiedParams.isEmpty {
                    let p = copiedParams.removeFirst()
                    out.append(.Mov(.Register(.SI), .Pseudo(p)))
                }
                if !copiedParams.isEmpty {
                    let p = copiedParams.removeFirst()
                    out.append(.Mov(.Register(.CX), .Pseudo(p)))
                }
                if !copiedParams.isEmpty {
                    let p = copiedParams.removeFirst()
                    out.append(.Mov(.Register(.R8), .Pseudo(p)))
                }
                if !copiedParams.isEmpty {
                    let p = copiedParams.removeFirst()
                    out.append(.Mov(.Register(.R9), .Pseudo(p)))
                }
                copiedParams.reverse()
                var counter = 0
                for p in copiedParams {
                    out.append(.Mov(.Stack(16 + counter), .Pseudo(p)))
                    counter = counter + 8
                }
                generate(instrs, symbolTable, &out)
                return .Function(name, isGlobal, out)
            case .StaticVariable(_, _, _):
                print("As yet unhandled global variable caught while generating assembly")
                exit(ExitCode.internalError.rawValue)
        }
    }

    func generate(program: Tacky.IR.Program, symbolTable: [Tacky.IR.Declaration]) -> Tree.Program {
        var assemblyDecls : [Assembly.Tree.Declaration] = []
        var internalSymbolTable : [String : Assembly.Tree.Declaration] = [:]
        for tackyDef in symbolTable {
            switch tackyDef {
                case .StaticVariable(let name, let isGlobal, let initValue):
                    let assemblyEntry : Tree.Declaration = .StaticVariable(name, isGlobal, initValue)
                    assemblyDecls.append(assemblyEntry)
                    internalSymbolTable[name] = assemblyEntry
                default: ()
            }
        }
        switch program {
            case .Statement(let declarations):
                for d in declarations {
                    assemblyDecls.append(generate(d, internalSymbolTable))
                }
                return .Statement(assemblyDecls)
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
            case .Data(_):
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
                case .SetCC(let cc, let op):
                    out.append(.SetCC(cc, replacePseudoRegisters(op, &stackSlotCounter, &nameStackMapping)))
                case .Label(_): out.append(instr)
                case .Call(_): out.append(instr)
                case .DeallocateStack(_): out.append(instr)
                case .Push(let op):
                    out.append(.Push(replacePseudoRegisters(op, &stackSlotCounter, &nameStackMapping)))
            }
        }

        out.insert(.AllocateStack(stackSlotCounter * 4), at: 0)

        return out
    }

    func replacePseudoRegisters(_ pls: Tree.Declaration) -> Tree.Declaration {
        switch pls {
            case .Function(let name, let isGlobal, let instrs):
                return .Function(name, isGlobal, replacePseudoRegisters(instrs))
            case .StaticVariable(let name, let isGlobal, let initVal):
                return .StaticVariable(name, isGlobal, initVal)
        }
    }

    func replacePseudoRegisters(program: Tree.Program) -> Tree.Program {
        switch program {
            case .Statement(let declarations):
                return .Statement(declarations.map{ replacePseudoRegisters($0) })
        }
    }

    func fixUpMoves(_ instrs: [Tree.Instruction]) -> [Tree.Instruction] {
        var out : [Tree.Instruction] = []
        for instr in instrs {
            switch instr {
                case .AllocateStack(_): out.append(instr)
                case .Mov(let opSrc, let opDst):
                    switch opSrc {
                        case .Stack(_): fallthrough
                        case .Data(_):
                            switch opDst {
                                case .Stack(_): fallthrough
                                case .Data(_):
                                    out.append(.Mov(opSrc, .Register(.R10)))
                                    out.append(.Mov(.Register(.R10), opDst))
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
                                case .Data(_): fallthrough
                                case .Stack(_):
                                switch dst {
                                    case .Data(_): fallthrough
                                    case .Stack(_):
                                        out.append(.Mov(src, .Register(.R10)))
                                        out.append(.Binary(op, .Register(.R10), dst))
                                    default: out.append(instr)
                                }
                                default: out.append(instr)
                            }
                        case .Mult: fallthrough
                        case .Or: fallthrough
                        case .Xor:
                            switch dst {
                                case .Data(_): fallthrough
                                case .Stack(_):
                                    out.append(.Mov(dst, .Register(.R11)))
                                    out.append(.Binary(op, src, .Register(.R11)))
                                    out.append(.Mov(.Register(.R11), dst))
                                default:
                                    out.append(instr)
                            }
                        case .Sar: fallthrough
                        case .Shl:
                            switch src {
                                case .Data(_): fallthrough
                                case .Stack(_):
                                    // move the value off of the stack and into CL, which is currently never used otherwise
                                    // and is in no danger of being overwritten
                                    out.append(.Mov(src, .Register(.CX)))
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
                        case .Data(_): fallthrough
                        case .Stack(_):
                            switch right {
                                case .Data(_): fallthrough
                                case .Stack(_):
                                    out.append(.Mov(left, .Register(.R10)))
                                    out.append(.Cmp(.Register(.R10), right))
                                case .Immediate(_):
                                    out.append(.Mov(right, .Register(.R11)))
                                    out.append(.Cmp(left, .Register(.R11)))
                                default:
                                    out.append(instr)
                            }
                        default:
                            switch right {
                                case .Immediate(_):
                                    out.append(.Mov(right, .Register(.R11)))
                                    out.append(.Cmp(left, .Register(.R11)))
                                default:
                                    out.append(instr)
                            }
                    }
                case .Jmp(_): out.append(instr)
                case .JmpCC(_, _): out.append(instr)
                case .SetCC(_, _): out.append(instr)
                case .Label(_): out.append(instr)
                case .Call(_): out.append(instr)
                case .DeallocateStack(_): out.append(instr)
                case .Push(_): out.append(instr)
            }
        }
        return out
    }

    func fixUpMoves(_ pls: Tree.Declaration) -> Tree.Declaration {
        switch pls {
            case .Function(let name, let isGlobal, let instrs):
                return .Function(name, isGlobal, fixUpMoves(instrs))
            case .StaticVariable(_, _, _):
                return pls
        }
    }

    func fixUpMoves(program: Tree.Program) -> Tree.Program {
        switch program {
            case .Statement(let declarations):
                return .Statement(declarations.map { fixUpMoves($0) })
        }
    }
}