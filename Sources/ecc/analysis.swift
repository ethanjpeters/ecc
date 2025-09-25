import Foundation

class SemanticAnalyzer {
    class VariableResolver {
        struct NameMapEntry {
            public let newName : String
            public let currentScope : Bool
            public let hasLinkage : Bool
        }


        private var tempNameCounter : Int = 0

        func makeTemp(_ base : String) -> String {
            let out = "\(base).uniqued.\(tempNameCounter)"  // used "uniqued" to avoid collisions with "tmp.#" variables
            tempNameCounter = tempNameCounter + 1
            return out
        }

        func copyNameMap(_ nameMap: [String : NameMapEntry]) -> [String : NameMapEntry] {
            var out : [String : NameMapEntry] = [:]
            for (name, entry) in nameMap {
                out[name] = .init(newName: entry.newName, currentScope: false, hasLinkage: entry.hasLinkage)
            }
            return out
        }

        func isValidLValue(_ exp: Parser.AST.Expression) -> Bool {
            switch exp {
                case .Var(_, _): return true
                default: return false
            }
        }

        func resolveExpression(_ exp : Parser.AST.Expression, _ nameMap: inout [String : NameMapEntry]) -> Parser.AST.Expression {
            switch exp {
                case .Assignment(let lValue, let rValue, _):
                    if !isValidLValue(lValue) {
                        print("Invalid lvalue in assignment \(exp)")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    return .Assignment(resolveExpression(lValue, &nameMap), resolveExpression(rValue, &nameMap), nil)
                case .CompoundAssignment(_,_,_,_):
                    print("Unreachable: Unsupported compound assignment found while analyzing")
                    exit(ExitCode.internalError.rawValue)
                case .Binary(let op, let left, let right, _):
                    return .Binary(op, resolveExpression(left, &nameMap), resolveExpression(right, &nameMap), nil)
                case .ConstInt(_, _): fallthrough
                case .ConstLong(_, _):
                    return exp
                case .Unary(let op, let child, _):
                    return .Unary(op, resolveExpression(child, &nameMap), nil)
                case .Var(let name, _):
                    if let uniqueName = nameMap[name] {
                        return .Var(uniqueName.newName, nil)
                    } else {
                        print("Undeclared variable \(name)")
                        exit(ExitCode.semanticError.rawValue)
                    }
                case .Conditional(let cond, let left, let right, _):
                    return .Conditional(resolveExpression(cond, &nameMap), resolveExpression(left, &nameMap), resolveExpression(right, &nameMap), nil)
                case .FunctionCall(let fun, let parameters, _):
                    if !isValidLValue(fun) {    // TODO: is this actually all we need for something to be callable?
                        print("Function \(fun) could not be resolved to valid lvalue")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    return .FunctionCall(resolveExpression(fun, &nameMap), parameters.map { resolveExpression($0, &nameMap) }, nil)
                case .Cast(let targetType, let child, _):
                    return .Cast(targetType, resolveExpression(child, &nameMap), nil)
            }
        }

        func resolveStatement(_ stmt : Parser.AST.Statement, _ nameMap: inout [String : NameMapEntry]) -> Parser.AST.Statement {
            switch stmt {
                case .Expression(let exp): return .Expression(resolveExpression(exp, &nameMap))
                case .Return(let exp): return .Return(exp == nil ? nil : resolveExpression(exp!, &nameMap))
                case .Null: return .Null
                case .If(let cond, let thenStatement, let elseStatement):
                    return .If(resolveExpression(cond, &nameMap), resolveStatement(thenStatement, &nameMap),
                               elseStatement == nil ? nil : resolveStatement(elseStatement!, &nameMap))
                case .Compound(let block):
                    switch block {
                        case .Block(let items):
                            var copiedNameMap = copyNameMap(nameMap)
                            return .Compound(.Block(items.map { itm in
                                return resolveBlockItem(itm, &copiedNameMap)
                            }))
                    }
                case .Break(_): return stmt
                case .Continue(_): return stmt
                case .While(let condition, let body, _):
                    var copiedNameMap = copyNameMap(nameMap)
                    return .While(resolveExpression(condition, &nameMap), resolveStatement(body, &copiedNameMap), "")
                case .DoWhile(let body, let condition, _):
                    var copiedNameMap = copyNameMap(nameMap)
                    return .DoWhile(resolveStatement(body, &copiedNameMap), resolveExpression(condition, &nameMap), "")
                case .For(let forInit, let condition, let inc, let body, _):
                    var copiedNameMap = copyNameMap(nameMap)
                    let resolvedForInit : Parser.AST.ForInit
                    switch forInit {
                        case .InitDecl(let decl):
                            resolvedForInit = .InitDecl(resolveDeclaration(decl, false, &copiedNameMap))
                        case .InitExp(let exp):
                            resolvedForInit = .InitExp(exp == nil ? nil : resolveExpression(exp!, &copiedNameMap))
                    }
                    let resolvedCondition = condition == nil ? nil : resolveExpression(condition!, &copiedNameMap)
                    let resolvedInc = inc == nil ? nil : resolveExpression(inc!, &copiedNameMap)
                    let resolvedBody = resolveStatement(body, &copiedNameMap)
                    return .For(resolvedForInit, resolvedCondition, resolvedInc, resolvedBody, "")
                case .Switch(let toggle, let body, let label):
                    return .Switch(resolveExpression(toggle, &nameMap), resolveStatement(body, &nameMap), label)
                case .Labeled(let ls):
                    switch ls {
                        case .CaseStatement(let val, let exe):
                            return .Labeled(.CaseStatement(resolveExpression(val, &nameMap), resolveStatement(exe, &nameMap)))
                        case .DefaultStatement(let exe):
                            return .Labeled(.DefaultStatement(resolveStatement(exe, &nameMap)))
                        case .IdentifiedLine(let name, let st):
                            return .Labeled(.IdentifiedLine(name, resolveStatement(st, &nameMap)))
                    }
            }
        }

        func resolveDeclaration(_ decl: Parser.AST.Declaration, _ fileScope: Bool, _ nameMap: inout [String : NameMapEntry]) -> Parser.AST.Declaration {
            switch decl {
                case .VariableDeclaration(let tp, let name, let exp, let storageClass):
                    if fileScope {
                        nameMap[name] = .init(newName: name, currentScope: true, hasLinkage: true)
                        return decl
                    } else {
                        if let n = nameMap[name] {
                            if n.currentScope {
                                if !(n.hasLinkage && storageClass == .Extern) {
                                    print("Duplicate variable name found: \(n)")
                                    exit(ExitCode.semanticError.rawValue)
                                }
                            }
                        }
                        if storageClass == .Extern {
                            nameMap[name] = .init(newName: name, currentScope: true, hasLinkage: true)
                            return decl
                        } else {
                            let uniqueName = makeTemp(name)
                            nameMap[name] = .init(newName: uniqueName, currentScope: true, hasLinkage: false)
                            var outInit : Parser.AST.Expression? = nil
                            if let initializer = exp {
                                outInit = resolveExpression(initializer, &nameMap)
                            }
                            return .VariableDeclaration(tp, uniqueName, outInit, storageClass)
                        }
                    }
                case .FunctionDeclaration(let returnType, let name, let params, let body,  let storageClass):
                    nameMap[name] = .init(newName: name, currentScope: true, hasLinkage: true)
                    var copiedNameMap = copyNameMap(nameMap)
                    var mangledPNames: [Parser.AST.Parameter] = []
                    for p in params {
                        switch p {
                            case .NamedParameter(let pType, let pName):
                                let uniqueName = makeTemp(pName)
                                copiedNameMap[pName] = .init(newName: uniqueName, currentScope: true, hasLinkage: false)
                                mangledPNames.append(.NamedParameter(pType, uniqueName))
                        }
                    }
                    if let b = body {
                        switch b {
                            case .Block(let items):
                                return .FunctionDeclaration(returnType, name, mangledPNames, .Block(items.map { resolveBlockItem($0, &copiedNameMap) }), storageClass)
                        }
                    } else {
                        return .FunctionDeclaration(returnType, name, mangledPNames, nil, storageClass)
                    }
            }
        }

        func resolveBlockItem(_ blockItem: Parser.AST.BlockItem, _ nameMap: inout [String : NameMapEntry]) -> Parser.AST.BlockItem {
            switch blockItem {
                case .D(let decl):
                    return .D(resolveDeclaration(decl, false, &nameMap))
                case .S(let stmt):
                    return .S(resolveStatement(stmt, &nameMap))
            }
        }

        func resolveVariables(_ program: Parser.AST.Program) -> Parser.AST.Program {
            var variableNameMapping : [String : NameMapEntry] = [:]
            switch program {
                case .Statement(let declarations):
                    var resolvedDecls : [Parser.AST.Declaration] = []
                    for decl in declarations {
                        resolvedDecls.append(resolveDeclaration(decl, true, &variableNameMapping))
                    }
                    return .Statement(resolvedDecls)
            }
        }
    }

    class LoopLabeler {
        private var tempLabelCounter : Int = 0

        func makeLoopLabel() -> String {
            let label = "loop\(tempLabelCounter)"
            tempLabelCounter = tempLabelCounter + 1
            return label
        }

        func makeSwitchLabel() -> String {
            let label = "switch\(tempLabelCounter)"
            tempLabelCounter = tempLabelCounter + 1
            return label
        }

        func labelLoops(_ statement: Parser.AST.Statement, loopLabel: String?, switchLabel: String?) -> Parser.AST.Statement {
            switch statement {
                case .Break(_):
                    if let lab = loopLabel {
                        return .Break(lab)
                    } else {
                        if let lab = switchLabel {
                            return .Break(lab)
                        } else {
                            print("Unlabeled break statement")
                            exit(ExitCode.semanticError.rawValue)
                        }
                    }
                case .Continue(_):
                    if let lab = loopLabel {
                        return .Continue(lab)
                    } else {
                        print("Continue found outside of loop")
                        exit(ExitCode.semanticError.rawValue)
                    }
                case .DoWhile(let body, let condition, _):
                    let newLabel = makeLoopLabel()
                    let labeledBody = labelLoops(body, loopLabel: newLabel, switchLabel: nil)
                    let labeledCondition = labelLoops(condition, loopLabel: newLabel, switchLabel: nil)
                    return .DoWhile(labeledBody, labeledCondition, newLabel)
                case .While(let condition, let body, _):
                    let newLabel = makeLoopLabel()
                    let labeledBody = labelLoops(body, loopLabel: newLabel, switchLabel: nil)
                    let labeledCondition = labelLoops(condition, loopLabel: newLabel, switchLabel: nil)
                    return .While(labeledCondition, labeledBody, newLabel)
                case .For(let forInit, let condition, let increment, let body, _):
                    let newLabel = makeLoopLabel()
                    let labeledForInit : Parser.AST.ForInit
                    switch forInit {
                        case .InitDecl(let decl):
                            switch decl {
                                case .VariableDeclaration(let tp, let name, let exp, let storageClass):
                                    labeledForInit = .InitDecl(.VariableDeclaration(
                                        tp,
                                        name,
                                        exp == nil ? nil : labelLoops(
                                            exp!,
                                            loopLabel: newLabel,
                                            switchLabel: nil
                                        ),
                                        storageClass
                                    ))
                                default:
                                    print("Unreachable case where something other than a variable was declared as the initializer to a for loop: \(decl)")
                                    exit(ExitCode.internalError.rawValue)
                            }
                        case .InitExp(let exp):
                            labeledForInit = .InitExp(exp == nil ? nil : labelLoops(
                                exp!,
                                loopLabel: newLabel,
                                switchLabel: nil
                            ))
                    }
                    let labeledCondition = condition == nil ? nil : labelLoops(condition!, loopLabel: newLabel, switchLabel: nil)
                    let labeledIncrement = increment == nil ? nil : labelLoops(increment!, loopLabel: newLabel, switchLabel: nil)
                    let labeledBody = labelLoops(body, loopLabel: newLabel, switchLabel: nil)
                    return .For(labeledForInit, labeledCondition, labeledIncrement, labeledBody, newLabel)
                case .Return(let exp):
                    return .Return(exp == nil ? nil : labelLoops(exp!, loopLabel: loopLabel, switchLabel: nil))
                case .Expression(let exp):
                    return .Expression(labelLoops(exp, loopLabel: loopLabel, switchLabel: nil))
                case .If(let cond, let thenStatement, let elseStatement):
                    return .If(
                        labelLoops(cond, loopLabel: loopLabel, switchLabel: nil),
                        labelLoops(thenStatement, loopLabel: loopLabel, switchLabel: nil),
                        elseStatement == nil ? nil : labelLoops(elseStatement!, loopLabel: loopLabel, switchLabel: nil)
                    )
                case .Compound(let block):
                    return .Compound(labelLoops(block, loopLabel: loopLabel, switchLabel: switchLabel))
                case .Null: return .Null
                case .Switch(let toggle, let body, _):
                    let switchLabel = makeSwitchLabel()
                    return .Switch(
                        labelLoops(toggle, loopLabel: nil, switchLabel: switchLabel),
                        labelLoops(body, loopLabel: nil, switchLabel: switchLabel),
                        switchLabel
                    )
                case .Labeled(let ls):
                    switch ls {
                        case .CaseStatement(let lbl, let lineStatement):
                            return .Labeled(.CaseStatement(
                                labelLoops(lbl, loopLabel: loopLabel, switchLabel: switchLabel),
                                labelLoops(lineStatement, loopLabel: loopLabel, switchLabel: switchLabel)
                            ))
                        case .DefaultStatement(let ds):
                            return .Labeled(.DefaultStatement(labelLoops(
                                ds,
                                loopLabel: loopLabel,
                                switchLabel: switchLabel
                            )))
                        case .IdentifiedLine(let lbl, let lineStatement):
                            return .Labeled(.IdentifiedLine(lbl, labelLoops(
                                lineStatement,
                                loopLabel: loopLabel,
                                switchLabel: switchLabel
                            )))
                    }
            }
        }

        func labelLoops(_ expression: Parser.AST.Expression, loopLabel: String?, switchLabel: String?) -> Parser.AST.Expression {
            // this might actually be correct
            return expression
        }

        func labelLoops(_ declaration: Parser.AST.Declaration, loopLabel: String?, switchLabel: String?) -> Parser.AST.Declaration {
            switch declaration {
                case .VariableDeclaration(let tp, let name, let exp, let storageClass):
                    let outExp : Parser.AST.Expression?
                    if let e = exp {
                        outExp = labelLoops(e, loopLabel: loopLabel, switchLabel: switchLabel)
                    } else {
                        outExp = nil
                    }
                    return .VariableDeclaration(tp, name, outExp, storageClass)
                case .FunctionDeclaration(let returnType, let name, let params, let body, let storageClass):
                    let outBody : Parser.AST.Block?
                    if let b = body {
                        outBody = labelLoops(b, loopLabel: loopLabel, switchLabel: switchLabel)
                    } else {
                        outBody = nil
                    }
                    return .FunctionDeclaration(returnType, name, params, outBody, storageClass)
            }
        }

        func labelLoops(_ blockItem: Parser.AST.BlockItem, loopLabel: String?, switchLabel: String?) -> Parser.AST.BlockItem {
            switch blockItem {
                case .D(let decl):
                    return .D(labelLoops(decl, loopLabel: loopLabel, switchLabel: switchLabel))
                case .S(let stmt):
                    return .S(labelLoops(stmt, loopLabel: loopLabel, switchLabel: switchLabel))
            }
        }

        func labelLoops(_ block : Parser.AST.Block, loopLabel: String?, switchLabel: String?) -> Parser.AST.Block {
            switch block {
                case .Block(let items):
                    var labeledItems : [Parser.AST.BlockItem] = []
                    for itm in items {
                        labeledItems.append(labelLoops(itm, loopLabel: loopLabel, switchLabel: switchLabel))
                    }
                    return .Block(labeledItems)
            }
        }

        func labelLoops(_ program: Parser.AST.Program) -> Parser.AST.Program {
            switch program {
                case .Statement(let decls):
                    return .Statement(decls.map { labelLoops($0, loopLabel: nil, switchLabel: nil) })
            }
        }
    }

    class CasePlacer {
        func placeCases(_ expression: Parser.AST.Expression, isInSwitch: Bool) -> Parser.AST.Expression {
            return expression
        }

        func placeCases(_ statement: Parser.AST.Statement, isInSwitch: Bool) -> Parser.AST.Statement {
            switch statement {
                case .Return(let exp): return .Return(exp == nil ? nil : placeCases(exp!, isInSwitch: isInSwitch))
                case .Expression(let exp): return .Expression(placeCases(exp, isInSwitch: isInSwitch))
                case .If(let condition, let thenClause, let elseClause):
                    let placedCondition = placeCases(condition, isInSwitch: isInSwitch)
                    let placedThen = placeCases(thenClause, isInSwitch: isInSwitch)
                    let placedElse: Parser.AST.Statement?
                    if let ec = elseClause {
                        placedElse = placeCases(ec, isInSwitch: isInSwitch)
                    } else {
                        placedElse = nil
                    }
                    return .If(placedCondition, placedThen, placedElse)
                case .Compound(let block):
                    return .Compound(placeCases(block, isInSwitch: isInSwitch))
                case .Null: return .Null
                case .Break(let label): return .Break(label)
                case .Continue(let label): return .Continue(label)
                case .While(let condition, let body, let label):
                    return .While(
                        placeCases(condition, isInSwitch: isInSwitch),
                        placeCases(body, isInSwitch: isInSwitch),
                        label
                    )
                case .DoWhile(let body, let condition, let label):
                    return .DoWhile(
                        placeCases(body, isInSwitch: isInSwitch),
                        placeCases(condition, isInSwitch: isInSwitch),
                        label
                    )
                case .For(let forInit, let condition, let post, let body, let label):
                    return .For(
                        forInit,    // forInits can not have labels of any kind because they contain no statements
                        condition == nil ? nil : placeCases(condition!, isInSwitch: isInSwitch),
                        post == nil ? nil : placeCases(post!, isInSwitch: isInSwitch),
                        placeCases(body, isInSwitch: isInSwitch),
                        label
                    )
                case .Switch(let toggle, let body, let label):
                    return .Switch(
                        placeCases(toggle, isInSwitch: false),
                        placeCases(body, isInSwitch: true),
                        label
                    )
                case .Labeled(let ls):
                    switch ls {
                        case .CaseStatement(let exp, let line):
                            if isInSwitch {
                                /**
                                * NOTE: this allows constructs like:
                                switch (x) {
                                    case 10: if (x > 100) { case 12: x; }
                                };
                                which are functionally meaningless but semantically and gramatically valid 
                                **/
                                return .Labeled(.CaseStatement(placeCases(exp, isInSwitch: true), placeCases(line, isInSwitch: true)))
                            } else {
                                print("Case statement found outside of switch statement")
                                exit(ExitCode.semanticError.rawValue)
                            }
                        case .DefaultStatement(let stmt):
                            // NOTE: we need to make sure there is only one default in every switch statement; we will attempt to
                            // enforce that in the tacky generation phase
                            if isInSwitch {
                                return .Labeled(.DefaultStatement(placeCases(stmt, isInSwitch: true)))
                            } else {
                                print("Default statement found outside of switch statement")
                                exit(ExitCode.semanticError.rawValue)
                            }
                        case .IdentifiedLine(let label, let stmt): return .Labeled(.IdentifiedLine(
                            label,
                            placeCases(stmt, isInSwitch: isInSwitch)
                        ))
                    }
            }
        }

        func placeCases(_ declaration: Parser.AST.Declaration, isInSwitch: Bool) -> Parser.AST.Declaration {
            switch declaration {
                case .FunctionDeclaration(let returnType, let name, let params, let body, let storageClass):
                    return .FunctionDeclaration(returnType, name, params, body == nil ? nil : placeCases(body!, isInSwitch: false), storageClass)
                case .VariableDeclaration(let tp, let name, let exp, let storageClass):
                    return .VariableDeclaration(tp, name, exp == nil ? nil : placeCases(exp!, isInSwitch: isInSwitch), storageClass)
            }
        }

        func placeCases(_ block: Parser.AST.Block, isInSwitch: Bool) -> Parser.AST.Block {
            switch block {
                case .Block(let items):
                    var placedItems : [Parser.AST.BlockItem] = []
                    for itm in items {
                        switch itm {
                            case .D(let decl):
                                placedItems.append(.D(placeCases(decl, isInSwitch: isInSwitch)))
                            case .S(let stmt):
                                placedItems.append(.S(placeCases(stmt, isInSwitch: isInSwitch)))
                        }
                    }
                    return .Block(placedItems)
            }
        }

        func placeCases(_ program: Parser.AST.Program) -> Parser.AST.Program {
            switch program {
                case .Statement(let declarations):
                    return .Statement(declarations.map { placeCases($0, isInSwitch: false) })
            }
        }
    }

    class TypeChecker {
        indirect enum CheckerType : Equatable {
            case Int
            case Long
            case Void
            case Function(CheckerType /* return */, [CheckerType] /* params */)
        }

        enum StaticInit {
            case IntInit(Int32)
            case LongInit(Int64)
        }

        enum InitialValue {
            case Tentative
            case Initial(StaticInit)   // NOTE: other types will affect this
            case NoInitializer
        }

        enum IdentifierAttributes {
            case FunAttr(Bool /* is defined */, Bool /* is global */)
            case StaticAttr(InitialValue /* init */, Bool /* is global */)
            case LocalAttr
        }

        static func deConvert(_ cType : CheckerType) -> Parser.AST.CType {
            switch cType {
                case .Int: return .Int
                case .Void: return .Void
                case .Long: return .Long
                case .Function(_, _):
                    print("UNREACHABLE FUNC")
                    exit(ExitCode.internalError.rawValue)
            }
        }

        func getCommonType(_ left : CheckerType, _ right: CheckerType) -> CheckerType {
            if left == right { return left }
            return .Long
        }

        func typeConvert(_ exp: Parser.AST.Expression, ofType: CheckerType, toType: CheckerType) -> Parser.AST.Expression {
            if ofType == toType { return exp }
            return .Cast(Self.deConvert(toType), exp, Self.deConvert(ofType))
        }

        func typeCheck(_ expression: Parser.AST.Expression, _ nameMap: [String: (CheckerType, IdentifierAttributes)]) -> (Parser.AST.Expression, CheckerType) {
            switch expression {
                case .ConstInt(let val, _): return (.ConstInt(val, .Int), .Int)
                case .ConstLong(let val, _): return (.ConstLong(val, .Long), .Long)
                case .Unary(let unOp, let e, _):
                    let (checkedE, eType) = typeCheck(e, nameMap) // TODO: not all operators make sense on every type
                    if eType == .Void {
                        print("Tried to perform unary operation \(unOp) on void expression \(e)")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    let outType : Parser.AST.CType
                    switch unOp {
                        case .Not:
                            outType = .Int
                        default:
                            outType = Self.deConvert(eType)
                    }
                    return (.Unary(unOp, checkedE, outType), converCTypeToCheckerType(outType))
                case .Binary(let binOp, let left, let right, _):
                    // TODO: not all binary operations on all pairs of types make sense
                    let (checkedLeft, leftType) = typeCheck(left, nameMap)
                    switch leftType {
                        case .Void: fallthrough
                        case .Function(_, _):
                            print("Left hand side (\(left)) of binary operation \(binOp) is \(leftType)")
                            exit(ExitCode.semanticError.rawValue)
                        default: ()
                    }
                    let (checkedRight, rightType) = typeCheck(right, nameMap)
                    switch rightType {
                        case .Void: fallthrough
                        case .Function(_, _):
                            print("Right hand side (\(right)) of binary operation \(binOp) is \(rightType)")
                            exit(ExitCode.semanticError.rawValue)
                        default: ()
                    }

                    switch binOp {
                        case .And: fallthrough
                        case .Or:
                            return (.Binary(binOp, checkedLeft, checkedRight, .Int), .Int)
                        default: ()
                    }
                    let outType = getCommonType(leftType, rightType)
                    let binExp : Parser.AST.Expression = .Binary(
                        binOp,
                        typeConvert(checkedLeft, ofType: leftType, toType: outType),
                        typeConvert(checkedRight, ofType: rightType, toType: outType),
                        Self.deConvert(outType)
                    )
                    switch binOp {
                        case .Add: fallthrough
                        case .Subtract: fallthrough
                        case .Multiply: fallthrough
                        case .Divide: fallthrough
                        case .Remainder: fallthrough
                        case .BitwiseShiftLeft: fallthrough
                        case .BitwiseShiftRight: fallthrough
                        case .BitwiseXor:
                            return (binExp, outType)
                        default:
                            return (binExp, .Int)
                    }
                case .Var(let name, _):
                    // name is enforced to exist
                    let (tp, _) = nameMap[name]!
                    return (.Var(name, Self.deConvert(tp)), tp)
                case .Assignment(let lValue, let exp, _):
                    // lValue is already enforced to be a valid lValue
                    let name: String
                    switch lValue {
                        case .Var(let nm, _):
                            name = nm
                        default:
                            print("Unreachable non lValue in assignment \(lValue)")
                            exit(ExitCode.internalError.rawValue)
                    }
                    let (tp, _) = nameMap[name]!
                    let (checkedExp, expType) = typeCheck(exp, nameMap)
                    return (.Assignment(
                        .Var(name, Self.deConvert(tp)),
                        typeConvert(checkedExp, ofType: expType, toType: tp),
                        Self.deConvert(tp)
                    ), tp)
                case .CompoundAssignment(_, _, _, _):
                    print("Unreachable compound assignment found during type checking")
                    exit(ExitCode.internalError.rawValue)
                case .Conditional(let cond, let left, let right, _):
                    let (checkedCond, condType) = typeCheck(cond, nameMap)
                    let (checkedLeft, leftType) = typeCheck(left, nameMap)
                    let (checkedRight, rightType) = typeCheck(right, nameMap)
                    let outType = getCommonType(leftType, rightType)
                    return (.Conditional(
                        typeConvert(checkedCond, ofType: condType, toType: .Int),
                        typeConvert(checkedLeft, ofType: leftType, toType: outType),
                        typeConvert(checkedRight, ofType: rightType, toType: outType),
                        Self.deConvert(outType)
                    ), outType)
                case .FunctionCall(let lValue, let params, _):
                    // lValue is already enforced to be a valid lValue
                    let name: String
                    switch lValue {
                        case .Var(let nm, _):
                            name = nm
                        default:
                            print("Unreachable non lValue in function call \(lValue)")
                            exit(ExitCode.internalError.rawValue)
                    }
                    var checkedParams : [(Parser.AST.Expression, TypeChecker.CheckerType)] = []
                    for p in params {
                        let q = typeCheck(p, nameMap)
                        checkedParams.append(q)
                    }
                    let (fType, _) = nameMap[name]!
                    switch fType {
                        case .Function(let rType, let pType):
                            if checkedParams.count != pType.count {
                                print("Function call \(name) does not have the right number of arguments")
                                exit(ExitCode.semanticError.rawValue)
                            }
                            var upCastExp : [Parser.AST.Expression] = []
                            for (incomingParam, expectedParam) in zip(checkedParams, pType) {
                                let commonType = getCommonType(incomingParam.1, expectedParam)
                                let ipExp = typeConvert(incomingParam.0, ofType: incomingParam.1, toType: commonType)
                                upCastExp.append(ipExp)
                            }
                            return (.FunctionCall(lValue, upCastExp, Self.deConvert(rType)), rType)
                        case .Int: fallthrough
                        case .Long: fallthrough
                        case .Void:
                            print("Can not call value \(lValue) of type \(fType)")
                            exit(ExitCode.semanticError.rawValue)
                    }
                case .Cast(let targetType, let child, _):
                    let tmp = typeCheck(child, nameMap)
                    // DEBUG
                    print("TYPE CHECKING CAST OF \(child) TO \(targetType): \(tmp)")
                    // END DEBUG
                    return (.Cast(targetType, tmp.0, Self.deConvert(tmp.1)), tmp.1)
            }
        }

        func typeCheck(_ statement: Parser.AST.Statement, _ nameMap: inout [String: (CheckerType, IdentifierAttributes)], _ enclosingFuncReturnType : Parser.AST.CType) -> Parser.AST.Statement {
            switch statement {
                case .Return(let exp):
                    if let e = exp {
                        if enclosingFuncReturnType == .Void {
                            print("Attempted to return non-void value \(e) from void function")
                            exit(ExitCode.semanticError.rawValue)
                        }
                        let (outExp, outTp) = typeCheck(e, nameMap)
                        let castExp = typeConvert(outExp, ofType: outTp, toType: converCTypeToCheckerType(enclosingFuncReturnType))
                        return .Return(castExp)
                    } else {
                        if enclosingFuncReturnType != .Void {
                            print("Returning void from non-void function (of type \(enclosingFuncReturnType))")
                            exit(ExitCode.semanticError.rawValue)
                        }
                        return .Return(nil)
                    }
                case .Expression(let exp):
                    return .Expression(typeCheck(exp, nameMap).0)
                case .If(let condition, let thenClause, let elseClause):
                    let checkedCond = typeCheck(condition, nameMap).0   // TODO: do we need to cast this guy?
                    let checkedThen = typeCheck(thenClause, &nameMap, enclosingFuncReturnType)
                    let checkedElse: Parser.AST.Statement?
                    if let els = elseClause {
                        checkedElse = typeCheck(els, &nameMap, enclosingFuncReturnType)
                    } else {
                        checkedElse = nil
                    }
                    return .If(checkedCond, checkedThen, checkedElse)
                case .Compound(let block):
                    return .Compound(typeCheck(block, &nameMap, enclosingFuncReturnType))
                case .Null: return .Null
                case .Break(_): return statement
                case .Continue(_): return statement
                case .While(let condition, let body, let lbl):
                    let checkedCond = typeCheck(condition, nameMap)
                    let checkedBody = typeCheck(body, &nameMap, enclosingFuncReturnType)
                    return .While(checkedCond.0, checkedBody, lbl)
                case .DoWhile(let body, let condition, let lbl):
                    let checkedBody = typeCheck(body, &nameMap, enclosingFuncReturnType)
                    let checkedCond = typeCheck(condition, nameMap)
                    return .DoWhile(checkedBody, checkedCond.0, lbl)
                case .For(let forInit, let condition, let post, let body, let lbl):
                    let checkedInit : Parser.AST.ForInit
                    switch forInit {
                        case .InitDecl(let decl):
                            switch decl {
                                case .FunctionDeclaration(_, let name, _, _, _):
                                    print("Unreachable totally guano-on-toast insanse situation where a function \(name) was declared in the initializer of a for loop")
                                    exit(ExitCode.internalError.rawValue)
                                case .VariableDeclaration(_, _ , _, _):
                                    checkedInit = .InitDecl(typeCheck(decl, false, &nameMap))
                            }
                        case .InitExp(let exp):
                            if let e = exp {
                                checkedInit = .InitExp(typeCheck(e, nameMap).0)
                            } else {
                                checkedInit = .InitExp(nil)
                            }
                    }
                    let checkedCondition : Parser.AST.Expression?
                    if let c = condition {
                        checkedCondition = typeCheck(c, nameMap).0
                    } else {
                        checkedCondition = nil
                    }
                    let checkedPost : Parser.AST.Expression?
                    if let p = post {
                        checkedPost = typeCheck(p, nameMap).0
                    } else {
                        checkedPost = nil
                    }
                    let checkedBody = typeCheck(body, &nameMap, enclosingFuncReturnType)
                    return .For(checkedInit, checkedCondition, checkedPost, checkedBody, lbl)
                case .Switch(let toggle, let body, let lbl):
                    // TODO: cast this to bool-like
                    let checkedToggle = typeCheck(toggle, nameMap)
                    let checkedBody = typeCheck(body, &nameMap, enclosingFuncReturnType)
                    return .Switch(checkedToggle.0, checkedBody, lbl)
                case .Labeled(let ls):
                    let checkedLine : Parser.AST.LabeledStatement
                    switch ls {
                        // TODO: some type checking that should be happening isn't happening inside of switch statements
                        case .CaseStatement(let lbl, let line):    // don't bother type checking a constant
                            checkedLine = .CaseStatement(lbl, typeCheck(line, &nameMap, enclosingFuncReturnType))
                        case .DefaultStatement(let line):
                            checkedLine = .DefaultStatement(typeCheck(line, &nameMap, enclosingFuncReturnType))
                        case .IdentifiedLine(let lbl, let line):
                            checkedLine = .IdentifiedLine(lbl, typeCheck(line, &nameMap, enclosingFuncReturnType))
                    }
                    return .Labeled(checkedLine)
            }
        }

        // NOTE: this does not match return statements with function return types
        func typeCheck(_ block: Parser.AST.Block, _ nameMap : inout [String : (CheckerType, IdentifierAttributes)], _ enclosingFuncReturnType : Parser.AST.CType) -> Parser.AST.Block {
            switch block {
                case .Block(let blockItems):
                    var typeCheckedItems : [Parser.AST.BlockItem] = []
                    for item in blockItems {
                        switch item {
                            case .D(let decl):
                                switch decl {
                                    case .FunctionDeclaration(_, let name, _, let body, _):
                                        if let _ = body {
                                            print("Inline functions are disallowed: \(name)")
                                            exit(ExitCode.semanticError.rawValue)
                                        }
                                    case .VariableDeclaration(_, _, _, _):
                                        typeCheckedItems.append(.D(typeCheck(decl, false, &nameMap)))
                                }
                            case .S(let stmt):
                                typeCheckedItems.append(.S(typeCheck(stmt, &nameMap, enclosingFuncReturnType)))
                        }
                    }
                    return .Block(typeCheckedItems)
            }
        }

        func typeCheck(_ declaration: Parser.AST.Declaration, _ fileLevel: Bool, _ nameMap : inout [String : (CheckerType, IdentifierAttributes)]) -> Parser.AST.Declaration {
            switch declaration {
                case .FunctionDeclaration(let returnType, let name, let params, let body, let storageClass):
                    if !fileLevel && body != nil {
                        print("Cannot define function \(name) inline")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    let sc : Parser.AST.StorageClass
                    if storageClass != nil { sc = storageClass! } else { sc = .Extern }
                    var paramTypes : [CheckerType] = []
                    for p in params {
                        switch p {
                            case .NamedParameter(let tp, _):
                                paramTypes.append(converCTypeToCheckerType(tp))
                        }
                    }
                    let constructedType : CheckerType = .Function(converCTypeToCheckerType(returnType), paramTypes)
                    let isDefined : Bool = body != nil
                    let isGlobal : Bool = sc != .Static
                    if let preExistingFunction = nameMap[name] {
                        let (oldType, oldAttributes) = preExistingFunction
                        if oldType != constructedType {
                            print("Funciton \(name) was redeclared with a different type")
                            exit(ExitCode.semanticError.rawValue)
                        }
                        switch oldAttributes {
                            case .FunAttr(let oldDefined, let oldGlobal):
                                if oldGlobal && sc == .Static {
                                    print("Static function \(name) declaration follows non-static")
                                    exit(ExitCode.semanticError.rawValue)
                                }
                                if oldDefined && isDefined {
                                    print("Function \(name) defined twice")
                                    exit(ExitCode.semanticError.rawValue)
                                }
                            default:
                                print("Unreachable non-function attributes attached to previously declared function")
                                exit(ExitCode.semanticError.rawValue)
                        }
                    }
                    nameMap[name] = (constructedType, .FunAttr(isDefined, isGlobal))
                    for p in params {
                        switch p {
                            case .NamedParameter(let tp, let name):
                                nameMap[name] = (converCTypeToCheckerType(tp), .LocalAttr)
                        }
                    }
                    let typeCheckedBody : Parser.AST.Block?
                    if let b = body {
                        typeCheckedBody = typeCheck(b, &nameMap, returnType)
                    } else {
                        typeCheckedBody = nil
                    }
                    return .FunctionDeclaration(returnType, name, params, typeCheckedBody, storageClass)
                case .VariableDeclaration(let tp, let name, let initExp, let storageClass):
                    var typeCheckedInit : Parser.AST.Expression?
                    let initType : CheckerType
                    let conTp = converCTypeToCheckerType(tp)
                    if let e = initExp {
                        (typeCheckedInit, initType) = typeCheck(e, nameMap)
                        let commonType = getCommonType(initType, conTp)
                        typeCheckedInit = typeConvert(typeCheckedInit!, ofType: initType, toType: commonType)
                    } else {
                        initType = conTp
                        typeCheckedInit = nil
                    }
                    if fileLevel {
                        var initVal : InitialValue
                        if let ie = initExp {
                            switch ie {
                                case .ConstInt(let i, _):
                                    initVal = .Initial(.IntInit(Int32(i)))
                                case .ConstLong(let i, _):
                                    initVal = .Initial(.LongInit(Int64(i)))
                                default:
                                    // NOTE: we could allow things that evaluate constantly, but we don't yet
                                    print("Non constant expression \(ie) used to initialize global \(name)")
                                    exit(ExitCode.semanticError.rawValue)
                            }
                        } else {
                            if storageClass == .Extern {
                                initVal = .NoInitializer
                            } else {
                                initVal = .Tentative
                            }
                        }
                        var isGlobal = storageClass != .Static

                        if let oldEntry = nameMap[name] {
                            let (oldType, oldAttr) = oldEntry
                            if oldType != conTp {
                                print("Variable \(name) redefined as incongruent type")
                                exit(ExitCode.semanticError.rawValue)
                            }
                            switch oldAttr {
                                case .FunAttr(_, _):
                                    print("Unreachable function variable")
                                    exit(ExitCode.internalError.rawValue)
                                case .LocalAttr:
                                    print("Unreachabel local that survived to file scope")
                                    exit(ExitCode.internalError.rawValue)
                                case .StaticAttr(let oldInit, let glob):
                                    if storageClass == .Extern {
                                        isGlobal = glob
                                    } else {
                                        if glob != isGlobal {
                                            print("Conflicting variable linkage for \(name)")
                                            exit(ExitCode.semanticError.rawValue)
                                        }
                                    }
                                    switch oldInit {
                                        case .Initial(_):
                                            switch initVal {
                                                case .Initial(_):
                                                    print("Conflicting file scope variable definitions of \(name)")
                                                    exit(ExitCode.semanticError.rawValue)
                                                default: ()
                                            }
                                            initVal = oldInit
                                        case .Tentative:
                                            switch initVal {
                                                case .Initial(_):
                                                    ()
                                                default:
                                                    initVal = .Tentative
                                            }
                                        default:
                                            ()
                                    }
                            }
                        }
                        nameMap[name] = (conTp, .StaticAttr(initVal, isGlobal))
                    } else {
                        if storageClass == .Extern {
                            if initExp != nil {
                                print("Initializer on local extern variable declaration \(name)")
                                exit(ExitCode.semanticError.rawValue)
                            }
                            if let oldEntry = nameMap[name] {
                                let (oldType, _) = oldEntry
                                if oldType != conTp {
                                    print("Variable \(name) redeclared with incompatible type")
                                    exit(ExitCode.semanticError.rawValue)
                                }
                            } else {
                                nameMap[name] = (conTp, .StaticAttr(.NoInitializer, true))
                            }
                        } else if storageClass == .Static {
                            let initValue : InitialValue
                            if let e = initExp {
                                switch e {
                                    case .ConstInt(let i, _):
                                        initValue = .Initial(.IntInit(Int32(i)))
                                    case .ConstLong(let i, _):
                                        initValue = .Initial(.LongInit(Int64(i)))
                                    default:
                                        print("Non-constant initializer on local static variable \(name)")
                                        exit(ExitCode.semanticError.rawValue)
                                }
                            } else {
                                initValue = .Initial(.IntInit(0))
                            }
                            nameMap[name] = (conTp, .StaticAttr(initValue, false))
                        } else {
                            nameMap[name] = (initType, .LocalAttr)
                        }
                    }
                    return .VariableDeclaration(tp, name, typeCheckedInit, storageClass)
            }
        }

        func typeCheck(_ program: Parser.AST.Program, _ symbolTable: inout [String : (CheckerType, IdentifierAttributes)]) -> Parser.AST.Program {
            switch program {
                case .Statement(let decls):
                    var typeCheckedDecls : [Parser.AST.Declaration] = []
                    for d in decls {
                        typeCheckedDecls.append(typeCheck(d, true, &symbolTable))
                    }
                    return .Statement(typeCheckedDecls)
            }
        }
    }

    func analyze(_ program: Parser.AST.Program) -> (Parser.AST.Program, [String : (TypeChecker.CheckerType, TypeChecker.IdentifierAttributes)]) {
        // currently our only semantic analysis step
        let resolvedProgram = VariableResolver().resolveVariables(program)
        let labeledProgram = LoopLabeler().labelLoops(resolvedProgram)
        let casedProgram = CasePlacer().placeCases(labeledProgram)

        var overallNameMap : [String : (
            TypeChecker.CheckerType,            // the value's type
            TypeChecker.IdentifierAttributes    // storage and other attributes
        )] = [:]

        let typeCheckedProgram = TypeChecker().typeCheck(casedProgram, &overallNameMap)
        return (typeCheckedProgram, overallNameMap)
    }
}

func converCTypeToCheckerType(_ pType : Parser.AST.CType) -> SemanticAnalyzer.TypeChecker.CheckerType {
    switch pType {
        case .Int: return .Int
        case .Void: return .Void
        case .Long: return .Long
    }
}