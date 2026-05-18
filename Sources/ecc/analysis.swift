import Foundation

class SemanticAnalyzer {
    class VariableResolver {
        struct NameMapEntry {
            public let newName : String
            public let currentScope : Bool
            public let hasLinkage : Bool
        }

        struct StructMapEntry {
            public let newName: String
            public let currentScope: Bool
        }

        typealias StructTable = [String: StructMapEntry]

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

        func copyStructMap(_ structMap: StructTable) -> StructTable {
            var out : StructTable = [:]
            for (name, entry) in structMap {
                out[name] = .init(newName: entry.newName, currentScope: false)
            }
            return out
        }

        func isValidLValue(_ exp: Parser.AST.Expression) -> Bool {
            switch exp {
                case .Var(_, _): return true
                case .Dereference(_, _): return true
                case .Subscript(_, _, _): return true
                case .Dot(_, _, _): return true
                case .Arrow(_, _, _): return true
                default: return false
            }
        }

        func resolveType(_ typeSpec: Parser.AST.CType, _ structMap: StructTable) -> Parser.AST.CType {
            switch typeSpec {
                case .Structure(let tag):
                    if let sm = structMap[tag] {
                        return .Structure(sm.newName)
                    } else {
                        print("Specified an undeclared struct type")
                        exit(ExitCode.semanticError.rawValue)
                    }
                case .Pointer(let nestedType):
                    return .Pointer(resolveType(nestedType, structMap))
                case .ArrayType(let elemType, let sz):
                    return .ArrayType(resolveType(elemType, structMap), sz)
                case .FunType(let pTypes, let retType):
                    return .FunType(pTypes.map{ resolveType($0, structMap) }, resolveType(retType, structMap))
                default: return typeSpec
            }
        }

        func resolveExpression(_ exp : Parser.AST.Expression, _ nameMap: inout [String : NameMapEntry], _ structMap: inout StructTable) -> Parser.AST.Expression {
            switch exp {
                case .Assignment(let lValue, let rValue, _):
                    if !isValidLValue(lValue) {
                        print("Invalid lvalue in assignment \(exp)")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    return .Assignment(resolveExpression(lValue, &nameMap, &structMap), resolveExpression(rValue, &nameMap, &structMap), nil)
                case .CompoundAssignment(_,_,_,_):
                    print("Unreachable: Unsupported compound assignment found while analyzing")
                    exit(ExitCode.internalError.rawValue)
                case .Binary(let op, let left, let right, _):
                    return .Binary(op, resolveExpression(left, &nameMap, &structMap), resolveExpression(right, &nameMap, &structMap), nil)
                case .Constant(_, _): return exp
                case .Unary(let op, let child, _):
                    return .Unary(op, resolveExpression(child, &nameMap, &structMap), nil)
                case .Var(let name, _):
                    if let uniqueName = nameMap[name] {
                        return .Var(uniqueName.newName, nil)
                    } else {
                        print("Undeclared variable \(name)")
                        exit(ExitCode.semanticError.rawValue)
                    }
                case .Conditional(let cond, let left, let right, _):
                    return .Conditional(resolveExpression(cond, &nameMap, &structMap), resolveExpression(left, &nameMap, &structMap), resolveExpression(right, &nameMap, &structMap), nil)
                case .FunctionCall(let fun, let parameters, _):
                    if !isValidLValue(fun) {    // TODO: is this actually all we need for something to be callable?
                        print("Function \(fun) could not be resolved to valid lvalue")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    return .FunctionCall(resolveExpression(fun, &nameMap, &structMap), parameters.map { resolveExpression($0, &nameMap, &structMap) }, nil)
                case .Cast(let targetType, let child, _):
                    return .Cast(targetType, resolveExpression(child, &nameMap, &structMap), nil)
                case .Dereference(let exp, _):
                    return .Dereference(resolveExpression(exp, &nameMap, &structMap), nil)
                case .AddrOf(let exp, _):
                    return .AddrOf(resolveExpression(exp, &nameMap, &structMap), nil)
                case .Subscript(let ptr, let offset, _):
                    return .Subscript(
                        resolveExpression(ptr, &nameMap, &structMap),
                        resolveExpression(offset, &nameMap, &structMap),
                        nil
                    )
                case .String(_, _): return exp
                case .SizeOf(_, _): return exp
                case .SizeOfT(_, _): return exp
                case .Dot(let exp, let memberName, _):
                    return .Dot(resolveExpression(exp, &nameMap, &structMap), memberName, nil)
                case .Arrow(let exp, let memberName, _):
                    return .Arrow(resolveExpression(exp, &nameMap, &structMap), memberName, nil)
            }
        }

        func resolveStatement(_ stmt : Parser.AST.Statement, _ nameMap: inout [String : NameMapEntry], _ structMap: inout StructTable) -> Parser.AST.Statement {
            switch stmt {
                case .Expression(let exp): return .Expression(resolveExpression(exp, &nameMap, &structMap))
                case .Return(let exp): return .Return(exp == nil ? nil : resolveExpression(exp!, &nameMap, &structMap))
                case .Null: return .Null
                case .If(let cond, let thenStatement, let elseStatement):
                    return .If(resolveExpression(cond, &nameMap, &structMap), resolveStatement(thenStatement, &nameMap, &structMap),
                               elseStatement == nil ? nil : resolveStatement(elseStatement!, &nameMap, &structMap))
                case .Compound(let block):
                    switch block {
                        case .Block(let items):
                            var copiedNameMap = copyNameMap(nameMap)
                            var copiedStructMap = copyStructMap(structMap)
                            return .Compound(.Block(items.map { itm in
                                return resolveBlockItem(itm, &copiedNameMap, &copiedStructMap)
                            }))
                    }
                case .Break(_): return stmt
                case .Continue(_): return stmt
                case .While(let condition, let body, _):
                    var copiedNameMap = copyNameMap(nameMap)
                    var copiedStructMap = copyStructMap(structMap)
                    return .While(resolveExpression(condition, &nameMap, &structMap), resolveStatement(body, &copiedNameMap, &copiedStructMap), "")
                case .DoWhile(let body, let condition, _):
                    var copiedNameMap = copyNameMap(nameMap)
                    var copiedStructMap = copyStructMap(structMap)
                    return .DoWhile(resolveStatement(body, &copiedNameMap, &copiedStructMap), resolveExpression(condition, &nameMap, &structMap), "")
                case .For(let forInit, let condition, let inc, let body, _):
                    var copiedNameMap = copyNameMap(nameMap)
                    var copiedStructMap = copyStructMap(structMap)
                    let resolvedForInit : Parser.AST.ForInit
                    switch forInit {
                        case .InitDecl(let decl):
                            resolvedForInit = .InitDecl(resolveDeclaration(decl, false, &copiedNameMap, &copiedStructMap))
                        case .InitExp(let exp):
                            resolvedForInit = .InitExp(exp == nil ? nil : resolveExpression(exp!, &copiedNameMap, &copiedStructMap))
                    }
                    let resolvedCondition = condition == nil ? nil : resolveExpression(condition!, &copiedNameMap, &copiedStructMap)
                    let resolvedInc = inc == nil ? nil : resolveExpression(inc!, &copiedNameMap, &copiedStructMap)
                    let resolvedBody = resolveStatement(body, &copiedNameMap, &copiedStructMap)
                    return .For(resolvedForInit, resolvedCondition, resolvedInc, resolvedBody, "")
                case .Switch(let toggle, let body, let label):
                    return .Switch(resolveExpression(toggle, &nameMap, &structMap), resolveStatement(body, &nameMap, &structMap), label)
                case .Labeled(let ls):
                    switch ls {
                        case .CaseStatement(let val, let exe):
                            return .Labeled(.CaseStatement(resolveExpression(val, &nameMap, &structMap), resolveStatement(exe, &nameMap, &structMap)))
                        case .DefaultStatement(let exe):
                            return .Labeled(.DefaultStatement(resolveStatement(exe, &nameMap, &structMap)))
                        case .IdentifiedLine(let name, let st):
                            return .Labeled(.IdentifiedLine(name, resolveStatement(st, &nameMap, &structMap)))
                    }
            }
        }

        func resolveInitializer(_ initializer: Parser.AST.Initializer, _ nameMap: inout [String: NameMapEntry], _ structMap: inout StructTable) -> Parser.AST.Initializer {
            switch initializer {
                case .SingleInit(let exp): return .SingleInit(resolveExpression(exp, &nameMap, &structMap))
                case .CompoundInit(let exps): return .CompoundInit(exps.map { resolveInitializer($0, &nameMap, &structMap) })
            }
        }

        func resolveDeclaration(_ decl: Parser.AST.Declaration, _ fileScope: Bool, _ nameMap: inout [String : NameMapEntry], _ structMap: inout StructTable) -> Parser.AST.Declaration {
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
                            var outInit : Parser.AST.Initializer? = nil
                            if let initializer = exp {
                                outInit = resolveInitializer(initializer, &nameMap, &structMap)
                            }
                            return .VariableDeclaration(tp, uniqueName, outInit, storageClass)
                        }
                    }
                case .FunctionDeclaration(let returnType, let name, let params, let body,  let storageClass):
                    nameMap[name] = .init(newName: name, currentScope: true, hasLinkage: true)
                    var copiedNameMap = copyNameMap(nameMap)
                    var mangledPNames: [String] = []
                    for pName in params {
                        let uniqueName = makeTemp(pName)
                        copiedNameMap[pName] = .init(newName: uniqueName, currentScope: true, hasLinkage: false)
                        mangledPNames.append(uniqueName)
                    }
                    var copiedStructMap = copyStructMap(structMap)
                    if let b = body {
                        switch b {
                            case .Block(let items):
                                return .FunctionDeclaration(returnType, name, mangledPNames, .Block(items.map { resolveBlockItem($0, &copiedNameMap, &copiedStructMap) }), storageClass)
                        }
                    } else {
                        return .FunctionDeclaration(returnType, name, mangledPNames, nil, storageClass)
                    }
                case .StructDeclaration(let tag, let members):
                    // look up the struct by tag in the struct map
                    let prevEntry = structMap[tag]
                    let uniqueTag : String
                    if prevEntry == nil || !prevEntry!.currentScope {
                        // no such struct in the map; construct a new entry with a new tag
                        uniqueTag = makeTemp("struct.\(tag)")
                        structMap[tag] = .init(newName: uniqueTag, currentScope: true)
                    } else {
                        // found it! grab the old tag
                        uniqueTag = prevEntry!.newName
                    }
                    // now, process the members using our new resolveType() method
                    let processedMembers = members.map { (name, typeSpec) in
                        return (name, resolveType(typeSpec, structMap))
                    }
                    return .StructDeclaration(uniqueTag, processedMembers)
            }
        }

        func resolveBlockItem(_ blockItem: Parser.AST.BlockItem, _ nameMap: inout [String : NameMapEntry], _ structMap: inout StructTable) -> Parser.AST.BlockItem {
            switch blockItem {
                case .D(let decl):
                    return .D(resolveDeclaration(decl, false, &nameMap, &structMap))
                case .S(let stmt):
                    return .S(resolveStatement(stmt, &nameMap, &structMap))
            }
        }

        func resolveVariables(_ program: Parser.AST.Program) -> Parser.AST.Program {
            var variableNameMapping : [String : NameMapEntry] = [:]
            var structMapping : StructTable = [:]
            switch program {
                case .Statement(let declarations):
                    var resolvedDecls : [Parser.AST.Declaration] = []
                    for decl in declarations {
                        resolvedDecls.append(resolveDeclaration(decl, true, &variableNameMapping, &structMapping))
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

        func labelLoops(_ initializer: Parser.AST.Initializer, loopLabel: String?, switchLabel: String?) -> Parser.AST.Initializer {
            return initializer
        }

        func labelLoops(_ declaration: Parser.AST.Declaration, loopLabel: String?, switchLabel: String?) -> Parser.AST.Declaration {
            switch declaration {
                case .VariableDeclaration(let tp, let name, let exp, let storageClass):
                    let outExp : Parser.AST.Initializer?
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
                case .StructDeclaration(_, _):
                    // nothing to do here
                    return declaration
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

        func placeCases(_ initializer: Parser.AST.Initializer, isInSwitch: Bool) -> Parser.AST.Initializer {
            return initializer
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
                case .StructDeclaration(_, _):
                    return declaration
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
            case Char
            case SChar
            case UChar
            case Int
            case UnsignedInt
            case Long
            case UnsignedLong
            case Double
            case Void
            case Pointer(CheckerType /* pointee type */)
            case Function(CheckerType /* return */, [CheckerType] /* params */)
            case ArrayType(CheckerType /* element */, UInt /* size */)
            case Structure(String /* tag */)
        }

        enum StaticInit {
            case IntInit(Int32)
            case UIntInit(UInt32)
            case LongInit(Int64)
            case ULongInit(UInt64)
            case DoubleInit(Double)
            case CharInit(Int32)
            case UCharInit(Int32)
            case ZeroInit(/* widthInBytes */ UInt)
            case StringInit(String /* value */, /* isNullTerminated */ Bool)
            case PointerInit(String /* name */)
        }

        enum InitialValue {
            case Tentative
            case Initial([StaticInit])   // NOTE: other types will affect this
            case NoInitializer
        }

        enum IdentifierAttributes {
            case FunAttr(Bool /* is defined */, Bool /* is global */)
            case StaticAttr(InitialValue /* init */, Bool /* is global */)
            case ConstantAttr(StaticInit /* init */)
            case LocalAttr
        }

        public struct TypeTableEntry {
            public struct MemberEntry {
                public let identifier: String
                public let typeSpec: Parser.AST.CType
                public let offset: Int
            }

            public struct StructEntry {
                public let alignment: Int
                public let size: Int
                public let memebers: [MemberEntry]
            }
        }

        typealias TypeTable = [String: TypeTableEntry.StructEntry]

        func alignment(_ tp: Parser.AST.CType, _ table: TypeTable) -> Int {
            switch tp {                
                case .Char: fallthrough
                case .SChar: fallthrough
                case .UChar: return 1
                case .Int: fallthrough
                case .UnsignedInt: return 4
                case .Long: fallthrough
                case .UnsignedLong: return 8
                case .Void:
                    print("Invalid operation: getting alignment of void type")
                    exit(ExitCode.internalError.rawValue)
                case .Double: return 8
                case .Pointer(_): return 8
                case .FunType(_, _):
                    print("Invalid operation getting the alignment of a function type")
                    exit(ExitCode.internalError.rawValue)
                case .ArrayType(let nestedType, let sz):
                    return alignment(nestedType, table)
                case .Structure(let tag):
                    if let definedStruct = table[tag] {
                        return definedStruct.alignment
                    } else {
                        print("Tried to use undefined structure type \(tag)")
                        exit(ExitCode.semanticError.rawValue)
                    }
            }
        }

        func size(_ tp: Parser.AST.CType, _ table: TypeTable) -> Int {
            switch tp {                
                case .Char: fallthrough
                case .SChar: fallthrough
                case .UChar: return 1
                case .Int: fallthrough
                case .UnsignedInt: return 4
                case .Long: fallthrough
                case .UnsignedLong: return 8
                case .Void:
                    print("Invalid operation: getting size of void type")
                    exit(ExitCode.internalError.rawValue)
                case .Double: return 8
                case .Pointer(_): return 8
                case .FunType(_, _):
                    print("Invalid operation getting the size of a function type")
                    exit(ExitCode.internalError.rawValue)
                case .ArrayType(let nestedType, let sz):
                    return size(nestedType, table) * Int(sz)
                case .Structure(let tag):
                    if let definedStruct = table[tag] {
                        return definedStruct.size
                    } else {
                        print("Tried to use undefined structure type \(tag)")
                        exit(ExitCode.semanticError.rawValue)
                    }
            }
        }

        var stringCounter : UInt = 0

        func stringConstantName() -> String {
            let out = "string.\(stringCounter)"
            stringCounter = stringCounter + 1
            return out
        }

        static func deConvert(_ cType : CheckerType) -> Parser.AST.CType {
            switch cType {
                case .Char: return .Char
                case .UChar: return .UChar
                case .SChar: return .SChar
                case .Int: return .Int
                case .UnsignedInt: return .UnsignedInt
                case .Void: return .Void
                case .Long: return .Long
                case .UnsignedLong: return .UnsignedLong
                case .Double: return .Double
                case .Pointer(let tp): return .Pointer(deConvert(tp))
                case .ArrayType(let tp, let sz): return .ArrayType(deConvert(tp), sz)
                case .Function(_, _):
                    print("UNREACHABLE FUNC")
                    exit(ExitCode.internalError.rawValue)
                case .Structure(let tag): return .Structure(tag)
            }
        }

        func isValidLValue(_ exp: Parser.AST.Expression) -> Bool {
            switch exp {
                case .Var(_, _): return true
                case .Dereference(_, _): return true
                case .Subscript(_, _, _): return true
                case .Dot(_, _, _): return true
                case .Arrow(_, _, _): return true
                default: return false
            }
        }

        func typeConvert(_ exp: Parser.AST.Expression, ofType: CheckerType, toType: CheckerType) -> Parser.AST.Expression {
            if ofType == toType { return exp }
            if (isPointerType(ofType) && isFloatingPoint(toType)) || (isPointerType(toType) && isFloatingPoint(ofType)) {
                print("Can not cast double to pointer or pointer to double")
                exit(ExitCode.semanticError.rawValue)
            }
            return .Cast(Self.deConvert(toType), exp, Self.deConvert(ofType))
        }

        func typeCheck(_ expression: Parser.AST.Expression, _ nameMap: [String: (CheckerType, IdentifierAttributes)], _ typeTable: TypeTable) -> (Parser.AST.Expression, CheckerType) {
            switch expression {
                case .Constant(let c, _):
                    switch c {
                        case .ConstInt(let val): return (.Constant(.ConstInt(val), .Int), .Int)
                        case .ConstLong(let val): return (.Constant(.ConstLong(val), .Long), .Long)
                        case .ConstUnsignedInt(let val): return (.Constant(.ConstUnsignedInt(val), .UnsignedInt), .UnsignedInt)
                        case .ConstUnsignedLong(let val): return (.Constant(.ConstUnsignedLong(val), .UnsignedLong), .UnsignedLong)
                        case .ConstDouble(let val): return (.Constant(.ConstDouble(val), .Double), .Double)
                        case .ConstChar(let val): return (.Constant(.ConstChar(val), .Char), .Char)
                        case .ConstUChar(let val): return (.Constant(.ConstChar(val), .UChar), .UChar)
                    }
                case .Unary(let unOp, let e, _):
                    let (checkedE, eType) = typeCheckAndConvert(e, nameMap, typeTable)
                    if eType == .Void {
                        print("Tried to perform unary operation \(unOp) on void expression \(e)")
                        exit(ExitCode.semanticError.rawValue)
                    }

                    if isFloatingPoint(eType) {
                        if unOp == .Complement {
                            print("Complement operator does not apply to floating point value")
                            exit(ExitCode.semanticError.rawValue)
                        }
                    }

                    // NOTE: soon we will add pointer arithmetic and some unary
                    // operations will become legal to perform on pointers
                    if isPointerType(eType) && [.Complement, .Negate].contains(unOp) {
                        print("Can not presently perform unary operation \(unOp) on pointer type \(eType)")
                        exit(ExitCode.semanticError.rawValue)
                    }

                    let outType : Parser.AST.CType
                    switch unOp {
                        case .Not:
                            outType = .Int
                        default:
                            if isCharacterType(eType) {
                                return (.Unary(unOp, typeConvert(checkedE, ofType: eType, toType: .Int), .Int), .Int)
                            } else {
                                outType = Self.deConvert(eType)
                            }
                    }
                    return (.Unary(unOp, checkedE, outType), convertCTypeToCheckerType(outType))
                case .Binary(let binOp, let left, let right, _):
                    // not all binary operations on all pairs of types make sense
                    let (checkedLeft, leftType) = typeCheckAndConvert(left, nameMap, typeTable)
                    switch leftType {
                        case .Void: fallthrough
                        case .Function(_, _):
                            print("Left hand side (\(left)) of binary operation \(binOp) is \(leftType)")
                            exit(ExitCode.semanticError.rawValue)
                        default: ()
                    }
                    let (checkedRight, rightType) = typeCheckAndConvert(right, nameMap, typeTable)
                    switch rightType {
                        case .Void: fallthrough
                        case .Function(_, _):
                            print("Right hand side (\(right)) of binary operation \(binOp) is \(rightType)")
                            exit(ExitCode.semanticError.rawValue)
                        default: ()
                    }

                    if binOp == .Equal {
                        if isPointerType(leftType) || isPointerType(rightType) {
                            // 👍
                        } else if isArithmeticType(leftType) && isArithmeticType(rightType) {
                            // 👍
                        } else {
                            print("Can not compare expressions of incompatible types \(leftType) and \(rightType)")
                        }
                    }

                    if isFloatingPoint(leftType) || isFloatingPoint(rightType) {
                        if binOp == .Remainder {
                            print("Remainder operator does not apply to floating point types")
                            exit(ExitCode.semanticError.rawValue)
                        }
                    }

                    if isPointerType(leftType) || isPointerType(rightType) {
                        switch binOp {
                            case .Equal: fallthrough
                            case .NotEqual:
                                // this call will fail if the types are not compatible
                                let outType = getCommonPointerType((checkedLeft, leftType), (checkedRight, rightType))
                                let binExp : Parser.AST.Expression = .Binary(
                                    binOp,
                                    typeConvert(checkedLeft, ofType: leftType, toType: outType),
                                    typeConvert(checkedRight, ofType: rightType, toType: outType),
                                    Self.deConvert(outType)
                                )
                                return (binExp, outType)
                            case .And: fallthrough
                            case .Or:
                                return (.Binary(binOp, checkedLeft, checkedRight, .Int), .Int)
                            case .Add:
                                if isPointerType(leftType) && isPointerType(rightType) {
                                    print("Cannot add pointers")
                                    exit(ExitCode.semanticError.rawValue)
                                }
                                if isPointerType(leftType) {
                                    if !isPointerToCompleteType(leftType) {
                                        print("Attempted to add pointer of incomplete type \(leftType)")
                                        exit(ExitCode.semanticError.rawValue)
                                    }
                                    // add/subtract only integers
                                    if !isIntegralType(rightType) {
                                        print("Tried to add non-integral value \(checkedRight) of type \(rightType) to pointer")
                                        exit(ExitCode.semanticError.rawValue)
                                    }

                                    return (.Binary(
                                        binOp,
                                        checkedLeft,
                                        typeConvert(checkedRight, ofType: rightType, toType: .Long),
                                        Self.deConvert(leftType)
                                    ), leftType)
                                } else {
                                    if !isPointerToCompleteType(rightType) {
                                        print("Attempted to add pointer of incomplete type \(rightType)")
                                        exit(ExitCode.semanticError.rawValue)
                                    }
                                    // add/subtract only integers
                                    if !isIntegralType(leftType) {
                                        print("Tried to add non-integral value \(checkedLeft) of type \(leftType) to pointer")
                                        exit(ExitCode.semanticError.rawValue)
                                    }

                                    return (.Binary(
                                        binOp,
                                        typeConvert(checkedLeft, ofType: leftType, toType: .Long),
                                        checkedRight,
                                        Self.deConvert(rightType)
                                    ), rightType)
                                }
                            case .Subtract:
                                if isPointerType(leftType) && isPointerType(rightType) {
                                    // subtracting one pointer from another yields an implementation defined
                                    // signed integer; we'll choose "long"
                                    return (.Binary(binOp, checkedLeft, checkedRight, .Long), .Long)
                                } else if isPointerType(leftType) {
                                    if !isPointerToCompleteType(leftType) {
                                        print("Attempted to subtract pointer of incomplete type \(leftType)")
                                        exit(ExitCode.semanticError.rawValue)
                                    }
                                    // add/subtract only integers
                                    if !isIntegralType(rightType) {
                                        print("Tried to add non-integral value \(checkedRight) of type \(rightType) to pointer")
                                        exit(ExitCode.semanticError.rawValue)
                                    }

                                    return (.Binary(
                                        binOp,
                                        checkedLeft,
                                        typeConvert(checkedRight, ofType: rightType, toType: .Long),
                                        Self.deConvert(leftType)
                                    ), leftType)
                                // } else if isPointerType(rightType) {    // redundant, but helps my head 🤕
                                } else {    // ok, I'd love to the above, but the compiler is being less-than-helpful
                                    if !isPointerToCompleteType(rightType) {
                                        print("Tried to subtract pointer of incomplete type \(rightType)")
                                        exit(ExitCode.semanticError.rawValue)
                                    }
                                    // add/subtract only integers
                                    if !isIntegralType(leftType) {
                                        print("Tried to add non-integral value \(checkedLeft) of type \(leftType) to pointer")
                                        exit(ExitCode.semanticError.rawValue)
                                    }

                                    switch checkedLeft {
                                        case .Constant(let cnstn, _):
                                            switch cnstn {
                                                case .ConstInt(let i32): if i32 == 0 {
                                                    print("Cannot subtract pointer from NULL")
                                                    exit(ExitCode.semanticError.rawValue)
                                                }
                                                case .ConstUnsignedInt(let u32): if u32 == 0 {
                                                    print("Cannot subtract pointer from NULL")
                                                    exit(ExitCode.semanticError.rawValue)
                                                }
                                                case .ConstLong(let i64): if i64 == 0 {
                                                    print("Cannot subtract pointer from NULL")
                                                    exit(ExitCode.semanticError.rawValue)
                                                }
                                                case .ConstUnsignedLong(let u64): if u64 == 0 {
                                                    print("Cannot subtract pointer from NULL")
                                                    exit(ExitCode.semanticError.rawValue)
                                                }
                                                case .ConstDouble(_):
                                                    print("Unreachable case where a constant double was subtracted from a pointer")
                                                    exit(ExitCode.internalError.rawValue)
                                                case .ConstChar(let i32): if i32 == 0 {
                                                    print("Cannot subtract pointer from NULL")
                                                    exit(ExitCode.semanticError.rawValue)
                                                }
                                                case .ConstUChar(let i32): if i32 == 0 {
                                                    print("Cannot subtract pointer from NULL")
                                                    exit(ExitCode.semanticError.rawValue)
                                                }
                                            }
                                        default: () // not a constant, totally fine
                                    }
                                    return (.Binary(
                                        binOp,
                                        typeConvert(checkedLeft, ofType: leftType, toType: .Long),
                                        checkedRight,
                                        Self.deConvert(rightType)
                                    ), rightType)
                                }
                            case .GreaterOrEqual: fallthrough
                            case .GreaterThan: fallthrough
                            case .LessOrEqual: fallthrough
                            case .LessThan:
                                // TODO: comparisons against NULL pointer are technically invalid, but Clang and GCC
                                // are more permissive than the standard so maybe we should be as well
                                return (.Binary(
                                    binOp,
                                    checkedLeft,
                                    checkedRight,
                                    .Int
                                ), .Int)
                            default:
                                print("Invalid binary operation \(binOp) called on pointer type(s) (\(leftType), \(rightType))")
                                exit(ExitCode.semanticError.rawValue)
                        }
                    } else {

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
                    }
                case .Var(let name, _):
                    // name is enforced to exist
                    if let x = nameMap[name] {
                        let (tp, _) = x
                        return (.Var(name, Self.deConvert(tp)), tp)
                    } else {
                        print("Variable \(name) was not found in name map")
                        exit(ExitCode.internalError.rawValue)
                    }
                case .Assignment(let lValue, let exp, _):
                    let (lV, lT) = typeCheckAndConvert(lValue, nameMap, typeTable)

                    if !isValidLValue(lV) {
                        print("Attempted to assign to non-lvalue expression \(lValue)")
                        exit(ExitCode.semanticError.rawValue)
                    }

                    let (checkedExp, expType) = typeCheckAndConvert(exp, nameMap, typeTable)
                    if expType == lT {
                        return (.Assignment(lV, checkedExp, Self.deConvert(lT)), lT)
                    }
                    if isArithmeticType(lT) && isArithmeticType(expType) {
                        return (.Assignment(lV, typeConvert(checkedExp, ofType: expType, toType: lT), Self.deConvert(lT)), lT)
                    }
                    if isNullConstant(checkedExp) && isPointerType(lT) {
                        return (.Assignment(lV, typeConvert(checkedExp, ofType: expType, toType: lT), Self.deConvert(lT)), lT)
                    }
                    if isPointerType(lT) && isPointerType(expType) {
                        if getPointeeType(lT) == .Void || getPointeeType(expType) == .Void {
                            return (.Assignment(lV, typeConvert(checkedExp, ofType: expType, toType: lT), Self.deConvert(lT)), lT)
                        } else {
                            print("Incompatible implicit pointer conversion found during assignment to \(lV)")
                            exit(ExitCode.semanticError.rawValue)
                        }
                    }

                    print("Cannot convert type \(expType) to \(lT) for assignment \(expression)")
                    exit(ExitCode.semanticError.rawValue)
                case .CompoundAssignment(_, _, _, _):
                    print("Unreachable compound assignment found during type checking")
                    exit(ExitCode.internalError.rawValue)
                case .Conditional(let cond, let left, let right, _):
                    let (checkedCond, condType) = typeCheckAndConvert(cond, nameMap, typeTable)
                    let (checkedLeft, leftType) = typeCheckAndConvert(left, nameMap, typeTable)
                    let (checkedRight, rightType) = typeCheckAndConvert(right, nameMap, typeTable)

                    if !isTypeScalar(condType) {
                        print("Conditional in conditional expression must be a scalar type, not \(condType)")
                        exit(ExitCode.semanticError.rawValue)
                    }

                    let outType : SemanticAnalyzer.TypeChecker.CheckerType
                    if isPointerType(leftType) || isPointerType(rightType) {
                        outType = getCommonPointerType((checkedLeft, leftType), (checkedRight, rightType))
                    } else if leftType == .Void && rightType == .Void {
                        outType = .Void
                    } else {
                        if (isStructureType(leftType) && !isStructureType(rightType)) || (!isStructureType(leftType) && isStructureType(rightType)) {
                            print("Conditional expression where only one side was a structure type")
                            exit(ExitCode.semanticError.rawValue)
                        }
                        if isStructureType(leftType) && isStructureType(rightType) {
                            if leftType != rightType {
                                print("Mismatched structure types in conditional expression")
                                exit(ExitCode.semanticError.rawValue)
                            }
                            outType = leftType
                        } else {
                            outType = getCommonType(leftType, rightType)
                        }
                    }
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
                        let q = typeCheckAndConvert(p, nameMap, typeTable)
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
                                let commonType : SemanticAnalyzer.TypeChecker.CheckerType
                                if isPointerType(incomingParam.1) && isPointerType(expectedParam) {
                                    if getPointeeType(incomingParam.1) == getPointeeType(expectedParam) {
                                        upCastExp.append(incomingParam.0)
                                    } else if getPointeeType(incomingParam.1) == .Void || getPointeeType(expectedParam) == .Void {
                                        upCastExp.append(typeConvert(incomingParam.0, ofType: incomingParam.1, toType: expectedParam))
                                    } else {
                                        print("Can not implicitly convert function parameter of poitner type \(incomingParam.1) to \(expectedParam)")
                                        exit(ExitCode.semanticError.rawValue)
                                    }
                                } else {
                                    commonType = getCommonType(incomingParam.1, expectedParam)
                                    let ipExp = typeConvert(incomingParam.0, ofType: incomingParam.1, toType: commonType)
                                    upCastExp.append(ipExp)
                                }
                            }
                            return (.FunctionCall(lValue, upCastExp, Self.deConvert(rType)), rType)
                        case .Char: fallthrough
                        case .SChar: fallthrough
                        case .UChar: fallthrough
                        case .Int: fallthrough
                        case .UnsignedInt: fallthrough
                        case .Long: fallthrough
                        case .UnsignedLong: fallthrough
                        case .Double: fallthrough
                        case .Pointer(_): fallthrough
                        case .Void: fallthrough
                        case .Structure(_): fallthrough
                        case .ArrayType(_, _):
                            print("Can not call value \(lValue) of type \(fType)")
                            exit(ExitCode.semanticError.rawValue)
                    }
                case .Cast(let targetType, let child, _):
                    switch targetType {
                        case .ArrayType(_, _):
                            print("Can't cast \(child) (or anything) to an array")
                            exit(ExitCode.semanticError.rawValue)
                        default: ()
                    }
                    let tmp = typeCheckAndConvert(child, nameMap, typeTable)
                    return (.Cast(targetType, tmp.0, Self.deConvert(tmp.1)), tmp.1)
                case .Dereference(let ptr, _):
                    // type check the pointer expression
                    let (child, childType) = typeCheckAndConvert(ptr, nameMap, typeTable)
                    // verify that the expression is a pointer
                    switch childType {
                        case .Pointer(let pointeeType):
                            // our type is whatever it points to
                            return (.Dereference(child, Self.deConvert(pointeeType)), pointeeType)
                        default:
                            print("Attempted to dereference a value of non-pointer type \(childType)")
                            exit(ExitCode.semanticError.rawValue)
                    }
                case .AddrOf(let exp, _):
                    // type check the child expression
                    let (child, childType) = typeCheckAndConvert(exp, nameMap, typeTable)
                    // verify that it is an lvalue
                    if !isValidLValue(child) {
                        print("Attempted to get the address of non-lvalue expression \(child)")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    // our type is pointer to the child's type
                    let ourType : CheckerType = .Pointer(childType)
                    return (.AddrOf(child, Self.deConvert(ourType)), ourType)
                case .Subscript(let ptr, let offset, _):
                    // well, actually, either ptr or offset could be the pointer; the other one has to be an integer though
                    let (checkedPtr, ptrType) = typeCheckAndConvert(ptr, nameMap, typeTable)
                    let (checkedOffset, offsetType) = typeCheckAndConvert(offset, nameMap, typeTable)
                    if isSubscribtableType(ptrType) && isIntegralType(offsetType) {
                        let innerType = getPointeeType(ptrType, permitArrays: true)
                        if !isTypeComplete(innerType) {
                            print("Tried to subscript \(ptr) with incomplete type")
                            exit(ExitCode.semanticError.rawValue)
                        }
                        return (.Subscript(
                            checkedPtr,
                            typeConvert(checkedOffset, ofType: offsetType, toType: .Long),
                            Self.deConvert(innerType)
                        ), innerType)
                    } else if isSubscribtableType(offsetType) && isIntegralType(ptrType) {
                        // .... what? Yes, this is legal.
                        let innerType = getPointeeType(offsetType, permitArrays: true)
                        if !isTypeComplete(innerType) {
                            print("Tried to subscript \(offset) with incomplete type")
                            exit(ExitCode.semanticError.rawValue)
                        }
                        // return (.Subscript(
                        //     typeConvert(checkedPtr, ofType: ptrType, toType: .Long),
                        //     checkedOffset,
                        //     Self.deConvert(innerType)
                        // ), innerType)
                        // can I do this?
                        return (.Subscript(
                            checkedOffset,
                            typeConvert(checkedPtr, ofType: ptrType, toType: .Long),
                            Self.deConvert(innerType)
                        ), innerType)
                    } else {
                        print("Invalid operand types \(ptrType), \(offsetType) for subscript expression \(expression)")
                        exit(ExitCode.semanticError.rawValue)
                    }
                case .String(let val, _):
                    let arrType : Parser.AST.CType = .ArrayType(.Char, UInt(val.count) + 1)
                    return (.String(val, arrType), convertCTypeToCheckerType(arrType))
                case .SizeOf(let exp, _):
                    let (checkedExp, checkedType) = typeCheckAndConvert(exp, nameMap, typeTable)
                    if !isTypeComplete(checkedType) {
                        print("Can not get size of expression \(exp) of incomplete type")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    return (.SizeOf(checkedExp, .UnsignedLong), .UnsignedLong)
                case .SizeOfT(let namedType, _):
                    validateTypeSpecifier(convertCTypeToCheckerType(namedType))
                    return (.SizeOfT(namedType, .UnsignedLong), .UnsignedLong)
                case .Dot(let exp, let memberName, _):
                    let (checkedExp, checkedType) = typeCheckAndConvert(exp, nameMap, typeTable)
                    let sType: TypeTableEntry.StructEntry
                    let tg: String
                    switch checkedType {
                        case .Structure(let tag):
                            if let te = typeTable[tag] {
                                sType = te
                                tg = tag
                            } else {
                                print("Somehow type checked the lhs of a dot expression and got an undefined structure")
                                exit(ExitCode.semanticError.rawValue)
                            }
                        default:
                            print("Tried to apply dot operation to non-record type \(checkedType)")
                            exit(ExitCode.semanticError.rawValue)
                    }
                    for m in sType.memebers {
                        if m.identifier == memberName {
                            return (.Dot(checkedExp, memberName, m.typeSpec), convertCTypeToCheckerType(m.typeSpec))
                        }
                    }
                    print("No member \(memberName) in structure \(tg)")
                    exit(ExitCode.semanticError.rawValue)
                case .Arrow(let exp, let memberName, _):
                    let (checkedExp, checkedType) = typeCheckAndConvert(exp, nameMap, typeTable)
                    let sType: TypeTableEntry.StructEntry
                    let tg: String
                    switch checkedType {
                        case .Pointer(let pointeeType):
                            switch pointeeType {
                                case .Structure(let tag):
                                    if let te = typeTable[tag] {
                                        sType = te
                                        tg = tag
                                    } else { 
                                        print("Somehow type checked the lhs of an arrow expression and got an undefined structure")
                                        exit(ExitCode.semanticError.rawValue)
                                    }
                                default:
                                    print("Tried to use arrow operator on pointer to non-struct type \(pointeeType)")
                                    exit(ExitCode.semanticError.rawValue)
                            }
                        default:
                            print("Tried to use arrow operator on non-pointer type \(checkedType)")
                            exit(ExitCode.semanticError.rawValue)
                    }
                    for m in sType.memebers {
                        if m.identifier == memberName {
                            return (.Arrow(checkedExp, memberName, m.typeSpec), convertCTypeToCheckerType(m.typeSpec))
                        }
                    }
                    print("No member \(memberName) in structure \(tg)")
                    exit(ExitCode.semanticError.rawValue)
            }
        }

        func typeCheck(_ targetType: Parser.AST.CType, _ initializer: Parser.AST.Initializer, _ nameMap: [String: (CheckerType, IdentifierAttributes)], _ typeTable: TypeTable) -> (Parser.AST.Initializer, CheckerType) {
            func zeroInitializer(_ initType: Parser.AST.CType) -> Parser.AST.Initializer {
                switch initType {
                    case .Int: return .SingleInit(.Constant(.ConstInt(0), .Int))
                    case .UnsignedInt: return .SingleInit(.Constant(.ConstUnsignedInt(0), .UnsignedInt))
                    case .Long: return .SingleInit(.Constant(.ConstLong(0), .Long))
                    case .UnsignedLong: return .SingleInit(.Constant(.ConstUnsignedLong(0), .UnsignedLong))
                    case .Void:
                        print("UNREACHABLE: Can not initialize type Void to zero")
                        exit(ExitCode.internalError.rawValue)
                    case .Double: return .SingleInit(.Constant(.ConstDouble(0), .Double))
                    case .Pointer(_): return .SingleInit(.Constant(.ConstUnsignedLong(0), .UnsignedLong))
                    case .FunType(_, _):
                        print("UNREACHABLE: Can not initialize a function to zero")
                        exit(ExitCode.internalError.rawValue)
                    case .ArrayType(let innerType, let size):
                        var out : [Parser.AST.Initializer] = []
                        var i = 0
                        while i < size {
                            out.append(zeroInitializer(innerType))
                            i = i + 1
                        }
                        return .CompoundInit(out)
                    case .Char: return .SingleInit(.Constant(.ConstUChar(0), .Char))
                    case .SChar: return .SingleInit(.Constant(.ConstChar(0), .SChar))
                    case .UChar: return .SingleInit(.Constant(.ConstUChar(0), .UChar))
                    case .Structure(let tag):
                        print("As-yet-unhandled structure type found while generating zero initializer")
                        exit(ExitCode.internalError.rawValue)
                }
            }
            switch initializer {
                case .SingleInit(let exp):

                    switch targetType {
                        case .ArrayType(let innerType, let size):
                            switch exp {
                                case .String(let val, _):
                                    if !isCharacterType(convertCTypeToCheckerType(innerType)) {
                                        print("Can not initialize a non-character type with a string literal")
                                        exit(ExitCode.semanticError.rawValue)
                                    }
                                    if UInt(val.count) > size {
                                        print("Too many characters to fit into string literal \"\(val)\"")
                                        exit(ExitCode.semanticError.rawValue)
                                    }
                                default: ()
                            }
                        default: ()
                    }

                    let (typecheckedExp, expType) = typeCheck(exp, nameMap, typeTable)
                    let tType = convertCTypeToCheckerType(targetType)
                    return (.SingleInit(typeConvert(typecheckedExp, ofType: expType, toType: tType)), tType)
                case .CompoundInit(let subInits):
                    let extractedInnerType : Parser.AST.CType
                    let extractedSize : UInt
                    switch targetType {
                        case .ArrayType(let innerType, let size):
                            extractedInnerType = innerType
                            extractedSize = size
                        default:
                            print("Compound initializer \(initializer) can not be used to initialize a non-array type \(targetType)")
                            exit(ExitCode.semanticError.rawValue)
                    }

                    if subInits.count > extractedSize {
                        print("Compound initializer \(initializer) has more than \(extractedSize) elements")
                        exit(ExitCode.semanticError.rawValue)
                    }

                    var typecheckedChildren : [Parser.AST.Initializer] = []
                    for s in subInits {
                        let (tcS, _) = typeCheck(extractedInnerType, s, nameMap, typeTable)
                        typecheckedChildren.append(tcS)
                    }

                    while typecheckedChildren.count < extractedSize {
                        typecheckedChildren.append(zeroInitializer(extractedInnerType))
                    }

                    return (.CompoundInit(typecheckedChildren), convertCTypeToCheckerType(targetType))
            }
        }

        func typeCheck(_ statement: Parser.AST.Statement, _ nameMap: inout [String: (CheckerType, IdentifierAttributes)], _ enclosingFuncReturnType : Parser.AST.CType, _ typeTable: inout TypeTable) -> Parser.AST.Statement {
            switch statement {
                case .Return(let exp):
                    if let e = exp {
                        if enclosingFuncReturnType == .Void {
                            print("Attempted to return non-void value \(e) from void function")
                            exit(ExitCode.semanticError.rawValue)
                        }
                        let (outExp, outTp) = typeCheckAndConvert(e, nameMap, typeTable)
                        let castExp = typeConvert(outExp, ofType: outTp, toType: convertCTypeToCheckerType(enclosingFuncReturnType))
                        return .Return(castExp)
                    } else {
                        if enclosingFuncReturnType != .Void {
                            print("Returning void from non-void function (of type \(enclosingFuncReturnType))")
                            exit(ExitCode.semanticError.rawValue)
                        }
                        return .Return(nil)
                    }
                case .Expression(let exp):
                    return .Expression(typeCheckAndConvert(exp, nameMap, typeTable).0)
                case .If(let condition, let thenClause, let elseClause):
                    let checkedCond = typeCheckAndConvert(condition, nameMap, typeTable).0   // TODO: do we need to cast this guy?
                    let checkedThen = typeCheck(thenClause, &nameMap, enclosingFuncReturnType, &typeTable)
                    let checkedElse: Parser.AST.Statement?
                    if let els = elseClause {
                        checkedElse = typeCheck(els, &nameMap, enclosingFuncReturnType, &typeTable)
                    } else {
                        checkedElse = nil
                    }
                    return .If(checkedCond, checkedThen, checkedElse)
                case .Compound(let block):
                    return .Compound(typeCheck(block, &nameMap, enclosingFuncReturnType, &typeTable))
                case .Null: return .Null
                case .Break(_): return statement
                case .Continue(_): return statement
                case .While(let condition, let body, let lbl):
                    let checkedCond = typeCheckAndConvert(condition, nameMap, typeTable)
                    let checkedBody = typeCheck(body, &nameMap, enclosingFuncReturnType, &typeTable)
                    return .While(checkedCond.0, checkedBody, lbl)
                case .DoWhile(let body, let condition, let lbl):
                    let checkedBody = typeCheck(body, &nameMap, enclosingFuncReturnType, &typeTable)
                    let checkedCond = typeCheckAndConvert(condition, nameMap, typeTable)
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
                                    checkedInit = .InitDecl(typeCheck(decl, false, &nameMap, &typeTable))
                                case .StructDeclaration(let tag, _):
                                    print("Unsupported struct declaration (\(tag)) found while parsing for loop header")
                                    exit(ExitCode.semanticError.rawValue)
                            }
                        case .InitExp(let exp):
                            if let e = exp {
                                checkedInit = .InitExp(typeCheckAndConvert(e, nameMap, typeTable).0)
                            } else {
                                checkedInit = .InitExp(nil)
                            }
                    }
                    let checkedCondition : Parser.AST.Expression?
                    if let c = condition {
                        checkedCondition = typeCheckAndConvert(c, nameMap, typeTable).0
                    } else {
                        checkedCondition = nil
                    }
                    let checkedPost : Parser.AST.Expression?
                    if let p = post {
                        checkedPost = typeCheckAndConvert(p, nameMap, typeTable).0
                    } else {
                        checkedPost = nil
                    }
                    let checkedBody = typeCheck(body, &nameMap, enclosingFuncReturnType, &typeTable)
                    return .For(checkedInit, checkedCondition, checkedPost, checkedBody, lbl)
                case .Switch(let toggle, let body, let lbl):
                    // TODO: cast this to bool-like
                    let checkedToggle = typeCheckAndConvert(toggle, nameMap, typeTable)
                    let checkedBody = typeCheck(body, &nameMap, enclosingFuncReturnType, &typeTable)
                    return .Switch(checkedToggle.0, checkedBody, lbl)
                case .Labeled(let ls):
                    let checkedLine : Parser.AST.LabeledStatement
                    switch ls {
                        // TODO: some type checking that should be happening isn't happening inside of switch statements
                        case .CaseStatement(let lbl, let line):    // don't bother type checking a constant
                            checkedLine = .CaseStatement(lbl, typeCheck(line, &nameMap, enclosingFuncReturnType, &typeTable))
                        case .DefaultStatement(let line):
                            checkedLine = .DefaultStatement(typeCheck(line, &nameMap, enclosingFuncReturnType, &typeTable))
                        case .IdentifiedLine(let lbl, let line):
                            checkedLine = .IdentifiedLine(lbl, typeCheck(line, &nameMap, enclosingFuncReturnType, &typeTable))
                    }
                    return .Labeled(checkedLine)
            }
        }

        // NOTE: this does not match return statements with function return types
        func typeCheck(_ block: Parser.AST.Block, _ nameMap : inout [String : (CheckerType, IdentifierAttributes)], _ enclosingFuncReturnType : Parser.AST.CType, _ typeTable: inout TypeTable) -> Parser.AST.Block {
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
                                        typeCheckedItems.append(.D(typeCheck(decl, false, &nameMap, &typeTable)))
                                    case .StructDeclaration(_, _):
                                        print("As-yet-unhandled struct declaration found while type checking")
                                        exit(ExitCode.internalError.rawValue)
                                }
                            case .S(let stmt):
                                typeCheckedItems.append(.S(typeCheck(stmt, &nameMap, enclosingFuncReturnType, &typeTable)))
                        }
                    }
                    return .Block(typeCheckedItems)
            }
        }

        func typeCheck(_ declaration: Parser.AST.Declaration, _ fileLevel: Bool, _ nameMap : inout [String : (CheckerType, IdentifierAttributes)], _ typeTable: inout TypeTable) -> Parser.AST.Declaration {

            func convert(_ initializer : Parser.AST.Initializer, _ targetType: Parser.AST.CType) -> InitialValue {
                switch initializer {
                    case .SingleInit(let exp):
                        switch exp {
                            case .Constant(let c, _):
                                let i : StaticInit
                                switch c {
                                    case .ConstInt(let i32): i = .IntInit(i32)
                                    case .ConstUnsignedInt(let u32): i = .UIntInit(u32)
                                    case .ConstLong(let i64): i = .LongInit(i64)
                                    case .ConstUnsignedLong(let u64): i = .ULongInit(u64)
                                    case .ConstDouble(let f): i = .DoubleInit(f)
                                    case .ConstChar(let i32): i = .CharInit(i32)
                                    case .ConstUChar(let i32): i = .UCharInit(i32)
                                }
                                return .Initial([i])
                            case .String(let val, _):
                                switch targetType {
                                    case .ArrayType(let nestedType, let count):
                                        if !isCharacterType(convertCTypeToCheckerType(nestedType)) {
                                            print("Can not assign string to non-character array of type \(nestedType)")
                                            exit(ExitCode.semanticError.rawValue)
                                        }
                                        if count < UInt(val.count) {
                                            print("Tried to assign string that is too long for array")
                                            exit(ExitCode.semanticError.rawValue)
                                        }
                                        if count == UInt(val.count) {
                                            return .Initial([.StringInit(val, false)])
                                        }
                                        if count == UInt(val.count + 1) {
                                            return .Initial([.StringInit(val, true)])
                                        }
                                        return .Initial([.StringInit(val, true), .ZeroInit(count - UInt(val.count + 1))])
                                    case .Pointer(let pointeeType):
                                        switch pointeeType {
                                            case .Char: ()
                                            default:
                                                print("Trying to assign a string to a non-char* type \(targetType)")
                                                exit(ExitCode.semanticError.rawValue)
                                        }
                                        let scName = stringConstantName()
                                        nameMap[scName] = (.ArrayType(.Char, UInt(val.count) + 1), .ConstantAttr(.StringInit(val, true)))
                                        return .Initial([.PointerInit(scName)])
                                    default:
                                        print("Tried to assign string to non-string target type \(targetType)")
                                        exit(ExitCode.semanticError.rawValue)
                                }
                            default:
                                print("Non constant expression \(exp) used to initialize value")
                                exit(ExitCode.semanticError.rawValue)
                        }
                    case .CompoundInit(let exps):
                        let nestedType : Parser.AST.CType
                        switch targetType {
                            case .ArrayType(let innerType, _):
                                nestedType = innerType
                            default:
                                print("Tried to initialize non-array type with compound initializer")
                                exit(ExitCode.semanticError.rawValue)
                        }
                        var out : [StaticInit] = []
                        for e in exps {
                            let ce = convert(e, nestedType)
                            switch ce {
                                case .Initial(let ie):
                                    out = out + ie
                                case .Tentative: fallthrough
                                case .NoInitializer:
                                    print("Unreachable converted initializer that is not an initializer \(ce)")
                                    exit(ExitCode.internalError.rawValue)
                            }
                        }
                        return .Initial(out)
                }
            }

            switch declaration {
                case .FunctionDeclaration(let funType, let name, let params, let body, let storageClass):
                    if !fileLevel && body != nil {
                        print("Cannot define function \(name) inline")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    let sc : Parser.AST.StorageClass
                    if storageClass != nil { sc = storageClass! } else { sc = .Extern }
                    let constructedType : CheckerType = convertCTypeToCheckerType(funType)
                    switch constructedType {
                        case .Function(let returnType, _):
                            switch returnType {
                                case .ArrayType(_, _):
                                    print("Tried to return an array from function \(name)")
                                    exit(ExitCode.semanticError.rawValue)
                                default: ()
                            }
                        default:
                            print("Unreachable case where function \(name) is not of function type")
                            exit(ExitCode.internalError.rawValue)
                    }
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
                    let paramTypes : [CheckerType]
                    switch constructedType {
                        case .Function(_, let pTypes):
                            paramTypes = pTypes
                        default:
                            print("Nonsense non-function type found describing function")
                            exit(ExitCode.internalError.rawValue)
                    }
                    for p in zip(params, paramTypes) {
                        let (pName, pType) = p
                        nameMap[pName] = (pType, .LocalAttr)
                    }
                    let typeCheckedBody : Parser.AST.Block?
                    let retType : Parser.AST.CType
                    if let b = body {
                        switch funType {
                            case .FunType(_, let rType):
                                retType = rType
                            default:
                                print("FUNCTION WITH NO FUNCTION TYPE WHAT IS GOING ON?!?!?")
                                exit(ExitCode.internalError.rawValue)
                        }
                        typeCheckedBody = typeCheck(b, &nameMap, retType, &typeTable)
                    } else {
                        typeCheckedBody = nil
                    }
                    return .FunctionDeclaration(funType, name, params, typeCheckedBody, storageClass)
                case .VariableDeclaration(let tp, let name, let initExp, let storageClass):
                    var typeCheckedInit : Parser.AST.Initializer?
                    let conTp = convertCTypeToCheckerType(tp)
                    if let e = initExp {
                        (typeCheckedInit, _) = typeCheck(tp, e, nameMap, typeTable)
                    } else {
                        typeCheckedInit = nil
                    }
                    if fileLevel {
                        var initVal : InitialValue
                        if let ie = initExp {
                            initVal = convert(ie, tp)
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
                                case .ConstantAttr(_):
                                    print("Unreachable constant \(name) as file-scoped variable")
                                    exit(ExitCode.internalError.rawValue)
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
                                initValue = convert(e, tp)
                            } else {
                                initValue = .Initial([.IntInit(0)])
                            }
                            nameMap[name] = (conTp, .StaticAttr(initValue, false))
                        } else {
                            nameMap[name] = (conTp, .LocalAttr)
                        }
                    }
                    return .VariableDeclaration(tp, name, typeCheckedInit, storageClass)
                case .StructDeclaration(let tag, let members):
                    func roundUp(_ x: Int, _ n: Int) -> Int {
                        return Int(ceil(Double(x) / Double(n))) * n
                    }
                    if members.isEmpty {
                        // we only have ot do work for complete struct definitions
                        return declaration
                    }

                    // ok, type check, then update the type table
                    // TODO: validate the declaration according to the rules laid out in the standard

                    // define a member entry for each member
                    var structSize: Int = 0
                    var structAlignment: Int = 0
                    var memberEntries: [TypeTableEntry.MemberEntry] = []
                    for (memberName, memberType) in members {
                        let memberAlignment = alignment(memberType, typeTable)
                        let memberOffset = roundUp(structSize, memberAlignment)
                        memberEntries.append(TypeTableEntry.MemberEntry(identifier: memberName, typeSpec: memberType, offset: memberOffset))
                        structAlignment = max(structAlignment, memberAlignment)
                        structSize = memberOffset + size(memberType, typeTable)
                    }
                    // figure out size/alignment
                    structSize = roundUp(structSize, structAlignment)
                    let structDef = TypeTableEntry.StructEntry(alignment: structAlignment, size: structSize, memebers: memberEntries)
                    // update the type table
                    typeTable[tag] = structDef
                    // bounce (to the ounce)
                    return .StructDeclaration(tag, members)
            }
        }

        func typeCheck(_ program: Parser.AST.Program, _ symbolTable: inout [String : (CheckerType, IdentifierAttributes)], _ typeTable: inout TypeTable) -> Parser.AST.Program {
            switch program {
                case .Statement(let decls):
                    var typeCheckedDecls : [Parser.AST.Declaration] = []
                    for d in decls {
                        typeCheckedDecls.append(typeCheck(d, true, &symbolTable, &typeTable))
                    }
                    return .Statement(typeCheckedDecls)
            }
        }

        func typeCheckAndConvert(_ expression: Parser.AST.Expression, _ nameMap: [String: (CheckerType, IdentifierAttributes)], _ typeTable: TypeTable) -> (Parser.AST.Expression, CheckerType) {
            let (typedExpression, expressionType) = typeCheck(expression, nameMap, typeTable)

            switch expressionType {
                case .ArrayType(let elementType, _):
                    if !isTypeComplete(elementType) {
                        print("Can not have an array of incomplete type \(elementType)")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    let addrOfType : CheckerType = .Pointer(elementType)
                    return (.AddrOf(typedExpression, Self.deConvert(addrOfType)), addrOfType)
                case .Structure(let tag):
                    if let _ = typeTable[tag] {
                        return (typedExpression, expressionType)
                    } else {
                        print("Invalid use of incomplete structure type \(tag)")
                        exit(ExitCode.semanticError.rawValue)
                    }
                default: return (typedExpression, expressionType)
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

        var typeTable : TypeChecker.TypeTable = [:]

        let typeCheckedProgram = TypeChecker().typeCheck(casedProgram, &overallNameMap, &typeTable)
        return (typeCheckedProgram, overallNameMap)
    }
}

func convertCTypeToCheckerType(_ pType : Parser.AST.CType) -> SemanticAnalyzer.TypeChecker.CheckerType {
    switch pType {
        case .Int: return .Int
        case .Void: return .Void
        case .Long: return .Long
        case .UnsignedInt: return .UnsignedInt
        case .UnsignedLong: return .UnsignedLong
        case .Double: return .Double
        case .FunType(let paramTypes, let returnType):
            return .Function(
                convertCTypeToCheckerType(returnType),
                paramTypes.map { convertCTypeToCheckerType($0) }
            )
        case .Pointer(let nestedType): return .Pointer(convertCTypeToCheckerType(nestedType))
        case .ArrayType(let elementType, let size):
            return .ArrayType(convertCTypeToCheckerType(elementType), size)
        case .Char: return .Char
        case .SChar: return .SChar
        case .UChar: return .UChar
        case .Structure(let tag):
            print("As-yet-unhandled structure type found while converting C type to checker type")
            exit(ExitCode.internalError.rawValue)
    }
}

func getTypeSize(_ tp: SemanticAnalyzer.TypeChecker.CheckerType) -> Int {
    switch tp {
        case .Function(_, _):
            print("GETTING TYPE SIZE OF FUNCTION MAKES NO SENSE")
            exit(ExitCode.internalError.rawValue)
        case .Int: return 4
        case .UnsignedInt: return 4
        case .Long: return 8
        case .UnsignedLong: return 8
        case .Double: return 8
        case .Pointer(_): return 8
        case .ArrayType(let nestedType, let length):
            return Int(length) * getTypeSize(nestedType)
        case .Char: fallthrough
        case .SChar: fallthrough
        case .UChar: return 1
        case .Structure(_):
            print("as-yet-unhandled .Structure construct when calling getTypeSize()")
            exit(ExitCode.internalError.rawValue)
        case .Void:
            print("GETTING TYPE SIZE OF VOID MAKES NO SENSE")
            exit(ExitCode.internalError.rawValue)
    }
}

func isSigned(_ tp: SemanticAnalyzer.TypeChecker.CheckerType) -> Bool {
    switch tp {
        case .SChar: fallthrough
        case .Int: fallthrough
        case .Long: return true
        case .UChar: fallthrough
        case .Char: fallthrough
        case .UnsignedInt: fallthrough
        case .UnsignedLong: return false
        case .Pointer(_): return false
        case .Function(_, _):
            print("GETTING SIGNED-NESS OF FUNCTION MAKES NO SENSE")
            exit(ExitCode.internalError.rawValue)
        case .Void:
            print("VOID IS NEITHER SIGNED NOR UNSIGNED DOES NOT COMPUTE BEEP BOOP")
            exit(ExitCode.internalError.rawValue)
        case .Double: return true   // feels like a lie by omission
        case .ArrayType(_, _):
            print("ARRAY IS NEITHER SIGNED NOR UNSIGNED")
            exit(ExitCode.internalError.rawValue)
        case .Structure(_): return false
    }
}

func isFloatingPoint(_ tp: SemanticAnalyzer.TypeChecker.CheckerType) -> Bool {
    switch tp {
        case .Char: fallthrough
        case .SChar: fallthrough
        case .UChar: fallthrough
        case .Int: fallthrough
        case .Long: fallthrough
        case .UnsignedInt: fallthrough
        case .UnsignedLong: return false
        case .Pointer(_): return false
        case .Function(_, _):
            print("GETTING FP-NESS OF FUNCTION MAKES NO SENSE")
            exit(ExitCode.internalError.rawValue)
        case .Void:
            print("VOID IS NEITHER FP NOR NOT FP DOES NOT COMPUTE BEEP BOOP")
            exit(ExitCode.internalError.rawValue)
        case .Double: return true
        case .ArrayType(_, _): return false
        case .Structure(_): return false
    }
}

func isIntegralType(_ tp: SemanticAnalyzer.TypeChecker.CheckerType) -> Bool {
    switch tp {
        case .SChar: fallthrough
        case .UChar: fallthrough
        case .Char: fallthrough
        case .Int: fallthrough
        case .Long: fallthrough
        case .UnsignedInt: fallthrough
        case .UnsignedLong: return true
        case .Double: return false
        case .Function(_, _): return false
        case .Pointer(_): return false
        case .ArrayType(_, _): return false
        case .Void: return false
        case .Structure(_): return false
    }
}

func isArithmeticType(_ tp: SemanticAnalyzer.TypeChecker.CheckerType) -> Bool {
    switch tp {
        case .SChar: fallthrough
        case .UChar: fallthrough
        case .Char: fallthrough
        case .Int: fallthrough
        case .Long: fallthrough
        case .UnsignedInt: fallthrough
        case .UnsignedLong: fallthrough
        case .Double: return true
        case .Function(_, _): fallthrough
        case .Pointer(_): fallthrough
        case .ArrayType(_, _): fallthrough
        case .Void: return false
        case .Structure(_): return false
    }
}

func getCommonType(_ left : SemanticAnalyzer.TypeChecker.CheckerType, _ right: SemanticAnalyzer.TypeChecker.CheckerType) -> SemanticAnalyzer.TypeChecker.CheckerType {
    if left == right { return left }
    if isSubscribtableType(left) || isSubscribtableType(right) {
        print("Can not cast arrays/pointers")
        exit(ExitCode.semanticError.rawValue)
    }
    // upcast characters to ints
    let lLeft: SemanticAnalyzer.TypeChecker.CheckerType = isCharacterType(left) ? .Int : left
    let rRight: SemanticAnalyzer.TypeChecker.CheckerType = isCharacterType(right) ? .Int : right
    // upcast to floating point where necessary
    if isFloatingPoint(lLeft) { return lLeft }
    if isFloatingPoint(rRight) { return rRight }
    if getTypeSize(lLeft) == getTypeSize(rRight) {
        if isSigned(lLeft) { return rRight }
        else { return lLeft }
    }
    if getTypeSize(lLeft) > getTypeSize(rRight) {
        return lLeft
    } else {
        return rRight
    }
}

func isCharacterType(_ tp: SemanticAnalyzer.TypeChecker.CheckerType) -> Bool {
    switch tp {
        case .Char: fallthrough
        case .SChar: fallthrough
        case .UChar: return true
        default: return false
    }
}

func isPointerType(_ tp: SemanticAnalyzer.TypeChecker.CheckerType) -> Bool {
    switch tp {
        case .Pointer(_): return true
        default: return false
    }
}

func isSubscribtableType(_ tp: SemanticAnalyzer.TypeChecker.CheckerType) -> Bool {
    switch tp {
        case .Pointer(_): return true
        case .ArrayType(_, _): return true
        default: return false
    }
}

func isStructureType(_ tp: SemanticAnalyzer.TypeChecker.CheckerType) -> Bool {
    switch tp {
        case .Structure(_): return true
        default: return false
    }
}

func getPointeeType(_ tp: SemanticAnalyzer.TypeChecker.CheckerType, permitArrays: Bool = false) -> SemanticAnalyzer.TypeChecker.CheckerType {
    switch tp {
        case .Pointer(let x): return x
        case .ArrayType(let innerType, _):
            if permitArrays {
                return innerType
            } else {
                print("Arrays not allowed in this context")
                exit(ExitCode.internalError.rawValue)
            }
        default:
            print("Doesn't make sense to get pointee type of non-pointer type \(tp)")
            exit(ExitCode.internalError.rawValue)
    }
}

func isNullConstant(_ e: Parser.AST.Expression) -> Bool {
    switch e {
        case .Constant(let val, _):
            switch val {
                case .ConstDouble(_): return false
                case .ConstInt(let i): return i == 0
                case .ConstLong(let l): return l == 0
                case .ConstUnsignedInt(let ui) : return ui == 0
                case .ConstUnsignedLong(let ul) : return ul == 0
                case .ConstChar(let i32): return i32 == 0
                case .ConstUChar(let i32): return i32 == 0
            }
        default: return false
    }
}

func getCommonPointerType(_ left: (Parser.AST.Expression, SemanticAnalyzer.TypeChecker.CheckerType), _ right: (Parser.AST.Expression, SemanticAnalyzer.TypeChecker.CheckerType)) -> SemanticAnalyzer.TypeChecker.CheckerType {
    let (leftExp, leftType) = left
    let (rightExp, rightType) = right

    if leftType == rightType {
        return leftType
    }

    if isNullConstant(leftExp) { return rightType }
    if isNullConstant(rightExp) { return rightType }

    if getPointeeType(leftType) == .Void && isPointerType(rightType) {
        return leftType
    }

    if getPointeeType(rightType) == .Void && isPointerType(leftType) {
        return rightType
    }

    print("Alleged pointers \(leftExp) and \(rightExp) have incompatible types \(leftType) and \(rightType)")
    exit(ExitCode.semanticError.rawValue)
}

func isTypeComplete(_ tp: SemanticAnalyzer.TypeChecker.CheckerType) -> Bool {
    return tp != .Void
}

func isPointerToCompleteType(_ tp: SemanticAnalyzer.TypeChecker.CheckerType) -> Bool {
    return isPointerType(tp) && isTypeComplete(getPointeeType(tp))
}

func isTypeScalar(_ tp: SemanticAnalyzer.TypeChecker.CheckerType) -> Bool {
    switch tp {
        case .Void: return false
        case .ArrayType(_, _): return false
        case .Function(_, _): return false
        default: return true
    }
}

func validateTypeSpecifier(_ tp: SemanticAnalyzer.TypeChecker.CheckerType) {
    switch tp {
        case .ArrayType(let innerType, _):
            if !isTypeComplete(innerType) {
                print("Illegal array of incomplete type")
                exit(ExitCode.semanticError.rawValue)
            }
            validateTypeSpecifier(innerType)
        case .Pointer(let nestedType):
            validateTypeSpecifier(nestedType)
        case .Function(let retType, let pTypes):
            for p in pTypes {
                validateTypeSpecifier(p)
            }
            validateTypeSpecifier(retType)
        default: ()
    }
}