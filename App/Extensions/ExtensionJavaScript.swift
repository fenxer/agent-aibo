import AiboCore
import Foundation
import JavaScriptCore
import Synchronization

enum ExtensionScriptError: Error {
    case missingRun
    case failed(String)
    case timedOut
    case undecodable
}

/// Runs one plugin round in a fresh JavaScriptCore context. The plugin file is plain
/// `export function run(params)`; the host strips `export` because this context is not a module.
enum ExtensionJavaScript: Sendable {
    private static let wallClockTimeoutSeconds: TimeInterval = 10

    nonisolated static func invoke(source: String, parameters: [String: ExtensionValue]) async throws -> ExtensionRoundResult {
        let payload = try ExtensionJSON.encodeObject(parameters)
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let settled = Mutex(false)
            let finish: @Sendable (Result<Data, Error>) -> Void = { result in
                let shouldResume = settled.withLock { done -> Bool in
                    guard !done else { return false }
                    done = true
                    return true
                }
                guard shouldResume else { return }
                continuation.resume(with: result)
            }

            let timeoutWork = DispatchWorkItem {
                finish(.failure(ExtensionScriptError.timedOut))
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + wallClockTimeoutSeconds,
                execute: timeoutWork
            )

            DispatchQueue.global(qos: .userInitiated).async {
                defer { timeoutWork.cancel() }
                do {
                    let result = try invokeSync(source: source, parameters: payload)
                    finish(.success(result))
                } catch {
                    finish(.failure(error))
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
        guard let context = JSContext() else {
            throw ExtensionScriptError.failed("JavaScript engine unavailable")
        }
        var thrown: String?
        context.exceptionHandler = { _, value in
            thrown = value?.toString()
        }
        let prepared = source.replacingOccurrences(
            of: #"(?m)^export\s+(?:default\s+)?(?=(?:async\s+)?function\b|const\b|let\b|var\b)"#,
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
            box.resolve(ok: ok as String?, err: err as String?)
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
        let snapshot = box.snapshot()
        if let thrown, !snapshot.done {
            throw ExtensionScriptError.failed(thrown)
        }
        // JavaScriptCore drains microtasks before `evaluateScript` returns; with no host
        // timers exposed in this context, an unsettled promise can never resolve later.
        if !snapshot.done {
            throw ExtensionScriptError.timedOut
        }
        if let err = snapshot.err, !err.isEmpty {
            throw ExtensionScriptError.failed(err)
        }
        guard let ok = snapshot.ok, let data = ok.data(using: .utf8) else {
            throw ExtensionScriptError.undecodable
        }
        return data
    }
}

private final class ScriptBox: Sendable {
    struct Snapshot: Sendable {
        var done = false
        var ok: String?
        var err: String?
    }

    private let state = Mutex(Snapshot())

    nonisolated init() {}

    nonisolated func resolve(ok: String?, err: String?) {
        state.withLock { current in
            guard !current.done else { return }
            current.ok = ok
            current.err = err
            current.done = true
        }
    }

    nonisolated func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}
