import Foundation

/// One capability the plugin asked for, and the host's best way to satisfy it.
///
/// Checked before the plugin runs. A missing provider cannot report itself.
public struct ExtensionDependencyIssue: Equatable, Sendable, Identifiable {
    public enum Remedy: Equatable, Sendable {
        /// Listed in the catalog and not installed yet.
        case install(String)
        /// Installed, but turned off.
        case enable(String)
        /// Nothing installed provides it, and the catalog has no match.
        case unavailable
    }

    public var capability: String
    /// Catalog id, installed plugin id, or the capability name when nothing matches.
    public var subjectID: String
    public var name: String
    public var summary: String
    public var remedy: Remedy

    public var id: String { capability }

    public init(
        capability: String,
        subjectID: String,
        name: String,
        summary: String,
        remedy: Remedy
    ) {
        self.capability = capability
        self.subjectID = subjectID
        self.name = name
        self.summary = summary
        self.remedy = remedy
    }
}

public enum ExtensionDependencyGate {
    public struct Installed: Equatable, Sendable {
        public var id: String
        public var name: String
        public var summary: String
        public var provides: [String]
        public var enabled: Bool

        public init(id: String, name: String, summary: String, provides: [String], enabled: Bool) {
            self.id = id
            self.name = name
            self.summary = summary
            self.provides = provides
            self.enabled = enabled
        }
    }

    public struct Listed: Equatable, Sendable {
        public var id: String
        public var name: String
        public var summary: String
        public var provides: [String]

        public init(id: String, name: String, summary: String, provides: [String]) {
            self.id = id
            self.name = name
            self.summary = summary
            self.provides = provides
        }
    }

    /// One issue per capability that no enabled plugin provides.
    /// An installed-but-off plugin wins over a catalog entry: the files are already here.
    /// Among several matches, the lowest id wins so the row stays put across reloads.
    public static func issues(
        required: [String],
        installed: [Installed],
        catalog: [Listed]
    ) -> [ExtensionDependencyIssue] {
        required.compactMap { capability in
            let providers = installed.filter { $0.provides.contains(capability) }
            if providers.contains(where: \.enabled) {
                return nil
            }
            if let disabled = providers.min(by: { $0.id < $1.id }) {
                return ExtensionDependencyIssue(
                    capability: capability,
                    subjectID: disabled.id,
                    name: disabled.name,
                    summary: disabled.summary,
                    remedy: .enable(disabled.id)
                )
            }
            if let listed = catalog.filter({ $0.provides.contains(capability) }).min(by: { $0.id < $1.id }) {
                return ExtensionDependencyIssue(
                    capability: capability,
                    subjectID: listed.id,
                    name: listed.name,
                    summary: listed.summary,
                    remedy: .install(listed.id)
                )
            }
            return ExtensionDependencyIssue(
                capability: capability,
                subjectID: capability,
                name: capability,
                summary: "",
                remedy: .unavailable
            )
        }
    }
}
