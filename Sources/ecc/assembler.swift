import Foundation

typealias BackendSymbolTable = [String : Assembly.Tree.AssemblySymbolTableEntry]

let negativeZeroLabel = "_double.constant.negativezero"

class Assembly {
    struct Tree {
        enum ConditionCode {
            case E
            case NE
            case G
            case GE
            case L
            case LE
            case A
            case AE
            case B
            case BE
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
            case XMM0
            case XMM1
            case XMM2
            case XMM3
            case XMM4
            case XMM5
            case XMM6
            case XMM7
            case XMM14
            case XMM15
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
            case DivDouble
        }

        enum AssemblyType {
            case Longword
            case Quadword
            case Double
        }

        enum Instruction {
            case Mov(AssemblyType, Operand /* src */, Operand /* dst */)
            case Movsx(Operand /* src */, Operand /* dst */)
            case Movzx(Operand /* src */, Operand /* dst */)
            case Cvttsd2dsi(AssemblyType, Operand /* src */, Operand /* dst */)
            case Cvtsi2sd(AssemblyType, Operand /* src */, Operand /* dst */ )
            case Unary(UnaryOperator, AssemblyType, Operand)
            case Binary(BinaryOperator, AssemblyType, Operand, Operand)
            case Cmp(AssemblyType, Operand, Operand)
            case Idiv(AssemblyType, Operand)
            case Div(AssemblyType, Operand)
            case Cdq(AssemblyType)
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
            case StaticVariable(String /* name */, Bool /* is global */, Int /* alignment */, SemanticAnalyzer.TypeChecker.StaticInit /* initial value */)
            case StaticConstant(String /* name */, Int /* alignment */, SemanticAnalyzer.TypeChecker.StaticInit /* init */)
        }

        enum Program {
            case Statement([Declaration])
        }

        enum AssemblySymbolTableEntry {
            case ObjEntry(AssemblyType, Bool /* is static */)
            case FunEntry(Bool /* is defined */)
        }
    }

    let negativeZero : Assembly.Tree.Declaration = .StaticConstant(negativeZeroLabel, 16, .DoubleInit(-0.0))

    class DoubleConstantExtractor {
        private var counter : Int = 1

        func makeLabel() -> String {
            let out = "_double.constant.\(counter)"
            counter = counter + 1
            return out
        }

        func extract(_ value: Tacky.IR.Value, _ mapping: inout [Double: Tree.Declaration]) {
            switch value {
                case .Constant(let constVal):
                    switch constVal {
                        case .ConstDouble(let d):
                            if mapping[d] == nil {
                                mapping[d] = .StaticConstant(makeLabel(), 8, .DoubleInit(d))
                            }
                        default: ()
                    }
                case .Var(_): ()
            }
        }

        func extract(_ program: Tacky.IR.Program) -> [Double: Tree.Declaration] {
            var out : [Double: Tree.Declaration] = [:]
            switch program {
                case .Statement(let decls):
                    for d in decls {
                        switch d {
                            case .Function(_, _, _, let body):
                                for instr in body {
                                    switch instr {
                                        case .Return(let val):
                                            if let v = val {
                                                extract(v, &out)
                                            }
                                        case .Unary(_, let src, _):
                                            extract(src, &out)
                                        case .Binary(_, let src1, let src2, _):
                                            extract(src1, &out)
                                            extract(src2, &out)
                                        case .Copy(let src, _):
                                            extract(src, &out)
                                        case .Jump(_): ()
                                        case .JumpIfZero(let val, _):
                                            extract(val, &out)
                                        case .JumpIfNotZero(let val, _):
                                            extract(val, &out)
                                        case .Label(_): ()
                                        case .Call(_, let params, _):
                                            for p in params {
                                                extract(p, &out)
                                            }
                                        case .SignExtend(let src, _):
                                            extract(src, &out)
                                        case .ZeroExtend(let src, _):
                                            extract(src, &out)
                                        case .Truncate(let src, _):
                                            extract(src, &out)
                                        case .DoubleToInt(let src, _):
                                            extract(src, &out)
                                        case .DoubleToUInt(let src, _):
                                            extract(src, &out)
                                        case .IntToDouble(let src, _):
                                            extract(src, &out)
                                        case .UIntToDouble(let src, _):
                                            extract(src, &out)
                                    }
                                }
                            case .StaticVariable(_, _, _, _): ()
                        }
                    }
            }

            return out
        }
    }

    private var extractedDoubles : [Double : Tree.Declaration] = [:]

    func convert(_ val: Tacky.IR.Value, _ symbolTable: [String : Assembly.Tree.Declaration]) -> Tree.Operand {
        switch val {
            case .Constant(let c):
                switch c {
                    case .ConstInt(let i): return .Immediate(Int(i))
                    case .ConstLong(let i): return .Immediate(Int(i))
                    case .ConstUnsignedInt(let i): return .Immediate(Int(i))
                    case .ConstUnsignedLong(let i): return .Immediate(Int(i))
                    case .ConstDouble(let f):
                        guard let staticVar = self.extractedDoubles[f] else {
                            print("Somehow got a constant double that has not been extracted")
                            exit(ExitCode.internalError.rawValue)
                        }
                        switch staticVar {
                            case .StaticConstant(let name, _, _):
                                return .Data(name)
                            default:
                                print("static declaration of a floating point constant is somehow not a constant?")
                                exit(ExitCode.internalError.rawValue)
                        }
                }
            case .Var(let name):
                if let _ = symbolTable[name] {
                    return .Data(name)
                }
                return .Pseudo(name)
        }
    }

    func deduceType(_ val: Tacky.IR.Value, _ symbolTable: SymbolTable) -> Tree.AssemblyType {
        switch val {
            case .Constant(let c):
                switch c {
                    case .ConstUnsignedInt: fallthrough
                    case .ConstInt(_) : return .Longword
                    case .ConstUnsignedLong: fallthrough
                    case .ConstLong(_) : return .Quadword
                    case .ConstDouble(_): return .Double
                }
            case .Var(let name):
                guard let entry = symbolTable[name] else {
                    print("Unreachable case where a variable was not in the symbol table during assembly generation: \(name)")
                    exit(ExitCode.internalError.rawValue)
                }
                let (checkerType, _) = entry
                switch checkerType {
                    case .Function(_, _):
                        print("Unreachable case where a variable was a function but was supposed to be a variable")
                        exit(ExitCode.internalError.rawValue)
                    case .Void: return .Longword    // functions can return "void" but really they return int
                    case .UnsignedInt: fallthrough
                    case .Int: return .Longword
                    case .UnsignedLong: fallthrough
                    case .Long: return .Quadword
                    case .Double: return .Double
                }
        }
    }

    func deduceIsSigned(_ val: Tacky.IR.Value, _ symbolTable: SymbolTable) -> Bool {
        switch val {
            case .Constant(let c):
                switch c {
                    case .ConstUnsignedInt: return false
                    case .ConstInt(_) : return true
                    case .ConstUnsignedLong: return false
                    case .ConstLong(_) : return true
                    case .ConstDouble(_): return true
                }
            case .Var(let name):
                guard let entry = symbolTable[name] else {
                    print("Unreachable case where a variable was not in the symbol table during assembly generation: \(name)")
                    exit(ExitCode.internalError.rawValue)
                }
                let (checkerType, _) = entry
                switch checkerType {
                    case .Function(_, _):
                        print("Unreachable case where a variable was a function but was supposed to be a variable")
                        exit(ExitCode.internalError.rawValue)
                    case .Void: return true    // functions can return "void" but really they return int
                    case .UnsignedInt: return false
                    case .Int: return true
                    case .UnsignedLong: return false
                    case .Long: return true
                    case .Double: return true
                }
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

    func generate(_ instructions: [Tacky.IR.Instruction], _ symbolTable: [String : Assembly.Tree.Declaration], _ out: inout [Tree.Instruction], _ typedSymbolTable: SymbolTable) {
        for instr in instructions {
            switch instr {
                case .Return(let val):
                    let v : Tacky.IR.Value = (val == nil ? .Constant(.ConstInt(0)) : val!)
                    out.append(.Mov(deduceType(v, typedSymbolTable), convert(v, symbolTable), .Register(.AX)))
                    out.append(.Ret)
                case .Unary(let op, let src, let dst):
                    let srcType = deduceType(src, typedSymbolTable)
                    let isFlop = (srcType == .Double)
                    if op == .Not {
                        if isFlop {
                            out.append(.Binary(.Xor, .Double, .Register(.XMM0), .Register(.XMM0)))
                            out.append(.Cmp(.Double, .Register(.XMM0), convert(src, symbolTable)))
                        } else {
                            out.append(.Cmp(srcType, .Immediate(0), convert(src, symbolTable)))
                        }
                        out.append(.Mov(srcType, .Immediate(0), convert(dst, symbolTable)))
                        out.append(.SetCC(.E, convert(dst, symbolTable)))
                    } else {
                        if isFlop && op == .Negate {
                            out.append(.Mov(srcType, convert(src, symbolTable), convert(dst, symbolTable)))
                            out.append(.Binary(.Xor, srcType, .Data(negativeZeroLabel), convert(dst, symbolTable)))
                        } else {
                            out.append(.Mov(srcType, convert(src, symbolTable), convert(dst, symbolTable)))
                            out.append(.Unary(convert(op), srcType, convert(dst, symbolTable)))
                        }
                    }
                case .Binary(let op, let src1, let src2, let dst):
                    let src1Conv = convert(src1, symbolTable)
                    let src2Conv = convert(src2, symbolTable)
                    let dstConv = convert(dst, symbolTable)
                    let srcType = deduceType(src1, typedSymbolTable)
                    let signedOp = deduceIsSigned(src1, typedSymbolTable)
                    let isFlop = (srcType == .Double)
                    switch op {
                        case .Add:
                            out.append(.Mov(srcType, src1Conv, dstConv))
                            out.append(.Binary(.Add, srcType, src2Conv, dstConv))
                        case .Subtract:
                            out.append(.Mov(srcType, src1Conv, dstConv))
                            out.append(.Binary(.Sub, srcType, src2Conv, dstConv))
                        case .Multiply:
                            out.append(.Mov(srcType, src1Conv, dstConv))
                            out.append(.Binary(.Mult, srcType, src2Conv, dstConv))
                        case .Divide:
                            if isFlop {
                                out.append(.Mov(srcType, src1Conv, dstConv))
                                out.append(.Binary(.DivDouble, srcType, src2Conv, dstConv))
                            } else {
                                if signedOp {
                                    out.append(.Mov(srcType, src1Conv, .Register(.AX)))
                                    out.append(.Cdq(srcType))
                                    out.append(.Idiv(srcType, src2Conv))
                                    out.append(.Mov(srcType, .Register(.AX), dstConv))
                                } else {
                                    out.append(.Mov(srcType, src1Conv, .Register(.AX)))
                                    out.append(.Mov(srcType, .Immediate(0), .Register(.DX)))
                                    out.append(.Div(srcType, src2Conv))
                                    out.append(.Mov(srcType, .Register(.AX), dstConv))
                                }
                            }
                        case .Remainder:
                            // safety check
                            if isFlop {
                                print("Remainder operation can not be applied to floating point operand")
                                exit(ExitCode.semanticError.rawValue)
                            }
                            if signedOp {
                                out.append(.Mov(srcType, src1Conv, .Register(.AX)))
                                out.append(.Cdq(srcType))
                                out.append(.Idiv(srcType, src2Conv))
                                out.append(.Mov(srcType, .Register(.DX), dstConv))
                            } else {
                                out.append(.Mov(srcType, src1Conv, .Register(.AX)))
                                out.append(.Mov(srcType, .Immediate(0), .Register(.DX)))
                                out.append(.Div(srcType, src2Conv))
                                out.append(.Mov(srcType, .Register(.DX), dstConv))
                            }
                        case .Equal:
                            out.append(.Cmp(srcType, src2Conv, src1Conv))
                            out.append(.Mov(isFlop ? .Longword : srcType, .Immediate(0), dstConv))
                            out.append(.SetCC(.E, dstConv))
                        case .NotEqual:
                            out.append(.Cmp(srcType, src2Conv, src1Conv))
                            out.append(.Mov(isFlop ? .Longword : srcType, .Immediate(0), dstConv))
                            out.append(.SetCC(.NE, dstConv))
                        case .LessThan:
                            out.append(.Cmp(srcType, src2Conv, src1Conv))
                            out.append(.Mov(isFlop ? .Longword : srcType, .Immediate(0), dstConv))
                            out.append(.SetCC(isFlop ? .B : (signedOp ? .L : .B), dstConv))
                        case .LessOrEqual:
                            out.append(.Cmp(srcType, src2Conv, src1Conv))
                            out.append(.Mov(isFlop ? .Longword : srcType, .Immediate(0), dstConv))
                            out.append(.SetCC(isFlop ? .BE : signedOp ? .LE : .BE, dstConv))
                        case .GreaterThan: 
                            out.append(.Cmp(srcType, src2Conv, src1Conv))
                            out.append(.Mov(isFlop ? .Longword : srcType, .Immediate(0), dstConv))
                            out.append(.SetCC(isFlop ? .A : signedOp ? .G : .A, dstConv))
                        case .GreaterOrEqual:
                            out.append(.Cmp(srcType, src2Conv, src1Conv))
                            out.append(.Mov(isFlop ? .Longword : srcType, .Immediate(0), dstConv))
                            out.append(.SetCC(isFlop ? .AE : signedOp ? .GE : .AE, dstConv))
                        case .BitwiseAnd:
                            out.append(.Mov(srcType, src1Conv, dstConv))
                            out.append(.Binary(.And, srcType, src2Conv, dstConv))
                        case .BitwiseOr:
                            out.append(.Mov(srcType, src1Conv, dstConv))
                            out.append(.Binary(.Or, srcType, src2Conv, dstConv))
                        case .BitwiseXor:
                            out.append(.Mov(srcType, src1Conv, dstConv))
                            out.append(.Binary(.Xor, srcType, src2Conv, dstConv))
                        case .BitwiseShiftRight:
                            out.append(.Mov(srcType, src1Conv, dstConv))
                            out.append(.Binary(.Sar, srcType, src2Conv, dstConv))
                        case .BitwiseShiftLeft:
                            out.append(.Mov(srcType, src1Conv, dstConv))
                            out.append(.Binary(.Shl, srcType, src2Conv, dstConv))
                    }
                case .Copy(let src, let dst):
                    out.append(.Mov(deduceType(src, typedSymbolTable), convert(src, symbolTable), convert(dst, symbolTable)))
                case .Jump(let label):
                    out.append(.Jmp(label))
                case .JumpIfZero(let val, let label):
                    let valType = deduceType(val, typedSymbolTable)
                    let isFlop = (valType == .Double)
                    if isFlop {
                        out.append(.Binary(.Xor, .Double, .Register(.XMM0), .Register(.XMM0)))
                        out.append(.Cmp(valType, convert(val, symbolTable), .Register(.XMM0)))
                    } else {
                        out.append(.Cmp(valType, .Immediate(0), convert(val, symbolTable)))
                    }
                    out.append(.JmpCC(.E, label))
                case .JumpIfNotZero(let val, let label):
                    let valType = deduceType(val, typedSymbolTable)
                    let isFlop = (valType == .Double)
                    if isFlop {
                        out.append(.Binary(.Xor, .Double, .Register(.XMM0), .Register(.XMM0)))
                        out.append(.Cmp(valType, convert(val, symbolTable), .Register(.XMM0)))
                    } else {
                        out.append(.Cmp(valType, .Immediate(0), convert(val, symbolTable)))
                    }
                    out.append(.JmpCC(.NE, label))
                case .Label(let name):
                    out.append(.Label(name))
                case .Call(let name, let params, let result):
                    // save context (currently not an issue because we only use scratch registers)
                    // move parameters into place
                    var copiedParams = params
                    if !copiedParams.isEmpty {
                        let p = copiedParams.removeFirst()
                        out.append(.Mov(deduceType(p, typedSymbolTable), convert(p, symbolTable), .Register(.DI)))
                    }
                    if !copiedParams.isEmpty {
                        let p = copiedParams.removeFirst()
                        out.append(.Mov(deduceType(p, typedSymbolTable), convert(p, symbolTable), .Register(.SI)))
                    }
                    if !copiedParams.isEmpty {
                        let p = copiedParams.removeFirst()
                        out.append(.Mov(deduceType(p, typedSymbolTable), convert(p, symbolTable), .Register(.CX)))
                    }
                    if !copiedParams.isEmpty {
                        let p = copiedParams.removeFirst()
                        out.append(.Mov(deduceType(p, typedSymbolTable), convert(p, symbolTable), .Register(.R8)))
                    }
                    if !copiedParams.isEmpty {
                        let p = copiedParams.removeFirst()
                        out.append(.Mov(deduceType(p, typedSymbolTable), convert(p, symbolTable), .Register(.R9)))
                    }

                    // the System V ABI requires the stack to be 16-byte aligned
                    let stackPadding = copiedParams.count % 2 == 0 ? 0 : 8

                    if stackPadding != 0 {
                        out.append(.AllocateStack(stackPadding))
                    }

                    copiedParams.reverse()
                    for p in copiedParams {
                        let src = convert(p, symbolTable)
                        var shouldPushStraight : Bool = deduceType(p, typedSymbolTable) == .Quadword
                        switch src {
                            case .Register(_): fallthrough
                            case .Immediate(_):
                                shouldPushStraight = true
                            default: ()
                        }
                        if shouldPushStraight {
                            out.append(.Push(src))
                        } else {
                            out.append(.Mov(.Longword, src, .Register(.AX)))
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
                    out.append(.Mov(deduceType(result, typedSymbolTable), .Register(.AX), convert(result, symbolTable)))
                case .SignExtend(let src, let dst):
                    out.append(.Movsx(convert(src, symbolTable), convert(dst, symbolTable)))
                case .Truncate(let src, let dst):
                    out.append(.Mov(.Longword, convert(src, symbolTable), convert(dst, symbolTable)))
                case .ZeroExtend(let src, let dst):
                    out.append(.Movzx(convert(src, symbolTable), convert(dst, symbolTable)))
                case .DoubleToInt(let src, let dst):
                    // straightforward case, done by one instruction
                    out.append(.Cvttsd2dsi(deduceType(src, typedSymbolTable), convert(src, symbolTable), convert(dst, symbolTable)))
                case .DoubleToUInt(let src, let dst):
                    print("As-yet-unhandled conversion instruction \(instr) found while generating assembly")
                    exit(ExitCode.internalError.rawValue)
                case .IntToDouble(let src, let dst):
                    out.append(.Cvtsi2sd(deduceType(src, typedSymbolTable), convert(src, symbolTable), convert(dst, symbolTable)))
                case .UIntToDouble(_, _):
                    print("As-yet-unhandled conversion instruction \(instr) found while generating assembly")
                    exit(ExitCode.internalError.rawValue)
}
        }
    }

    func generate(_ pls: Tacky.IR.Declaration, _ symbolTable: [String : Assembly.Tree.Declaration], _ typedSymbolTable: SymbolTable) -> Tree.Declaration {
        switch pls {
            case .Function(let name, let isGlobal, let params, let instrs):
                var out : [Tree.Instruction] = []
                var copiedParams = params
                if !copiedParams.isEmpty {
                    let p: String = copiedParams.removeFirst()
                    out.append(.Mov(deduceType(.Var(p), typedSymbolTable), .Register(.DI), .Pseudo(p)))
                }
                if !copiedParams.isEmpty {
                    let p = copiedParams.removeFirst()
                    out.append(.Mov(deduceType(.Var(p), typedSymbolTable), .Register(.SI), .Pseudo(p)))
                }
                if !copiedParams.isEmpty {
                    let p = copiedParams.removeFirst()
                    out.append(.Mov(deduceType(.Var(p), typedSymbolTable), .Register(.CX), .Pseudo(p)))
                }
                if !copiedParams.isEmpty {
                    let p = copiedParams.removeFirst()
                    out.append(.Mov(deduceType(.Var(p), typedSymbolTable), .Register(.R8), .Pseudo(p)))
                }
                if !copiedParams.isEmpty {
                    let p = copiedParams.removeFirst()
                    out.append(.Mov(deduceType(.Var(p), typedSymbolTable), .Register(.R9), .Pseudo(p)))
                }
                copiedParams.reverse()
                var counter = 0
                for p in copiedParams {
                    out.append(.Mov(deduceType(.Var(p), typedSymbolTable), .Stack(16 + counter), .Pseudo(p)))
                    counter = counter + 8
                }
                generate(instrs, symbolTable, &out, typedSymbolTable)
                return .Function(name, isGlobal, out)
            case .StaticVariable(_, _, _, _):
                print("As yet unhandled global variable caught while generating assembly")
                exit(ExitCode.internalError.rawValue)
        }
    }

    func generate(program: Tacky.IR.Program, symbolTable: [Tacky.IR.Declaration], typedSymbolTable: SymbolTable) -> (Tree.Program, BackendSymbolTable) {
        var assemblyDecls : [Assembly.Tree.Declaration] = []
        var internalSymbolTable : [String : Assembly.Tree.Declaration] = [:]
        for tackyDef in symbolTable {
            switch tackyDef {
                case .StaticVariable(let name, let isGlobal, let tp, let initValue):
                    let assemblyEntry : Tree.Declaration = .StaticVariable(name, isGlobal, tp == .Int ? 4 : 8, initValue)
                    assemblyDecls.append(assemblyEntry)
                    internalSymbolTable[name] = assemblyEntry
                default: ()
            }
        }
        self.extractedDoubles = DoubleConstantExtractor().extract(program)
        for (_, decl) in self.extractedDoubles {
            assemblyDecls.append(decl)
        }
        // constant constant
        assemblyDecls.append(negativeZero)
        let out: Tree.Program
        switch program {
            case .Statement(let declarations):
                for d in declarations {
                    assemblyDecls.append(generate(d, internalSymbolTable, typedSymbolTable))
                }
                out = .Statement(assemblyDecls)
        }

        var asmSymTab : BackendSymbolTable = .init()
        for (name, entry) in typedSymbolTable {
            let (checkerType, attrs) = entry
            switch checkerType {
                case .Int: fallthrough
                case .UnsignedInt: fallthrough
                case .Long: fallthrough
                case .UnsignedLong:
                    let asmType : Tree.AssemblyType = (checkerType == .Int ? .Longword : .Quadword)
                    let isStatic: Bool
                    switch attrs {
                        case .StaticAttr(_, _):
                            isStatic = true
                        case .LocalAttr:
                            isStatic = false
                        case .FunAttr(_, _):
                            print("Totally meaningless function typed int/long \(name)")
                            exit(ExitCode.internalError.rawValue)
                    }
                    asmSymTab[name] = .ObjEntry(asmType, isStatic)
                case .Void:
                    asmSymTab[name] = .ObjEntry(.Longword, false)   // function return types can be void
                case .Function(_, _):
                    switch attrs {
                        case .FunAttr(let isDefined, _):
                            asmSymTab[name] = .FunEntry(isDefined)
                        default:
                            print("Meaningless non-function attributes attached to function \(name)")
                            exit(ExitCode.internalError.rawValue)
                    }
                case .Double:
                    print("As-yet-unhandled floating point value found while generating assembly")
                    exit(ExitCode.internalError.rawValue)
            }
        }

        return (out, asmSymTab)
    }

    func replacePseudoRegisters(_ op: Tree.Operand, _ stackSlotCounter: inout Int, _ nameStackMapping: inout [String: Int], _ symbolTable : SymbolTable) -> Tree.Operand {
        switch op {
            case .Immediate(_):
                return op
            case .Register(_):
                return op
            case .Pseudo(let name):
                guard let (tp, _) = symbolTable[name] else {
                    print("Impossible situation where pseudo \(name) is not in the symbol table")
                    exit(ExitCode.internalError.rawValue)
                }
                let width : Int
                switch tp {
                    case .Function(_, _):
                        print("No comprendo; can't have a pseudo of function type (\(name))")
                        exit(ExitCode.internalError.rawValue)
                    case .Void: width = 4   // function return types can be void but they're really int
                    case .Int: width = 4
                    case .UnsignedInt: width = 4
                    case .Long: width = 8
                    case .UnsignedLong: width = 8
                    case .Double: width = 8
                }
                if let slot = nameStackMapping[name] {
                    return .Stack(-slot)
                }
                var tmp = stackSlotCounter + width
                if tmp % width != 0 {
                    // must be aligned
                    tmp = tmp + (tmp % width)
                }
                stackSlotCounter = tmp
                nameStackMapping[name] = stackSlotCounter
                return .Stack(-stackSlotCounter)
            case .Stack(_):
                return op
            case .Data(_):
                return op
        }
    }

    func replacePseudoRegisters(_ instructions: [Tree.Instruction], _ symbolTable : SymbolTable) -> [Tree.Instruction] {
        var out : [Tree.Instruction] = []

        var stackSlotCounter : Int = 0
        var nameStackMapping : [String: Int] = [:]

        for instr: Assembly.Tree.Instruction in instructions {
            switch instr {
                case .AllocateStack(_):
                    out.append(instr)
                case .Mov(let tp, let op1, let op2):
                    out.append(.Mov(tp, replacePseudoRegisters(op1, &stackSlotCounter, &nameStackMapping, symbolTable),
                                    replacePseudoRegisters(op2, &stackSlotCounter, &nameStackMapping, symbolTable)))
                case .Ret:
                    out.append(instr)
                case .Unary(let unOp, let tp, let op):
                    out.append(.Unary(unOp, tp, replacePseudoRegisters(op, &stackSlotCounter, &nameStackMapping, symbolTable)))
                case .Binary(let binOp, let tp, let left, let right):
                    out.append(.Binary(binOp, tp, replacePseudoRegisters(left, &stackSlotCounter, &nameStackMapping, symbolTable), replacePseudoRegisters(right, &stackSlotCounter, &nameStackMapping, symbolTable)))
                case .Cdq(let tp): out.append(.Cdq(tp))
                case .Idiv(let tp, let op): out.append(.Idiv(tp, replacePseudoRegisters(op, &stackSlotCounter, &nameStackMapping, symbolTable)))
                case .Div(let tp, let op): out.append(.Div(tp, replacePseudoRegisters(op, &stackSlotCounter, &nameStackMapping, symbolTable)))
                case .Cmp(let tp, let left, let right):
                    out.append(.Cmp(tp, replacePseudoRegisters(left, &stackSlotCounter, &nameStackMapping, symbolTable),
                                    replacePseudoRegisters(right, &stackSlotCounter, &nameStackMapping, symbolTable)))
                case .Jmp(_): out.append(instr)
                case .JmpCC(_, _): out.append(instr)
                case .SetCC(let cc, let op):
                    out.append(.SetCC(cc, replacePseudoRegisters(op, &stackSlotCounter, &nameStackMapping, symbolTable)))
                case .Label(_): out.append(instr)
                case .Call(_): out.append(instr)
                case .DeallocateStack(_): out.append(instr)
                case .Push(let op):
                    out.append(.Push(replacePseudoRegisters(op, &stackSlotCounter, &nameStackMapping, symbolTable)))
                case .Movsx(let src, let dst):
                    out.append(.Movsx(
                        replacePseudoRegisters(src, &stackSlotCounter, &nameStackMapping, symbolTable),
                        replacePseudoRegisters(dst, &stackSlotCounter, &nameStackMapping, symbolTable)
                    ))
                case .Movzx(let src, let dst):
                    out.append(.Movzx(
                        replacePseudoRegisters(src, &stackSlotCounter, &nameStackMapping, symbolTable),
                        replacePseudoRegisters(dst, &stackSlotCounter, &nameStackMapping, symbolTable)
                    ))
                case .Cvttsd2dsi(_, _, _): fallthrough
                case .Cvtsi2sd(_, _, _):
                    print("As-yet-unhandled conversion instruction found while generating assembly")
                    exit(ExitCode.internalError.rawValue)
            }
        }

        out.insert(.AllocateStack(stackSlotCounter), at: 0)

        return out
    }

    func replacePseudoRegisters(_ pls: Tree.Declaration, _ symbolTable : SymbolTable) -> Tree.Declaration {
        switch pls {
            case .Function(let name, let isGlobal, let instrs):
                return .Function(name, isGlobal, replacePseudoRegisters(instrs, symbolTable))
            case .StaticVariable(let name, let isGlobal, let alignment, let initVal):
                return .StaticVariable(name, isGlobal, alignment, initVal)
            case .StaticConstant(let name, let alignment, let initVal):
                return .StaticConstant(name, alignment, initVal)
        }
    }

    func replacePseudoRegisters(program: Tree.Program, _ symbolTable : SymbolTable) -> Tree.Program {
        switch program {
            case .Statement(let declarations):
                return .Statement(declarations.map{ replacePseudoRegisters($0, symbolTable) })
        }
    }

    func fixUpMoves(_ instrs: [Tree.Instruction]) -> [Tree.Instruction] {
        var out : [Tree.Instruction] = []
        for instr in instrs {
            switch instr {
                case .AllocateStack(_): out.append(instr)
                case .Mov(let tp, let opSrc, let opDst):
                    switch opSrc {
                        case .Stack(_): fallthrough
                        case .Data(_):
                            switch opDst {
                                case .Stack(_): fallthrough
                                case .Data(_):
                                    out.append(.Mov(tp, opSrc, .Register(.R10)))
                                    out.append(.Mov(tp, .Register(.R10), opDst))
                                default:
                                    out.append(instr)
                            }
                        default:
                            out.append(instr)
                    }
                case .Ret: out.append(instr)
                case .Unary(_, _, _): out.append(instr)
                case .Binary(let op, let tp, let src, let dst):
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
                                        out.append(.Mov(tp, src, .Register(.R10)))
                                        out.append(.Binary(op, tp, .Register(.R10), dst))
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
                                    out.append(.Mov(tp, dst, .Register(.R11)))
                                    out.append(.Binary(op, tp, src, .Register(.R11)))
                                    out.append(.Mov(tp, .Register(.R11), dst))
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
                                    out.append(.Mov(tp, src, .Register(.CX)))
                                    out.append(.Binary(op, tp, .Register(.CL), dst))
                                default:
                                    out.append(instr)
                            }
                        case .DivDouble:
                            print("As-yet-unhandled floating point division found while fixing up moves")
                            exit(ExitCode.internalError.rawValue)
                    }
                case .Cdq: out.append(instr)
                case .Idiv(let tp, let op):
                    switch op {
                        case .Immediate(let val):
                            out.append(.Mov(tp, .Immediate(val), .Register(.R10)))
                            out.append(.Idiv(tp, .Register(.R10)))
                        default: out.append(instr)
                    }
                case .Div(let tp, let op):
                    switch op {
                        case .Immediate(let val):
                            out.append(.Mov(tp, .Immediate(val), .Register(.R10)))
                            out.append(.Div(tp, .Register(.R10)))
                        default: out.append(instr)
                    }
                case .Cmp(let tp, let left, let right):
                    switch left {
                        case .Data(_): fallthrough
                        case .Stack(_):
                            switch right {
                                case .Data(_): fallthrough
                                case .Stack(_):
                                    out.append(.Mov(tp, left, .Register(.R10)))
                                    out.append(.Cmp(tp, .Register(.R10), right))
                                case .Immediate(_):
                                    out.append(.Mov(tp, right, .Register(.R11)))
                                    out.append(.Cmp(tp, left, .Register(.R11)))
                                default:
                                    out.append(instr)
                            }
                        default:
                            switch right {
                                case .Immediate(_):
                                    out.append(.Mov(tp, right, .Register(.R11)))
                                    out.append(.Cmp(tp, left, .Register(.R11)))
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
                case .Movsx(let src, let dst):
                    let realSrc : Tree.Operand
                    switch src {
                        case .Immediate(_):
                            realSrc = .Register(.R10)
                            out.append(.Mov(.Longword, src, realSrc))
                        default:
                            realSrc = src
                    }
                    let realDst : Tree.Operand
                    let postfix : Tree.Instruction?
                    switch dst {
                        case .Data(_): fallthrough
                        case .Stack(_):
                            realDst = .Register(.R11)
                            postfix = .Mov(.Quadword, realDst, dst)
                        default:
                            postfix = nil
                            realDst = dst
                    }
                    out.append(.Movsx(realSrc, realDst))
                    if let p = postfix { out.append(p) }
                case .Movzx(let src, let dst):
                    switch dst {
                        case .Register(_):
                            out.append(.Mov(.Longword, src, dst))
                        case .Stack(_): fallthrough
                        case .Data(_):
                            out.append(.Mov(.Longword, src, .Register(.R11)))
                            out.append(.Mov(.Quadword, .Register(.R11), dst))
                        case .Pseudo(_):
                            print("Unreachable: psuedo slot survived past pseudo replacement")
                            exit(ExitCode.internalError.rawValue)
                        case .Immediate(_):
                            print("Unreachable: immediate as the destination of a movzx")
                            exit(ExitCode.internalError.rawValue)
                    }
                case .Cvttsd2dsi(_, _, _): fallthrough
                case .Cvtsi2sd(_, _, _):
                    print("As-yet-unhandled floating point conversion found while fixing up moves")
                    exit(ExitCode.internalError.rawValue)
            }
        }
        return out
    }

    func fixUpMoves(_ pls: Tree.Declaration) -> Tree.Declaration {
        switch pls {
            case .Function(let name, let isGlobal, let instrs):
                return .Function(name, isGlobal, fixUpMoves(instrs))
            case .StaticVariable(_, _, _, _):
                return pls
            case .StaticConstant(_, _, _):
                return pls
        }
    }

    func fixUpMoves(program: Tree.Program) -> Tree.Program {
        switch program {
            case .Statement(let declarations):
                return .Statement(declarations.map { fixUpMoves($0) })
        }
    }

    func fixUpImmediates(program: Tree.Program) -> Tree.Program {
        switch program {
            case .Statement(let decls):
                var fixedDecls : [Tree.Declaration] = []
                for dec in decls {
                    switch dec {
                        case .Function(let name, let isGlobal, let body):
                            var fixedBody : [Tree.Instruction] = []
                            for instr in body {
                                switch instr {
                                    case .Mov(let tp, let src, let dst):
                                        switch src {
                                            case .Immediate(let val):
                                                if tp == .Quadword {
                                                    switch dst {
                                                        case .Register(_):
                                                            fixedBody.append(instr)
                                                        default:
                                                            if val > Int32.max {
                                                                fixedBody.append(.Mov(
                                                                    tp,
                                                                    src,
                                                                    .Register(.R10)
                                                                ))
                                                                fixedBody.append(.Mov(
                                                                    tp,
                                                                    .Register(.R10),
                                                                    dst
                                                                ))
                                                            } else {
                                                                fixedBody.append(instr)
                                                            }
                                                    }
                                                } else {
                                                    // truncate
                                                    fixedBody.append(.Mov(
                                                        tp,
                                                        .Immediate(val % Int(Int32.max)),
                                                        dst
                                                    ))
                                                }
                                            default: fixedBody.append(instr)
                                        }
                                    case .Movsx(_, _): fixedBody.append(instr)
                                    case .Unary(_, _, _): fixedBody.append(instr)
                                    case .Binary(let op, let tp, let src, let dst):
                                        if tp == .Quadword {
                                            switch op {
                                                case .Add: fallthrough
                                                case .Mult: fallthrough
                                                case .Sub:
                                                    switch src {
                                                        case .Immediate(let val):
                                                            if val > Int32.max {
                                                                fixedBody.append(.Mov(
                                                                    tp,
                                                                    src,
                                                                    .Register(.R10)
                                                                ))
                                                                fixedBody.append(.Binary(
                                                                    op,
                                                                    tp,
                                                                    .Register(.R10),
                                                                    dst
                                                                ))
                                                            } else {
                                                                fixedBody.append(instr)
                                                            }
                                                        default: fixedBody.append(instr)
                                                    }
                                                default: fixedBody.append(instr)
                                            }
                                        } else {
                                            fixedBody.append(instr)
                                        }
                                    case .Cmp(let tp, let src, let dst):
                                        if tp == .Quadword {
                                            switch src {
                                                case .Immediate(let val):
                                                    if val > Int32.max {
                                                        fixedBody.append(.Mov(
                                                            tp,
                                                            src,
                                                            .Register(.R10)
                                                        ))
                                                        fixedBody.append(.Cmp(
                                                            tp,
                                                            .Register(.R10),
                                                            dst
                                                        ))
                                                    } else {
                                                        fixedBody.append(instr)
                                                    }
                                                default: fixedBody.append(instr)
                                            }
                                        } else {
                                            fixedBody.append(instr)
                                        }
                                    case .Idiv(_, _): fallthrough
                                    case .Cdq(_): fallthrough
                                    case .Jmp(_): fallthrough
                                    case .JmpCC(_, _): fallthrough
                                    case .SetCC(_, _): fallthrough
                                    case .Label(_): fallthrough
                                    case .AllocateStack(_): fallthrough
                                    case .DeallocateStack(_): fallthrough
                                    case .Push(_): fallthrough
                                    case .Call(_): fallthrough
                                    case .Movzx(_, _): fallthrough
                                    case .Div(_, _): fallthrough
                                    case .Ret: fixedBody.append(instr)
                                    case .Cvttsd2dsi(_, _, _): fallthrough
                                    case .Cvtsi2sd(_, _, _):
                                        print("As-yet-unhandled floating point conversion found while fixing up immediates")
                                        exit(ExitCode.internalError.rawValue)
                                }
                            }
                            fixedDecls.append(.Function(name, isGlobal, fixedBody))
                        case .StaticVariable(_, _, _, _):
                            fixedDecls.append(dec)
                        case .StaticConstant(_, _, _):
                            fixedDecls.append(dec)
                    }
                }
                return .Statement(fixedDecls)
        }
    }

    func assemble(program: Tacky.IR.Program, symbolTable: [Tacky.IR.Declaration], typedSymbolTable: SymbolTable) -> (Tree.Program, BackendSymbolTable) {
        let (assembly, backendSymbolTable) = generate(program: program, symbolTable: symbolTable, typedSymbolTable: typedSymbolTable)
        let dePseudoed = replacePseudoRegisters(program: assembly, typedSymbolTable)
        let fixedUp = fixUpMoves(program: dePseudoed)
        let noBigImms = fixUpImmediates(program: fixedUp)
        return (noBigImms, backendSymbolTable)
    }
}