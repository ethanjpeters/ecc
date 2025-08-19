import Foundation

func convert(_ operand: Assembly.Tree.Operand) -> String {
    switch operand {
        case .Immediate(let val):
            return "$\(val)"
        case .Pseudo(let name):
            print("Encountered Pseudo way late in the pipeline: \(name)")
            exit(ExitCode.internalError.rawValue)
        case .Register(let reg):
            switch reg {
                case .AX:
                    return "%eax"
                case .DX:
                    return "%edx"
                case .R10:
                    return "%r10d"
                case .R11:
                    return "%r11d"
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
            default:
                print("Unhandled construct: \(instr)")
                exit(ExitCode.parserError.rawValue)
        }
    }
}

func emitProgram(program: Assembly.Tree.Program) -> [String] {
    var out : [String] = []

    switch program {
        case .Function(let name, let instrs):
            out.append("\t.global _\(name)")
            out.append("_\(name):")
            out.append("\tpushq\t%rbp")
            out.append("\tmovq\t%rsp, %rbp")
            emitInstructions(instrs, out: &out)
    }

    return out
}