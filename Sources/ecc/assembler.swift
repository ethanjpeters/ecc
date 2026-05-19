import Foundation

typealias BackendSymbolTable = [String : Assembly.Tree.AssemblySymbolTableEntry]

let negativeZeroLabel = "L._double.constant.negativezero"
let biggestQuadwordLabel = "L._double.constant.biggestquadword"
let longMaxPlusOne : UInt64 = 9223372036854775808
let biggestQuadwordValue : Double = Double(longMaxPlusOne)

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
            case BP
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

        enum Imm {
            case SignedImmediate(Int)
            case UnsignedImmediate(UInt)
        }

        enum Operand {
            case Immediate(Imm)
            case Register(Register)
            case Pseudo(String)
            case Stack(Int)
            case Data(String /* identifier */, Int /* constant offset */)
            case Memory(Register, Int)
            case PseudoMem(String /* identifier */, UInt /* offset */)
            case Indexed(Register /* base */, Register /* index */, UInt /* scale */)
        }

        enum UnaryOperator {
            case Neg
            case Not
            case Shr
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
            case Shr
            case DivDouble
        }

        enum AssemblyType : Equatable {
            case Byte
            case Longword
            case Quadword
            case Double
            case ByteArray(UInt /* size */, UInt /* alignment */)
        }

        enum Instruction {
            case Mov(AssemblyType, Operand /* src */, Operand /* dst */)
            case Movsx(AssemblyType /* src */, AssemblyType /* dst */, Operand /* src */, Operand /* dst */)
            case Movzx(AssemblyType /* srcType */, AssemblyType /* dstType */, Operand /* src */, Operand /* dst */)
            case Cvttsd2si(AssemblyType, Operand /* src */, Operand /* dst */)
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
            case Lea(Operand /* src */, Operand /* dst */)
        }

        enum Declaration {
            case Function(String, Bool /* is global */, [Instruction])
            case StaticVariable(String /* name */, Bool /* is global */, Int /* alignment */, [SemanticAnalyzer.TypeChecker.StaticInit] /* initial values */)
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

    enum StructClass {
        case Memory
        case SSE
        case Integer
    }

    typealias StructEntry = SemanticAnalyzer.TypeChecker.TypeTableEntry.StructEntry
    typealias MemberEntry = SemanticAnalyzer.TypeChecker.TypeTableEntry.MemberEntry
    typealias TypeTable = SemanticAnalyzer.TypeChecker.TypeTable

    func classifyStruct(_ s: StructEntry, _ typeTable: TypeTable) -> [StructClass] {
        // if a struct is bigger than 16 bytes, then it is treated
        // as a collection of eightbyte values all stored in memory
        if s.size > 16 {    // magic number much?
            var sz = s.size
            var out: [StructClass] = []
            while sz > 0 {
                out.append(.Memory)
                sz = sz - 8
            }
            return out
        }

        // flatten list of members, including nested structs
        var members: [MemberEntry] = []
        func dumpMembers(_ se: StructEntry) {
            for m in se.members {
                switch m.typeSpec {
                    case .Structure(let tag):
                        if let x = typeTable[tag] {
                            dumpMembers(x)
                        } else {
                            print("Unreachable case where nested struct is not defined anywhere")
                            exit(ExitCode.internalError.rawValue)
                        }
                    default: members.append(m)
                }
            }
        }

        // if a struct is bigger than 8 bytes (i.e. has at least two elements)
        if s.size > 8 {
            // this seems odd to me, but I'm rolling with it
            if members.first!.typeSpec == .Double && members.last!.typeSpec == .Double {
                return [.SSE, .SSE]
            }
            if members.first!.typeSpec == .Double {
                return [.SSE, .Integer]
            }
            if members.last!.typeSpec == .Double {
                return [.Integer, .SSE]
            }
            return [.Integer, .Integer]
        } else {
            // otherwise, treat it as a single eightbyte value, which is either an integer or a double
            if members.first!.typeSpec == .Double {
                return [.SSE]
            } else {
                return [.Integer]
            }
        }
    }

    struct TypedOperand {
        public let op: Tree.Operand
        public let tp: Tree.AssemblyType
    }

    struct ClassifiedParams {
        public let integerRegisterArguments: [TypedOperand]
        public let floatingRegisterArguments: [TypedOperand]
        public let stackArguments: [TypedOperand]
    }

    func classifyParams(_ values: [Tacky.IR.Value], _ returnInMemory: Bool, _ symbolTable: [String: Assembly.Tree.Declaration], _ typedSymbolTable: SymbolTable, _ typeTable: TypeTable) -> ClassifiedParams {

        // TODO:
        func getEightbyteType(_ offset: Int, _ size: Int) -> Tree.AssemblyType {
            let bytesFromEnd = size - offset
            if bytesFromEnd >= 8 {
                return .Quadword
            }
            if bytesFromEnd >= 4 {
                return .Longword
            }
            if bytesFromEnd == 1 {
                return .Byte
            }
            return .ByteArray(UInt(bytesFromEnd), 8)
        }

        var intRegArgs: [TypedOperand] = []
        var doubleRegArgs: [TypedOperand] = []
        var stackArgs: [TypedOperand] = []

        let intRegsAvailable = returnInMemory ? 5 : 6
        let fpRegsAvailable = 8

        for v in values {
            let typedOp = TypedOperand(op: convert(v, symbolTable, typedSymbolTable), tp: deduceType(v, typedSymbolTable, typeTable))
            if typedOp.tp == .Double {
                if doubleRegArgs.count < fpRegsAvailable {
                    doubleRegArgs.append(typedOp)
                } else {
                    stackArgs.append(typedOp)
                }
            } else if isScalar(typedOp.tp) {
                if intRegArgs.count < intRegsAvailable {
                    intRegArgs.append(typedOp)
                } else {
                    doubleRegArgs.append(typedOp)
                }
            } else {
                // value is a structure, complicated stuff to be found here
                // ok, first all of, split the struct into eightbyteses by class
                // well, first-first we need to get the StructEntry for this object; this is giving me a headache. Ok, this should be a variable
                let klazzes : [StructClass]
                let structSize : Int
                let varName : String
                var useStack = true
                switch v {
                    case .Constant(_):
                        print("There is no such thing as a constant struct")
                        exit(ExitCode.internalError.rawValue)
                    case .Var(let name):
                        varName = name
                        if let (sType, _) = typedSymbolTable[name] {
                            switch sType {
                                case .Structure(let tag):
                                    if let se = typeTable[tag] {
                                        klazzes = classifyStruct(se, typeTable)
                                        structSize = se.size
                                    } else {
                                        print("Tried to pass undefined struct \(tag) to function")
                                        exit(ExitCode.internalError.rawValue)
                                    }
                                default:
                                    print("Unreachable case where we're trying to pass a non-struct to a function as a struct")
                                    exit(ExitCode.internalError.rawValue)
                            }
                        } else {
                            print("Unreachable case where a structure was not defined before we tried to pass it to a function")
                            exit(ExitCode.internalError.rawValue)
                        }
                }
                // then, potentially, put things in registers
                if klazzes.first! != .Memory {
                    // make tentative assignments to registers
                    var tentativeInts: [TypedOperand] = []
                    var tentativeDoubles: [TypedOperand] = []
                    var offset: UInt = 0

                    for k in klazzes {
                        let op : Tree.Operand = .PseudoMem(varName, offset)
                        if k == .SSE {
                            tentativeDoubles.append(TypedOperand(op: op, tp: .Double))
                        } else {
                            let ebType = getEightbyteType(Int(offset), structSize)
                            tentativeInts.append(TypedOperand(op: op, tp: ebType))
                        }
                        offset = offset + 8
                    }

                    // finalize **if** there are enough registers
                    if tentativeDoubles.count + doubleRegArgs.count <= fpRegsAvailable && tentativeInts.count + intRegArgs.count <= intRegsAvailable {
                        for q in tentativeDoubles {
                            doubleRegArgs.append(q)
                        }
                        for q in tentativeInts {
                            intRegArgs.append(q)
                        }
                        useStack = false
                    }
                }
                // finally, put stuff on the stack
                if useStack {
                    var offset: UInt = 0
                    for _ in klazzes {
                        let op: Tree.Operand = .PseudoMem(varName, offset)
                        let ebType = getEightbyteType(Int(offset), structSize)
                        stackArgs.append(TypedOperand(op: op, tp: ebType))
                        offset = offset + 8
                    }
                }
            }
        }

        return ClassifiedParams(integerRegisterArguments: intRegArgs, floatingRegisterArguments: doubleRegArgs, stackArguments: stackArgs)
    }

    func convert(_ val: Tacky.IR.Value, _ symbolTable: [String : Assembly.Tree.Declaration], _ typedSymbolTable: SymbolTable) -> Assembly.Tree.Operand {
        switch val {
            case .Constant(let c):
                switch c {
                    case .ConstInt(let i): return .Immediate(.SignedImmediate(Int(i)))
                    case .ConstLong(let i): return .Immediate(.SignedImmediate(Int(i)))
                    case .ConstUnsignedInt(let i): return .Immediate(.UnsignedImmediate(UInt(i)))
                    case .ConstUnsignedLong(let i): return .Immediate(.UnsignedImmediate(UInt(i)))
                    case .ConstDouble(let f):
                        guard let staticVar = self.extractedDoubles[f] else {
                            print("Somehow got a constant double that has not been extracted")
                            exit(ExitCode.internalError.rawValue)
                        }
                        switch staticVar {
                            case .StaticConstant(let name, _, _):
                                return .Data(name, 0)
                            default:
                                print("static declaration of a floating point constant is somehow not a constant?")
                                exit(ExitCode.internalError.rawValue)
                        }
                    case .ConstChar(let i32): return .Immediate(.SignedImmediate(Int(i32)))
                    case .ConstUnsignedChar(let i32): return .Immediate(.SignedImmediate(Int(i32)))
                }
            case .Var(let name):
                if let _ = symbolTable[name] {
                    return .Data(name, 0)
                }
                if let x = typedSymbolTable[name] {
                    switch x.0 {
                        case .ArrayType(_, _):
                            return .PseudoMem(name, 0)
                        case .Structure(_):
                            return .PseudoMem(name, 0)
                        default: ()
                    }
                }
                return .Pseudo(name)
        }
    }

    func isScalar(_ t: Tree.AssemblyType) -> Bool {
        switch t {
            case .Byte: fallthrough
            case .Longword: fallthrough
            case .Quadword: fallthrough
            case .Double: return true
            case .ByteArray(_, _): return false
        }
    }

    let negativeZero : Assembly.Tree.Declaration = .StaticConstant(negativeZeroLabel, 16, .DoubleInit(-0.0))
    let biggestQuadword : Assembly.Tree.Declaration = .StaticConstant(biggestQuadwordLabel, 8, .DoubleInit(biggestQuadwordValue))

    class DoubleConstantExtractor {
        private var counter : Int = 1

        func makeLabel() -> String {
            let out = "L._double.constant.\(counter)"
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
                                        case .GetAddress(let src, _):
                                            extract(src, &out)
                                        case .Load(_, _): ()
                                        case .Store(let src, _):
                                            extract(src, &out)
                                        case .AddPtr(let ptr, let index, _, _):
                                            extract(ptr, &out)
                                            extract(index, &out)
                                        case .CopyToOffset(let src, _, _):
                                            extract(src, &out)
                                        case .CopyFromOffset(let base, let offset, let dst):
                                            extract(dst, &out)
                                    }
                                }
                            case .StaticVariable(_, _, _, _): ()
                            case .StaticConstant(_, _, _): ()
                        }
                    }
            }

            return out
        }
    }

    private var extractedDoubles : [Double : Tree.Declaration] = [:]

    private var labelCounter : UInt = 0
    func makeLabel() -> String {
        let out = "L._assembly.label.\(labelCounter)"
        labelCounter = labelCounter + 1
        return out
    }

    func deduceType(_ val: Tacky.IR.Value, _ symbolTable: SymbolTable, _ typeTable: SemanticAnalyzer.TypeChecker.TypeTable) -> Tree.AssemblyType {
        switch val {
            case .Constant(let c):
                switch c {
                    case .ConstUnsignedInt: fallthrough
                    case .ConstInt(_) : return .Longword
                    case .ConstUnsignedLong: fallthrough
                    case .ConstLong(_) : return .Quadword
                    case .ConstDouble(_): return .Double
                    case .ConstChar(_): fallthrough
                    case .ConstUnsignedChar(_): return .Byte
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
                    case .Pointer(_): return .Quadword
                    case .ArrayType(let tp, let count):
                        let totalSize = UInt(getTypeSize(tp, typeTable)) * count
                        if totalSize < 16 {
                            return .ByteArray(totalSize, UInt(getTypeSize(tp, typeTable)))
                        } else {
                            return .ByteArray(totalSize, 16)
                        }
                    case .Char: fallthrough
                    case .SChar: fallthrough
                    case .UChar: return .Byte
                    case .Structure(let tag):
                        if let structDef = typeTable[tag] {
                            return .ByteArray(UInt(structDef.size), UInt(structDef.alignment))
                        } else {
                            print("Unreachable case where we failed to deduce type because a struct was not defined")
                            exit(ExitCode.internalError.rawValue)
                        }
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
                    case .ConstChar(_): return true
                    case .ConstUnsignedChar(_): return false
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
                    case .Pointer(_): return false
                    case .ArrayType(_, _): return false
                    case .SChar: return true
                    case .Char: fallthrough
                    case .UChar: return false
                    case .Structure(_): return false
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

    func generate(_ instructions: [Tacky.IR.Instruction], _ symbolTable: [String : Assembly.Tree.Declaration], _ out: inout [Tree.Instruction], _ typedSymbolTable: SymbolTable, _ typeTable: SemanticAnalyzer.TypeChecker.TypeTable) {
        let zero : Assembly.Tree.Operand = .Immediate(.UnsignedImmediate(0))

        func copyBytes(_ count: UInt, _ s: Tree.Operand, _ d: Tree.Operand) {
            var sz = count
            var i: UInt = 0
            while sz >= 8 {
                let ss : Tree.Operand
                switch s {
                    case .PseudoMem(let sName, let sOff):
                        ss = .PseudoMem(sName, sOff + i)
                    case .Memory(let reg, let off):
                        ss = .Memory(reg, off + Int(i))
                    case .Immediate(_): fallthrough
                    case .Register(_): fallthrough
                    case .Pseudo(_): fallthrough
                    case .Stack(_): fallthrough
                    case .Data(_, _): fallthrough
                    case .Indexed(_, _, _):
                        print("Unexpected operand type \(s) found while processing ByteArray")
                        exit(ExitCode.internalError.rawValue)
                }
                let dd : Tree.Operand
                switch d {
                    case .PseudoMem(let sName, let sOff):
                        dd = .PseudoMem(sName, sOff + i)
                    case .Memory(let reg, let off):
                        dd = .Memory(reg, off + Int(i))
                    case .Immediate(_): fallthrough
                    case .Register(_): fallthrough
                    case .Pseudo(_): fallthrough
                    case .Stack(_): fallthrough
                    case .Data(_, _): fallthrough
                    case .Indexed(_, _, _):
                        print("Unexpected operand type \(d) found while processing ByteArray")
                        exit(ExitCode.internalError.rawValue)
                }
                out.append(.Mov(.Quadword, ss, dd))

                sz = sz - 8
                i = i + 8
            }
            while sz >= 4 {
                let ss : Tree.Operand
                switch s {
                    case .PseudoMem(let sName, let sOff):
                        ss = .PseudoMem(sName, sOff + i)
                    case .Memory(let reg, let off):
                        ss = .Memory(reg, off + Int(i))
                    case .Immediate(_): fallthrough
                    case .Register(_): fallthrough
                    case .Pseudo(_): fallthrough
                    case .Stack(_): fallthrough
                    case .Data(_, _): fallthrough
                    case .Indexed(_, _, _):
                        print("Unexpected operand type \(s) found while processing ByteArray")
                        exit(ExitCode.internalError.rawValue)
                }
                let dd : Tree.Operand
                switch d {
                    case .PseudoMem(let sName, let sOff):
                        dd = .PseudoMem(sName, sOff + i)
                    case .Memory(let reg, let off):
                        dd = .Memory(reg, off + Int(i))
                    case .Immediate(_): fallthrough
                    case .Register(_): fallthrough
                    case .Pseudo(_): fallthrough
                    case .Stack(_): fallthrough
                    case .Data(_, _): fallthrough
                    case .Indexed(_, _, _):
                        print("Unexpected operand type \(d) found while processing ByteArray")
                        exit(ExitCode.internalError.rawValue)
                }
                out.append(.Mov(.Longword, ss, dd))

                sz = sz - 4
                i = i + 4
            }
            while sz >= 1 {
                let ss : Tree.Operand
                switch s {
                    case .PseudoMem(let sName, let sOff):
                        ss = .PseudoMem(sName, sOff + i)
                    case .Memory(let reg, let off):
                        ss = .Memory(reg, off + Int(i))
                    case .Immediate(_): fallthrough
                    case .Register(_): fallthrough
                    case .Pseudo(_): fallthrough
                    case .Stack(_): fallthrough
                    case .Data(_, _): fallthrough
                    case .Indexed(_, _, _):
                        print("Unexpected operand type \(s) found while processing ByteArray")
                        exit(ExitCode.internalError.rawValue)
                }
                let dd : Tree.Operand
                switch d {
                    case .PseudoMem(let sName, let sOff):
                        dd = .PseudoMem(sName, sOff + i)
                    case .Memory(let reg, let off):
                        dd = .Memory(reg, off + Int(i))
                    case .Immediate(_): fallthrough
                    case .Register(_): fallthrough
                    case .Pseudo(_): fallthrough
                    case .Stack(_): fallthrough
                    case .Data(_, _): fallthrough
                    case .Indexed(_, _, _):
                        print("Unexpected operand type \(d) found while processing ByteArray")
                        exit(ExitCode.internalError.rawValue)
                }
                out.append(.Mov(.Byte, ss, dd))

                sz = sz - 1
                i = i + 1
            }
        }

        for instr in instructions {
            switch instr {
                case .Return(let val):
                    if let v = val {
                        let tp = deduceType(v, typedSymbolTable, typeTable)
                        out.append(.Mov(tp, convert(v, symbolTable, typedSymbolTable), tp == .Double ? .Register(.XMM0) : .Register(.AX)))
                    }
                    out.append(.Ret)
                case .Unary(let op, let src, let dst):
                    let srcType = deduceType(src, typedSymbolTable, typeTable)
                    let isFlop = (srcType == .Double)
                    if op == .Not {
                        if isFlop {
                            out.append(.Binary(.Xor, .Double, .Register(.XMM0), .Register(.XMM0)))
                            out.append(.Cmp(.Double, .Register(.XMM0), convert(src, symbolTable, typedSymbolTable)))
                        } else {
                            out.append(.Cmp(srcType, .Immediate(.UnsignedImmediate(0)), convert(src, symbolTable, typedSymbolTable)))
                        }
                        out.append(.Mov(srcType, .Immediate(.UnsignedImmediate(0)), convert(dst, symbolTable, typedSymbolTable)))
                        out.append(.SetCC(.E, convert(dst, symbolTable, typedSymbolTable)))
                    } else {
                        if isFlop && op == .Negate {
                            out.append(.Mov(srcType, convert(src, symbolTable, typedSymbolTable), convert(dst, symbolTable, typedSymbolTable)))
                            out.append(.Binary(.Xor, srcType, .Data(negativeZeroLabel, 0), convert(dst, symbolTable, typedSymbolTable)))
                        } else {
                            out.append(.Mov(srcType, convert(src, symbolTable, typedSymbolTable), convert(dst, symbolTable, typedSymbolTable)))
                            out.append(.Unary(convert(op), srcType, convert(dst, symbolTable, typedSymbolTable)))
                        }
                    }
                case .Binary(let op, let src1, let src2, let dst):
                    let src1Conv = convert(src1, symbolTable, typedSymbolTable)
                    let src2Conv = convert(src2, symbolTable, typedSymbolTable)
                    let dstConv = convert(dst, symbolTable, typedSymbolTable)
                    let srcType = deduceType(src1, typedSymbolTable, typeTable)
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
                                    out.append(.Mov(srcType, .Immediate(.UnsignedImmediate(0)), .Register(.DX)))
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
                                out.append(.Mov(srcType, zero, .Register(.DX)))
                                out.append(.Div(srcType, src2Conv))
                                out.append(.Mov(srcType, .Register(.DX), dstConv))
                            }
                        case .Equal:
                            out.append(.Cmp(srcType, src2Conv, src1Conv))
                            out.append(.Mov(isFlop ? .Longword : srcType, zero, dstConv))
                            out.append(.SetCC(.E, dstConv))
                        case .NotEqual:
                            out.append(.Cmp(srcType, src2Conv, src1Conv))
                            out.append(.Mov(isFlop ? .Longword : srcType, zero, dstConv))
                            out.append(.SetCC(.NE, dstConv))
                        case .LessThan:
                            out.append(.Cmp(srcType, src2Conv, src1Conv))
                            out.append(.Mov(isFlop ? .Longword : srcType, zero, dstConv))
                            out.append(.SetCC(isFlop ? .B : (signedOp ? .L : .B), dstConv))
                        case .LessOrEqual:
                            out.append(.Cmp(srcType, src2Conv, src1Conv))
                            out.append(.Mov(isFlop ? .Longword : srcType, zero, dstConv))
                            out.append(.SetCC(isFlop ? .BE : signedOp ? .LE : .BE, dstConv))
                        case .GreaterThan: 
                            out.append(.Cmp(srcType, src2Conv, src1Conv))
                            out.append(.Mov(isFlop ? .Longword : srcType, zero, dstConv))
                            out.append(.SetCC(isFlop ? .A : signedOp ? .G : .A, dstConv))
                        case .GreaterOrEqual:
                            out.append(.Cmp(srcType, src2Conv, src1Conv))
                            out.append(.Mov(isFlop ? .Longword : srcType, zero, dstConv))
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
                    // how many bytes are we moving?
                    let srcType = deduceType(src, typedSymbolTable, typeTable)
                    let s = convert(src, symbolTable, typedSymbolTable)
                    let d = convert(dst, symbolTable, typedSymbolTable)
                    switch srcType {
                        case .Byte: fallthrough
                        case .Longword: fallthrough
                        case .Quadword: fallthrough
                        case .Double:
                            // up to 8; one instruction
                            out.append(.Mov(srcType, s, d))
                        case .ByteArray(let size, _):
                            // potentially a lot, do it cleverly
                            copyBytes(size, s, d)
                    }
                case .Jump(let label):
                    out.append(.Jmp(label))
                case .JumpIfZero(let val, let label):
                    let valType = deduceType(val, typedSymbolTable, typeTable)
                    let isFlop = (valType == .Double)
                    if isFlop {
                        out.append(.Binary(.Xor, .Double, .Register(.XMM0), .Register(.XMM0)))
                        out.append(.Cmp(valType, convert(val, symbolTable, typedSymbolTable), .Register(.XMM0)))
                    } else {
                        out.append(.Cmp(valType, zero, convert(val, symbolTable, typedSymbolTable)))
                    }
                    out.append(.JmpCC(.E, label))
                case .JumpIfNotZero(let val, let label):
                    let valType = deduceType(val, typedSymbolTable, typeTable)
                    let isFlop = (valType == .Double)
                    if isFlop {
                        out.append(.Binary(.Xor, .Double, .Register(.XMM0), .Register(.XMM0)))
                        out.append(.Cmp(valType, convert(val, symbolTable, typedSymbolTable), .Register(.XMM0)))
                    } else {
                        out.append(.Cmp(valType, zero, convert(val, symbolTable, typedSymbolTable)))
                    }
                    out.append(.JmpCC(.NE, label))
                case .Label(let name):
                    out.append(.Label(name))
                case .Call(let name, let params, let result):
                    // save context (currently not an issue because we only use scratch registers)
                    // move parameters into place

                    // 1. use the helper function to classify incoming parameters
                    let paramClasses = classifyParams(params, /* TODO */ false, symbolTable, typedSymbolTable, typeTable)
                    // 2. assign to registers/stack
                    let fpRegisterTargets : [Tree.Register] = [.XMM0, .XMM1, .XMM2, .XMM3, .XMM4, .XMM5, .XMM6, .XMM7]
                    let intRegisterTargets : [Tree.Register] = [.DI, .SI, .DX, .CX, .R8, .R9] // TODO: DI
                    for (fpReg, fpParm) in zip(fpRegisterTargets, paramClasses.floatingRegisterArguments) {
                        out.append(.Mov(fpParm.tp, fpParm.op, .Register(fpReg)))
                    }
                    for (intReg, intParm) in zip(intRegisterTargets, paramClasses.integerRegisterArguments) {
                        out.append(.Mov(intParm.tp, intParm.op, .Register(intReg)))
                    }

                    // the System V ABI requires the stack to be 16-byte aligned
                    let stackPadding = paramClasses.stackArguments.count % 2 == 0 ? 0 : 8

                    if stackPadding != 0 {
                        out.append(.AllocateStack(stackPadding))
                    }

                    var stackParams = paramClasses.stackArguments
                    stackParams.reverse()
                    for p in stackParams {
                        var shouldPushStraight : Bool = p.tp == .Quadword
                        switch p.op {
                            case .Register(_): fallthrough
                            case .Immediate(_):
                                shouldPushStraight = true
                            default: ()
                        }
                        if shouldPushStraight {
                            out.append(.Push(p.op))
                        } else {
                            out.append(.Mov(.Longword, p.op, .Register(.AX)))
                            out.append(.Push(.Register(.AX)))
                        }
                    }
                    // call the function
                    out.append(.Call(name))

                    let bytesToRemove = 8 * stackParams.count + stackPadding
                    if bytesToRemove != 0 {
                        out.append(.DeallocateStack(bytesToRemove))
                    }

                    // move the result
                    if let rslt = result {
                        out.append(.Mov(
                            deduceType(rslt, typedSymbolTable, typeTable),
                            .Register(.AX),
                            convert(rslt, symbolTable, typedSymbolTable)
                        ))
                    }
                case .SignExtend(let src, let dst):
                    let cSrc = convert(src, symbolTable, typedSymbolTable)
                    let cDst = convert(dst, symbolTable, typedSymbolTable)
                    let srcType = deduceType(src, typedSymbolTable, typeTable)
                    let dstType = deduceType(dst, typedSymbolTable, typeTable)
                    out.append(.Movsx(srcType, dstType, cSrc, cDst))
                case .Truncate(let src, let dst):
                    out.append(.Mov(
                        deduceType(dst, typedSymbolTable, typeTable),
                        convert(src, symbolTable, typedSymbolTable),
                        convert(dst, symbolTable, typedSymbolTable)
                    ))
                case .ZeroExtend(let src, let dst):
                    let cSrc = convert(src, symbolTable, typedSymbolTable)
                    let cDst = convert(dst, symbolTable, typedSymbolTable)
                    let srcType = deduceType(src, typedSymbolTable, typeTable)
                    let dstType = deduceType(dst, typedSymbolTable, typeTable)
                    out.append(.Movzx(srcType, dstType, cSrc, cDst))
                case .DoubleToInt(let src, let dst):
                    let dType = deduceType(dst, typedSymbolTable, typeTable)
                    let cSrc = convert(src, symbolTable, typedSymbolTable)
                    let cDst = convert(dst, symbolTable, typedSymbolTable)
                    if dType == .Byte {
                        out.append(.Cvttsd2si(.Longword, cSrc, .Register(.AX)))
                        out.append(.Mov(.Byte, .Register(.AX), cDst))
                    } else {
                        out.append(.Cvttsd2si(dType, cSrc, cDst))
                    }
                case .DoubleToUInt(let src, let dst):
                    // not straightforward
                    let dType = deduceType(dst, typedSymbolTable, typeTable)
                    // if we're dealing with one of those 4-byte integers, then we...
                    if dType == .Longword {
                        // convert to a quadword, then truncate
                        out.append(.Cvttsd2si(.Quadword, convert(src, symbolTable, typedSymbolTable), .Register(.AX)))
                        out.append(.Mov(.Longword, .Register(.AX), convert(dst, symbolTable, typedSymbolTable)))
                    } else if dType == .Byte {
                        // convert to a quadword, then truncate
                        out.append(.Cvttsd2si(.Quadword, convert(src, symbolTable, typedSymbolTable), .Register(.AX)))
                        out.append(.Mov(.Byte, .Register(.AX), convert(dst, symbolTable, typedSymbolTable)))
                    } else {
                        // otherwise, oh my god...
                        // check if our value fits into a quadword
                        out.append(.Cmp(.Double, .Data(biggestQuadwordLabel, 0), convert(src, symbolTable, typedSymbolTable)))
                        let outOfRangeLabel = makeLabel()
                        out.append(.JmpCC(.AE, outOfRangeLabel))
                        // if it fits into a signed quadword, convert to a signed quadword
                        out.append(.Cvttsd2si(.Quadword, convert(src, symbolTable, typedSymbolTable), convert(dst, symbolTable, typedSymbolTable)))
                        let endLabel = makeLabel()
                        out.append(.Jmp(endLabel))
                        // if it doesn't fit into a signed quadword
                        out.append(.Label(outOfRangeLabel))
                        // subtract LONG_MAX + 1
                        out.append(.Mov(.Double, convert(src, symbolTable, typedSymbolTable), .Register(.XMM1)))
                        out.append(.Binary(.Sub, .Double, .Data(biggestQuadwordLabel, 0), .Register(.XMM1)))
                        // then convert to a signed long
                        out.append(.Cvttsd2si(.Quadword, .Register(.XMM1), convert(dst, symbolTable, typedSymbolTable)))
                        // then add LONG_MAX + 1 back
                        out.append(.Binary(.Add, .Quadword, .Immediate(.UnsignedImmediate(UInt(longMaxPlusOne))), convert(dst, symbolTable, typedSymbolTable)))
                        out.append(.Label(endLabel))
                    }
                case .IntToDouble(let src, let dst):
                    let sType = deduceType(src, typedSymbolTable, typeTable)
                    if sType == .Byte {
                        out.append(.Movsx(.Byte, .Longword, convert(src, symbolTable, typedSymbolTable), .Register(.AX)))
                        out.append(.Cvtsi2sd(.Longword, .Register(.AX), convert(dst, symbolTable, typedSymbolTable)))
                    } else {
                        // straightforward case, done by one instruction
                        out.append(.Cvtsi2sd(deduceType(dst, typedSymbolTable, typeTable), convert(src, symbolTable, typedSymbolTable), convert(dst, symbolTable, typedSymbolTable)))
                    }
                case .UIntToDouble(let src, let dst):
                    // not straightforward
                    // if we're dealing with a 4-byte integer
                    let sType = deduceType(src, typedSymbolTable, typeTable)
                    let cSrc = convert(src, symbolTable, typedSymbolTable)
                    if sType == .Longword {
                        // zero extend it to a quadword
                        out.append(.Movzx(.Longword, .Quadword, cSrc, .Register(.AX)))
                        // then convert it
                        out.append(.Cvtsi2sd(.Quadword, .Register(.AX), convert(dst, symbolTable, typedSymbolTable)))
                    } else if sType == .Byte {
                        out.append(.Movzx(.Byte, .Longword, cSrc, .Register(.AX)))
                        out.append(.Cvtsi2sd(.Longword, .Register(.AX), convert(dst, symbolTable, typedSymbolTable)))
                    } else {
                        // check if the value is positive (fits into an unsigned value)
                        out.append(.Cmp(.Quadword, zero, convert(src, symbolTable, typedSymbolTable)))
                        let outOfRangeLabel = makeLabel()
                        out.append(.JmpCC(.L, outOfRangeLabel))
                        // if the value is positive, go ahead and use the native instruction
                        out.append(.Cvtsi2sd(.Quadword, convert(src, symbolTable, typedSymbolTable), convert(dst, symbolTable, typedSymbolTable)))
                        let endLabel = makeLabel()
                        out.append(.Jmp(endLabel))
                        // if the value can not be represented as an unsigned integer
                        out.append(.Label(outOfRangeLabel))
                        // cut it in half, preserving oddness
                        out.append(.Mov(.Quadword, convert(src, symbolTable, typedSymbolTable), .Register(.AX)))
                        out.append(.Mov(.Quadword, .Register(.AX), .Register(.DX)))
                        out.append(.Unary(.Shr, .Quadword, .Register(.DX)))
                        out.append(.Binary(.And, .Quadword, .Immediate(.UnsignedImmediate(1)), .Register(.AX)))
                        out.append(.Binary(.Or, .Quadword, .Register(.AX), .Register(.DX)))
                        // convert
                        out.append(.Cvtsi2sd(.Quadword, .Register(.DX), convert(dst, symbolTable, typedSymbolTable)))
                        // double it
                        out.append(.Binary(.Add, .Double, convert(dst, symbolTable, typedSymbolTable), convert(dst, symbolTable, typedSymbolTable)))
                        out.append(.Label(endLabel))
                    }
                case .GetAddress(let src, let dst):
                    out.append(.Lea(convert(src, symbolTable, typedSymbolTable), convert(dst, symbolTable, typedSymbolTable)))
                case .Load(let ptr, let dst):
                    let dstType = deduceType(dst, typedSymbolTable, typeTable)
                    let p = convert(ptr, symbolTable, typedSymbolTable)
                    let d = convert(dst, symbolTable, typedSymbolTable)
                    out.append(.Mov(.Quadword, p, .Register(.AX)))
                    switch dstType {
                        case .Byte: fallthrough
                        case .Longword: fallthrough
                        case .Quadword: fallthrough
                        case .Double:
                            out.append(.Mov(dstType, .Memory(.AX, 0), d))
                        case .ByteArray(let size, _):
                            copyBytes(size, .Memory(.AX, 0), d)
                    }
                case .Store(let src, let ptr):
                    let srcType = deduceType(src, typedSymbolTable, typeTable)
                    let s = convert(src, symbolTable, typedSymbolTable)
                    let p = convert(ptr, symbolTable, typedSymbolTable)
                    out.append(.Mov(.Quadword, p, .Register(.AX)))
                    switch srcType {
                        case .Byte: fallthrough
                        case .Longword: fallthrough
                        case .Quadword: fallthrough
                        case .Double:
                            out.append(.Mov(srcType, s, .Memory(.AX, 0)))
                        case .ByteArray(let size, _):
                            copyBytes(size, s, .Memory(.AX, 0))
                    }
                case .AddPtr(let ptr, let index, let scale, let dst):
                    if [1, 2, 4, 8].contains(scale) {
                        out.append(.Mov(.Quadword, convert(ptr, symbolTable, typedSymbolTable), .Register(.AX)))
                        out.append(.Mov(.Quadword, convert(index, symbolTable, typedSymbolTable), .Register(.DX)))
                        out.append(.Lea(.Indexed(.AX, .DX, scale), convert(dst, symbolTable, typedSymbolTable)))
                    } else {
                        out.append(.Mov(.Quadword, convert(ptr, symbolTable, typedSymbolTable), .Register(.AX)))
                        out.append(.Mov(.Quadword, convert(index, symbolTable, typedSymbolTable), .Register(.DX)))
                        out.append(.Binary(.Mult, .Quadword, .Immediate(.UnsignedImmediate(scale)), .Register(.DX)))
                        out.append(.Lea(.Indexed(.AX, .DX, 1), convert(dst, symbolTable, typedSymbolTable)))
                    }
                    // TODO: we could technically save an instruction if we determined that index was constant; heck it,
                    // make the machine work
                case .CopyToOffset(let src, let identifier, let offset):
                    let srcType = deduceType(src, typedSymbolTable, typeTable)
                    let s = convert(src, symbolTable, typedSymbolTable)
                    switch srcType {
                        case .Byte: fallthrough
                        case .Longword: fallthrough
                        case .Quadword: fallthrough
                        case .Double:
                            out.append(.Mov(srcType, s, .PseudoMem(identifier, offset)))
                        case .ByteArray(let size, _):
                            copyBytes(size, s, .PseudoMem(identifier, offset))
                    }
                case .CopyFromOffset(let base, let offset, let dst):
                    let dstType = deduceType(dst, typedSymbolTable, typeTable)
                    let d = convert(dst, symbolTable, typedSymbolTable)
                    switch dstType {
                        case .Byte: fallthrough
                        case .Longword: fallthrough
                        case .Quadword: fallthrough
                        case .Double:
                            out.append(.Mov(dstType, .PseudoMem(base, UInt(offset)), d))
                        case .ByteArray(let size, _):
                            copyBytes(size, .PseudoMem(base, UInt(offset)), d)
                    }
            }
        }
    }

    func generate(_ pls: Tacky.IR.Declaration, _ symbolTable: [String : Assembly.Tree.Declaration], _ typedSymbolTable: SymbolTable, _ typeTable: SemanticAnalyzer.TypeChecker.TypeTable) -> Tree.Declaration {
        switch pls {
            case .Function(let name, let isGlobal, let params, let instrs):
                var out : [Tree.Instruction] = []

                var fpRegisterTargets : [Tree.Register] = [.XMM0, .XMM1, .XMM2, .XMM3, .XMM4, .XMM5, .XMM6, .XMM7]
                var intRegisterTargets : [Tree.Register] = [.DI, .SI, .DX, .CX, .R8, .R9]
                var stackParams : [String] = []
                for p in params {
                    let tp = deduceType(.Var(p), typedSymbolTable, typeTable)
                    // if we're looking at a floating point value AND we have floating point registers left unallocated
                    if tp == .Double && !fpRegisterTargets.isEmpty {
                        let source = fpRegisterTargets.removeFirst()
                        out.append(.Mov(tp, .Register(source), .Pseudo(p)))
                    // if we're NOT looking at a floating point value AND we have non-floating point registers left unallocated
                    } else if tp != .Double && !intRegisterTargets.isEmpty {
                        let source = intRegisterTargets.removeFirst()
                        out.append(.Mov(tp, .Register(source), .Pseudo(p)))
                    // we ran out of registers for this type of parameter
                    } else {
                        // stack time!
                        stackParams.append(p)
                    }
                }
                stackParams.reverse()
                var counter = 0
                for p in stackParams {
                    out.append(.Mov(deduceType(.Var(p), typedSymbolTable, typeTable), .Stack(16 + counter), .Pseudo(p)))
                    counter = counter + 8
                }
                generate(instrs, symbolTable, &out, typedSymbolTable, typeTable)
                return .Function(name, isGlobal, out)
            case .StaticVariable(_, _, _, _):
                print("As yet unhandled global variable caught while generating assembly")
                exit(ExitCode.internalError.rawValue)
            case .StaticConstant(_, _, _):
                print("As-yet-unhanlded static constant caught while generating assembly")
                exit(ExitCode.internalError.rawValue)
        }
    }

    func generate(program: Tacky.IR.Program, symbolTable: [Tacky.IR.Declaration], typedSymbolTable: SymbolTable, typeTable: SemanticAnalyzer.TypeChecker.TypeTable) -> (Tree.Program, BackendSymbolTable) {
        var assemblyDecls : [Assembly.Tree.Declaration] = []
        var internalSymbolTable : [String : Assembly.Tree.Declaration] = [:]
        for tackyDef in symbolTable {
            switch tackyDef {
                case .StaticVariable(let name, let isGlobal, let tp, let initValue):
                    var alignment: Int = 0
                    switch tp {
                        case .Int: alignment = 4
                        case .UnsignedInt: alignment = 4
                        case .Long: alignment = 8
                        case .UnsignedLong: alignment = 8
                        case .Void:
                            print("UNREACHABLE VOID VARIABLE TYPE")
                            exit(ExitCode.internalError.rawValue)
                        case .Double: alignment = 8
                        case .Pointer(_): alignment = 8
                        case .FunType(_, _):
                            print("UNREACHABLE FUN TYPE VARIABLE TYPE")
                            exit(ExitCode.internalError.rawValue)
                        case .ArrayType(let nestedType, let size):
                            if UInt(getTypeSize(convertCTypeToCheckerType(nestedType), typeTable)) * size >= 16 {
                                alignment = 16
                            } else {
                                alignment = getTypeSize(convertCTypeToCheckerType(nestedType), typeTable)
                            }
                        case .Char: fallthrough
                        case .SChar: fallthrough
                        case .UChar: alignment = 1
                        case .Structure(let tag):
                            print("As-yet-unhandled structure type found while generating assembly")
                            exit(ExitCode.internalError.rawValue)
                    }
                    let assemblyEntry : Tree.Declaration = .StaticVariable(name, isGlobal, alignment, initValue)
                    assemblyDecls.append(assemblyEntry)
                    internalSymbolTable[name] = assemblyEntry
                case .StaticConstant(let name, let tp, let initVal):
                    var alignment: Int = 0
                    switch tp {
                        case .Int: alignment = 4
                        case .UnsignedInt: alignment = 4
                        case .Long: alignment = 8
                        case .UnsignedLong: alignment = 8
                        case .Void:
                            print("UNREACHABLE VOID VARIABLE TYPE")
                            exit(ExitCode.internalError.rawValue)
                        case .Double: alignment = 8
                        case .Pointer(_): alignment = 8
                        case .FunType(_, _):
                            print("UNREACHABLE FUN TYPE VARIABLE TYPE")
                            exit(ExitCode.internalError.rawValue)
                        case .ArrayType(let nestedType, let size):
                            if UInt(getTypeSize(convertCTypeToCheckerType(nestedType), typeTable)) * size >= 16 {
                                alignment = 16
                            } else {
                                alignment = getTypeSize(convertCTypeToCheckerType(nestedType), typeTable)
                            }
                        case .Char: fallthrough
                        case .SChar: fallthrough
                        case .UChar: alignment = 1
                        case .Structure(let tag):
                            print("As-yet-unhandled structure type found while generating assembly")
                            exit(ExitCode.internalError.rawValue)
                    }
                    let asmEntry : Tree.Declaration = .StaticConstant(name, alignment, initVal)
                    assemblyDecls.append(asmEntry)
                    internalSymbolTable[name] = asmEntry
                case .Function(_, _, _, _): ()
            }
        }
        self.extractedDoubles = DoubleConstantExtractor().extract(program)
        for (_, decl) in self.extractedDoubles {
            assemblyDecls.append(decl)
        }
        // constant constant
        assemblyDecls.append(negativeZero)
        assemblyDecls.append(biggestQuadword)
        let out: Tree.Program
        switch program {
            case .Statement(let declarations):
                for d in declarations {
                    assemblyDecls.append(generate(d, internalSymbolTable, typedSymbolTable, typeTable))
                }
                out = .Statement(assemblyDecls)
        }

        var asmSymTab : BackendSymbolTable = .init()
        for (name, entry) in typedSymbolTable {
            let (checkerType, attrs) = entry
            switch checkerType {
                case .Char: fallthrough
                case .SChar: fallthrough
                case .UChar: fallthrough
                case .Int: fallthrough
                case .UnsignedInt: fallthrough
                case .Long: fallthrough
                case .UnsignedLong: fallthrough
                case .Double: fallthrough
                case .Pointer(_):
                    let asmType : Tree.AssemblyType
                    switch checkerType {
                        case .Char: fallthrough
                        case .SChar: fallthrough
                        case .UChar: asmType = .Byte
                        case .Int: fallthrough
                        case .UnsignedInt: asmType = .Longword
                        case .Long: fallthrough
                        case .UnsignedLong: asmType = .Quadword
                        case .Double: asmType = .Double
                        case .Void:
                            print("UNREACHABLE VOID")
                            exit(ExitCode.internalError.rawValue)
                        case .Pointer(_): asmType = .Quadword
                        case .Function(_, _):
                            print("UNREACHABLE FUNC")
                            exit(ExitCode.internalError.rawValue)
                        case .ArrayType(_, _):
                            print("UNREACHABLE ARRAY")
                            exit(ExitCode.internalError.rawValue)
                        case .Structure(_):
                            print("Unreachable STRUCTURE")
                            exit(ExitCode.internalError.rawValue)
                    }
                    let isStatic: Bool
                    switch attrs {
                        case .StaticAttr(_, _):
                            isStatic = true
                        case .LocalAttr:
                            isStatic = false
                        case .ConstantAttr(_):
                            isStatic = true
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
                case .ArrayType(let nestedType, let count):
                    let tSize = UInt(getTypeSize(nestedType, typeTable))
                    let aSize = UInt(tSize) * count
                    let alignment: UInt = aSize >= 16 ? 16 : tSize
                    var isGlobal = false
                    switch attrs {
                        case .StaticAttr(_, _):
                            isGlobal = true
                        case .LocalAttr:
                            isGlobal = false
                        case .ConstantAttr(_):
                            isGlobal = true
                        case .FunAttr(_, _):
                            print("UNREACHABLE: FUN ATTR FOR ARRAY TYPE")
                            exit(ExitCode.internalError.rawValue)
                    }
                    asmSymTab[name] = .ObjEntry(.ByteArray(UInt(getTypeSize(nestedType, typeTable)) * count, alignment), isGlobal)
                case .Structure(let tag):
                    print("As-yet-unhandled structure found while generating assembly")
                    exit(ExitCode.internalError.rawValue)
            }
        }

        return (out, asmSymTab)
    }

    func replacePseudoRegisters(_ op: Tree.Operand, _ stackSlotCounter: inout Int, _ nameStackMapping: inout [String: Int], _ symbolTable : SymbolTable, _ typeTable: SemanticAnalyzer.TypeChecker.TypeTable) -> Tree.Operand {
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
                    case .Char: fallthrough
                    case .SChar: fallthrough
                    case .UChar: width = 1
                    case .Int: width = 4
                    case .UnsignedInt: width = 4
                    case .Long: width = 8
                    case .UnsignedLong: width = 8
                    case .Double: width = 8
                    case .Pointer(_): width = 8
                    case .Structure(_):
                        print("As-yet-unhandled attempt to get width of structure when replacing pseudo registers")
                        exit(ExitCode.internalError.rawValue)
                    case .ArrayType(_, _):
                        print("Unreachable case getting the width of an array in the assembler")
                        exit(ExitCode.internalError.rawValue)
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
            case .Memory(_, _):
                return op
            case .PseudoMem(let name, let offset):
                guard let (tp, attr) = symbolTable[name] else {
                    print("Impossible situation where pseudo mem \(name) is not in the symbol table")
                    exit(ExitCode.internalError.rawValue)
                }

                switch tp {
                    case .ArrayType(_, _): ()
                    default:
                        print("Impossible situation reached where pseudo mem operand is not an array (\(tp), \(name))")
                        exit(ExitCode.internalError.rawValue)
                }

                switch attr {
                    case .StaticAttr(_, _): return .Data(name, 0)
                    default: ()
                }

                if let slot = nameStackMapping[name] {
                    return .Stack(-slot + Int(offset))
                }

                let width = getTypeSize(tp, typeTable)

                var tmp = stackSlotCounter + width
                if tmp % width != 0 {
                    // must be aligned
                    tmp = tmp + (tmp % width)
                }
                stackSlotCounter = tmp
                nameStackMapping[name] = stackSlotCounter
                return .Stack(-stackSlotCounter + Int(offset))
            case .Indexed(_, _, _):
                return op
        }
    }

    func replacePseudoRegisters(_ instructions: [Tree.Instruction], _ symbolTable : SymbolTable, _ typeTable: SemanticAnalyzer.TypeChecker.TypeTable) -> [Tree.Instruction] {
        var out : [Tree.Instruction] = []

        var stackSlotCounter : Int = 0
        var nameStackMapping : [String: Int] = [:]

        for instr: Assembly.Tree.Instruction in instructions {
            switch instr {
                case .AllocateStack(_):
                    out.append(instr)
                case .Mov(let tp, let op1, let op2):
                    out.append(.Mov(tp, replacePseudoRegisters(op1, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable),
                                    replacePseudoRegisters(op2, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable)))
                case .Ret:
                    out.append(instr)
                case .Unary(let unOp, let tp, let op):
                    out.append(.Unary(unOp, tp, replacePseudoRegisters(op, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable)))
                case .Binary(let binOp, let tp, let left, let right):
                    out.append(.Binary(binOp, tp, replacePseudoRegisters(left, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable), replacePseudoRegisters(right, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable)))
                case .Cdq(let tp): out.append(.Cdq(tp))
                case .Idiv(let tp, let op): out.append(.Idiv(tp, replacePseudoRegisters(op, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable)))
                case .Div(let tp, let op): out.append(.Div(tp, replacePseudoRegisters(op, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable)))
                case .Cmp(let tp, let left, let right):
                    out.append(.Cmp(tp, replacePseudoRegisters(left, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable),
                                    replacePseudoRegisters(right, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable)))
                case .Jmp(_): out.append(instr)
                case .JmpCC(_, _): out.append(instr)
                case .SetCC(let cc, let op):
                    out.append(.SetCC(cc, replacePseudoRegisters(op, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable)))
                case .Label(_): out.append(instr)
                case .Call(_): out.append(instr)
                case .DeallocateStack(_): out.append(instr)
                case .Push(let op):
                    out.append(.Push(replacePseudoRegisters(op, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable)))
                case .Movsx(let srcType, let dstType, let src, let dst):
                    out.append(.Movsx(
                        srcType,
                        dstType,
                        replacePseudoRegisters(src, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable),
                        replacePseudoRegisters(dst, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable)
                    ))
                case .Movzx(let srcType, let dstType, let src, let dst):
                    out.append(.Movzx(
                        srcType,
                        dstType,
                        replacePseudoRegisters(src, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable),
                        replacePseudoRegisters(dst, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable)
                    ))
                case .Cvttsd2si(let tp, let src, let dst):
                    out.append(.Cvttsd2si(
                        tp,
                        replacePseudoRegisters(src, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable),
                        replacePseudoRegisters(dst, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable)
                    ))
                case .Cvtsi2sd(let tp, let src, let dst):
                    out.append(.Cvtsi2sd(
                        tp,
                        replacePseudoRegisters(src, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable),
                        replacePseudoRegisters(dst, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable)
                    ))
                case .Lea(let src, let dst):
                    out.append(.Lea(
                        replacePseudoRegisters(src, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable),
                        replacePseudoRegisters(dst, &stackSlotCounter, &nameStackMapping, symbolTable, typeTable)
                    ))
            }
        }

        out.insert(.AllocateStack(stackSlotCounter), at: 0)

        return out
    }

    func replacePseudoRegisters(_ pls: Tree.Declaration, _ symbolTable : SymbolTable, _ typeTable: SemanticAnalyzer.TypeChecker.TypeTable) -> Tree.Declaration {
        switch pls {
            case .Function(let name, let isGlobal, let instrs):
                return .Function(name, isGlobal, replacePseudoRegisters(instrs, symbolTable, typeTable))
            case .StaticVariable(let name, let isGlobal, let alignment, let initVal):
                return .StaticVariable(name, isGlobal, alignment, initVal)
            case .StaticConstant(let name, let alignment, let initVal):
                return .StaticConstant(name, alignment, initVal)
        }
    }

    func replacePseudoRegisters(program: Tree.Program, _ symbolTable : SymbolTable, _ typeTable: SemanticAnalyzer.TypeChecker.TypeTable) -> Tree.Program {
        switch program {
            case .Statement(let declarations):
                return .Statement(declarations.map{ replacePseudoRegisters($0, symbolTable, typeTable) })
        }
    }

    func fixUpMoves(_ instrs: [Tree.Instruction]) -> [Tree.Instruction] {
        var out : [Tree.Instruction] = []
        for instr in instrs {
            switch instr {
                case .AllocateStack(_): out.append(instr)
                case .Mov(let tp, let opSrc, let opDst):
                    let scratchRegister : Assembly.Tree.Operand = .Register(tp == .Double ? .XMM14 : .R10)
                    switch opSrc {
                        case .Stack(_): fallthrough
                        case .Memory(_, _): fallthrough
                        case .Data(_):
                            switch opDst {
                                case .Stack(_): fallthrough
                                case .Memory(_, _): fallthrough
                                case .Data(_):
                                    out.append(.Mov(tp, opSrc, scratchRegister))
                                    out.append(.Mov(tp, scratchRegister, opDst))
                                default:
                                    out.append(instr)
                            }
                        default:
                            out.append(instr)
                    }
                case .Ret: out.append(instr)
                case .Unary(_, _, _): out.append(instr)
                case .Binary(let op, let tp, let src, let dst):
                    if tp == .Double {
                        switch op {
                            case .Add: fallthrough
                            case .Sub: fallthrough
                            case .Mult: fallthrough
                            case .DivDouble:
                                switch dst {
                                    case .Data(_): fallthrough
                                    case .Memory(_, _): fallthrough
                                    case .Stack(_):
                                        out.append(.Binary(op, tp, src, .Register(.XMM15)))
                                        out.append(.Mov(tp, .Register(.XMM15), dst))
                                    case .Register(_): out.append(instr)
                                    case .Pseudo(let name):
                                        print("Unreachable: pseudo slot \(name) survived pseudo replacement")
                                        exit(ExitCode.internalError.rawValue)
                                    case .Immediate(_):
                                        print("Unreachable: immeditate was destination of floating point binary operation: \(op)")
                                        exit(ExitCode.internalError.rawValue)
                                    case .PseudoMem(_, _):
                                        print("As-yet-unhandled pseudo mem in binary operation")
                                        exit(ExitCode.internalError.rawValue)
                                    case .Indexed(_, _, _):
                                        print("As-yet-unhandled indexed mem in binary operation")
                                        exit(ExitCode.internalError.rawValue)
                                }
                            // xorpd also has requirements but we generate all xorpd instructions directly so we know
                            // they're satisfied; other than that, we don't do bitwise operations on floating point values
                            default: out.append(instr)
                        }
                    } else {
                        switch op {
                            case .Add: fallthrough
                            case .Sub: fallthrough
                            case .And:
                                switch src {
                                    case .Data(_): fallthrough
                                    case .Memory(_, _): fallthrough
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
                                    case .Memory(_, _): fallthrough
                                    case .Stack(_):
                                        out.append(.Mov(tp, dst, .Register(.R11)))
                                        out.append(.Binary(op, tp, src, .Register(.R11)))
                                        out.append(.Mov(tp, .Register(.R11), dst))
                                    default:
                                        out.append(instr)
                                }
                            case .Sar: fallthrough
                            case .Shr: fallthrough
                            case .Shl:
                                switch src {
                                    case .Data(_): fallthrough
                                    case .Memory(_, _): fallthrough
                                    case .Stack(_):
                                        // move the value off of the stack and into CL, which is currently never used otherwise
                                        // and is in no danger of being overwritten
                                        out.append(.Mov(tp, src, .Register(.CX)))
                                        out.append(.Binary(op, tp, .Register(.CL), dst))
                                    default:
                                        out.append(instr)
                                }
                            case .DivDouble:
                                print("Unreachable: DivDouble applied to non-floating point values")
                                exit(ExitCode.internalError.rawValue)
                        }
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
                    if tp == .Double {
                        switch right {
                            case .Data(_): fallthrough
                            case .Stack(_): fallthrough
                            case .Memory(_, _): fallthrough
                            case .Immediate(_):
                                out.append(.Mov(tp, right, .Register(.XMM15)))
                                out.append(.Cmp(tp, left, .Register(.XMM15)))
                            case .Register(_):
                                out.append(instr)
                            case .Pseudo(_): fallthrough
                            case .PseudoMem(_, _):
                                print("Unreachable: pseudo slot survived past pseudo replacement")
                                exit(ExitCode.internalError.rawValue)
                            case .Indexed(_, _, _):
                                print("As-yet-unhandled index mem op in cmp")
                                exit(ExitCode.internalError.rawValue)
                        }
                    } else {
                        switch left {
                            case .Data(_): fallthrough
                            case .Stack(_):
                                switch right {
                                    case .Data(_): fallthrough
                                    case .Memory(_, _): fallthrough
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
                    }
                case .Jmp(_): out.append(instr)
                case .JmpCC(_, _): out.append(instr)
                case .SetCC(_, _): out.append(instr)
                case .Label(_): out.append(instr)
                case .Call(_): out.append(instr)
                case .DeallocateStack(_): out.append(instr)
                case .Push(_): out.append(instr)
                case .Movsx(let srcType, let dstType, let src, let dst):
                    let realSrc : Tree.Operand
                    switch src {
                        case .Immediate(_):
                            realSrc = .Register(.R10)
                            out.append(.Mov(srcType, src, realSrc))
                        default:
                            realSrc = src
                    }
                    let realDst : Tree.Operand
                    let postfix : Tree.Instruction?
                    switch dst {
                        case .Data(_): fallthrough
                        case .Memory(_, _): fallthrough
                        case .Stack(_):
                            realDst = .Register(.R11)
                            postfix = .Mov(dstType, realDst, dst)
                        default:
                            postfix = nil
                            realDst = dst
                    }
                    out.append(.Movsx(srcType, dstType, realSrc, realDst))
                    if let p = postfix { out.append(p) }
                case .Movzx(let srcType, let dstType, let src, let dst):
                    switch dst {
                        case .Register(_):
                            switch srcType {
                                case .Byte:
                                    out.append(instr)
                                case .Longword:
                                    // can only be zero extending to a quad
                                    out.append(.Mov(.Longword, src, dst))
                                case .Double: fallthrough
                                case .Quadword:
                                    print("Can not zero extend any 8 byte values to anything bigger")
                                    exit(ExitCode.internalError.rawValue)
                                case .ByteArray(_, _):
                                    print("Unreachable byte array movzx")
                                    exit(ExitCode.internalError.rawValue)
                            }
                        case .Stack(_): fallthrough
                        case .Memory(_, _): fallthrough
                        case .Data(_):
                            switch srcType {
                                case .Byte:
                                    out.append(.Movzx(srcType, dstType, src, .Register(.R11)))
                                    out.append(.Mov(dstType, .Register(.R11), dst))
                                case .Longword:
                                    out.append(.Mov(.Longword, src, .Register(.R11)))
                                    out.append(.Mov(.Quadword, .Register(.R11), dst))
                                case .Double: fallthrough
                                case .Quadword:
                                    print("Can not zero extend any 8 byte values to anything bigger")
                                    exit(ExitCode.internalError.rawValue)
                                case .ByteArray(_, _):
                                    print("Unreachable byte array movzx")
                                    exit(ExitCode.internalError.rawValue)
                            }
                        case .Pseudo(_): fallthrough
                        case .PseudoMem(_, _):
                            print("Unreachable: psuedo slot survived past pseudo replacement")
                            exit(ExitCode.internalError.rawValue)
                        case .Immediate(_):
                            print("Unreachable: immediate as the destination of a movzx")
                            exit(ExitCode.internalError.rawValue)
                        case .Indexed(_, _, _):
                            print("As-yet-unhandled operation found during .movzx fixing up")
                            exit(ExitCode.internalError.rawValue)
                    }
                case .Cvttsd2si(let tp, let src, let dst):
                    switch dst {
                        case .Register(_): out.append(instr)
                        case .Stack(_): fallthrough
                        case .Memory(_, _): fallthrough
                        case .Data(_):
                            out.append(.Cvttsd2si(tp, src, .Register(.R11)))
                            out.append(.Mov(tp, .Register(.R11), dst))
                        case .PseudoMem(_, _): fallthrough
                        case .Pseudo(_):
                            print("Unreachable: psuedo slot survived past pseudo replacement")
                            exit(ExitCode.internalError.rawValue)
                        case .Immediate(_):
                            print("Unreachable: immediate as the destination of a Cvttsd2si")
                            exit(ExitCode.internalError.rawValue)
                        case .Indexed(_, _, _):
                            print("As-yet-unhandled operation found during .Cvttsd2si fixing up")
                            exit(ExitCode.internalError.rawValue)
                    }
                case .Cvtsi2sd(let tp, let src, let dst):
                    let realSrc: Assembly.Tree.Operand
                    switch src {
                        case .Immediate(_):
                            realSrc = .Register(.R11)
                            out.append(.Mov(.Quadword, src, realSrc))
                        default:
                            realSrc = src
                    }
                    switch dst {
                        case .Register(_): out.append(instr)
                        case .Stack(_): fallthrough
                        case .Memory(_, _): fallthrough
                        case .Data(_):
                            out.append(.Cvtsi2sd(tp, realSrc, .Register(.XMM15)))
                            out.append(.Mov(tp, .Register(.XMM15), dst))
                        case .PseudoMem(_, _): fallthrough
                        case .Pseudo(_):
                            print("Unreachable: pseudo slot survived past pseudo replacement")
                            exit(ExitCode.internalError.rawValue)
                        case .Immediate(_):
                            print("Unreachable: immediate as the destination of a Cvtsi2sd")
                            exit(ExitCode.internalError.rawValue)
                        case .Indexed(_, _, _):
                            print("As-yet-unhandled operation found during .Cvtsi2sd fixing up")
                            exit(ExitCode.internalError.rawValue)
                    }
                case .Lea(let src, let dst):
                    switch src {
                        case .Immediate(_): fallthrough
                        case .Register(_):
                            print("src of lea must be a memory address: \(src)")
                            exit(ExitCode.internalError.rawValue)
                        case .Stack(_): fallthrough
                        case .Data(_): fallthrough
                        case .Memory(_, _): ()
                        case .PseudoMem(_, _): fallthrough
                        case .Pseudo(_):
                            print("Unreachable: pseudo slot survived past pseudo replacement")
                            exit(ExitCode.internalError.rawValue)
                        case .Indexed(_, _, _): ()
                    }
                    switch dst {
                        case .Immediate(_): fallthrough
                        case .Stack(_): fallthrough
                        case .Data(_): fallthrough
                        case .Memory(_, _):
                            out.append(.Lea(src, .Register(.AX)))
                            out.append(.Mov(.Quadword, .Register(.AX), dst))
                        case .Register(_): ()
                        case .PseudoMem(_, _): fallthrough
                        case .Pseudo(_):
                            print("Unreachable: pseudo slot survived past pseudo replacement")
                            exit(ExitCode.internalError.rawValue)
                        case .Indexed(_, _, _):
                            print("As-yet-unhandled operation found during .lea dst fixing up")
                            exit(ExitCode.internalError.rawValue)
                    }
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
                                                switch val {
                                                    case .SignedImmediate(let i64):
                                                        if tp == .Quadword {
                                                            switch dst {
                                                                case .Register(_):
                                                                    fixedBody.append(instr)
                                                                default:
                                                                    if i64 > Int32.max {
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
                                                                .Immediate(.SignedImmediate(i64 % Int(Int32.max))),
                                                                dst
                                                            ))
                                                        }
                                                    case .UnsignedImmediate(let u64):
                                                        if tp == .Quadword {
                                                            switch dst {
                                                                case .Register(_):
                                                                    fixedBody.append(instr)
                                                                default:
                                                                    if u64 > Int32.max {
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
                                                                .Immediate(.UnsignedImmediate(u64 % UInt(Int32.max))),
                                                                dst
                                                            ))
                                                        }
                                                }

                                            default: fixedBody.append(instr)
                                        }
                                    case .Movsx(_, _, _, _): fixedBody.append(instr)
                                    case .Unary(_, _, _): fixedBody.append(instr)
                                    case .Binary(let op, let tp, let src, let dst):
                                        if tp == .Quadword {
                                            switch op {
                                                case .Add: fallthrough
                                                case .Mult: fallthrough
                                                case .Sub:
                                                    switch src {
                                                        case .Immediate(let val):
                                                            switch val {
                                                                case .SignedImmediate(let i64):
                                                                    if i64 > Int32.max {
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
                                                                case .UnsignedImmediate(let u64):
                                                                    if u64 > Int32.max {
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
                                                    switch val {
                                                        case .SignedImmediate(let i64):
                                                            if i64 > Int32.max {
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
                                                        case .UnsignedImmediate(let u64):
                                                            if u64 > Int32.max {
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
                                    case .Movzx(_, _, _, _): fallthrough
                                    case .Div(_, _): fallthrough
                                    case .Ret: fallthrough
                                    case .Lea(_, _): fallthrough
                                    case .Cvttsd2si(_, _, _): fallthrough
                                    case .Cvtsi2sd(_, _, _): fixedBody.append(instr)
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

    func assemble(program: Tacky.IR.Program, symbolTable: [Tacky.IR.Declaration], typedSymbolTable: SymbolTable, typeTable: SemanticAnalyzer.TypeChecker.TypeTable) -> (Tree.Program, BackendSymbolTable) {
        let (assembly, backendSymbolTable) = generate(program: program, symbolTable: symbolTable, typedSymbolTable: typedSymbolTable, typeTable: typeTable)
        let dePseudoed = replacePseudoRegisters(program: assembly, typedSymbolTable, typeTable)
        let fixedUp = fixUpMoves(program: dePseudoed)
        let noBigImms = fixUpImmediates(program: fixedUp)
        return (noBigImms, backendSymbolTable)
    }
}