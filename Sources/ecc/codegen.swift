import Foundation

enum RegisterWidth {
    case oneByte
    case twoByte
    case fourByte
    case eightByte
}

func typeToWidth(_ tp: Assembly.Tree.AssemblyType) -> RegisterWidth {
    switch tp {
        case .Longword: return .fourByte
        case .Quadword: return .eightByte
        case .Double: return .eightByte
    }
}

func convert(_ operand: Assembly.Tree.Operand, _ width: RegisterWidth = .fourByte) -> String {
    switch operand {
        case .Immediate(let val):
            return "$\(val)"
        case .Pseudo(let name):
            print("Encountered Pseudo way late in the pipeline: \(name)")
            exit(ExitCode.internalError.rawValue)
        case .Register(let reg):
            switch reg {
                case .AX:
                    switch width {
                        case .oneByte: return "%al"
                        case .twoByte: return "%ax"
                        case .fourByte: return "%eax"
                        case .eightByte: return "%rax"
                    }
                case .DX:
                    switch width {
                        case .oneByte: return "%dl"
                        case .twoByte: return "%dx"
                        case .fourByte: return "%edx"
                        case .eightByte: return "%rdx"
                    }
                case .CL:
                    return "%cl"
                case .CX:
                    switch width {
                        case .oneByte: return "%cl"
                        case .twoByte: return "%cx"
                        case .fourByte: return "%ecx"
                        case .eightByte: return "%rcx"
                    }
                case .R8:
                    switch width {
                        case .oneByte: return "%r8b"
                        case .twoByte: return "%r8w"
                        case .fourByte: return "%r8d"
                        case .eightByte: return "%r8"
                    }
                case .R9:
                    switch width {
                        case .oneByte: return "%r9b"
                        case .twoByte: return "%r9w"
                        case .fourByte: return "%r9d"
                        case .eightByte: return "%r9"
                    }
                case .R10:
                    switch width {
                        case .oneByte: return "%r10b"
                        case .twoByte: return "%r10w"
                        case .fourByte: return "%r10d"
                        case .eightByte: return "%r10"
                    }
                case .R11:
                    switch width {
                        case .oneByte: return "%r11b"
                        case .twoByte: return "%r11w"
                        case .fourByte: return "%r11d"
                        case .eightByte: return "%r11"
                    }
                case .DI:
                    switch width {
                        case .oneByte:
                            print("No oneByte option for register rdi/edi/di")
                            exit(ExitCode.internalError.rawValue)
                        case .twoByte: return "%di"
                        case .fourByte: return "%edi"
                        case .eightByte: return "%rdi"
                    }
                case .SI:
                    switch width {
                        case .oneByte:
                            print("No oneByte option for register rsi/esi/si")
                            exit(ExitCode.internalError.rawValue)
                        case .twoByte: return "%si"
                        case .fourByte: return "%esi"
                        case .eightByte: return "%rsi"
                    }
                case .XMM0: fallthrough
                case .XMM1: fallthrough
                case .XMM2: fallthrough
                case .XMM3: fallthrough
                case .XMM4: fallthrough
                case .XMM5: fallthrough
                case .XMM6: fallthrough
                case .XMM7: fallthrough
                case .XMM14: fallthrough
                case .XMM15:
                    print("As-yet-unhandled floating point register encountered while generating code")
                    exit(ExitCode.internalError.rawValue)
            }
        case .Stack(let slot):
            return "\(slot)(%rbp)"
        case .Data(let name):
            return "\(name)(%rip)"
    }
}

func convert(_ op: Assembly.Tree.UnaryOperator, _ tp: Assembly.Tree.AssemblyType) -> String {
    switch op {
        case .Neg:
            return "neg\(typeToSuffix(tp))"
        case .Not:
            return "not\(typeToSuffix(tp))"
        case .Shr:
            return "shr\(typeToSuffix(tp))"
    }
}

func convert(_ op: Assembly.Tree.BinaryOperator, _ tp: Assembly.Tree.AssemblyType) -> String {
    switch op {
        case .Add:
            return "add\(typeToSuffix(tp))"
        case .Sub:
            return "sub\(typeToSuffix(tp))"
        case .Mult:
            return "imul\(typeToSuffix(tp))"
        case .And:
            return "and\(typeToSuffix(tp))"
        case .Or:
            return "or\(typeToSuffix(tp))"
        case .Xor:
            return "xor\(typeToSuffix(tp, isPacked: true))"
        case .Sar:
            return "sar\(typeToSuffix(tp))"
        case .Shl:
            return "shl\(typeToSuffix(tp))"
        case .DivDouble:
            print("As-yet-unhandled floating point division found while generating code")
            exit(ExitCode.internalError.rawValue)
    }
}

func convert(_ cc: Assembly.Tree.ConditionCode) -> String {
    switch cc {
        case .E: return "e"
        case .NE: return "ne"
        case .G: return "g"
        case .GE: return "ge"
        case .L: return "l"
        case .LE: return "le"
        case .A: return "a"
        case .AE: return "ae"
        case .B: return "b"
        case .BE: return "be"
    }
}

func makeFunctionName(_ name : String) -> String {
    // macOS-only for now
    return "_\(name)"
}

func typeToSuffix(_ tp : Assembly.Tree.AssemblyType, isPacked : Bool = false) -> String {
    switch tp {
        case .Longword: return "l"
        case .Quadword: return "q"
        case .Double: return isPacked ? "pd" : "sd"
    }
}

func emitInstructions(_ instructions: [Assembly.Tree.Instruction], out: inout [String]) {
    for instr in instructions {
        switch instr {
            case .AllocateStack(let count):
                if count != 0 { out.append("\tsubq\t$\(count), %rsp") }
            case .Mov(let tp, let opSrc, let opDst):
                out.append("\tmov\(typeToSuffix(tp))\t\(convert(opSrc, typeToWidth(tp))), \(convert(opDst, typeToWidth(tp)))")
            case .Ret:
                out.append("\tmovq\t%rbp, %rsp")
                out.append("\tpopq\t%rbp")
                out.append("\tret")
            case .Unary(let unOp, let tp, let op):
                out.append("\t\(convert(unOp, tp))\t\(convert(op, typeToWidth(tp)))")
            case .Binary(let binOp, let tp, let leftOperand, let rightOperand):
                out.append("\t\(convert(binOp, tp))\t\(convert(leftOperand, typeToWidth(tp))), \(convert(rightOperand, typeToWidth(tp)))")
            case .Cdq(let tp):
                if tp == .Longword {
                    out.append("\tcdq")
                } else {
                    out.append("\tcqo")
                }
            case .Idiv(let tp, let op):
                out.append("\tidiv\(typeToSuffix(tp))\t\(convert(op, typeToWidth(tp)))")
            case .Div(let tp, let op):
                out.append("\tdiv\(typeToSuffix(tp))\t\(convert(op, typeToWidth(tp)))")
            case .Cmp(let tp, let left, let right):
                out.append("\tcmp\(typeToSuffix(tp))\t\(convert(left, typeToWidth(tp))), \(convert(right, typeToWidth(tp)))")
            case .Jmp(let label):
                out.append("\tjmp\t\(label)")
            case .JmpCC(let cc, let label):
                out.append("\tj\(convert(cc))\t\(label)")
            case .SetCC(let cc, let op):
                out.append("\tset\(convert(cc))\t\(convert(op, .oneByte))")
            case .Label(let name):
                out.append("\(name):")
            case .DeallocateStack(let count):
                if count != 0 { out.append("\taddq\t$\(count), %rsp")}
            case .Push(let operand):
                out.append("\tpushq\t\(convert(operand))")
            case .Call(let fName):
                out.append("\tcall\t\(makeFunctionName(fName))")
            case .Movsx(let src, let dst):
                out.append("\tmovslq\t\(convert(src, .fourByte)), \(convert(dst, .eightByte))")
            case .Movzx(_, _):
                print("Unreachable movzx survived assembly fixup")
                exit(ExitCode.internalError.rawValue)
            case .Cvttsd2dsi(_, _, _): fallthrough
            case .Cvtsi2sd(_, _, _):
                print("As-yet-unhandled floating point conversion found while emitting instructions")
                exit(ExitCode.internalError.rawValue)
        }
    }
}

func emitProgramLevelStatement(_ pls: Assembly.Tree.Declaration, out: inout [String]) {
    switch pls {
        case .Function(let name, let isGlobal, let instrs):
            let fName = makeFunctionName(name)
            if isGlobal {
                out.append("\t.global \(fName)")
            }
            out.append("\t.text")
            out.append("\(fName):")
            out.append("\tpushq\t%rbp")
            out.append("\tmovq\t%rsp, %rbp")
            emitInstructions(instrs, out: &out)
            out.append("\n\n")
        case .StaticVariable(let name, let isGlobal, let alignment, let initVal):
            if isGlobal {
                out.append("\t.globl \(name)")
            }
            out.append("\t.data")
            out.append("\t.balign\t\(alignment)")
            out.append("\(name):")
            switch initVal {
                case .IntInit(let i): out.append("\t.long\t\(i)")
                case .LongInit(let i): out.append("\t.quad\t\(i)")
                case .UIntInit(let i): out.append("\t.long\t\(i)")
                case .ULongInit(let i): out.append("\t.quad\t\(i)")
                case .DoubleInit(let f):
                    print("As-yet-unhandled floating point initializer found while emitting program level statement")
                    exit(ExitCode.internalError.rawValue)
            }
        case .StaticConstant(_, _, _):
            print("As-yet=unhandled static constant found while emitting program level statement")
            exit(ExitCode.internalError.rawValue)
    }
}

func emitProgram(program: Assembly.Tree.Program) -> [String] {
    var out : [String] = []

    switch program {
        case .Statement(let declarations):
            for decl in declarations {
                emitProgramLevelStatement(decl, out: &out)
            }
    }

    return out
}