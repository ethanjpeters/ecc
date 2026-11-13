import Testing
@testable import ecc

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

    static let basicStruct : String = """
    struct LLNode {
        void *item;
        struct LLNode *next;
    };

    struct LLNode *reverseInternal(struct LLNode * head, struct LLNode * prev) {
        if (head) {
            struct LLNode *n = head->next;
            head->next = prev;
            if (n) {
                return reverseInternal(n, head);
            }
        }
        return head;
    }

    struct LLNode *reverse(struct LLNode * head) {
        return reverseInternal(head, (struct LLNode*)0);
    }

    int main(void) {
        return 0;
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

    @Test("Basic struct program")
    func testBasicStructProgram() async throws {
        let structDef : [Lexer.Token] = [
            .keywordStruct, .identifier("LLNode"), .openBrace,
            .keywordVoid, .asterisk, .identifier("item"), .semicolon,
            .keywordStruct, .identifier("LLNode"), .asterisk, .identifier("next"), .semicolon,
            .closeBrace, .semicolon
        ]
        let internalFuncDef : [Lexer.Token] = [
            .keywordStruct, .identifier("LLNode"), .asterisk,
            .identifier("reverseInternal"), .openParen, .keywordStruct,
            .identifier("LLNode"), .asterisk, .identifier("head"), .comma,
            .keywordStruct, .identifier("LLNode"), .asterisk, .identifier("prev"),
            .closeParen, .openBrace,
            .keywordIf, .openParen, .identifier("head"), .closeParen, .openBrace,
            .keywordStruct, .identifier("LLNode"), .asterisk, .identifier("n"),
            .equal, .identifier("head"), .arrow, .identifier("next"), .semicolon,
            .identifier("head"), .arrow, .identifier("next"), .equal, .identifier("prev"),
            .semicolon,
            .keywordIf, .openParen, .identifier("n"), .closeParen, .openBrace,
            .keywordReturn, .identifier("reverseInternal"), .openParen, .identifier("n"),
            .comma, .identifier("head"), .closeParen, .semicolon,
            .closeBrace,
            .closeBrace,
            .keywordReturn, .identifier("head"), .semicolon,
            .closeBrace
        ]
        let reverseFuncDef : [Lexer.Token] = [
            .keywordStruct, .identifier("LLNode"), .asterisk, .identifier("reverse"),
            .openParen, .keywordStruct, .identifier("LLNode"), .asterisk, .identifier("head"),
            .closeParen, .openBrace,
            .keywordReturn, .identifier("reverseInternal"), .openParen, .identifier("head"),
            .comma, .openParen, .keywordStruct, .identifier("LLNode"), .asterisk, .closeParen,
            .constant("0"), .closeParen, .semicolon,
            .closeBrace
        ]
        let mainFuncDef : [Lexer.Token] = [
            .keywordInt, .identifier("main"), .openParen, .keywordVoid, .closeParen, .openBrace,
            .keywordReturn, .constant("0"), .semicolon,
            .closeBrace
        ]
        let t = toks(ProgramSourceCodes.basicStruct)
        #expect(t == (
            structDef +
            internalFuncDef +
            reverseFuncDef +
            mainFuncDef
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

/*
    @Test("Most basic program")
    func testMostBasicProgram() async throws {
        #expect(ast(ProgramSourceCodes.ret2) == .Statement([
            .FunctionDeclaration(.FunType([], .Int),
                "main",
                [],
                .Block([
                    .S(.Return(.Constant(
                        .ConstInt(2), nil)
                    ))
                ]),
                nil
            )
        ]))
    }

    @Test("Basic arrays program")
    func testBasicArraysProgram() async throws {
        let xDecl : Parser.AST.Declaration = .VariableDeclaration(
            .ArrayType(.Int, 3),
            "x",
            .CompoundInit([
                .SingleInit(.Constant(.ConstInt(1), nil)),
                .SingleInit(.Constant(.ConstInt(2), nil)),
                .SingleInit(.Constant(.ConstInt(3), nil))
            ]),
            nil
        )
        let yDecl : Parser.AST.Declaration = .VariableDeclaration(
            .ArrayType(.ArrayType(.Int, 3), 2),
            "y",
            .CompoundInit([
                .CompoundInit([
                    .SingleInit(.Constant(.ConstInt(3), nil)),
                    .SingleInit(.Constant(.ConstInt(4), nil)),
                    .SingleInit(.Constant(.ConstInt(5), nil)),
                ]),
                .CompoundInit([
                    .SingleInit(.Constant(.ConstInt(6), nil)),
                    .SingleInit(.Constant(.ConstInt(7), nil)),
                    .SingleInit(.Constant(.ConstInt(8), nil)),
                ])
            ]),
            nil
        )
        #expect(ast(ProgramSourceCodes.arrays) == .Statement([
            .VariableDeclaration(.ArrayType(.Int, 4), "z", nil, .Static),
            .FunctionDeclaration(.FunType([], .Int),
                "main",
                [],
                .Block([
                    .D(xDecl),
                    .D(yDecl),
                    .S(.Return(
                        .Subscript(
                            .Var("x", nil),
                            .Constant(.ConstInt(2), nil),
                            nil
                        )
                    ))
                ]),
                nil
            )
        ]))
    }
*/
    @Test("Basic struct program")
    func testBasicStructsProgram() async throws {
        let structDecl : Parser.AST.Declaration = .StructDeclaration(
            "LLNode",
            [
                ("item", .Pointer(.Void)),
                ("next", .Pointer(.Structure("LLNode")))
            ]
        )
        let internalFuncDef : Parser.AST.Declaration = .FunctionDeclaration(
            .Pointer(.Structure("LLNode")),
            "reverseInternal",
            ["head", "prev"],
            .Block([
                .S(.If(
                    // condition
                    .Var("head", nil),
                    // then path
                    .Compound(.Block([
                        // struct LLNode *n = head->next;
                        .D(.VariableDeclaration(
                            // type
                            .Pointer(.Structure("LLNode")),
                            // name
                            "n",
                            // initializer
                            .SingleInit(.Arrow(
                                .Var("head", nil),
                                "next",
                                nil
                            )),
                            // storage class
                            nil
                        )),
                        // head->next = prev;
                        .S(.Expression(.Assignment(
                            .Arrow(
                                .Var("head", nil),
                                "head",
                                nil
                            ),
                            .Var("prev", nil),
                            nil
                        ))),
                        // if (n) { ... }
                        .S(.If(
                            // condition
                            .Var("n", nil),
                            // then path
                            .Compound(.Block([
                                .S(.Return(
                                    .FunctionCall(
                                        // name
                                        .Var("reverseInternal", nil),
                                        // parameters
                                        [
                                            .Var("n", nil),
                                            .Var("head", nil)
                                        ],
                                        // type
                                        nil
                                    )
                                ))
                            ])),
                            // else path
                            nil
                        ))
                    ])),
                    // else path
                    nil
                )),
                .S(.Return(.Var("head", nil)))
            ]),
            nil
        )
        let reverseFuncDef : Parser.AST.Declaration = .FunctionDeclaration(
            .Pointer(.Structure("LLNode")),
            "reverse",
            ["head"],
            .Block([
                .S(.Return(
                    .FunctionCall(
                        // name
                        .Var("reverseInternal", nil),
                        // parameters
                        [
                            .Var("head", nil),
                            .Cast(
                                .Pointer(.Structure("LLNode")),
                                .Constant(
                                    .ConstInt(Int32(0)),
                                    nil
                                ),
                                nil
                            )
                        ],
                        // type
                        nil
                    )
                ))
            ]),
            nil
        )
        let mainFuncDef : Parser.AST.Declaration = .FunctionDeclaration(
            .Int,
            "main",
            [],
            .Block([.S(.Return(.Constant(.ConstInt(0), nil)))]),
            nil
        )
        let expectedProgramDef : Parser.AST.Program = .Statement([
            structDecl,
            internalFuncDef,
            reverseFuncDef,
            mainFuncDef
        ])
        let actualProgramDef = ast(ProgramSourceCodes.basicStruct)
        #expect(actualProgramDef == expectedProgramDef)
    }
}

/**
@Suite("Analyzer Tests")
struct AnalysisTests {
    private func ast(_ from: String) -> (Parser.AST.Program, [String : (SemanticAnalyzer.TypeChecker.CheckerType, SemanticAnalyzer.TypeChecker.IdentifierAttributes)], SemanticAnalyzer.TypeChecker.TypeTable) {
        let lexer = Lexer(withString: from)
        var tokenStream = lexer.lex()
        let ast = Parser().parse(tokenStream: &tokenStream)
        return SemanticAnalyzer().analyze(ast)
    }

    @Test("Most basic program")
    func testMostBasicProgram() async throws {
        let (vAst, sTable, tTable) = ast(ProgramSourceCodes.ret2)
        let expAst : Parser.AST.Program = .Statement([
            .FunctionDeclaration(.FunType([], .Int),
                "main",
                [],
                .Block([
                    .S(.Return(.Constant(
                        .ConstInt(2), .Int)
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
        #expect(tTable.count == 0)
    }

    @Test("Basic arrays program")
    func testBasicArraysProgram() async throws {
        let (vAst, sTable, tTable) = ast(ProgramSourceCodes.arrays)
        let xDecl : Parser.AST.Declaration = .VariableDeclaration(
            .ArrayType(.Int, 3),
            "x.uniqued.0",
            .CompoundInit([
                .SingleInit(.Constant(.ConstInt(1), .Int)),
                .SingleInit(.Constant(.ConstInt(2), .Int)),
                .SingleInit(.Constant(.ConstInt(3), .Int))
            ]),
            nil
        )
        let yDecl : Parser.AST.Declaration = .VariableDeclaration(
            .ArrayType(.ArrayType(.Int, 3), 2),
            "y.uniqued.1",
            .CompoundInit([
                .CompoundInit([
                    .SingleInit(.Constant(.ConstInt(3), .Int)),
                    .SingleInit(.Constant(.ConstInt(4), .Int)),
                    .SingleInit(.Constant(.ConstInt(5), .Int)),
                ]),
                .CompoundInit([
                    .SingleInit(.Constant(.ConstInt(6), .Int)),
                    .SingleInit(.Constant(.ConstInt(7), .Int)),
                    .SingleInit(.Constant(.ConstInt(8), .Int)),
                ])
            ]),
            nil
        )
        let expAst : Parser.AST.Program = .Statement([
            .VariableDeclaration(.ArrayType(.Int, 4), "z", nil, .Static),
            .FunctionDeclaration(.FunType([], .Int),
                "main",
                [],
                .Block([
                    .D(xDecl),
                    .D(yDecl),
                    .S(.Return(
                        .Subscript(
                            .AddrOf(.Var("x.uniqued.0", .ArrayType(.Int, 3)), .Pointer(.Int)),
                            .Cast(.Long, .Constant(.ConstInt(2), .Int), .Int),
                            .Int
                        )
                    ))
                ]),
                nil
            )
        ])
        #expect(vAst == expAst)
    }
    
    @Test("Basic struct program")
    func testBasicStructsProgram() async throws {
        let structDecl : Parser.AST.Declaration = .StructDeclaration(
            "LLNode",
            [
                ("item", .Pointer(.Void)),
                ("next", .Pointer(.Structure("LLNode")))
            ]
        )
        let internalFuncDef : Parser.AST.Declaration = .FunctionDeclaration(
            .Pointer(.Structure("struct.LLNode")),
            "reverseInternal",
            ["head", "prev"],
            .Block([
                .S(.If(
                    // condition
                    .Var("head", nil),
                    // then path
                    .Compound(.Block([
                        // struct LLNode *n = head->next;
                        .D(.VariableDeclaration(
                            // type
                            .Pointer(.Structure("struct.LLNode")),
                            // name
                            "n",
                            // initializer
                            .SingleInit(.Arrow(
                                .Var("head", nil),
                                "next",
                                nil
                            )),
                            // storage class
                            nil
                        )),
                        // head->next = prev;
                        .S(.Expression(.Assignment(
                            .Arrow(
                                .Var("head", nil),
                                "head",
                                nil
                            ),
                            .Var("prev", nil),
                            nil
                        ))),
                        // if (n) { ... }
                        .S(.If(
                            // condition
                            .Var("n", nil),
                            // then path
                            .Compound(.Block([
                                .S(.Return(
                                    .FunctionCall(
                                        // name
                                        .Var("reverseInternal", nil),
                                        // parameters
                                        [
                                            .Var("n", nil),
                                            .Var("head", nil)
                                        ],
                                        // type
                                        nil
                                    )
                                ))
                            ])),
                            // else path
                            nil
                        ))
                    ])),
                    // else path
                    nil
                )),
                .S(.Return(.Var("head", nil)))
            ]),
            nil
        )
        let reverseFuncDef : Parser.AST.Declaration = .FunctionDeclaration(
            .Pointer(.Structure("struct.LLNode")),
            "reverse",
            ["head"],
            .Block([
                .S(.Return(
                    .FunctionCall(
                        // name
                        .Var("reverseInternal", nil),
                        // parameters
                        [
                            .Var("head", nil),
                            .Cast(
                                .Pointer(.Structure("LLNode")),
                                .Constant(
                                    .ConstInt(Int32(0)),
                                    nil
                                ),
                                nil
                            )
                        ],
                        // type
                        nil
                    )
                ))
            ]),
            nil
        )
        let mainFuncDef : Parser.AST.Declaration = .FunctionDeclaration(
            .Int,
            "main",
            [],
            .Block([.S(.Return(.Constant(.ConstInt(0), nil)))]),
            nil
        )
        let expectedProgramDef : Parser.AST.Program = .Statement([
            structDecl,
            internalFuncDef,
            reverseFuncDef,
            mainFuncDef
        ])

        let (vAst, sTable, tTable) = ast(ProgramSourceCodes.basicStruct)

        #expect(expectedProgramDef == vAst)
    }
}*/