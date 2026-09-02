import Foundation
@testable import HushCore
import XCTest

final class OllamaReplyGeneratorTests: XCTestCase {
    func testDraftUsesLocalEndpointAndParsesReply() async throws {
        let captured = RequestBox()
        let generator = OllamaReplyGenerator(model: "qwen3:8b") { request in
            captured.request = request
            let data = Data(#"{"message":{"role":"assistant","content":"  Friday works for me.  "}}"#.utf8)
            return (
                data,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }

        let reply = try await generator.draft(
            messages: [ChatMessage(role: .user, content: "Can we meet Friday?")]
        )

        XCTAssertEqual(reply, "Friday works for me.")
        XCTAssertEqual(captured.request?.url?.absoluteString, "http://127.0.0.1:11434/api/chat")
        let body = try XCTUnwrap(captured.request?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "qwen3:8b")
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertEqual(json["think"] as? Bool, false)
    }

    func testRejectsMalformedResponse() {
        XCTAssertThrowsError(try OllamaReplyGenerator.parseReply(Data("{}".utf8))) { error in
            XCTAssertEqual(error as? OllamaReplyError, .invalidResponse)
        }
    }

    func testRejectsEmptyReply() {
        let data = Data(#"{"message":{"role":"assistant","content":"  "}}"#.utf8)
        XCTAssertThrowsError(try OllamaReplyGenerator.parseReply(data)) { error in
            XCTAssertEqual(error as? OllamaReplyError, .emptyReply)
        }
    }
}

private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?

    var request: URLRequest? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
