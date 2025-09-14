import Foundation

func convert(_ operand: Assembly.Tree.Operand, _ fourByte: Bool = true) -> String {
    switch operand {
        case .Immediate(let val):
            return "$\(val)"
        case .Pseudo(let name):
            print("Encountered Pseudo way late in the pipeline: \(name)")
            exit(ExitCode.internalError.rawValue)
        case .Register(let reg):
            switch reg {
                case .AX:
                    return fourByte ? "%eax" : "%al"
                case .DX:
                    return fourByte ? "%edx" : "%dl"
                case .CL:
                    return "%cl"
                case .CX:
                    return fourByte ? "%ecx" : "%cl"
                case .R10:
                    return fourByte ? "%r10d" : "%r10b"
                case .R11:
                    return fourByte ? "%r11d" : "%r11b"
                case .DI:
                    // ummm, di is not a single byte 🤔
                    return fourByte ? "%edi" : "%di"
                case .SI:
                    return fourByte ? "%esi" : "%si"
                case .R8:
                    return fourByte ? "%r8d" : "%r8b"
                case .R9:
                    return fourByte ? "%r9d" : "%r9b"
            }
        case .Stack(let slot):
            return "\(slot)(%rbp)"
    }
}

func convert(_ op: Assembly.Tree.UnaryOperator) -> String {
    switch op {
        case .Neg:
            return "negl"
        case .Not:
            return "notl"
    }
}

func convert(_ op: Assembly.Tree.BinaryOperator) -> String {
    switch op {
        case .Add:
            return "addl"
        case .Sub:
            return "subl"
        case .Mult:
            return "imull"
        case .And:
            return "andl"
        case .Or:
            return "orl"
        case .Xor:
            return "xorl"
        case .Sar:
            return "sarl"
        case .Shl:
            return "shll"
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
    }
}

func emitInstructions(_ instructions: [Assembly.Tree.Instruction], out: inout [String]) {
    for instr in instructions {
        switch instr {
            case .AllocateStack(let count):
                if count != 0 { out.append("\tsubq\t$\(count), %rsp") }
            case .Mov(let opSrc, let opDst):
                out.append("\tmovl\t\(convert(opSrc)), \(convert(opDst))")
            case .Ret:
                out.append("\tmovq\t%rbp, %rsp")
                out.append("\tpopq\t%rbp")
                out.append("\tret")
            case .Unary(let unOp, let op):
                out.append("\t\(convert(unOp))\t\(convert(op))")
            case .Binary(let binOp, let leftOperand, let rightOperand):
                out.append("\t\(convert(binOp))\t\(convert(leftOperand)), \(convert(rightOperand))")
            case .Cdq:
                out.append("\tcdq")
            case .Idiv(let op):
                out.append("\tidivl\t\(convert(op))")
            case .Cmp(let left, let right):
                out.append("\tcmpl\t\(convert(left)), \(convert(right))")
            case .Jmp(let label):
                out.append("\tjmp\t\(label)")
            case .JmpCC(let cc, let label):
                out.append("\tj\(convert(cc))\t\(label)")
            case .SetCC(let cc, let op):
                out.append("\tset\(convert(cc))\t\(convert(op, false))")
            case .Label(let name):
                out.append("\(name):")
            case .DeallocateStack(_): fallthrough
            case .Push(_): fallthrough
            case .Call(_):
                print("Unsupported instruction \(instr) found while emitting code")
                exit(ExitCode.internalError.rawValue)
}
    }
}

func emitProgramLevelStatement(_ pls: Assembly.Tree.ProgramLevelStatement, out: inout [String]) {
    switch pls {
        case .Function(let name, let instrs):
            out.append("\t.global _\(name)")
            out.append("_\(name):")
            out.append("\tpushq\t%rbp")
            out.append("\tmovq\t%rsp, %rbp")
            emitInstructions(instrs, out: &out)
            out.append("\n\n")
    }
}

func emitProgram(program: Assembly.Tree.Program) -> [String] {
    var out : [String] = []

    switch program {
        case .Statement(let statements):
            for stmt in statements {
                emitProgramLevelStatement(stmt, out: &out)
            }
    }

    return out
}