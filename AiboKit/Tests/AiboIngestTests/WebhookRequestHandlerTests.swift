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
    #expect(once.delivery?.status == "FINISHED")
    #expect(once.delivery?.summary == "done")
    #expect(once.delivery?.id == "delivery-1")
    #expect(once.delivery?.skipReceiveLog == false)

    let twice = WebhookRequestHandler.handle(request: request, secret: secret, idCache: &cache)
    #expect(twice.statusCode == 200)
    #expect(twice.delivery == nil)
}

@Test func webhookHandlerMarksTestHeaderAsSkipReceiveLog() {
    let body = Data(#"{"status":"FINISHED","summary":"probe"}"#.utf8)
    let secret = "s3cret"
    let request = HTTPRequest(
        method: "POST",
        path: "/webhook",
        headers: [
            "X-Webhook-Signature": WebhookSignature.sign(body: body, secret: secret),
            "X-Webhook-ID": "delivery-test",
            WebhookRequestHandler.testHeaderName: "1",
        ],
        body: body
    )
    var cache = WebhookIDCache()
    let result = WebhookRequestHandler.handle(request: request, secret: secret, idCache: &cache)
    #expect(result.statusCode == 200)
    #expect(result.delivery?.skipReceiveLog == true)
    #expect(result.delivery?.summary == "probe")
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

@Test func httpParserRejectsMalformedLengthChunkedAndOversizedPayloads() {
    let badLength = Data("POST /webhook HTTP/1.1\r\nContent-Length: abc\r\n\r\n".utf8)
    #expect(throws: HTTPRequestParser.ParseError.malformed) {
        try HTTPRequestParser.parse(badLength)
    }

    let negativeLength = Data("POST /webhook HTTP/1.1\r\nContent-Length: -5\r\n\r\n".utf8)
    #expect(throws: HTTPRequestParser.ParseError.malformed) {
        try HTTPRequestParser.parse(negativeLength)
    }

    let chunked = Data("POST /webhook HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n".utf8)
    #expect(throws: HTTPRequestParser.ParseError.unsupported) {
        try HTTPRequestParser.parse(chunked)
    }

    let oversizedHeader = Data(repeating: UInt8(ascii: "A"), count: 128)
    #expect(throws: HTTPRequestParser.ParseError.payloadTooLarge) {
        try HTTPRequestParser.parse(oversizedHeader, maxHeaderBytes: 64)
    }

    let oversizedBody = Data("POST /webhook HTTP/1.1\r\nContent-Length: 500\r\n\r\n".utf8)
    #expect(throws: HTTPRequestParser.ParseError.payloadTooLarge) {
        try HTTPRequestParser.parse(oversizedBody, maxBodyBytes: 100)
    }
}

@Test func webhookHandlerTreatsEmptyWebhookIDAsMissing() {
    let secret = "s3cret"
    let bodyA = Data(#"{"status":"FINISHED","summary":"first"}"#.utf8)
    let bodyB = Data(#"{"status":"FINISHED","summary":"second"}"#.utf8)
    var cache = WebhookIDCache()

    let first = WebhookRequestHandler.handle(
        request: HTTPRequest(
            method: "POST",
            path: "/webhook",
            headers: [
                "X-Webhook-Signature": WebhookSignature.sign(body: bodyA, secret: secret),
                "X-Webhook-ID": "   ",
            ],
            body: bodyA
        ),
        secret: secret,
        idCache: &cache
    )
    let second = WebhookRequestHandler.handle(
        request: HTTPRequest(
            method: "POST",
            path: "/webhook",
            headers: [
                "X-Webhook-Signature": WebhookSignature.sign(body: bodyB, secret: secret),
                "X-Webhook-ID": "",
            ],
            body: bodyB
        ),
        secret: secret,
        idCache: &cache
    )
    #expect(first.statusCode == 200)
    #expect(first.delivery != nil)
    #expect(second.statusCode == 200)
    #expect(second.delivery != nil)
    #expect(first.delivery?.id != second.delivery?.id)
}
