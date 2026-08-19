import AiboCore
import SwiftUI

struct GeneralSettingsPane: View {
    @Bindable private var settings = AppSettings.shared
    @Bindable private var library = AiboLibraryStore.shared

    var body: some View {
        Form {
            GeneralPreviewSection(
                themeMode: settings.themeMode,
                placement: library.selectedRecord.bubblePlacement,
                bubbleDistance: library.selectedRecord.bubbleDistance,
                record: library.selectedRecord
            )

            GeneralThemeSection(themeMode: $settings.themeMode)

            GeneralMusicSection(settings: settings)

            GeneralBubbleSection(
                placement: Binding(
                    get: { library.selectedRecord.bubblePlacement },
                    set: { library.setBubblePlacement($0) }
                ),
                distance: Binding(
                    get: { library.selectedRecord.bubbleDistance },
                    set: { library.setBubbleDistance($0) }
                )
            )

            GeneralActionSection()
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(title: String(localized: "General"))
    }
}

private struct GeneralPreviewSection: View {
    var themeMode: AppThemeMode
    var placement: BubblePlacement
    var bubbleDistance: Double
    var record: AiboLibraryRecord

    var body: some View {
        Section {
            GeneralPreview(
                themeMode: themeMode,
                placement: placement,
                bubbleDistance: bubbleDistance,
                record: record
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }
}

private struct GeneralPreview: View {
    var themeMode: AppThemeMode
    var placement: BubblePlacement
    var bubbleDistance: Double
    var record: AiboLibraryRecord

    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.displayScale) private var displayScale
    @Bindable private var settings = AppSettings.shared
    @State private var floatingNotes: [FloatingMusicNote] = []
    @State private var burstTask: Task<Void, Never>?
    @State private var colorBurstTask: Task<Void, Never>?

    /// Preview slot; desktop is `basePointSize` × Aibo Size. Distance is scaled to this ratio.
    private let aiboNominalSize: CGFloat = 80

    private var previewAiboLayoutSize: CGSize {
        AiboSpriteDisplay.desktopSize(
            for: record,
            nominal: aiboNominalSize,
            backingScale: displayScale
        )
    }

    private var desktopAiboLayoutSize: CGSize {
        AiboSpriteDisplay.desktopSize(
            for: record,
            nominal: AiboSpriteDisplay.basePointSize
                * CGFloat(record.scalePercent / 100),
            backingScale: displayScale
        )
    }

    /// Same point distance would over-eat a smaller preview sprite (transparent padding scales with size).
    private var spacing: CGFloat {
        let previewSpan: CGFloat
        let desktopSpan: CGFloat
        switch placement {
        case .top, .bottom:
            previewSpan = previewAiboLayoutSize.height
            desktopSpan = desktopAiboLayoutSize.height
        case .left, .right:
            previewSpan = previewAiboLayoutSize.width
            desktopSpan = desktopAiboLayoutSize.width
        }
        guard desktopSpan > 0 else { return CGFloat(bubbleDistance) }
        return CGFloat(bubbleDistance) * (previewSpan / desktopSpan)
    }

    private var aiboSize: CGFloat {
        max(previewAiboLayoutSize.width, previewAiboLayoutSize.height)
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                Image("WallpaperBg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width + 20, height: geo.size.height + 20)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .accessibilityHidden(true)
            }

            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .overlay(alignment: .topLeading) {
            Text(String(localized: "PREVIEW"))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Preview"))
        .onChange(of: settings.musicNotesEnabled) { _, _ in
            playPreviewNotes()
        }
        .onChange(of: settings.musicNotesColorMode) { _, _ in
            playPreviewNotes()
        }
        .onChange(of: settings.musicNotesCustomColor) { _, _ in
            playPreviewNotesAfterColorChange()
        }
        .onDisappear {
            burstTask?.cancel()
            colorBurstTask?.cancel()
            burstTask = nil
            colorBurstTask = nil
            floatingNotes.removeAll()
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch placement {
        case .top:
            VStack(spacing: spacing) {
                previewBubble
                previewPet
            }
        case .bottom:
            VStack(spacing: spacing) {
                previewPet
                previewBubble
            }
        case .left:
            HStack(alignment: .center, spacing: spacing) {
                previewBubble
                previewPet
            }
        case .right:
            HStack(alignment: .center, spacing: spacing) {
                previewPet
                previewBubble
            }
        }
    }

    private var previewBubble: GeneralPreviewBubble {
        GeneralPreviewBubble(
            placement: placement,
            colorScheme: themeMode.resolvedColorScheme(system: systemColorScheme)
        )
    }

    private var previewPet: some View {
        ZStack {
            AiboSpriteView(
                record: record,
                activity: .idle,
                spriteState: .idle,
                size: aiboNominalSize,
                pixelLayout: .fillWidth
            )
            ForEach(floatingNotes) { note in
                FloatingMusicNoteView(
                    note: note,
                    color: settings.resolvedMusicNotesColor(for: record),
                    aiboSize: aiboSize
                )
                .allowsHitTesting(false)
            }
        }
    }

    private func playPreviewNotes() {
        colorBurstTask?.cancel()
        burstTask?.cancel()
        burstTask = Task { @MainActor in
            await MusicNoteMotion.spawnBurst(into: $floatingNotes)
        }
    }

    /// ColorPicker emits many updates while dragging; collapse them to one burst.
    private func playPreviewNotesAfterColorChange() {
        colorBurstTask?.cancel()
        colorBurstTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            playPreviewNotes()
        }
    }
}

/// Same chrome as `StatusBubble` (padding, capsule, glass, arrow) with bones instead of copy.
private struct GeneralPreviewBubble: View {
    var placement: BubblePlacement
    var colorScheme: ColorScheme

    private let arrowHeight: CGFloat = 6
    private let arrowWidth: CGFloat = 10
    private let cornerRadius: CGFloat = 16
    private let contentPadding: CGFloat = 12
    private let headerSpacing: CGFloat = 8
    private let sectionSpacing: CGFloat = 10
    private let capsuleWidth: CGFloat = 56
    private let capsuleHeight: CGFloat = 22
    private let statusLineHeight: CGFloat = 22
    private let glassStyle = BubbleGlassStyle.regular

    var body: some View {
        let prefersLightLabel = colorScheme == .dark
        let ink = prefersLightLabel ? Color.white : Color.black
        let edge = placement.arrowEdge

        skeletonContent(ink: ink)
            .padding(contentPadding)
            .padding(Edge.Set(edge), arrowHeight)
            .background { bubbleBackground(edge: edge) }
            .environment(\.colorScheme, colorScheme)
            .environment(
                \.backgroundProminence,
                prefersLightLabel ? .increased : .standard
            )
            .fixedSize()
            .alignmentGuide(.trailing) { d in
                placement == .left ? d[.trailing] - arrowHeight : d[.trailing]
            }
            .alignmentGuide(.leading) { d in
                placement == .right ? d[.leading] + arrowHeight : d[.leading]
            }
            .accessibilityHidden(true)
    }

    private func skeletonContent(ink: Color) -> some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            HStack(spacing: headerSpacing) {
                bone(width: 56, height: 8, ink: ink)
                    .frame(height: 12)
                bone(width: 68, height: 8, ink: ink.opacity(0.6))
                    .frame(height: 12)
            }

            HStack(alignment: .center, spacing: headerSpacing) {
                capsuleBone(fill: ink)
                bone(width: 88, height: 10, ink: ink)
                    .frame(height: statusLineHeight, alignment: .center)
            }
        }
        .frame(minWidth: 200, alignment: .leading)
    }

    private func capsuleBone(fill: Color) -> some View {
        Capsule()
            .fill(fill)
            .frame(width: capsuleWidth, height: capsuleHeight)
    }

    private func bone(width: CGFloat, height: CGFloat, ink: Color) -> some View {
        Capsule()
            .fill(ink.opacity(0.22))
            .frame(width: width, height: height)
    }

    @ViewBuilder
    private func bubbleBackground(edge: Edge) -> some View {
        let shape = PopoverBubbleShape(
            arrowEdge: edge,
            cornerRadius: cornerRadius,
            arrowWidth: arrowWidth,
            arrowHeight: arrowHeight
        )
        shape
            .fill(Color.clear)
            .glassEffect(glassStyle.glass.interactive(), in: shape)
            .background {
                shape.fill(Color.white.opacity(0.2))
            }
    }
}

private struct GeneralThemeSection: View {
    @Binding var themeMode: AppThemeMode

    var body: some View {
        Section {
            Picker(String(localized: "Theme"), selection: $themeMode) {
                ForEach(AppThemeMode.settingsCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
        } header: {
            Text(String(localized: "Appearance"))
        }
    }
}

private struct GeneralMusicSection: View {
    @Bindable var settings: AppSettings
    // @Binding var customMusicNotificationNames: String

    var body: some View {
        Section {
            Toggle(isOn: $settings.musicNotesEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Music Notes"))
                    Text(String(localized: "Float notes while playing music or video"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(VerticallyCenteredSwitchToggleStyle())

            LabeledContent(String(localized: "Notes Color")) {
                HStack(spacing: 8) {
                    if settings.musicNotesColorMode == .custom {
                        ColorPicker(
                            String(localized: "Notes Color"),
                            selection: $settings.musicNotesCustomColor,
                            supportsOpacity: false
                        )
                        .labelsHidden()
                    }

                    Picker(String(localized: "Notes Color"), selection: $settings.musicNotesColorMode) {
                        ForEach(MusicNotesColorMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
            .labeledContentStyle(VerticallyCenteredLabeledContentStyle())

            // DisclosureGroup(String(localized: "Advanced")) {
            //     TextField(
            //         String(localized: "Custom notification names"),
            //         text: $customMusicNotificationNames,
            //         prompt: Text("com.example.playerInfo"),
            //         axis: .vertical
            //     )
            //     .lineLimit(3...6)
            //
            //     Text(String(localized: "Optional fallback: one distributed notification name per line. Payload should include Player State = Playing / Paused. Most Chinese clients do not post these — Now Playing covers them instead."))
            //         .font(.caption)
            //         .foregroundStyle(.secondary)
            // }
        } header: {
            Text(String(localized: "Music"))
        }
    }
}

/// Form `Toggle` aligns the switch to the title baseline, so a subtitle
/// makes the control sit high. Center against the whole label instead.
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

private struct VerticallyCenteredLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            configuration.content
        }
    }
}

private struct GeneralBubbleSection: View {
    @Binding var placement: BubblePlacement
    @Binding var distance: Double

    var body: some View {
        Section {
            Picker(String(localized: "Position"), selection: $placement) {
                ForEach(BubblePlacement.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.menu)

            BubbleDistanceRow(
                distance: $distance,
                range: AiboLibraryRecord.bubbleDistanceRange
            )
        } header: {
            Text(String(localized: "Bubble"))
        }
    }
}

private struct BubbleDistanceRow: View {
    @Binding var distance: Double
    var range: ClosedRange<Double>

    private static let tickDistances: [Double] = [-40, -20, 0, 20, 40]

    var body: some View {
        LabeledContent(String(localized: "Distance")) {
            HStack(spacing: 12) {
                Slider(value: roundedDistanceBinding, in: range) {
                    EmptyView()
                } ticks: {
                    SliderTickContentForEach(Self.tickDistances, id: \.self) { value in
                        SliderTick(value)
                    }
                }

                HStack(spacing: 6) {
                    TextField(
                        String(localized: "Distance"),
                        value: distanceIntBinding,
                        format: .number.grouping(.never)
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 64)

                    Text(verbatim: "pt")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var roundedDistanceBinding: Binding<Double> {
        Binding(
            get: { distance },
            set: { distance = $0.rounded() }
        )
    }

    private var distanceIntBinding: Binding<Int> {
        Binding(
            get: { Int(distance.rounded()) },
            set: { distance = Double($0) }
        )
    }
}

private struct GeneralActionSection: View {
    @Bindable private var settings = AppSettings.shared
    @Bindable private var actions = AiboActionSettings.shared

    var body: some View {
        Section {
            ForEach(AiboUserAction.allCases) { action in
                Picker(action.settingsTitle, selection: spriteBinding(for: action)) {
                    ForEach(PetdexSpriteState.allCases, id: \.self) { state in
                        Text(state.localizedTitle).tag(state)
                    }
                }
                .pickerStyle(.menu)
            }

            Toggle(isOn: $settings.disableMouseTracking) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Disable Mouse Tracking"))
                    Text(String(localized: "V2 assets only"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(VerticallyCenteredSwitchToggleStyle())
        } header: {
            Text(String(localized: "Extra Action"))
        }
    }

    private func spriteBinding(for action: AiboUserAction) -> Binding<PetdexSpriteState> {
        Binding(
            get: { actions.sprite(for: action) },
            set: { actions.setSprite($0, for: action) }
        )
    }
}
