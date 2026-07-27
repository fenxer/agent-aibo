import AiboCore
import Foundation
import Testing
@testable import AiboIngest

@Test func httpParserReadsPostBody() throws {
    let raw = Data(
        """
        POST /webhook HTTP/1.1\r
        Host: 127.0.0.1\r
        Content-Length: 5\r
        \r
        hello
        """.utf8
    )
    let request = try HTTPRequestParser.parse(raw)
    #expect(request.method == "POST")
    #expect(request.path == "/webhook")
    #expect(request.body == Data("hello".utf8))
}

@Test func webhookHandlerAcceptsSignedPost() {
    let body = Data(#"{"status":"FINISHED","summary":"done"}"#.utf8)
    let secret = "s3cret"
    let request = HTTPRequest(
        method: "POST",
        path: "/webhook",
        headers: [
            "X-Webhook-Signature": WebhookSignature.sign(body: body, secret: secret),
            "X-Webhook-ID": "delivery-1",
        ],
        body: body
    )
    var cache = WebhookIDCache()
    let once = WebhookRequestHandler.handle(request: request, secret: secret, idCache: &cache)
    #expect(once.statusCode == 200)
    #expect(once.delivery?.displayText == "FINISHED: done")
    #expect(once.delivery?.id == "delivery-1")

    let twice = WebhookRequestHandler.handle(request: request, secret: secret, idCache: &cache)
    #expect(twice.statusCode == 200)
    #expect(twice.delivery == nil)
}

@Test func webhookHandlerRejectsBadSignature() {
    let body = Data(#"{"status":"FINISHED"}"#.utf8)
    let request = HTTPRequest(
        method: "POST",
        path: "/webhook",
        headers: [
            "X-Webhook-Signature": "sha256=deadbeef",
        ],
        body: body
    )
    var cache = WebhookIDCache()
    let result = WebhookRequestHandler.handle(request: request, secret: "s3cret", idCache: &cache)
    #expect(result.statusCode == 401)
    #expect(result.delivery == nil)
}
