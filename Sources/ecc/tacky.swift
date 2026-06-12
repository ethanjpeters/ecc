import Foundation

typealias SymbolTable = [String : (SemanticAnalyzer.TypeChecker.CheckerType, SemanticAnalyzer.TypeChecker.IdentifierAttributes)]

class Tacky {
    public struct IR {
        public enum UnaryOperator: Equatable {
            case Complement
            case Negate
            case Not
            case PreIncrement
            case PostIncrement
            case PreDecrement
            case PostDecrement
        }

        public enum BinaryOperator: Equatable {
            case Add
            case Subtract
            case Multiply
            case Divide
            case Remainder
            case Equal
            case NotEqual
            case LessThan
            case LessOrEqual
            case GreaterThan
            case GreaterOrEqual
            case BitwiseAnd
            case BitwiseOr
            // these operations do not have non-bitwise counterparts, but
            // grouping makes things easier for me
            case BitwiseXor
            case BitwiseShiftRight
            case BitwiseShiftLeft
        }

        public enum ConstVal: Equatable {
            case ConstChar(Int32)
            case ConstUnsignedChar(Int32)
            case ConstInt(Int32)
            case ConstUnsignedInt(UInt32)
            case ConstLong(Int64)
            case ConstUnsignedLong(UInt64)
            case ConstDouble(Double)
        }

        public enum Value: Equatable {
            case Constant(ConstVal)
            case Var(String)
        }

        public enum Instruction: Equatable {
            case Return(Value?)
            case Unary(UnaryOperator, Value/* src */, Value /* dst */)
            case Binary(BinaryOperator, Value /* src1 */, Value /* src2 */, Value /* dst */)
            case Copy(Value /* src */, Value /* dst */)
            case Jump(String /* identifier target */)
            case JumpIfZero(Value /* condition */, String /* identifier target */)
            case JumpIfNotZero(Value /* condition */, String /* identifier target */)
            case Label(String /* identifier */)
            case Call(String /* function name */, [Value] /* parameters */, Value? /* result */)
            case SignExtend(Value /* src */, Value /* dst */)
            case ZeroExtend(Value /* src */, Value /* dst */)
            case Truncate(Value /* src */, Value /* dst */)
            case DoubleToInt(Value /* src */, Value /* dst */)
            case DoubleToUInt(Value /* src */, Value /* dst */)
            case IntToDouble(Value /* src */, Value /* dst */)
            case UIntToDouble(Value /* src */, Value /* dst */)
            case GetAddress(Value /* src */, Value /* dst */)
            case Load(Value /* src_ptr */, Value /* dst */)
            case Store(Value /* src */, Value /* dst_ptr */)
            case AddPtr(Value /* ptr */, Value /* index */, UInt /* scale */, Value /* dst */)
            case CopyToOffset(Value /* src */, String /* identifier dst */, UInt /* offset */)
            case CopyFromOffset(String /* src */, Int /* offset */, Value /* dst */)
        }

        public enum Declaration: Equatable {
            case Function(String /* name */, Bool /* is global */, [String] /* params */, [Instruction] /* body */)
            case StaticVariable(String /* name */, Bool /* is global */, Parser.AST.CType, [SemanticAnalyzer.TypeChecker.StaticInit] /* initial value */)
            case StaticConstant(String /* name */, Parser.AST.CType /* type */, SemanticAnalyzer.TypeChecker.StaticInit /* init */)
        }

        public enum Program: Equatable {
            case Statement([Declaration])
        }
    }

    private var tempNameCounter : Int = 0
    private var tempLabelCounter : Int = 0

    func makeTemp() -> String {
        let out = "tmp.\(tempNameCounter)"
        tempNameCounter = tempNameCounter + 1
        return out
    }

    func makeTempVariable(_ tp: Parser.AST.CType, _ symbolTable: inout SymbolTable) -> Tacky.IR.Value {
        let varName = makeTemp()
        symbolTable[varName] = (convertCTypeToCheckerType(tp), .LocalAttr)
        return .Var(varName)
    }

    func makeLabel(_ descriptor: String = "") -> String {
        let out = "L\(descriptor)label.\(tempLabelCounter)"
        tempLabelCounter = tempLabelCounter + 1
        return out
    }

    func makeLoopLabel(_ descriptor: String) -> String {
        return "L.loop.\(descriptor)label.inf"
    }

    func makeSwitchLabel(_ descriptor: String) -> String {
        return "L.switch.\(descriptor)label.inf"
    }

    func makeStringLabel() -> String {
        let out = "string.tacky.\(tempNameCounter)"
        tempNameCounter = tempNameCounter + 1
        return out
    }

    func transformUserLabel(_ userLabel: String) -> String {
        let out = "L.user.\(userLabel).eps"
        return out
    }

    func convert(_ op : Parser.AST.BinaryOperator) -> IR.BinaryOperator {
        switch op {
            case .Add: return .Add
            case .Subtract: return .Subtract
            case .Multiply: return .Multiply
            case .Divide: return .Divide
            case .Equal: return .Equal
            case .NotEqual: return .NotEqual
            case .LessThan: return .LessThan
            case .LessOrEqual: return .LessOrEqual
            case .GreaterThan: return .GreaterThan
            case .GreaterOrEqual: return .GreaterOrEqual
            case .Remainder: return .Remainder
            case .BitwiseAnd: return .BitwiseAnd
            case .BitwiseOr: return .BitwiseOr
            case .BitwiseXor: return .BitwiseXor
            case .BitwiseShiftLeft: return .BitwiseShiftLeft
            case .BitwiseShiftRight: return .BitwiseShiftRight
            case .And: fallthrough
            case .Or:
                print("Unreachable 4")
                exit(ExitCode.internalError.rawValue)
        }
    }

    enum ExpResult {
        case PlainOperand(IR.Value)
        case DereferencedPointer(IR.Value)
        case SubObject(String /* base */, Int /* offset */)
    }

    func generateTACKYExpression(_ exp: Parser.AST.Expression, out: inout [Tacky.IR.Instruction], symbolTable: inout SymbolTable, typeTable: SemanticAnalyzer.TypeChecker.TypeTable) -> ExpResult {

        func generateTACKYOp(_ op: Parser.AST.UnaryOperator) -> Tacky.IR.UnaryOperator {
            switch op {
                case .Complement: return .Complement
                case .Negate: return .Negate
                case .Not: return .Not
                case .PreIncrement: return .PreIncrement
                case .PreDecrement: return .PreDecrement
                case .PostIncrement: return .PostIncrement
                case .PostDecrement: return .PostDecrement
            }
        }

        func isIncOrDec(_ op: Parser.AST.UnaryOperator) -> Bool {
            switch op {
                case .PreIncrement: fallthrough
                case .PreDecrement: fallthrough
                case .PostIncrement: fallthrough
                case .PostDecrement: return true
                default: return false
            }
        }

        switch exp {
            case .Constant(let c, _):
                switch c {
                    case .ConstInt(let val):
                        return .PlainOperand(.Constant(.ConstInt(val)))
                    case .ConstLong(let val):
                        return .PlainOperand(.Constant(.ConstLong(val)))
                    case .ConstUnsignedInt(let val):
                        return .PlainOperand(.Constant(.ConstUnsignedInt(val)))
                    case .ConstUnsignedLong(let val):
                        return .PlainOperand(.Constant(.ConstUnsignedLong(val)))
                    case .ConstDouble(let val):
                        return .PlainOperand(.Constant(.ConstDouble(val)))
                    case .ConstChar(let i32):
                        return .PlainOperand(.Constant(.ConstChar(i32)))
                    case .ConstUChar(let i32):
                        return .PlainOperand(.Constant(.ConstUnsignedChar(i32)))
                }
            case .Unary(let op, let exp, let tp):
                if isIncOrDec(op) {
                    let src = generateTACKYExpression(exp, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                    let dst = makeTempVariable(tp!, &symbolTable)
                    let one : Tacky.IR.Value = .Constant(tp == .Int ? .ConstInt(1) : .ConstLong(1))
                    switch op {
                        case .PreIncrement:
                            switch src {
                                case .PlainOperand(let obj):
                                    out.append(.Binary(.Add, one, obj, dst))
                                    out.append(.Copy(dst, obj))
                                    return .PlainOperand(obj)
                                case .DereferencedPointer(let ptr):
                                    let tmp = makeTempVariable(tp!, &symbolTable)
                                    out.append(.Load(ptr, tmp))
                                    out.append(.Binary(.Add, one, tmp, dst))
                                    out.append(.Store(dst, ptr))
                                    return .PlainOperand(dst)
                                case .SubObject(let base, let offset):
                                    // NOTE: earlier passes should have already verified this is a valid lvalue
                                    let tmp = makeTempVariable(tp!, &symbolTable)
                                    out.append(.CopyFromOffset(base, offset, tmp))
                                    out.append(.Binary(.Add, one, tmp, tmp))
                                    out.append(.CopyToOffset(tmp, base, UInt(offset)))
                                    return .SubObject(base, offset)
                            }
                        case .PreDecrement:
                            switch src {
                                case .PlainOperand(let obj):
                                    out.append(.Binary(.Subtract, obj, one, dst))
                                    out.append(.Copy(dst, obj))
                                    return .PlainOperand(obj)
                                case .DereferencedPointer(let ptr):
                                    let tmp = makeTempVariable(tp!, &symbolTable)
                                    out.append(.Load(ptr, tmp))
                                    out.append(.Binary(.Subtract, tmp, one, dst))
                                    out.append(.Store(dst, ptr))
                                    return .PlainOperand(dst)
                                case .SubObject(let base, let offset):
                                    // NOTE: earlier passes should have already verified this is a valid lvalue
                                    let tmp = makeTempVariable(tp!, &symbolTable)
                                    out.append(.CopyFromOffset(base, offset, tmp))
                                    out.append(.Binary(.Subtract, tmp, one, tmp))
                                    out.append(.CopyToOffset(tmp, base, UInt(offset)))
                                    return .SubObject(base, offset)
                            }
                        case .PostIncrement:
                            switch src {
                                case .PlainOperand(let obj):
                                    let tmp = makeTempVariable(tp!, &symbolTable)
                                    out.append(.Copy(obj, tmp))
                                    out.append(.Binary(.Add, one, obj, dst))
                                    out.append(.Copy(dst, obj))
                                    return .PlainOperand(tmp)
                                case .DereferencedPointer(let ptr):
                                    let tmp = makeTempVariable(tp!, &symbolTable)
                                    out.append(.Load(ptr, tmp))
                                    out.append(.Binary(.Add, tmp, one, dst))
                                    out.append(.Store(dst, ptr))
                                    return .PlainOperand(tmp)
                                case .SubObject(let base, let offset):
                                    let tmp = makeTempVariable(tp!, &symbolTable)
                                    out.append(.CopyFromOffset(base, offset, tmp))
                                    out.append(.Binary(.Add, one, tmp, dst))
                                    out.append(.CopyToOffset(dst, base, UInt(offset)))
                                    return .PlainOperand(tmp)
                            }
                        case .PostDecrement:
                            switch src {
                                case .PlainOperand(let obj):
                                    let tmp = makeTempVariable(tp!, &symbolTable)
                                    out.append(.Copy(obj, tmp))
                                    out.append(.Binary(.Subtract, obj, one, dst))
                                    out.append(.Copy(dst, obj))
                                    return .PlainOperand(tmp)
                                case .DereferencedPointer(let ptr):
                                    let tmp = makeTempVariable(tp!, &symbolTable)
                                    out.append(.Load(ptr, tmp))
                                    out.append(.Binary(.Subtract, tmp, one, dst))
                                    out.append(.Store(dst, ptr))
                                    return .PlainOperand(tmp)
                                case .SubObject(let base, let offset):
                                    let tmp = makeTempVariable(tp!, &symbolTable)
                                    out.append(.CopyFromOffset(base, offset, tmp))
                                    out.append(.Binary(.Subtract, tmp, one, dst))
                                    out.append(.CopyToOffset(dst, base, UInt(offset)))
                                    return .PlainOperand(tmp)
                            }
                        default:
                            print("Unreachable B")
                            exit(ExitCode.internalError.rawValue)
                    }
                } else {
                    let src = generateTACKYExpressionAndConvert(exp, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                    let dst = makeTempVariable(tp!, &symbolTable)
                    let tackyOp = generateTACKYOp(op)
                    out.append(.Unary(tackyOp, src, dst))
                    return .PlainOperand(dst)
                }
            case .Binary(let op, let left, let right, let tp):
                let one : Tacky.IR.Value = .Constant(tp == .Int ? .ConstInt(1) : .ConstLong(1))
                let zero : Tacky.IR.Value = .Constant(tp == .Int ? .ConstInt(0) : .ConstLong(0))
                if op == .And {
                    let v1 = generateTACKYExpressionAndConvert(left, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                    let falseLabel = makeLabel("and_false")
                    out.append(.JumpIfZero(v1, falseLabel))
                    let v2 = generateTACKYExpressionAndConvert(right, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                    out.append(.JumpIfZero(v2, falseLabel))
                    let result = makeTempVariable(tp!, &symbolTable)
                    // result = 1
                    out.append(.Copy(one, result))
                    let endLabel = makeLabel()
                    out.append(.Jump(endLabel))
                    out.append(.Label(falseLabel))
                    // result = 0
                    out.append(.Copy(zero, result))
                    out.append(.Label(endLabel))
                    return .PlainOperand(result)
                } else if op == .Or {
                    let v1: Tacky.IR.Value = generateTACKYExpressionAndConvert(left, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                    let trueLabel = makeLabel("or_true")
                    out.append(.JumpIfNotZero(v1, trueLabel))
                    let v2 = generateTACKYExpressionAndConvert(right, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                    out.append(.JumpIfNotZero(v2, trueLabel))
                    let result = makeTempVariable(tp!, &symbolTable)
                    // result = 0
                    out.append(.Copy(zero, result))
                    let endLabel = makeLabel()
                    out.append(.Jump(endLabel))
                    out.append(.Label(trueLabel))
                    // result = 1
                    out.append(.Copy(one, result))
                    out.append(.Label(endLabel))
                    return .PlainOperand(result)
                } else {
                    let v1 = generateTACKYExpressionAndConvert(left, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                    let v2  = generateTACKYExpressionAndConvert(right, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                    let dst = makeTempVariable(tp!, &symbolTable)

                    let lType = convertCTypeToCheckerType(getType(left))
                    let rType = convertCTypeToCheckerType(getType(right))

                    // <ptr> + <int> uses a special instruction
                    if op == .Add && isPointerType(lType) && isIntegralType(rType) {
                        out.append(.AddPtr(v1, v2, UInt(getTypeSize(getPointeeType(lType), typeTable)), dst))
                    // <int> + <ptr>
                    } else if op == .Add && isPointerType(rType) && isIntegralType(lType) {
                        out.append(.AddPtr(v1, v2, UInt(getTypeSize(getPointeeType(rType), typeTable)), dst))
                    // <ptr> - <int> uses, oddly enough, the same special instruction
                    } else if op == .Subtract && isPointerType(lType) && isIntegralType(rType) {
                        let negV2 = makeTempVariable(.Long, &symbolTable)
                        out.append(.Unary(.Negate, v2, negV2))
                        out.append(.AddPtr(v1, negV2, UInt(getTypeSize(getPointeeType(lType), typeTable)), dst))
                    // <int> - <ptr> is nonsense
                    // <ptr> - <ptr>, however, is valid
                    } else if op == .Subtract && isPointerType(lType) && isPointerType(rType) {
                        let diff : Tacky.IR.Value = makeTempVariable(tp!, &symbolTable)
                        out.append(.Binary(.Subtract, v1, v2, diff))
                        out.append(.Binary(.Divide, diff, .Constant(.ConstLong(Int64(getTypeSize(getPointeeType(lType), typeTable)))), dst))
                    } else {
                        out.append(.Binary(convert(op), v1, v2, dst))
                    }
                    return .PlainOperand(dst)
                }
            case .Var(let name, _):
                return .PlainOperand(.Var(name))
            case .Assignment(let lVal, let rVal, _):
                let left = generateTACKYExpression(lVal, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                let right = generateTACKYExpressionAndConvert(rVal, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                switch left {
                    case .PlainOperand(let obj):
                        out.append(.Copy(right, obj))
                        return left
                    case .DereferencedPointer(let ptr):
                        out.append(.Store(right, ptr))
                        return .PlainOperand(right)
                    case .SubObject(let base, let offset):
                        out.append(.CopyToOffset(right, base, UInt(offset)))
                        return .PlainOperand(right)
                }
            case .CompoundAssignment(_,_,_,_):
                print("Unreachable compound assignment")
                exit(ExitCode.internalError.rawValue)
            case .Conditional(let cond, let left, let right, let tp):
                let condValue = generateTACKYExpressionAndConvert(cond, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                let e2Label = makeLabel("right")
                let endLabel = makeLabel("end")
                out.append(.JumpIfZero(condValue, e2Label))
                if tp == .Void {
                    let _ = generateTACKYExpressionAndConvert(left, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                    out.append(.Jump(endLabel))
                    out.append(.Label(e2Label))
                    let _ = generateTACKYExpressionAndConvert(right, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                    out.append(.Label(endLabel))
                    return .PlainOperand(.Var("DUMMY"))
                } else {
                    let e1Value = generateTACKYExpressionAndConvert(left, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                    let dst = makeTempVariable(tp!, &symbolTable)
                    out.append(.Copy(e1Value, dst))
                    out.append(.Jump(endLabel))
                    out.append(.Label(e2Label))
                    let e2Value = generateTACKYExpressionAndConvert(right, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                    out.append(.Copy(e2Value, dst))
                    out.append(.Label(endLabel))
                    return .PlainOperand(dst)
                }
            case .FunctionCall(let fun, let params, let tp):
                // fun has already been constrained to an lValue, currently just a name
                let funName : String
                switch fun {
                    case .Var(let fnNm, _):
                        funName = fnNm
                    default:
                        print("Unreachable non-lValue function \(fun)")
                        exit(ExitCode.internalError.rawValue)
                }
                var paramValues : [Tacky.IR.Value] = []
                for p in params {
                    paramValues.append(generateTACKYExpressionAndConvert(p, out: &out, symbolTable: &symbolTable, typeTable: typeTable))
                }
                let dst = makeTempVariable(tp!, &symbolTable)
                out.append(.Call(funName, paramValues, dst))
                return .PlainOperand(dst)
            case .Cast(let targetType, let child, let tp):
                let unCastedValue = generateTACKYExpressionAndConvert(child, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                if targetType != tp {
                    let dst = makeTempVariable(targetType, &symbolTable)

                    let targetCp = convertCTypeToCheckerType(targetType)
                    let innerCp = convertCTypeToCheckerType(tp!)
                    
                    // allow an array to decay to a pointer
                    if isPointerType(targetCp) {
                        switch innerCp {
                            case .ArrayType(let nested, _):
                                if nested != getPointeeType(targetCp) {
                                    print("Can't decay array of type \(nested) to pointer of type \(targetCp)")
                                    exit(ExitCode.semanticError.rawValue)
                                }
                                out.append(.GetAddress(unCastedValue, dst))
                                return .PlainOperand(dst)
                            // allow a pointer to be explicitly cast to another pointer
                            case .Pointer(_):
                                // is this even necessary?
                                out.append(.Copy(unCastedValue, dst))
                                return .PlainOperand(dst)
                            default: ()
                        }
                    }
                    
                    switch targetCp {
                        case .ArrayType(_, _):
                            print("Can not cast \(child) of type \(innerCp) to array \(targetCp)")
                            exit(ExitCode.semanticError.rawValue)
                        default: ()
                    }

                    if targetCp == .Void {
                        // dont' try to get the size or signedness of "Void", it's meaningless
                        return .PlainOperand(.Var("DUMMY"))
                    } else if isFloatingPoint(targetCp) && !isFloatingPoint(innerCp) {
                        if isSigned(innerCp) {
                            out.append(.IntToDouble(unCastedValue, dst))
                        } else {
                            out.append(.UIntToDouble(unCastedValue, dst))
                        }
                    } else if isFloatingPoint(innerCp) && !isFloatingPoint(targetCp) {
                        if isSigned(targetCp) {
                            out.append(.DoubleToInt(unCastedValue, dst))
                        } else {
                            out.append(.DoubleToUInt(unCastedValue, dst))
                        }
                    } else {
                        if getTypeSize(targetCp, typeTable) == getTypeSize(innerCp, typeTable) {
                            out.append(.Copy(unCastedValue, dst))
                        } else if getTypeSize(targetCp, typeTable) < getTypeSize(innerCp, typeTable) {
                            out.append(.Truncate(unCastedValue, dst))
                        } else if isSigned(innerCp) {
                            out.append(.SignExtend(unCastedValue, dst))
                        } else {
                            out.append(.ZeroExtend(unCastedValue, dst))
                        }
                    }
                    return .PlainOperand(dst)
                } else {
                    return .PlainOperand(unCastedValue)
                }
            case .Dereference(let exp, _):
                return .DereferencedPointer(generateTACKYExpressionAndConvert(exp, out: &out, symbolTable: &symbolTable, typeTable: typeTable))
            case .AddrOf(let exp, let tp):
                let v = generateTACKYExpression(exp, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                switch v {
                    case .PlainOperand(let obj):
                        let dst = makeTempVariable(tp!, &symbolTable)
                        out.append(.GetAddress(obj, dst))
                        return .PlainOperand(dst)
                    case .DereferencedPointer(let ptr):
                        return .PlainOperand(ptr)
                    case .SubObject(let base, let offset):
                        let dst = makeTempVariable(getType(exp), &symbolTable)
                        out.append(.GetAddress(.Var(base), dst))
                        out.append(.AddPtr(dst, .Constant(.ConstLong(Int64(offset))), 1, dst))
                        return .PlainOperand(dst)
                }
            case .Subscript(let ptr, let off, let tp):
                let arrayValue = generateTACKYExpressionAndConvert(ptr, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                let offset = generateTACKYExpressionAndConvert(off, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                let tmp0 = makeTempVariable(.Pointer(tp!), &symbolTable)
                out.append(.GetAddress(arrayValue, tmp0))
                let tmp1 = makeTempVariable(.Pointer(tp!), &symbolTable)
                out.append(.AddPtr(tmp0, offset, UInt(getTypeSize(convertCTypeToCheckerType(tp!), typeTable)), tmp1))
                return .DereferencedPointer(tmp1)
            case .String(let val, _):
                // TODO: string interning
                let varName = makeStringLabel()
                symbolTable[varName] = (.ArrayType(.Char, UInt(val.count) + 1), .ConstantAttr(.StringInit(val, true)))
                return .PlainOperand(.Var(varName))
            case .SizeOf(let inner, _):
                return .PlainOperand(.Constant(.ConstUnsignedLong(UInt64(getTypeSize(convertCTypeToCheckerType(getType(inner)), typeTable)))))
            case .SizeOfT(let namedType, _):
                return .PlainOperand(.Constant(.ConstUnsignedLong(UInt64(getTypeSize(convertCTypeToCheckerType(namedType), typeTable)))))
            case .Dot(let exp, let memberName, _):
                let structType = getType(exp)
                let tg: String
                switch structType {
                    case .Structure(let tag):
                        tg = tag
                    default:
                        print("Unreachable no-type's land where dot operator was used on non-structure")
                        exit(ExitCode.internalError.rawValue)
                }
                if let structDef = typeTable[tg] {
                    for m in structDef.members {
                        if m.identifier == memberName {
                            let memberOffset = m.offset
                            let innerObject = generateTACKYExpression(exp, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                            switch innerObject {
                                case .PlainOperand(let val):
                                    switch val {
                                        case .Var(let valName): return .SubObject(valName, memberOffset)
                                        case .Constant(_):
                                            print("Tried to do dot operation on constant \(val)")
                                            exit(ExitCode.internalError.rawValue)
                                    }
                                case .SubObject(let base, let offset): return .SubObject(base, offset + memberOffset)
                                case .DereferencedPointer(let ptr):
                                    let dstPtr = makeTempVariable(.Pointer(getType(exp)), &symbolTable)
                                    out.append(.AddPtr(ptr, .Constant(.ConstLong(Int64(memberOffset))), 1, dstPtr))
                                    return .DereferencedPointer(dstPtr)
                            }
                        }
                    }
                    print("Unreachable point where struct member name is not valid")
                    exit(ExitCode.internalError.rawValue)
                } else {
                    print("Unreachable point where struct is not defined but we're generating TACKY out of its dot operation")
                    exit(ExitCode.internalError.rawValue)
                }
            case .Arrow(let exp, let memberName, _):
                let structType: Parser.AST.CType = getType(exp)
                let innerStructType: Parser.AST.CType
                let tg: String
                switch structType {
                    case .Pointer(let innerType):
                        switch innerType {
                            case .Structure(let tag):
                                tg = tag
                                innerStructType = innerType
                            default:
                                print("Unreachable no-type's land where arrow operator was used on pointer to non-struct")
                                exit(ExitCode.internalError.rawValue)
                        }
                    default:
                        print("Unreachable no-type's land where arrow operator was used on non-pointer")
                        exit(ExitCode.internalError.rawValue)
                }
                if let structDef = typeTable[tg] {
                    for m in structDef.members {
                        if m.identifier == memberName {
                            let memberOffset = m.offset
                            let innerObject = generateTACKYExpressionAndConvert(exp, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                            let tmp = makeTempVariable(.Pointer(innerStructType), &symbolTable)
                            out.append(.AddPtr(innerObject, .Constant(.ConstLong(Int64(memberOffset))), 1, tmp))
                            return .DereferencedPointer(tmp)
                        }
                    }
                    print("Unreachable point where struct member name is not valid")
                    exit(ExitCode.internalError.rawValue)
                } else {
                    print("Unreachable point where struct is not defined but we're generating TACKY out of its dot operation")
                    exit(ExitCode.internalError.rawValue)
                }
        }
    }

    func generateTACKYExpressionAndConvert(_ exp: Parser.AST.Expression, out: inout [Tacky.IR.Instruction], symbolTable: inout SymbolTable, typeTable: SemanticAnalyzer.TypeChecker.TypeTable) -> IR.Value {
        switch generateTACKYExpression(exp, out: &out, symbolTable: &symbolTable, typeTable: typeTable) {
            case .PlainOperand(let val): return val
            case .DereferencedPointer(let ptr):
                let dst = makeTempVariable(getType(exp), &symbolTable)
                out.append(.Load(ptr, dst))
                return dst
            case .SubObject(let base, let offset):
                let dst = makeTempVariable(getType(exp), &symbolTable)
                out.append(.CopyFromOffset(base, offset, dst))
                return dst
        }
    }

    func generateTACKYStatement(statement: Parser.AST.Statement, out : inout [Tacky.IR.Instruction], switchValue: Tacky.IR.Value?, fallthroughValue: Tacky.IR.Value?, symbolTable: inout SymbolTable, typeTable: SemanticAnalyzer.TypeChecker.TypeTable) {
        switch statement {
            case .Return(let exp):
                let child : Tacky.IR.Value?
                if let e = exp {
                    child = generateTACKYExpressionAndConvert(e, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                } else {
                    child = nil
                }
                out.append(.Return(child))
            case .Expression(let exp):
                let _ = generateTACKYExpression(exp, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
            case .If(let cond, let thenStatement, let elseStatement):
                let condValue = generateTACKYExpressionAndConvert(cond, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                let elseLabel = makeLabel("ifelse")
                let endLabel = makeLabel("ifend")
                out.append(.JumpIfZero(condValue, elseLabel))
                generateTACKYStatement(
                    statement: thenStatement,
                    out: &out,
                    switchValue: switchValue,
                    fallthroughValue: fallthroughValue,
                    symbolTable: &symbolTable, typeTable: typeTable
                )
                out.append(.Jump(endLabel))
                out.append(.Label(elseLabel))
                if let es = elseStatement {
                    generateTACKYStatement(
                        statement: es,
                        out: &out,
                        switchValue: switchValue,
                        fallthroughValue: fallthroughValue,
                        symbolTable: &symbolTable, typeTable: typeTable
                    )
                }
                out.append(.Label(endLabel))
            case .Null: ()
            case .Compound(let block):
                switch block {
                    case .Block(let items):
                        for itm in items {
                            switch itm {
                                case .S(let stmt):
                                    generateTACKYStatement(
                                        statement: stmt,
                                        out: &out,
                                        switchValue: switchValue,
                                        fallthroughValue: fallthroughValue,
                                        symbolTable: &symbolTable, typeTable: typeTable
                                    )
                                case .D(let decl):
                                    let _ = generateTACKYDeclaration(decl: decl, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                            }
                        }
                }
            case .Break(let label):
                out.append(.Jump(makeLoopLabel("\(label).break")))
            case .Continue(let label):
                out.append(.Jump(makeLoopLabel("\(label).continue")))
            case .While(let condition, let body, let label):
                let startLabel = makeLoopLabel("\(label).start")
                out.append(.Label(startLabel))  // for debugging purposes
                let continueLabel = makeLoopLabel("\(label).continue")
                out.append(.Label(continueLabel))
                let condValue = generateTACKYExpressionAndConvert(condition, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                let breakLabel = makeLoopLabel("\(label).break")
                out.append(.JumpIfZero(condValue, breakLabel))
                generateTACKYStatement(statement: body, out: &out, switchValue: switchValue, fallthroughValue: fallthroughValue, symbolTable: &symbolTable, typeTable: typeTable)
                out.append(.Jump(continueLabel))
                out.append(.Label(breakLabel))
            case .DoWhile(let body, let condition, let label):
                let startLabel = makeLoopLabel("\(label).start")
                out.append(.Label(startLabel))
                generateTACKYStatement(statement: body, out: &out, switchValue: switchValue, fallthroughValue: fallthroughValue, symbolTable: &symbolTable, typeTable: typeTable)
                let continueLabel = makeLoopLabel("\(label).continue")
                out.append(.Label(continueLabel))
                let condValue = generateTACKYExpressionAndConvert(condition, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                out.append(.JumpIfNotZero(condValue, startLabel))
                out.append(.Label(makeLoopLabel("\(label).break")))
            case .For(let forInit, let condition, let increment, let body, let label):
                switch forInit {
                    case .InitDecl(let decl):
                        let _ = generateTACKYDeclaration(decl: decl, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                    case .InitExp(let exp):
                        if let e = exp {
                            let _ = generateTACKYExpression(e, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                        }
                }
                let startLabel = makeLoopLabel("\(label).start")
                out.append(.Label(startLabel))
                let condValue : Tacky.IR.Value
                if let c = condition {
                    condValue = generateTACKYExpressionAndConvert(c, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                } else {
                    condValue = .Constant(.ConstInt(1))
                }
                let breakLabel = makeLoopLabel("\(label).break")
                out.append(.JumpIfZero(condValue, breakLabel))
                generateTACKYStatement(statement: body, out: &out, switchValue: switchValue, fallthroughValue: fallthroughValue, symbolTable: &symbolTable, typeTable: typeTable)
                out.append(.Label(makeLoopLabel("\(label).continue")))
                if let inc = increment {
                    let _ = generateTACKYExpressionAndConvert(inc, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                }
                out.append(.Jump(startLabel))
                out.append(.Label(breakLabel))
            case .Switch(let toggle, let stmt, let label):
                // NOTE: something here is broken, duff's device does not function properly
                let breakLabel = makeLoopLabel("\(label).break")
                let toggleVal = generateTACKYExpressionAndConvert(toggle, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                let ftVal = makeTempVariable(.Int, &symbolTable)
                out.append(.Copy(.Constant(.ConstInt(0)), ftVal))
                generateTACKYStatement(statement: stmt, out: &out, switchValue: toggleVal, fallthroughValue: ftVal, symbolTable: &symbolTable, typeTable: typeTable)
                out.append(.Label(breakLabel))
            case .Labeled(let ls):
                switch ls {
                    case .CaseStatement(let labelExp, let line):
                        // check if we're falling through
                        let ftLabel = makeLabel("case.fallthrough")
                        let ftCmpTmp = makeTempVariable(.Int, &symbolTable)
                        out.append(.Binary(.Equal, fallthroughValue!, .Constant(.ConstInt(1)), ftCmpTmp))
                        out.append(.JumpIfNotZero(ftCmpTmp, ftLabel))
                        let labelVal = generateTACKYExpressionAndConvert(labelExp, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                        let tmp = makeTempVariable(.Int, &symbolTable)
                        // semantic analyzer catches when we're not in a switch statement
                        // and switchValue would be nil
                        out.append(.Binary(.Equal, labelVal, switchValue!, tmp))
                        let skipLabel = makeLabel("case.skip")
                        out.append(.JumpIfZero(tmp, skipLabel))
                        out.append(.Copy(tmp, fallthroughValue!))
                        out.append(.Label(ftLabel))
                        generateTACKYStatement(statement: line, out: &out, switchValue: switchValue, fallthroughValue: fallthroughValue, symbolTable: &symbolTable, typeTable: typeTable)
                        out.append(.Label(skipLabel))
                    case .IdentifiedLine(let label, let line):
                        out.append(.Label(transformUserLabel(label)))
                        generateTACKYStatement(statement: line, out: &out, switchValue: switchValue, fallthroughValue: fallthroughValue, symbolTable: &symbolTable, typeTable: typeTable)
                    case .DefaultStatement(let stmt):
                        // unconditionally execute this statement
                        out.append(.Label(makeLabel("case.default")))
                        generateTACKYStatement(statement: stmt, out: &out, switchValue: nil, fallthroughValue: nil, symbolTable: &symbolTable, typeTable: typeTable)
                }
        }
    }

    func generateTACKYInit(_ i: Parser.AST.Initializer, dest: String, offset: UInt, out: inout [Tacky.IR.Instruction], symbolTable: inout SymbolTable, typeTable: SemanticAnalyzer.TypeChecker.TypeTable) {
        switch i {
            case .SingleInit(let exp):
                let child = generateTACKYExpressionAndConvert(exp, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                switch symbolTable[dest]!.0 {
                    case .ArrayType(_, _):
                        out.append(.CopyToOffset(child, dest, offset))
                    case .Pointer(_): fallthrough
                    case .Char: fallthrough
                    case .SChar: fallthrough
                    case .UChar: fallthrough
                    case .Int: fallthrough
                    case .UnsignedInt: fallthrough
                    case .Long: fallthrough
                    case .UnsignedLong: fallthrough
                    case .Structure(_): fallthrough
                    case .Double:
                        out.append(.Copy(child, .Var(dest)))
                    case .Void: fallthrough
                    case .Function(_, _):
                        print("Unreachable invalid type \(symbolTable[dest]!.0) found while initializing \(dest)")
                        exit(ExitCode.internalError.rawValue)
                }
            case .CompoundInit(let children):
                switch (symbolTable[dest]!.0) {
                    // we don't need the length here because we added zero initializers to pad the compound initializer
                    case .ArrayType(let innerType, _):
                        let size = UInt(getTypeSize(innerType, typeTable))
                        var off = offset
                        for c in children {
                            generateTACKYInit(c, dest: dest, offset: off, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                            off = off + size
                        }
                    case .Structure(let tag):
                        if let structDef = typeTable[tag] {
                            for (memInit, member) in zip(children, structDef.members) {
                                let memOffset = Int(offset) + member.offset
                                generateTACKYInit(memInit, dest: dest, offset: UInt(memOffset), out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                            }
                        } else {
                            print("Unreachable case where structure was initialized but never defined")
                            exit(ExitCode.internalError.rawValue)
                        }
                    default:
                        print("UNREACHABLE: tried to assign compound initializer to non-array/non-struct type value \(dest)")
                        exit(ExitCode.internalError.rawValue)
                }

        }
    }

    func generateTACKYDeclaration(decl: Parser.AST.Declaration, out : inout [Tacky.IR.Instruction], symbolTable: inout SymbolTable, typeTable: SemanticAnalyzer.TypeChecker.TypeTable) -> Tacky.IR.Declaration? {
        switch decl {
            // TODO: use type information to determine size of parameters
            case .VariableDeclaration(_, let name, let exp, _):
                if exp != nil {
                    generateTACKYInit(exp!, dest: name, offset: 0, out: &out, symbolTable: &symbolTable, typeTable: typeTable)
                }
                return nil
            case .FunctionDeclaration(let returnType, let name, let parameters, let body, let storageClass):
                if let b = body {
                    switch b {
                        case .Block(let items):
                            var instrs : [Tacky.IR.Instruction] = []
                            for blockItem in items {
                                switch blockItem {
                                    case .S(let stmt):
                                        generateTACKYStatement(statement: stmt, out: &instrs, switchValue: nil, fallthroughValue: nil, symbolTable: &symbolTable, typeTable: typeTable)
                                    case .D(let decl):
                                        let _ = generateTACKYDeclaration(decl: decl, out: &instrs, symbolTable: &symbolTable, typeTable: typeTable)
                                }
                            }
                            if returnType != .Void {
                                instrs.append(.Return(.Constant(returnType == .Long ? .ConstLong(0) : .ConstInt(0))))
                            }
                            var tackyIds : [String] = []
                            for name in parameters {
                                tackyIds.append(name)
                            }
                            return .Function(name, storageClass != .Static, tackyIds, instrs)
                    }
                } else {
                    // no code for undefined functions
                    return nil
                }
            case .StructDeclaration(let tag, let members):
                return nil
        }
    }

    func generateTACKYSymbolTable(symbolTable: [String : (SemanticAnalyzer.TypeChecker.CheckerType, SemanticAnalyzer.TypeChecker.IdentifierAttributes)], typeTable: SemanticAnalyzer.TypeChecker.TypeTable) -> [Tacky.IR.Declaration] {
        var tackyDefs : [Tacky.IR.Declaration] = []
        for (name, entry) in symbolTable {
            let (tp, attrs) = entry
            switch attrs {
                case .StaticAttr(let initVal, let isGlobal):
                    switch initVal {
                        case .Initial(let i):
                            tackyDefs.append(.StaticVariable(name, isGlobal, SemanticAnalyzer.TypeChecker.deConvert(tp), i))
                        case .Tentative:
                            let tentInit : SemanticAnalyzer.TypeChecker.StaticInit = .ZeroInit(UInt(getTypeSize(tp, typeTable)))
                            tackyDefs.append(.StaticVariable(name, isGlobal, SemanticAnalyzer.TypeChecker.deConvert(tp), [tentInit]))
                        case .NoInitializer: ()
                    }
                case .ConstantAttr(let initVal):
                    tackyDefs.append(.StaticConstant(name, SemanticAnalyzer.TypeChecker.deConvert(tp), initVal))
                case .FunAttr(_, _): fallthrough
                case .LocalAttr: ()
            }
        }
        return tackyDefs
    }

    func generateTACKYProgram(program: Parser.AST.Program, symbolTable: inout SymbolTable, typeTable: SemanticAnalyzer.TypeChecker.TypeTable) -> (Tacky.IR.Program, [Tacky.IR.Declaration]) {
        var out : [Tacky.IR.Instruction] = []
        switch program {
            case .Statement(let declarations):
                var tackyDecls : [Tacky.IR.Declaration] = []
                for decl in declarations {
                    if let d = generateTACKYDeclaration(decl: decl, out: &out, symbolTable: &symbolTable, typeTable: typeTable) {
                        tackyDecls.append(d)
                    }
                }
                return (.Statement(tackyDecls), generateTACKYSymbolTable(symbolTable: symbolTable, typeTable: typeTable))
        }
    }

    func getType(_ e: Parser.AST.Expression) -> Parser.AST.CType {
        switch e {
            case .Constant(_, let tp): return tp!
            case .Unary(_, _, let tp): return tp!
            case .Binary(_, _, _, let tp): return tp!
            case .Var(_, let tp): return tp!
            case .Assignment(_, _, let tp): return tp!
            case .CompoundAssignment(_, _, _, let tp): return tp!
            case .Conditional(_, _, _, let tp): return tp!
            case .FunctionCall(_, _, let tp): return tp!
            case .Cast(_, _, let tp): return tp!
            case .Dereference(_, let tp): return tp!
            case .AddrOf(_, let tp): return tp!
            case .Subscript(_, _, let tp):  return tp!
            case .String(_, let tp): return tp!
            case .SizeOf(_, let tp): return tp!
            case .SizeOfT(_, let tp): return tp!
            case .Dot(_, _, let tp): return tp!
            case .Arrow(_, _, let tp): return tp!
        }
    }

}