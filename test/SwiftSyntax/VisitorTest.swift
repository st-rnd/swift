// RUN: %target-run-simple-swift
// REQUIRES: executable_test
// REQUIRES: OS=macosx
// REQUIRES: objc_interop

import StdlibUnittest
import Foundation
import SwiftSyntax
import SwiftLang

func getInput(_ file: String) -> URL {
  var result = URL(fileURLWithPath: #file)
  result.deleteLastPathComponent()
  result.appendPathComponent("Inputs")
  result.appendPathComponent(file)
  return result
}

func getSyntaxTree(_ url: URL) throws -> SourceFileSyntax {
  let content = try SwiftLang.parse(path: url.path).data(using: .utf8)!
  return try SyntaxTreeDeserializer().deserialize(content,
                                                  serializationFormat: .json)
}

var VisitorTests = TestSuite("SyntaxVisitor")

VisitorTests.test("Basic") {
  class FuncCounter: SyntaxVisitor {
    var funcCount = 0
    override func visit(_ node: FunctionDeclSyntax) {
      funcCount += 1
      super.visit(node)
    }
  }
  expectDoesNotThrow({
    let parsed = try getSyntaxTree(getInput("visitor.swift"))
    let counter = FuncCounter()
    let hashBefore = parsed.hashValue
    counter.visit(parsed)
    expectEqual(counter.funcCount, 3)
    expectEqual(hashBefore, parsed.hashValue)
  })
}

VisitorTests.test("RewritingNodeWithEmptyChild") {
  class ClosureRewriter: SyntaxRewriter {
    override func visit(_ node: ClosureExprSyntax) -> ExprSyntax {
      // Perform a no-op transform that requires rebuilding the node.
      return node.withSignature(node.signature)
    }
  }
  expectDoesNotThrow({
    let parsed = try getSyntaxTree(getInput("closure.swift"))
    let rewriter = ClosureRewriter()
    let rewritten = rewriter.visit(parsed)
    expectEqual(parsed.description, rewritten.description)
  })
}

VisitorTests.test("SyntaxRewriter.visitAny") {
  class VisitAnyRewriter: SyntaxRewriter {
    let transform: (TokenSyntax) -> TokenSyntax
    init(transform: @escaping (TokenSyntax) -> TokenSyntax) {
      self.transform = transform
    }
    override func visitAny(_ node: Syntax) -> Syntax? {
      if let tok = node as? TokenSyntax {
        return transform(tok)
      }
      return nil
    }
  }
  expectDoesNotThrow({
    let parsed = try getSyntaxTree(getInput("near-empty.swift"))
    let rewriter = VisitAnyRewriter(transform: { _ in
       return SyntaxFactory.makeIdentifier("")
    })
    let rewritten = rewriter.visit(parsed)
    expectEqual(rewritten.description, "")
  })
}

VisitorTests.test("SyntaxRewriter.visitCollection") {
  class VisitCollections: SyntaxVisitor {
    var numberOfCodeBlockItems = 0

    override func visit(_ items: CodeBlockItemListSyntax) {
      numberOfCodeBlockItems += items.count
      super.visit(items)
    }
  }

  expectDoesNotThrow({
    let parsed = try getSyntaxTree(getInput("nested-blocks.swift"))
    let visitor = VisitCollections()
    visitor.visit(parsed)
    expectEqual(4, visitor.numberOfCodeBlockItems)
  })
}

runAllTests()
