import Foundation

class SemanticAnalyzer {
    class VariableResolver {
        private var tempNameCounter : Int = 0

        func makeTemp(_ base : String) -> String {
            let out = "\(base).uniqued.\(tempNameCounter)"  // used "uniqued" to avoid collisions with "tmp.#" variables
            tempNameCounter = tempNameCounter + 1
            return out
        }

        func copyNameMap(_ nameMap: [String : (String, Bool)]) -> [String : (String, Bool)] {
            var out : [String : (String, Bool)] = [:]
            for (k, v) in nameMap {
                out[k] = (v.0, false)
            }
            return out
        }

        func isValidLValue(_ exp: Parser.AST.Expression) -> Bool {
            switch exp {
                case .Var(_): return true
                default: return false
            }
        }

        func resolveExpression(_ exp : Parser.AST.Expression, _ nameMap: inout [String : (String, Bool)]) -> Parser.AST.Expression {
            switch exp {
                case .Assignment(let lValue, let rValue):
                    if !isValidLValue(lValue) {
                        print("Invalid lvalue in assignment \(exp)")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    return .Assignment(resolveExpression(lValue, &nameMap), resolveExpression(rValue, &nameMap))
                case .CompoundAssignment(_,_,_):
                    print("Unreachable: Unsupported compound assignment found while analyzing")
                    exit(ExitCode.internalError.rawValue)
                case .Binary(let op, let left, let right):
                    return .Binary(op, resolveExpression(left, &nameMap), resolveExpression(right, &nameMap))
                case .Constant(_):
                    return exp
                case .Unary(let op, let child):
                    return .Unary(op, resolveExpression(child, &nameMap))
                case .Var(let name):
                    if let uniqueName = nameMap[name] {
                        return .Var(uniqueName.0)
                    } else {
                        print("Undeclared variable \(name)")
                        exit(ExitCode.semanticError.rawValue)
                    }
                case .Conditional(let cond, let left, let right):
                    return .Conditional(resolveExpression(cond, &nameMap), resolveExpression(left, &nameMap), resolveExpression(right, &nameMap))
                case .FunctionCall(let fun, let parameters):
                    if !isValidLValue(fun) {    // TODO: is this actually all we need for something to be callable?
                        print("Function \(fun) could not be resolved to valid lvalue")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    return .FunctionCall(resolveExpression(fun, &nameMap), parameters.map { resolveExpression($0, &nameMap) })
            }
        }

        func resolveStatement(_ stmt : Parser.AST.Statement, _ nameMap: inout [String : (String, Bool)]) -> Parser.AST.Statement {
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
                            resolvedForInit = .InitDecl(resolveDeclaration(decl, &copiedNameMap))
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

        func resolveDeclaration(_ decl: Parser.AST.Declaration, _ nameMap: inout [String : (String, Bool)]) -> Parser.AST.Declaration {
            switch decl {
                case .Declaration(let tp, let name, let exp):
                    if let n = nameMap[name] {
                        if n.1 {
                            print("Duplicate variable name found: \(n)")
                            exit(ExitCode.semanticError.rawValue)
                        }
                    }
                    let uniqueName = makeTemp(name)
                    nameMap[name] = (uniqueName, true)
                    var outInit : Parser.AST.Expression? = nil
                    if let initializer = exp {
                        outInit = resolveExpression(initializer, &nameMap)
                    }
                    return .Declaration(tp, uniqueName, outInit)
            }
        }

        func resolveBlockItem(_ blockItem: Parser.AST.BlockItem, _ nameMap: inout [String : (String, Bool)]) -> Parser.AST.BlockItem {
            switch blockItem {
                case .D(let decl):
                    return .D(resolveDeclaration(decl, &nameMap))
                case .S(let stmt):
                    return .S(resolveStatement(stmt, &nameMap))
            }
        }

        func resolveVariables(_ pls: Parser.AST.ProgramLevelStatement, _ nameMap: inout [String : (String, Bool)]) -> Parser.AST.ProgramLevelStatement {
           switch pls {
                case .Function(let returnType, let name, let parameters, let body):
                    nameMap[name] = (name, true)
                    var copiedNameMap = copyNameMap(nameMap)
                    var mangledPNames: [Parser.AST.Parameter] = []
                    for p in parameters {
                        switch p {
                            case .Declaration(let pType, let pName):
                                let uniqueName = makeTemp(pName)
                                copiedNameMap[pName] = (uniqueName, true)
                                mangledPNames.append(.Declaration(pType, uniqueName))
                        }
                    }
                    switch body {
                        case .Block(let items):
                            copiedNameMap[name] = (name, true)    // function names don't get mangled!
                            return .Function(returnType, name, mangledPNames, .Block(items.map { resolveBlockItem($0, &copiedNameMap) }))
                    }
                case .FunctionDeclaration(let returnType, let name, let params):
                    nameMap[name] = (name, true)
                    return .FunctionDeclaration(returnType, name, params)
            }
        }

        func resolveVariables(_ program: Parser.AST.Program) -> Parser.AST.Program {
            var variableNameMapping : [String : (String, Bool)] = [:]
            switch program {
                case .Statement(let statements):
                    return .Statement(statements.map { resolveVariables($0, &variableNameMapping) })
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
                                case .Declaration(let tp, let name, let exp):
                                    labeledForInit = .InitDecl(.Declaration(
                                        tp,
                                        name,
                                        exp == nil ? nil : labelLoops(
                                            exp!,
                                            loopLabel: newLabel,
                                            switchLabel: nil
                                        )
                                    ))
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

        func labelLoops(_ blockItem: Parser.AST.BlockItem, loopLabel: String?, switchLabel: String?) -> Parser.AST.BlockItem {
            switch blockItem {
                case .D(let decl):
                    switch decl {
                        case .Declaration(let tp, let name, let exp):
                            let outExp : Parser.AST.Expression?
                            if let e = exp {
                                outExp = labelLoops(e, loopLabel: loopLabel, switchLabel: switchLabel)
                            } else {
                                outExp = nil
                            }
                            return .D(.Declaration(tp, name, outExp))
                    }
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

        func labelLoops(_ pls: Parser.AST.ProgramLevelStatement) -> Parser.AST.ProgramLevelStatement {
            switch pls {
                case .Function(let returnType, let name, let parameters, let body):
                    return .Function(returnType, name, parameters, labelLoops(body, loopLabel: nil, switchLabel: nil))
                case .FunctionDeclaration(_, _, _): return pls
            }
        }

        func labelLoops(_ program: Parser.AST.Program) -> Parser.AST.Program {
            switch program {
                case .Statement(let statements):
                    return .Statement(statements.map { labelLoops($0) })
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

        func placeCases(_ block: Parser.AST.Block, isInSwitch: Bool) -> Parser.AST.Block {
            switch block {
                case .Block(let items):
                    var placedItems : [Parser.AST.BlockItem] = []
                    for itm in items {
                        switch itm {
                            case .D(let decl):
                                switch decl {
                                    case .Declaration(let tp, let name, let initializer):
                                        placedItems.append(.D(.Declaration(
                                            tp,
                                            name,
                                            initializer == nil ? nil : placeCases(initializer!, isInSwitch: isInSwitch)
                                        )))
                                }
                            case .S(let stmt):
                                placedItems.append(.S(placeCases(stmt, isInSwitch: isInSwitch)))
                        }
                    }
                    return .Block(placedItems)
            }
        }

        func placeCases(_ pls: Parser.AST.ProgramLevelStatement, isInSwitch: Bool) -> Parser.AST.ProgramLevelStatement {
            switch pls {
                case .Function(let returnType, let name, let parameters, let body):
                    return .Function(returnType, name, parameters, placeCases(body, isInSwitch: isInSwitch))
                case .FunctionDeclaration(_, _, _): return pls
            }
        }

        func placeCases(_ program: Parser.AST.Program) -> Parser.AST.Program {
            switch program {
                case .Statement(let statements):
                    return .Statement(statements.map { placeCases($0, isInSwitch: false) })
            }
        }
    }

    class TypeChecker {
        indirect enum CheckerType : Equatable {
            case Int
            case Void
            case Function(CheckerType /* return */, [CheckerType] /* params */)
        }

        func convert(_ pType : Parser.AST.CType) -> CheckerType {
            switch pType {
                case .Int: return .Int
                case .Void: return .Void
            }
        }

        func copyNameMap(_ nameMap: [String : (CheckerType, Bool)]) -> [String : (CheckerType, Bool)] {
            var out : [String : (CheckerType, Bool)] = [:]
            for (name, entry) in nameMap {
                out[name] = entry
            }
            return out
        }

        func typeCheck(_ expression: Parser.AST.Expression, _ nameMap: [String: (CheckerType, Bool)]) -> CheckerType {
            switch expression {
                case .Constant(_): return .Int  // TODO: other types of constants
                case .Unary(let unOp, let e):
                    let eType = typeCheck(e, nameMap) // TODO: not all operators make sense on every type
                    if eType == .Void {
                        print("Tried to perform unary operation \(unOp) on void expression \(e)")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    return eType
                case .Binary(let binOp, let left, let right):
                    // TODO: not all binary operations on all pairs of types make sense and types should match
                    let leftType = typeCheck(left, nameMap)
                    if leftType == .Void {
                        print("Left hand side (\(left)) of binary operation \(binOp) is void")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    let rightType = typeCheck(right, nameMap)
                    if rightType == .Void {
                        print("Right hand side (\(right)) of binary operation \(binOp) is void")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    if leftType != rightType {
                        // TODO: this is sometimes ok and currently impossible
                        print("Mismatched expression types between \(left) and \(right) (\(leftType), \(rightType)))")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    return leftType
                case .Var(let name):
                    // name is enforced to exist
                    let (tp, def) = nameMap[name]!
                    if !def {
                        // NOTE: this is actually permitted in C
                        // print("WARNING: Use of undefined variable \(name)")
                        // exit(ExitCode.semanticError.rawValue)
                    }
                    return tp
                case .Assignment(let lValue, let exp):
                    // lValue is already enforced to be a valid lValue
                    let name: String
                    switch lValue {
                        case .Var(let nm):
                            name = nm
                        default:
                            print("Unreachable non lValue in assignment \(lValue)")
                            exit(ExitCode.internalError.rawValue)
                    }
                    // TODO: this is where we would update defined-ness but we messed up
                    let (tp, _) = nameMap[name]!
                    let expType = typeCheck(exp, nameMap)
                    if tp != expType {
                        // TODO: this is sometimes ok and currently impossible
                        print("Mismatched expression types during assignment -- \(lValue): \(tp), \(exp): \(expType)")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    return tp
                case .CompoundAssignment(_, _, _):
                    print("Unreachable compound assignment found during type checking")
                    exit(ExitCode.internalError.rawValue)
                case .Conditional(let cond, let left, let right):
                    let _ = typeCheck(cond, nameMap)
                    let leftType = typeCheck(left, nameMap)
                    let rightType = typeCheck(right, nameMap)
                    if leftType != rightType {
                        // NOTE: C is not a strongly typed language and this is an unacceptable level of pedantry
                        print("Sides of conditional expression do not match -- \(left): \(leftType), \(right): \(rightType)")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    return leftType
                case .FunctionCall(let lValue, let params):
                    // lValue is already enforced to be a valid lValue
                    let name: String
                    switch lValue {
                        case .Var(let nm):
                            name = nm
                        default:
                            print("Unreachable non lValue in function call \(lValue)")
                            exit(ExitCode.internalError.rawValue)
                    }
                    var paramsType : [TypeChecker.CheckerType] = []
                    for p in params {
                        paramsType.append(typeCheck(p, nameMap))
                    }
                    let (fType, _) = nameMap[name]!
                    switch fType {
                        case .Function(let rType, let pType):
                            if pType != paramsType {
                                print("Function call \(expression) of type \(paramsType), does not match \(pType)")
                                exit(ExitCode.semanticError.rawValue)
                            }
                            return rType
                        case .Int: fallthrough
                        case .Void:
                            print("Can not call value \(lValue) of type \(fType)")
                            exit(ExitCode.semanticError.rawValue)
                    }
            }
        }

        func typeCheck(_ statement: Parser.AST.Statement, _ nameMap: inout [String: (CheckerType, Bool)]) -> CheckerType {
            switch statement {
                case .Return(let exp):
                    if let e = exp {
                        return typeCheck(e, nameMap)
                    } else { return .Void }
                case .Expression(let exp):
                    return typeCheck(exp, nameMap)
                case .If(let condition, let thenClause, let elseClause):
                    let _ = typeCheck(condition, nameMap)
                    let _ = typeCheck(thenClause, &nameMap)
                    if let els = elseClause {
                        let _ = typeCheck(els, &nameMap)
                    }
                    return .Void   // statements don't generally return
                case .Compound(let block):
                    return typeCheck(block, &nameMap)
                case .Null: return .Void
                case .Break(_): return .Void
                case .Continue(_): return .Void
                case .While(let condition, let body, _):
                    let _ = typeCheck(condition, nameMap)
                    var copiedNameMap = copyNameMap(nameMap)
                    let _ = typeCheck(body, &copiedNameMap)
                    return .Void
                case .DoWhile(let body, let condition, _):
                    var copiedNameMap = copyNameMap(nameMap)
                    let _ = typeCheck(body, &copiedNameMap)
                    let _ = typeCheck(condition, nameMap)
                    return .Void
                case .For(let forInit, let condition, let post, let body, _):
                    var copiedNameMap = copyNameMap(nameMap)
                    switch forInit {
                        case .InitDecl(let decl):
                            switch decl {
                                case .Declaration(let tp, let name, let exp):
                                    let initType : CheckerType
                                    if let e = exp {
                                        initType = typeCheck(e, copiedNameMap)
                                    } else {
                                        initType = convert(tp)
                                    }
                                    if initType != convert(tp) {
                                        print("Declaration \(decl) is ill-typed")
                                        exit(ExitCode.semanticError.rawValue)
                                    }
                                    copiedNameMap[name] = (initType, exp != nil)
                            }
                        case .InitExp(let exp):
                            if let e = exp {
                                let _ = typeCheck(e, copiedNameMap)
                            }
                    }
                    if let c = condition {
                        let _ = typeCheck(c, copiedNameMap)
                    }
                    if let p = post {
                        let _ = typeCheck(p, copiedNameMap)
                    }
                    let _ = typeCheck(body, &copiedNameMap)
                    return .Void
                case .Switch(let toggle, let body, _):
                    let _ = typeCheck(toggle, nameMap)
                    var copiedNameMap = copyNameMap(nameMap)
                    let _ = typeCheck(body, &copiedNameMap)
                    return .Void
                case .Labeled(let ls):
                    switch ls {
                        // TODO: some type checking that should be happening isn't happening inside of switch statements
                        case .CaseStatement(_, let line):    // don't bother type checking a constant
                            let _ = typeCheck(line, &nameMap)
                        case .DefaultStatement(let line):
                            let _ = typeCheck(line, &nameMap)
                        case .IdentifiedLine(_, let line):
                            let _ = typeCheck(line, &nameMap)
                    }
                    return .Void
            }
        }

        // NOTE: this does not match return statements with function return types
        func typeCheck(_ block: Parser.AST.Block, _ nameMap : inout [String : (CheckerType, Bool)]) -> CheckerType {
            switch block {
                case .Block(let blockItems):
                    for item in blockItems {
                        switch item {
                            case .D(let decl):
                                switch decl {
                                    case .Declaration(let tp, let name, let exp):
                                        let initType : CheckerType
                                        if let e = exp {
                                            initType = typeCheck(e, nameMap)
                                        } else {
                                            initType = convert(tp)
                                        }
                                        if initType != convert(tp) {
                                            print("Declaration \(decl) is ill-typed")
                                            exit(ExitCode.semanticError.rawValue)
                                        }
                                        nameMap[name] = (initType, exp != nil)
                                }
                            case .S(let stmt):
                                let _ = typeCheck(stmt, &nameMap)
                        }
                    }
                    return .Void
            }
        }

        func typeCheck(_ pls : Parser.AST.ProgramLevelStatement, _ nameMap : inout [String : (CheckerType, Bool)]) -> CheckerType {
            switch pls {
                case .Function(let returnType, let name, let params, let body):
                    var paramTypes : [CheckerType] = []
                    for p in params {
                        switch p {
                            case .Declaration(let tp, _):
                                paramTypes.append(convert(tp))
                        }
                    }
                    let constructedType : CheckerType = .Function(convert(returnType), paramTypes)
                    if let preExistingFunction = nameMap[name] {
                        let (oldType, oldDefined) = preExistingFunction
                        if oldDefined {
                            print("Redefinition of function \(name)")
                            exit(ExitCode.semanticError.rawValue)
                        }
                        if oldType != constructedType {
                            print("Funciton \(name) was redeclared with a different type")
                            exit(ExitCode.semanticError.rawValue)
                        }
                    } else {
                        nameMap[name] = (constructedType, true)
                    }
                    var copy = copyNameMap(nameMap)
                    for p in params {
                        switch p {
                            case .Declaration(let tp, let name):
                                copy[name] = (convert(tp), true)
                        }
                    }
                    return typeCheck(body, &copy)
                case .FunctionDeclaration(let returnType, let name, let params):
                    var paramTypes : [CheckerType] = []
                    for p: Parser.AST.Parameter in params {
                        switch p {
                            case .Declaration(let tp, _):
                                paramTypes.append(convert(tp))
                        }
                    }
                    let constructedType : CheckerType = .Function(convert(returnType), paramTypes)
                    if let preExistingFunction = nameMap[name] {
                        let (oldType, _) = preExistingFunction
                        if oldType != constructedType {
                            print("Funciton \(name) was redeclared with a different type")
                            exit(ExitCode.semanticError.rawValue)
                        }
                    } else {
                        nameMap[name] = (constructedType, false)
                    }
                    return constructedType
            }
        }

        func typeCheck(_ program: Parser.AST.Program) {
            var overallNameMap : [String : (
                CheckerType,    // the value's type
                Bool            // whether the value has been defined
            )] = [:]

            switch program {
                case .Statement(let pls):
                    for p in pls {
                        let _ = typeCheck(p, &overallNameMap)
                    }
            }
        }
    }

    func analyze(_ program: Parser.AST.Program) -> Parser.AST.Program {
        // currently our only semantic analysis step
        let resolvedProgram = VariableResolver().resolveVariables(program)
        let labeledProgram = LoopLabeler().labelLoops(resolvedProgram)
        let casedProgram = CasePlacer().placeCases(labeledProgram)
        let _ = TypeChecker().typeCheck(casedProgram)
        return casedProgram
    }
}