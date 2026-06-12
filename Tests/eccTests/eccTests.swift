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
}

@Suite("Lexer Tests")
struct LexerTest {
    @Test("Most basic program")
    func testMostBasicProgram() async throws {
        let lexer = Lexer(withString: ProgramSourceCodes.ret2)
        let tokenStream = lexer.lex()
        let justTokens = tokenStream.map{ $0.0 }
        #expect(justTokens == [
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
}