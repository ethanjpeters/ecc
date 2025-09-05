import Foundation

class SemanticAnalyzer {
    class VariableResolver {
        private var tempNameCounter : Int = 0

        func makeTemp(_ base : String) -> String {
            let out = "\(base).uniqued.\(tempNameCounter)"  // used "uniqued" to avoid collisions with "tmp.#" variables
            tempNameCounter = tempNameCounter + 1
            return out
        }

        func resolveExpression(_ exp : Parser.AST.Expression, _ nameMap: inout [String : String]) -> Parser.AST.Expression {
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
                        return .Var(uniqueName)
                    } else {
                        print("Undeclared variable \(name)")
                        exit(ExitCode.semanticError.rawValue)
                    }
            }
        }

        func resolveStatement(_ stmt : Parser.AST.Statement, _ nameMap: inout [String : String]) -> Parser.AST.Statement {
            switch stmt {
                case .Expression(let exp): return .Expression(resolveExpression(exp, &nameMap))
                case .Return(let exp): return .Return(resolveExpression(exp, &nameMap))
                case .Null: return .Null
            }
        }

        func resolveDeclaration(_ decl: Parser.AST.Declaration, _ nameMap: inout [String : String]) -> Parser.AST.Declaration {
            switch decl {
                case .Declaration(let name, let exp):
                    if let n = nameMap[name] {
                        print("Duplicate variable name found: \(n)")
                        exit(ExitCode.semanticError.rawValue)
                    }
                    let uniqueName = makeTemp(name)
                    nameMap[name] = uniqueName
                    var outInit : Parser.AST.Expression? = nil
                    if let initializer = exp {
                        outInit = resolveExpression(initializer, &nameMap)
                    }
                    return .Declaration(uniqueName, outInit)
            }
        }

        func resolveBlockItem(_ blockItem: Parser.AST.BlockItem, _ nameMap: inout [String : String]) -> Parser.AST.BlockItem {
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
                    var variableNameMapping : [String : String] = [:]
                    return .Function(name, body.map { resolveBlockItem($0, &variableNameMapping) })
            }
        }
    }

    func analyze(_ program: Parser.AST.Program) -> Parser.AST.Program {
        // currently our only semantic analysis step
        return VariableResolver().resolveVariables(program)
    }
}