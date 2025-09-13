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

        func resolveExpression(_ exp : Parser.AST.Expression, _ nameMap: inout [String : (String, Bool)]) -> Parser.AST.Expression {
            switch exp {
                case .Assignment(let lValue, let rValue):
                    switch lValue {
                        case .Var(_):
                            ()
                        default:
                            print("Invalid lvalue in assignment \(exp)")
                            exit(ExitCode.semanticError.rawValue)
                    }
                    return .Assignment(resolveExpression(lValue, &nameMap), resolveExpression(rValue, &nameMap))
                case .CompoundAssignment(_,_,_):
                    print("Unreachable: Unsupported compound assignment found while generating tacky")
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
                        // DEBUG
                        print("\(nameMap)")
                        // END DEBUG
                        exit(ExitCode.semanticError.rawValue)
                    }
                case .Conditional(let cond, let left, let right):
                    return .Conditional(resolveExpression(cond, &nameMap), resolveExpression(left, &nameMap), resolveExpression(right, &nameMap))
                case .FunctionCall(_, _):
                    print("Unsupported expression found while trying to resolve expressions \(exp)")
                    exit(ExitCode.internalError.rawValue)
            }
        }

        func resolveStatement(_ stmt : Parser.AST.Statement, _ nameMap: inout [String : (String, Bool)]) -> Parser.AST.Statement {
            switch stmt {
                case .Expression(let exp): return .Expression(resolveExpression(exp, &nameMap))
                case .Return(let exp): return .Return(resolveExpression(exp, &nameMap))
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
                case .Declaration(let name, let exp):
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
                    return .Declaration(uniqueName, outInit)
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

        func resolveVariables(_ pls: Parser.AST.ProgramLevelStatement) -> Parser.AST.ProgramLevelStatement {
           switch pls {
                case .Function(let name, let body):
                    // MARK - globals to be introduced here
                    var variableNameMapping : [String : (String, Bool)] = [:]
                    switch body {
                        case .Block(let items):
                            return .Function(name, .Block(items.map { resolveBlockItem($0, &variableNameMapping) }))
                    }
            }
        }

        func resolveVariables(_ program: Parser.AST.Program) -> Parser.AST.Program {
            switch program {
                case .Statement(let statements):
                    return .Statement(statements.map { resolveVariables($0) })
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
                                case .Declaration(let name, let exp):
                                    labeledForInit = .InitDecl(.Declaration(
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
                    return .Return(labelLoops(exp, loopLabel: loopLabel, switchLabel: nil))
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
                        case .Declaration(let name, let exp):
                            let outExp : Parser.AST.Expression?
                            if let e = exp {
                                outExp = labelLoops(e, loopLabel: loopLabel, switchLabel: switchLabel)
                            } else {
                                outExp = nil
                            }
                            return .D(.Declaration(name, outExp))
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
                case .Function(let name, let body):
                    return .Function(name, labelLoops(body, loopLabel: nil, switchLabel: nil))
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
                case .Return(let exp): return .Return(placeCases(exp, isInSwitch: isInSwitch))
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
                                    case .Declaration(let name, let initializer):
                                        placedItems.append(.D(.Declaration(
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
                case .Function(let name, let body):
                    return .Function(name, placeCases(body, isInSwitch: isInSwitch))
            }
        }

        func placeCases(_ program: Parser.AST.Program) -> Parser.AST.Program {
            switch program {
                case .Statement(let statements):
                    return .Statement(statements.map { placeCases($0, isInSwitch: false) })
            }
        }
    }

    func analyze(_ program: Parser.AST.Program) -> Parser.AST.Program {
        // currently our only semantic analysis step
        let resolvedProgram = VariableResolver().resolveVariables(program)
        let labeledProgram = LoopLabeler().labelLoops(resolvedProgram)
        return CasePlacer().placeCases(labeledProgram)
    }
}