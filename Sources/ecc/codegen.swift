import Foundation

enum RegisterWidth {
    case oneByte
    case twoByte
    case fourByte
    case eightByte
}

func typeToWidth(_ tp: Assembly.Tree.AssemblyType) -> RegisterWidth {
    switch tp {
        case .Byte: return .oneByte
        case .Longword: return .fourByte
        case .Quadword: return .eightByte
        case .Double: return .eightByte
        case .ByteArray(_, _):
            print("Getting byte array width may not make sense")
            exit(ExitCode.internalError.rawValue)
    }
}

func convert(_ operand: Assembly.Tree.Operand, _ width: RegisterWidth = .fourByte) -> String {
    switch operand {
        case .Immediate(let val):
            switch val {
                case .SignedImmediate(let i64): return "$\(i64)"
                case .UnsignedImmediate(let u64): return "$\(u64)"
            }
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
                case .BP:
                    switch width {
                        case .oneByte: fallthrough
                        case .twoByte:
                            print("Invalid access of base pointer with width \(width)")
                            exit(ExitCode.internalError.rawValue)
                        case .fourByte: return "%ebp"
                        case .eightByte: return "%rbp"
                    }
                case .SP:
                    switch width {
                        case .eightByte: return "%rsp"
                        default:
                            print("Invalid op: trying to adjust stack pointer but not with quadword value")
                            exit(ExitCode.internalError.rawValue)
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
                case .XMM0: return "%xmm0"
                case .XMM1: return "%xmm1"
                case .XMM2: return "%xmm2"
                case .XMM3: return "%xmm3"
                case .XMM4: return "%xmm4"
                case .XMM5: return "%xmm5"
                case .XMM6: return "%xmm6"
                case .XMM7: return "%xmm7"
                case .XMM14: return "%xmm14"
                case .XMM15: return "%xmm15 "
            }
        case .Stack(let slot):
            return "\(slot)(%rbp)"
        case .Data(let name, let offset):
            if offset == 0 {
                return "\(name)(%rip)"
            } else {
                return "\(name)+\(offset)(%rip)"
            }
        case .Memory(let reg, let off):
            let prefix = off == 0 ? "" : "\(off)"
            return "\(prefix)(\(convert(.Register(reg), .eightByte)))"
        case .PseudoMem(let name, _):
            print("Encountered pseudo mem \(name) way late in the pipeline")
            exit(ExitCode.internalError.rawValue)
        case .Indexed(let base, let index, let scale):
            return "(\(convert(.Register(base), width)), \(convert(.Register(index), width)), \(scale))"
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
        case .Shr:
            return "shr\(typeToSuffix(tp))"
        case .DivDouble:
            return "div\(typeToSuffix(tp))"
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
        case .Byte: return "b"
        case .Longword: return "l"
        case .Quadword: return "q"
        case .Double: return isPacked ? "pd" : "sd"
        case .ByteArray(_, _):
            print("Don't know how to compute suffix for byte array type")
            exit(ExitCode.internalError.rawValue)
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
                if tp == .Double {
                    out.append("\tcomisd\t\(convert(left, typeToWidth(tp))), \(convert(right, typeToWidth(tp)))")
                } else {
                    out.append("\tcmp\(typeToSuffix(tp))\t\(convert(left, typeToWidth(tp))), \(convert(right, typeToWidth(tp)))")
                }
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
            case .Movsx(let srcType, let dstType, let src, let dst):
                let srcSuff = typeToSuffix(srcType)
                let dstSuff = typeToSuffix(dstType)
                let cSrc = convert(src, typeToWidth(srcType))
                let cDst = convert(dst, typeToWidth(dstType))
                out.append("\tmovs\(srcSuff)\(dstSuff)\t\(cSrc), \(cDst)")
            case .Movzx(let srcType, let dstType, let src, let dst):
                let srcSuff = typeToSuffix(srcType)
                let dstSuff = typeToSuffix(dstType)
                let cSrc = convert(src, typeToWidth(srcType))
                let cDst = convert(dst, typeToWidth(dstType))
                out.append("\tmovz\(srcSuff)\(dstSuff)\t\(cSrc), \(cDst)")
            case .Cvttsd2si(let tp, let src, let dst):
                out.append("\tcvttsd2si\(typeToSuffix(tp))\t\(convert(src, typeToWidth(tp))), \(convert(dst, typeToWidth(tp)))")
            case .Cvtsi2sd(let tp, let src, let dst):
                out.append("\tcvtsi2sd\t\(convert(src, typeToWidth(tp))), \(convert(dst, typeToWidth(tp)))")
            case .Lea(let src, let dst):
                // TODO: I just feel like this is a ticking time bomb
                out.append("\tlea\t\(convert(src, .eightByte)), \(convert(dst, .eightByte))")
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
        case .StaticVariable(let name, let isGlobal, let alignment, let initVals):
            if isGlobal {
                out.append("\t.globl \(name)")
            }
            out.append("\t.data")
            out.append("\t.balign\t\(alignment)")
            out.append("\(name):")
            for initVal in initVals {
                switch initVal {
                    case .IntInit(let i): out.append("\t.long\t\(i)")
                    case .LongInit(let i): out.append("\t.quad\t\(i)")
                    case .UIntInit(let i): out.append("\t.long\t\(i)")
                    case .ULongInit(let i): out.append("\t.quad\t\(i)")
                    case .DoubleInit(let f): out.append("\t.double\t\(f)")
                    case .CharInit(let i32): out.append("\t.byte\t\(i32)")
                    case .UCharInit(let i32): out.append("\t.byte\t\(i32)")
                    case .ZeroInit(let w): out.append("\t.zero\t\(w)")
                    case .StringInit(let val, let zero):
                        let s = escapeString(val)
                        if zero {
                            out.append("\t.asciz\t\"\(s)\"")
                        } else {
                            out.append("\t.ascii\t\"\(s)\"")
                        }
                    case .PointerInit(let name): out.append("\t.quad\t\(name)")
                }
            }
        case .StaticConstant(let name, let alignment, let initVal):
            if isStringInit(initVal) {
                out.append(".cstring")
            } else {
                if alignment == 8 {
                    out.append(".literal8")
                } else if alignment == 16 {
                    out.append(".literal16")
                }
            }
            out.append("\t.balign\t\(alignment)")
            out.append("\(name):")
            switch initVal {
                case .IntInit(let i): out.append("\t.long\t\(i)")
                case .LongInit(let i): out.append("\t.quad\t\(i)")
                case .UIntInit(let i): out.append("\t.long\t\(i)")
                case .ULongInit(let i): out.append("\t.quad\t\(i)")
                case .DoubleInit(let f):
                    out.append("\t.double\t\(f)")
                    if f == -0.0 {
                        out.append("\t.quad\t0")
                    }
                case .CharInit(let i32): out.append("\t.byte\t\(i32)")
                case .UCharInit(let i32): out.append("\t.byte\t\(i32)")
                case .ZeroInit(let w):
                    out.append("\t.zero\t\(w)")
                case .StringInit(let val, let zero):
                        let s = escapeString(val)
                        if zero {
                            out.append("\t.asciz\t\"\(s)\"")
                        } else {
                            out.append("\t.ascii\t\"\(s)\"")
                        }
                case .PointerInit(let label): out.append("\t.quad\t\(label)")
            }
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

func isStringInit(_ v: SemanticAnalyzer.TypeChecker.StaticInit) -> Bool {
    switch v {
        case .StringInit(_, _): return true
        default: return false
    }
}

func escapeString(_ s: String) -> String {
    var out : String = ""

    for c in s {
        if c.isLetter || c.isNumber {
            out = out + String(c)
        } else {
            out = out + "\\\(String(c.asciiValue!, radix: 8))"
        }
    }

    return out
}