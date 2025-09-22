import Foundation

enum RegisterWidth {
    case oneByte
    case twoByte
    case fourByte
    case eightByte
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
            }
        case .Stack(let slot):
            return "\(slot)(%rbp)"
        case .Data(let name):
            return "\(name)(%rip)"
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

func makeFunctionName(_ name : String) -> String {
    // macOS-only for now
    return "_\(name)"
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
                out.append("\tset\(convert(cc))\t\(convert(op, .oneByte))")
            case .Label(let name):
                out.append("\(name):")
            case .DeallocateStack(let count):
                if count != 0 { out.append("\taddq\t$\(count), %rsp")}
            case .Push(let operand):
                out.append("\tpushq\t\(convert(operand))")
            case .Call(let fName):
                out.append("\tcall\t\(makeFunctionName(fName))")
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
        case .StaticVariable(let name, let isGlobal, let initVal):
            if isGlobal {
                out.append("\t.globl \(name)")
            }
            out.append("\t.data")
            out.append(".balign\t4")
            out.append("\(name):")
            out.append("\t.long\t\(initVal)")
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