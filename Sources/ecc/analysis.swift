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
                case .Switch(_, _): fallthrough
                case .Labeled(_):
                    print("Unsupported statement found during analysis: \(stmt)")
                    exit(ExitCode.internalError.rawValue)
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

        func resolveVariables(_ program: Parser.AST.Program) -> Parser.AST.Program {
            switch program {
                case .Function(let name, let body):
                    // MARK - globals to be introduced here
                    var variableNameMapping : [String : (String, Bool)] = [:]
                    switch body {
                        case .Block(let items):
                            return .Function(name, .Block(items.map { resolveBlockItem($0, &variableNameMapping) }))
                    }
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

        func labelLoops(_ statement: Parser.AST.Statement, loopLabel: String?) -> Parser.AST.Statement {
            switch statement {
                case .Break(_):
                    if let lab = loopLabel {
                        return .Break(lab)
                    } else {
                        print("Break found outside of loop")
                        exit(ExitCode.semanticError.rawValue)
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
                    let labeledBody = labelLoops(body, loopLabel: newLabel)
                    let labeledCondition = labelLoops(condition, loopLabel: newLabel)
                    return .DoWhile(labeledBody, labeledCondition, newLabel)
                case .While(let condition, let body, _):
                    let newLabel = makeLoopLabel()
                    let labeledBody = labelLoops(body, loopLabel: newLabel)
                    let labeledCondition = labelLoops(condition, loopLabel: newLabel)
                    return .While(labeledCondition, labeledBody, newLabel)
                case .For(let forInit, let condition, let increment, let body, _):
                    let newLabel = makeLoopLabel()
                    let labeledForInit : Parser.AST.ForInit
                    switch forInit {
                        case .InitDecl(let decl):
                            switch decl {
                                case .Declaration(let name, let exp):
                                    labeledForInit = .InitDecl(.Declaration(name, exp == nil ? nil : labelLoops(exp!, loopLabel: newLabel)))
                            }
                        case .InitExp(let exp):
                            labeledForInit = .InitExp(exp == nil ? nil : labelLoops(exp!, loopLabel: newLabel))
                    }
                    let labeledCondition = condition == nil ? nil : labelLoops(condition!, loopLabel: newLabel)
                    let labeledIncrement = increment == nil ? nil : labelLoops(increment!, loopLabel: newLabel)
                    let labeledBody = labelLoops(body, loopLabel: newLabel)
                    return .For(labeledForInit, labeledCondition, labeledIncrement, labeledBody, newLabel)
                case .Return(let exp): return .Return(labelLoops(exp, loopLabel: loopLabel))
                case .Expression(let exp): return .Expression(labelLoops(exp, loopLabel: loopLabel))
                case .If(let cond, let thenStatement, let elseStatement):
                    return .If(
                        labelLoops(cond, loopLabel: loopLabel),
                        labelLoops(thenStatement, loopLabel: loopLabel),
                        elseStatement == nil ? nil : labelLoops(elseStatement!, loopLabel: loopLabel)
                    )
                case .Compound(let block):
                    return .Compound(labelLoops(block, loopLabel: loopLabel))
                case .Null: return .Null
                case .Switch(_, _): fallthrough
                case .Labeled(_):
                    print("Unsupported statement found during loop labeling: \(statement)")
                    exit(ExitCode.internalError.rawValue)
            }
        }

        func labelLoops(_ expression: Parser.AST.Expression, loopLabel: String?) -> Parser.AST.Expression {
            // this might actually be correct
            return expression
        }

        func labelLoops(_ blockItem: Parser.AST.BlockItem, loopLabel: String?) -> Parser.AST.BlockItem {
            switch blockItem {
                case .D(let decl):
                    switch decl {
                        case .Declaration(let name, let exp):
                            let outExp : Parser.AST.Expression?
                            if let e = exp {
                                outExp = labelLoops(e, loopLabel: loopLabel)
                            } else {
                                outExp = nil
                            }
                            return .D(.Declaration(name, outExp))
                    }
                case .S(let stmt):
                    return .S(labelLoops(stmt, loopLabel: loopLabel))
            }
        }

        func labelLoops(_ block : Parser.AST.Block, loopLabel: String?) -> Parser.AST.Block {
            switch block {
                case .Block(let items):
                    var labeledItems : [Parser.AST.BlockItem] = []
                    for itm in items {
                        labeledItems.append(labelLoops(itm, loopLabel: loopLabel))
                    }
                    return .Block(labeledItems)
            }
        }

        func labelLoops(_ program: Parser.AST.Program) -> Parser.AST.Program {
            switch program {
                case .Function(let name, let body):
                    return .Function(name, labelLoops(body, loopLabel: nil))
            }
        }
    }

    func analyze(_ program: Parser.AST.Program) -> Parser.AST.Program {
        // currently our only semantic analysis step
        let resolvedProgram = VariableResolver().resolveVariables(program)
        return LoopLabeler().labelLoops(resolvedProgram)
    }
}