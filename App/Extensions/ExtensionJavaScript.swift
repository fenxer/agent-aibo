import AiboCore
import Foundation
import JavaScriptCore

enum ExtensionScriptError: Error {
    case missingRun
    case failed(String)
    case timedOut
    case undecodable
}

/// Runs one plugin round in a fresh JavaScriptCore context. The plugin file is plain
/// `export function run(params)`; the host strips `export` because this context is not a module.
enum ExtensionJavaScript: Sendable {
    nonisolated static func invoke(source: String, parameters: [String: ExtensionValue]) async throws -> ExtensionRoundResult {
        let payload = try ExtensionJSON.encodeObject(parameters)
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try invokeSync(source: source, parameters: payload)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        do {
            return try ExtensionRoundCodec.decode(data)
        } catch {
            throw ExtensionScriptError.undecodable
        }
    }

    nonisolated private static func invokeSync(source: String, parameters: Data) throws -> Data {
        let context = JSContext()!
        var thrown: String?
        context.exceptionHandler = { _, value in
            thrown = value?.toString()
        }
        let prepared = source.replacingOccurrences(
            of: #"(?m)^export\s+"#,
            with: "",
            options: .regularExpression
        )
        context.evaluateScript(prepared)
        if let thrown {
            throw ExtensionScriptError.failed(thrown)
        }
        guard context.objectForKeyedSubscript("run")?.isUndefined == false else {
            throw ExtensionScriptError.missingRun
        }
        let json = String(data: parameters, encoding: .utf8) ?? "{}"
        context.setObject(json, forKeyedSubscript: "__aiboParams" as NSString)
        let box = ScriptBox()
        let resolve: @convention(block) (NSString?, NSString?) -> Void = { ok, err in
            box.ok = ok as String?
            box.err = err as String?
            box.done = true
        }
        context.setObject(resolve, forKeyedSubscript: "__aiboResolve" as NSString)
            context.evaluateScript(
                """
                try {
                  const params = JSON.parse(__aiboParams);
                  const value = run(params);
                  const finish = (v) => __aiboResolve(JSON.stringify(v), "");
                  const fail = (e) => __aiboResolve("", (e && e.message) ? String(e.message) : String(e));
                  if (value && typeof value.then === "function") {
                    value.then(finish, fail);
                  } else {
                    finish(value);
                  }
                } catch (e) {
                  __aiboResolve("", (e && e.message) ? String(e.message) : String(e));
                }
                """
            )
        if let thrown, !box.done {
            throw ExtensionScriptError.failed(thrown)
        }
        let deadline = Date().addingTimeInterval(10)
        while !box.done && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if !box.done {
            throw ExtensionScriptError.timedOut
        }
        if let err = box.err, !err.isEmpty {
            throw ExtensionScriptError.failed(err)
        }
        guard let ok = box.ok, let data = ok.data(using: .utf8) else {
            throw ExtensionScriptError.undecodable
        }
        return data
    }
}

private final class ScriptBox: @unchecked Sendable {
    nonisolated(unsafe) var done = false
    nonisolated(unsafe) var ok: String?
    nonisolated(unsafe) var err: String?

    nonisolated init() {}
}
