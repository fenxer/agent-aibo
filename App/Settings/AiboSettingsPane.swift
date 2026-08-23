import AiboCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AiboSettingsPane: View {
    @State private var showsAllPets = false

    var body: some View {
        Group {
            if showsAllPets {
                AllPetsSettingsView {
                    showsAllPets = false
                }
            } else {
                AiboSettingsRootView {
                    showsAllPets = true
                }
            }
        }
    }
}

private struct AiboSettingsRootView: View {
    var onShowAllPets: () -> Void

    @Bindable private var settings = AppSettings.shared
    @Bindable private var library = AiboLibraryStore.shared
    @State private var petdexInput = ""
    @State private var isImportingLocal = false

    @State private var isAskingPetdex = false
    @State private var isAskingDuplicateName = false
    @State private var duplicateDraftName = ""
    @State private var duplicateExistingName = ""
    @State private var installErrorMessage: String?

    var body: some View {
        Form {
            AiboPreviewAndSelectionSection(library: library)

            AiboConfigurationSection(
                record: library.selectedRecord,
                pixelOptimizationEnabled: Binding(
                    get: { library.selectedRecord.pixelOptimizationEnabled },
                    set: { library.setPixelOptimizationEnabled($0) }
                ),
                scalePercent: Binding(
                    get: { library.selectedRecord.scalePercent },
                    set: { library.setScalePercent($0) }
                )
            )

            AiboWindowBehaviorSection(settings: settings)

            Section {
                AllPetsEntryRow(action: onShowAllPets)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(title: String(localized: "Aibo")) {
            ToolbarItem {
                NewAiboToolbarMenu(
                    isInstalling: library.isInstalling,
                    onInstallLocal: { isImportingLocal = true },
                    onInstallPetdex: { isAskingPetdex = true }
                )
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .fileImporter(
            isPresented: $isImportingLocal,
            allowedContentTypes: [.png, .jpeg, .webP, .heic, .tiff, .image, .zip],
            allowsMultipleSelection: false
        ) { result in
            handleLocalImport(result)
        }
        .alert(String(localized: "Install from PetDex"), isPresented: $isAskingPetdex) {
            TextField(String(localized: "PetDex URL or slug"), text: $petdexInput)
            Button(String(localized: "Install"), action: installPetdex)
                .disabled(petdexInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Enter PetDex URL or slug to download."))
        }
        .alert(String(localized: "Aibo Already Exists"), isPresented: $isAskingDuplicateName) {
            TextField(String(localized: "Name"), text: $duplicateDraftName)
            Button(String(localized: "Install")) {
                let name = duplicateDraftName
                Task {
                    await library.confirmPendingNamedImport(displayName: name)
                    if let message = library.lastErrorMessage {
                        installErrorMessage = message
                    }
                }
            }
            .disabled(!library.canConfirmPendingNamedImport(displayName: duplicateDraftName))
            Button(String(localized: "Cancel"), role: .cancel) {
                library.cancelPendingNamedImport()
            }
        } message: {
            Text(duplicateInstallMessage)
        }
        .alert(
            String(localized: "Couldn't Install Aibo"),
            isPresented: Binding(
                get: { installErrorMessage != nil },
                set: { if !$0 { installErrorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(installErrorMessage ?? "")
        }
    }

    private func installPetdex() {
        let input = petdexInput
        Task {
            await library.installPetdex(from: input)
            if let message = library.lastErrorMessage {
                installErrorMessage = message
            } else {
                petdexInput = ""
            }
        }
    }

    private var duplicateInstallMessage: String {
        String(localized: "“\(duplicateExistingName)” is already in your library. Choose a different name to install this aibo.")
    }

    private func handleLocalImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                await library.importLocal(from: url)
                if let pending = library.pendingNamedImport {
                    duplicateExistingName = pending.existingDisplayName
                    duplicateDraftName = pending.suggestedDisplayName
                    isAskingDuplicateName = true
                } else if let message = library.lastErrorMessage {
                    installErrorMessage = message
                }
            }
        case .failure:
            break
        }
    }
}

private struct AiboPreviewAndSelectionSection: View {
    var library: AiboLibraryStore

    var body: some View {
        Section {
            AiboPreviewBanner(
                record: library.selectedRecord,
                onRename: { library.rename(id: $0, to: $1) }
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color(nsColor: .windowBackgroundColor))

            Picker(String(localized: "Active Aibo"), selection: selectedAiboBinding) {
                ForEach(library.records) { record in
                    Text(record.displayName).tag(record.id)
                }
            }
        }
    }

    private var selectedAiboBinding: Binding<String> {
        Binding(
            get: { library.selectedID },
            set: { library.select(id: $0) }
        )
    }
}

private struct AiboNamePrompt: Identifiable, Equatable {
    let id: String
    var name: String
    var existingDisplayName: String?
}

private struct AiboPreviewBanner: View {
    var record: AiboLibraryRecord
    var onRename: (String, String) -> AiboRenameOutcome

    @State private var isPreviewing = false
    @State private var renamePrompt: AiboNamePrompt?
    @State private var conflictPrompt: AiboNamePrompt?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                AiboNameMarquee(name: record.displayName)
                    .id(record.displayName)
                AiboSwitchingSpriteView(
                    record: record,
                    activity: .idle,
                    spriteState: .idle,
                    size: 120,
                    pixelLayout: .fillWidth
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(record.displayName)

            HStack(spacing: 0) {
                Button {
                    isPreviewing = true
                } label: {
                    Image(systemName: "eyes.inverse")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(String(localized: "Preview"))
                .accessibilityLabel(String(localized: "Preview"))

                if record.canRename {
                    Button {
                        renamePrompt = AiboNamePrompt(id: record.id, name: record.displayName)
                    } label: {
                        Image(systemName: "pencil.line")
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(String(localized: "Rename"))
                    .accessibilityLabel(String(localized: "Rename"))
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: 138)
        .alert(
            String(localized: "Rename Aibo"),
            isPresented: renamePromptPresented,
            presenting: renamePrompt
        ) { prompt in
            TextField(String(localized: "Name"), text: renameNameBinding(for: prompt))
            Button(String(localized: "Rename")) {
                applyRename(id: prompt.id, name: renamePrompt?.name ?? prompt.name)
            }
            .disabled(AiboLibraryNaming.normalizedDisplayName(renamePrompt?.name ?? prompt.name) == nil)
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .alert(
            String(localized: "Aibo Already Exists"),
            isPresented: conflictPromptPresented,
            presenting: conflictPrompt
        ) { prompt in
            TextField(String(localized: "Name"), text: conflictNameBinding(for: prompt))
            Button(String(localized: "Rename")) {
                applyRename(id: prompt.id, name: conflictPrompt?.name ?? prompt.name)
            }
            .disabled(!canConfirmConflictName(prompt))
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { prompt in
            Text(
                String(
                    localized: "“\(prompt.existingDisplayName ?? "")” is already in your library. Choose a different name."
                )
            )
        }
        .sheet(isPresented: $isPreviewing) {
            AiboActionPreviewSheet(record: record)
                .id(record.id)
        }
    }

    private var renamePromptPresented: Binding<Bool> {
        Binding(
            get: { renamePrompt != nil },
            set: { if !$0 { renamePrompt = nil } }
        )
    }

    private var conflictPromptPresented: Binding<Bool> {
        Binding(
            get: { conflictPrompt != nil },
            set: { if !$0 { conflictPrompt = nil } }
        )
    }

    private func renameNameBinding(for prompt: AiboNamePrompt) -> Binding<String> {
        Binding(
            get: { renamePrompt?.name ?? prompt.name },
            set: { renamePrompt?.name = $0 }
        )
    }

    private func conflictNameBinding(for prompt: AiboNamePrompt) -> Binding<String> {
        Binding(
            get: { conflictPrompt?.name ?? prompt.name },
            set: { conflictPrompt?.name = $0 }
        )
    }

    private func canConfirmConflictName(_ prompt: AiboNamePrompt) -> Bool {
        let name = conflictPrompt?.name ?? prompt.name
        guard AiboLibraryNaming.normalizedDisplayName(name) != nil else { return false }
        return AiboLibraryNaming.collidingRecord(
            slug: nil,
            displayName: name,
            in: AiboLibraryStore.shared.records,
            excludingID: prompt.id
        ) == nil
    }

    private func applyRename(id: String, name: String) {
        switch onRename(id, name) {
        case .renamed, .unchanged:
            renamePrompt = nil
            conflictPrompt = nil
        case .nameTaken(let existing, let suggested):
            renamePrompt = nil
            // Present after the rename alert finishes dismissing.
            Task { @MainActor in
                conflictPrompt = AiboNamePrompt(
                    id: id,
                    name: suggested,
                    existingDisplayName: existing
                )
            }
        }
    }
}

/// Repeating pet-name watermark. Linear `withAnimation` loop — not `TimelineView`.
private struct AiboNameMarquee: View {
    var name: String

    @State private var offset: CGFloat = 0
    @State private var lineWidth: CGFloat = 0

    private static let fontSize: CGFloat = 40
    private static let pointsPerSecond: CGFloat = 40
    private static let repeatsPerLine = 8
    private static let edgeFade: CGFloat = 0.12

    private var line: String {
        String(repeating: "\(name) ", count: Self.repeatsPerLine)
    }

    var body: some View {
        Color.clear
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    lineText
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.width
                        } action: { width in
                            guard width > 0, width != lineWidth else { return }
                            lineWidth = width
                            start()
                        }
                    lineText
                }
                .offset(x: offset)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: Self.edgeFade),
                        .init(color: .black, location: 1 - Self.edgeFade),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { start() }
    }

    private var lineText: some View {
        Text(verbatim: line)
            .font(.system(size: Self.fontSize, weight: .black).italic())
            .foregroundStyle(.quaternary)
            .textCase(.uppercase)
            .lineLimit(1)
            .fixedSize()
    }

    private func start() {
        let width = lineWidth
        guard width > 0 else { return }
        // Settings first-attach can drop a same-turn animation; wait one turn.
        Task { @MainActor in
            await Task.yield()
            guard lineWidth == width else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                offset = 0
            }
            withAnimation(
                .linear(duration: width / Self.pointsPerSecond)
                .repeatForever(autoreverses: false)
            ) {
                offset = -width
            }
        }
    }
}

private struct AiboConfigurationSection: View {
    var record: AiboLibraryRecord
    var pixelOptimizationEnabled: Binding<Bool>
    var scalePercent: Binding<Double>

    var body: some View {
        Section {
            Toggle(isOn: pixelOptimizationEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Pixel Optimization"))
                    Text(String(localized: "Note: Turn off for non-pixel-art images"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(VerticallyCenteredSwitchToggleStyle())

            AiboSizeRow(
                percent: scalePercent,
                percentRange: AppSettings.aiboScalePercentRange,
                usesPixelSteps: record.pixelOptimizationEnabled,
                record: record
            )
        }
    }
}

private struct AiboWindowBehaviorSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            Toggle(String(localized: "Restore Last Position"), isOn: $settings.restoreLastAiboPosition)

            Toggle(String(localized: "Hide When Fullscreen"), isOn: $settings.hideWhenFullscreen)
        }
    }
}

private struct AiboSizeRow: View {
    @Binding var percent: Double
    var percentRange: ClosedRange<Double>
    var usesPixelSteps: Bool
    var record: AiboLibraryRecord

    @Environment(\.displayScale) private var displayScale

    /// Tick marks only — do not use `step:` (that paints a mark at every increment).
    private static let tickPercents: [Double] = [0, 50, 100, 150, 200, 250, 300]

    private var pixelSteps: [Double] {
        AiboSpriteDisplay.pixelOptimizationPercents(for: record, backingScale: displayScale)
    }

    var body: some View {
        LabeledContent(String(localized: "Aibo Size")) {
            if usesPixelSteps {
                Picker(String(localized: "Aibo Size"), selection: pixelStepBinding) {
                    ForEach(pixelSteps, id: \.self) { step in
                        Text(verbatim: "\(Int(step))%").tag(step)
                    }
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .labelsHidden()
            } else {
                HStack(spacing: 12) {
                    Slider(value: roundedPercentBinding, in: percentRange) {
                        EmptyView()
                    } ticks: {
                        SliderTickContentForEach(Self.tickPercents, id: \.self) { value in
                            SliderTick(value)
                        }
                    }

                    HStack(spacing: 6) {
                        TextField(
                            String(localized: "Aibo Size"),
                            value: percentIntBinding,
                            format: .number.grouping(.never)
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 64)

                        Text(verbatim: "%")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var pixelStepBinding: Binding<Double> {
        Binding(
            get: { AppSettings.snapAiboScalePercentToPixelSteps(percent, steps: pixelSteps) },
            set: { percent = $0 }
        )
    }

    private var roundedPercentBinding: Binding<Double> {
        Binding(
            get: { percent },
            set: { percent = $0.rounded() }
        )
    }

    private var percentIntBinding: Binding<Int> {
        Binding(
            get: { Int(percent.rounded()) },
            set: { percent = Double($0) }
        )
    }
}

private struct NewAiboToolbarMenu: View {
    var isInstalling: Bool
    var onInstallLocal: () -> Void
    var onInstallPetdex: () -> Void

    var body: some View {
        Menu {
            Button(String(localized: "Install from Local File"), action: onInstallLocal)
            Divider()
            Button(String(localized: "Install from PetDex"), action: onInstallPetdex)
        } label: {
            Text(String(localized: "New Aibo"))
                .font(.body)
                .foregroundStyle(.white)
                .frame(height: AllPetsToolbarMetrics.controlHeight)
                .padding(.horizontal, 10)
                .opacity(isInstalling ? 0 : 1)
                .overlay {
                    if isInstalling {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                }
                .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .glassEffect(
            .regular
                .tint(Color.accentColor)
                .interactive(),
            in: .capsule
        )
        .disabled(isInstalling)
        .help(String(localized: "New Aibo"))
        .accessibilityLabel(String(localized: "New Aibo"))
    }
}

private struct VerticallyCenteredSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            Toggle(configuration)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private struct AllPetsEntryRow: View {
    var action: () -> Void

    @Bindable private var library = AiboLibraryStore.shared
    @State private var occupiedBytes: Int64 = 0

    var body: some View {
        Button(action: action) {
            HStack {
                Text(String(localized: "All Aibos"))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(occupiedBytes, format: .byteCount(style: .file)) used")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Shows all installed aibos"))
        .task(id: library.records) {
            occupiedBytes = library.occupiedDiskBytes()
        }
    }
}

private enum AllPetsSort: Hashable {
    case addedDate
    case name
    case size
}

private struct AllPetsSettingsView: View {
    var onBack: () -> Void

    @Bindable private var library = AiboLibraryStore.shared
    @State private var sort: AllPetsSort = .addedDate
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var pendingDeleteIDs: [String] = []
    @State private var isConfirmingDelete = false
    @State private var showsKeepOneAlert = false
    @State private var sizeByID: [String: Int64] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(displayedRecords) { record in
                    AllPetsRow(
                        record: record,
                        occupiedBytes: sizeByID[record.id] ?? 0,
                        isSelecting: isSelecting,
                        isSelected: selectedIDs.contains(record.id),
                        onTap: { handleTap(record) },
                        onRevealInFinder: record.revealsOnDiskFolder
                            ? { library.revealInFinder(record) }
                            : nil,
                        onDelete: record.canRemoveFromLibrary
                            ? { confirmDelete(ids: [record.id]) }
                            : nil
                    )
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(
            title: String(localized: "All Aibos"),
            canGoBack: true,
            onBack: onBack
        ) {
            ToolbarItem {
                Picker(selection: $sort) {
                    Text(String(localized: "Date Added")).tag(AllPetsSort.addedDate)
                        .padding(.horizontal, 8)
                    Text(String(localized: "Name")).tag(AllPetsSort.name)
                        .padding(.horizontal, 8)
                    Text(String(localized: "Size")).tag(AllPetsSort.size)
                        .padding(.horizontal, 8)
                } label: {
                    Text(String(localized: "Sort"))
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.body)
                .frame(height: AllPetsToolbarMetrics.controlHeight)
                .glassEffect(.regular.interactive(), in: .capsule)
                .help(String(localized: "Sort"))
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                AllPetsSelectionToolbar(
                    isSelecting: isSelecting,
                    canDelete: !selectedIDs.isEmpty,
                    onToggleSelecting: toggleSelecting,
                    onDelete: confirmDeleteSelected
                )
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive, action: performPendingDelete)
            Button(String(localized: "Cancel"), role: .cancel) {
                pendingDeleteIDs = []
            }
        } message: {
            Text(deleteDialogMessage)
        }
        .alert(
            String(localized: "Keep at Least One Aibo"),
            isPresented: $showsKeepOneAlert
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "You must keep at least one aibo."))
        }
        .task(id: library.records) {
            var sizes: [String: Int64] = [:]
            for record in library.records {
                sizes[record.id] = library.occupiedDiskBytes(for: record)
            }
            sizeByID = sizes
        }
    }

    private var deleteDialogTitle: String {
        pendingDeleteIDs.count > 1
            ? String(localized: "Delete Aibos?")
            : String(localized: "Delete Aibo?")
    }

    private var displayedRecords: [AiboLibraryRecord] {
        switch sort {
        case .addedDate:
            AiboLibraryOrdering.installedAtNewestFirst(library.records)
        case .name:
            AiboLibraryOrdering.byDisplayName(library.records)
        case .size:
            AiboLibraryOrdering.bySizeLargestFirst(library.records, bytesForID: sizeByID)
        }
    }

    private var deleteDialogMessage: String {
        if pendingDeleteIDs.count == 1,
           let name = library.records.first(where: { $0.id == pendingDeleteIDs[0] })?.displayName
        {
            return String(localized: "Are you sure you want to delete “\(name)”?")
        }
        return String(localized: "Are you sure you want to delete \(pendingDeleteIDs.count) aibos?")
    }

    private func handleTap(_ record: AiboLibraryRecord) {
        if isSelecting {
            guard record.canRemoveFromLibrary else { return }
            if selectedIDs.contains(record.id) {
                selectedIDs.remove(record.id)
            } else {
                selectedIDs.insert(record.id)
            }
        } else {
            library.select(id: record.id)
        }
    }

    private func toggleSelecting() {
        withAnimation(.smooth) {
            isSelecting.toggle()
            if !isSelecting {
                selectedIDs.removeAll()
            }
        }
    }

    private func confirmDeleteSelected() {
        let ids = displayedRecords.map(\.id).filter { selectedIDs.contains($0) }
        confirmDelete(ids: ids)
    }

    private func confirmDelete(ids: [String]) {
        guard let allowed = AiboLibraryDeletion.idsToRemove(requested: ids, from: library.records) else {
            showsKeepOneAlert = true
            return
        }
        guard !allowed.isEmpty else { return }
        pendingDeleteIDs = allowed
        isConfirmingDelete = true
    }

    private func performPendingDelete() {
        library.remove(ids: pendingDeleteIDs)
        selectedIDs.subtract(pendingDeleteIDs)
        pendingDeleteIDs = []
        if isSelecting {
            withAnimation(.smooth) {
                isSelecting = false
                selectedIDs.removeAll()
            }
        }
    }
}

private enum AllPetsToolbarMetrics {
    static let controlHeight: CGFloat = 32
}

/// Delete + select live in one `GlassEffectContainer`. Morph is automatic
/// (`glassEffect` + `glassEffectID` + `withAnimation`); do not add
/// `glassEffectTransition` or view `.transition` on top of that.
private struct AllPetsSelectionToolbar: View {
    var isSelecting: Bool
    var canDelete: Bool
    var onToggleSelecting: () -> Void
    var onDelete: () -> Void

    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if isSelecting {
                    Button(role: .destructive, action: onDelete) {
                        Text(String(localized: "Delete"))
                            .font(.body)
                            .frame(height: AllPetsToolbarMetrics.controlHeight)
                            .padding(.horizontal, 10)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        .regular
                            .tint(canDelete ? Color.red : nil)
                            .interactive(),
                        in: .capsule
                    )
                    .disabled(!canDelete)
                    .glassEffectID("delete", in: glassNamespace)
                }

                Button(action: onToggleSelecting) {
                    Image(systemName: isSelecting ? "checkmark" : "checklist")
                        .font(.body)
                        .frame(
                            width: AllPetsToolbarMetrics.controlHeight,
                            height: AllPetsToolbarMetrics.controlHeight
                        )
                        .contentShape(Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("select", in: glassNamespace)
                .help(isSelecting ? String(localized: "Done") : String(localized: "Select Aibos"))
                .accessibilityLabel(isSelecting ? String(localized: "Done") : String(localized: "Select Aibos"))
            }
        }
    }
}

private struct AllPetsRow: View {
    var record: AiboLibraryRecord
    var occupiedBytes: Int64
    var isSelecting: Bool
    var isSelected: Bool
    var onTap: () -> Void
    var onRevealInFinder: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onTap) {
                HStack(alignment: .center, spacing: 12) {
                    if isSelecting {
                        if record.canRemoveFromLibrary {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                .imageScale(.medium)
                        } else {
                            Image(systemName: "circle")
                                .imageScale(.medium)
                                .hidden()
                        }
                    }

                    AiboSpriteView(
                        record: record,
                        activity: .idle,
                        spriteState: .idle,
                        size: 48
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.displayName)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        AllPetsSubtitle(record: record, occupiedBytes: occupiedBytes)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isSelecting, onRevealInFinder != nil || onDelete != nil {
                HStack(spacing: 24) {
                    if let onRevealInFinder {
                        Button(action: onRevealInFinder) {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(String(localized: "Show in Finder"))
                        .accessibilityLabel(String(localized: "Show \(record.displayName) in Finder"))
                    }

                    if let onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(String(localized: "Delete"))
                        .accessibilityLabel(String(localized: "Delete \(record.displayName)"))
                    }
                }
            }
        }
    }
}

private struct AllPetsSubtitle: View {
    var record: AiboLibraryRecord
    var occupiedBytes: Int64

    var body: some View {
        Group {
            if record.kind == .builtInDefault {
                Text(String(localized: "Built-in"))
            } else {
                HStack(spacing: 4) {
                    sizeText
                        .fixedSize(horizontal: true, vertical: false)
                    Text(verbatim: "·")
                        .fixedSize()
                    dateText
                        .fixedSize(horizontal: true, vertical: false)
                    Text(verbatim: "·")
                        .fixedSize()
                    Text(installSourceText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var sizeText: some View {
        Text(occupiedBytes, format: .byteCount(style: .file))
    }

    @ViewBuilder
    private var dateText: some View {
        if let installedAt = record.installedAt {
            Text(
                installedAt,
                format: .relative(presentation: .numeric, unitsStyle: .abbreviated)
            )
        } else {
            Text(verbatim: "—")
        }
    }

    private var installSourceText: String {
        if let source = record.installSource?.trimmingCharacters(in: .whitespacesAndNewlines),
           !source.isEmpty
        {
            return source
        }
        switch record.kind {
        case .builtInDefault:
            return String(localized: "Built-in")
        case .staticImage:
            return String(localized: "Local")
        case .petdex:
            if let slug = record.slug {
                return PetdexInstallAPI.petPageURL(slug: slug).absoluteString
            }
            return String(localized: "PetDex")
        }
    }
}
