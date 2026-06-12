import Testing
@testable import ecc

@Test func example() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
}

struct ProgramSourceCodes {
    static let ret2 : String = """
    int main(void) {
        return 2;
    }
    """

    static let arrays : String = """
    static int z[4];

    int main(void) {
        int x[3] = { 1, 2, 3 };
        int y[2][3] = { { 3, 4, 5 }, { 6, 7, 8 } };
        return x[2];
    }
    """
}

@Suite("Lexer Tests")
struct LexerTests {
    private func toks(_ from: String) -> [Lexer.Token] {
        let lexer = Lexer(withString: from)
        let tokenStream = lexer.lex()
        let justTokens = tokenStream.map { $0.0 }
        return justTokens
    }

    @Test("Most basic program")
    func testMostBasicProgram() async throws {
        #expect(toks(ProgramSourceCodes.ret2) == [
            .keywordInt,
            .identifier("main"),
            .openParen,
            .keywordVoid,
            .closeParen,
            .openBrace,
            .keywordReturn,
            .constant("2"),
            .semicolon,
            .closeBrace
        ])
    }

    @Test("Basic arrays program")
    func testBasicArraysProgram() async throws {
        let staticDef : [Lexer.Token] = [
            .keywordStatic,
            .keywordInt,
            .identifier("z"),
            .openBracket,
            .constant("4"),
            .closeBracket,
            .semicolon,
        ]
        let mainHeader : [Lexer.Token] = [
            .keywordInt,
            .identifier("main"),
            .openParen,
            .keywordVoid,
            .closeParen,
            .openBrace,
        ]
        let xDef : [Lexer.Token] = [
            .keywordInt,
            .identifier("x"),
            .openBracket,
            .constant("3"),
            .closeBracket,
            .equal,
            .openBrace,
            .constant("1"),
            .comma,
            .constant("2"),
            .comma,
            .constant("3"),
            .closeBrace,
            .semicolon
        ]
        let yDef : [Lexer.Token] = [
            .keywordInt,
            .identifier("y"),
            .openBracket,
            .constant("2"),
            .closeBracket,
            .openBracket,
            .constant("3"),
            .closeBracket,
            .equal,
            .openBrace,
            .openBrace,
            .constant("3"),
            .comma,
            .constant("4"),
            .comma,
            .constant("5"),
            .closeBrace,
            .comma,
            .openBrace,
            .constant("6"),
            .comma,
            .constant("7"),
            .comma,
            .constant("8"),
            .closeBrace,
            .closeBrace,
            .semicolon,
        ]
        let retStmt : [Lexer.Token] = [
            .keywordReturn,
            .identifier("x"),
            .openBracket,
            .constant("2"),
            .closeBracket,
            .semicolon,
            .closeBrace
        ]
        let t = toks(ProgramSourceCodes.arrays)
        #expect(t == (
            staticDef +
            mainHeader +
            xDef +
            yDef +
            retStmt
        ))
    }
}

@Suite("Parser Tests")
struct ParserTests {
    private func ast(_ from: String) -> Parser.AST.Program {
        let lexer = Lexer(withString: from)
        var tokenStream = lexer.lex()
        return Parser().parse(tokenStream: &tokenStream)
    }

    func testMostBasicProgram() async throws {
        #expect(ast(ProgramSourceCodes.ret2) == .Statement([
            .FunctionDeclaration(.Int,
                "main",
                [],
                .Block([
                    .S(.Return(.Constant(
                        .ConstInt(Int32(2)), nil)
                    ))
                ]),
                nil
            )
        ]))
    }
}

@Suite("Analyzer Tests")
struct AnalysisTests {
    private func ast(_ from: String) -> (Parser.AST.Program, [String : (SemanticAnalyzer.TypeChecker.CheckerType, SemanticAnalyzer.TypeChecker.IdentifierAttributes)], SemanticAnalyzer.TypeChecker.TypeTable) {
        let lexer = Lexer(withString: from)
        var tokenStream = lexer.lex()
        let ast = Parser().parse(tokenStream: &tokenStream)
        return SemanticAnalyzer().analyze(ast)
    }

    func testMostBasicProgram() async throws {
        let (vAst, sTable, tTable) = ast(ProgramSourceCodes.ret2)
        let expAst : Parser.AST.Program = .Statement([
            .FunctionDeclaration(.Int,
                "main",
                [],
                .Block([
                    .S(.Return(.Constant(
                        .ConstInt(Int32(2)), .Int)
                    ))
                ]),
                nil
            )
        ])
        #expect(vAst == expAst)
        let expSTable : [String : (SemanticAnalyzer.TypeChecker.CheckerType, SemanticAnalyzer.TypeChecker.IdentifierAttributes)] = [
            "main" : (.Function(.Int, []), .FunAttr(true, true))
        ]
        #expect(sTable.count == expSTable.count)
        #expect(sTable.keys == expSTable.keys)
        for k in sTable.keys {
            let (lTp, lIdentAttr) = sTable[k]!
            let (rTp, rIdentAttr) = expSTable[k]!
            #expect(lTp == rTp)
            #expect(lIdentAttr == rIdentAttr)
        }
    }
}