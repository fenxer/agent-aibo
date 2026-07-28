import Foundation
import Testing
@testable import AiboCore

@Test func webhookSignatureRoundTrip() {
    let body = Data(#"{"status":"FINISHED"}"#.utf8)
    let secret = "test-secret"
    let header = WebhookSignature.sign(body: body, secret: secret)
    #expect(WebhookSignature.isValid(body: body, signatureHeader: header, secret: secret))
    #expect(WebhookSignature.isValid(body: body, signatureHeader: header, secret: "other") == false)
    #expect(
        WebhookSignature.isValid(
            body: Data(#"{"status":"ERROR"}"#.utf8),
            signatureHeader: header,
            secret: secret
        ) == false
    )
}

@Test func webhookMessagePrefersSummary() {
    let body = Data(
        #"{"event":"statusChange","status":"FINISHED","summary":"Added README"}"#.utf8
    )
    let parsed = WebhookMessageFormatter.parse(from: body)
    #expect(parsed.displayText == "FINISHED: Added README")
    #expect(parsed.status == "FINISHED")
    #expect(parsed.summary == "Added README")
}

@Test func webhookMessageExtractsSource() {
    let cursor = Data(
        #"{"event":"statusChange","status":"FINISHED","summary":"done"}"#.utf8
    )
    #expect(WebhookMessageFormatter.parse(from: cursor).source == "Cursor")

    let explicit = Data(
        #"{"source":"Deploy Bot","summary":"shipped"}"#.utf8
    )
    let parsed = WebhookMessageFormatter.parse(from: explicit)
    #expect(parsed.source == "Deploy Bot")
    #expect(parsed.summary == "shipped")
    #expect(parsed.status == nil)
}

@Test func webhookIDCacheDedups() {
    var cache = WebhookIDCache(capacity: 2)
    #expect(cache.containsOrInsert("a") == false)
    #expect(cache.containsOrInsert("a") == true)
    #expect(cache.containsOrInsert("b") == false)
    #expect(cache.containsOrInsert("c") == false)
    // "a" should have been evicted
    #expect(cache.containsOrInsert("a") == false)
}
