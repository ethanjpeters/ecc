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
                    print("Unsupported compount assignment found while generating tacky")
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
            }
        }

        func resolveStatement(_ stmt : Parser.AST.Statement, _ nameMap: inout [String : (String, Bool)]) -> Parser.AST.Statement {
            switch stmt {
                case .Expression(let exp): return .Expression(resolveExpression(exp, &nameMap))
                case .Return(let exp): return .Return(resolveExpression(exp, &nameMap))
                case .Null: return .Null
                case .If(let cond, let thenStatement, let elseStatement):
                    var copiedNameMap = copyNameMap(nameMap)
                    return .If(resolveExpression(cond, &nameMap), resolveStatement(thenStatement, &copiedNameMap),
                               elseStatement == nil ? nil : resolveStatement(elseStatement!, &copiedNameMap))
                case .Compound(let block):
                    switch block {
                        case .Block(let items):
                            return .Compound(.Block(items.map { itm in
                                var copiedNameMap = copyNameMap(nameMap)
                                return resolveBlockItem(itm, &copiedNameMap)
                            }))
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

    func analyze(_ program: Parser.AST.Program) -> Parser.AST.Program {
        // currently our only semantic analysis step
        return VariableResolver().resolveVariables(program)
    }
}