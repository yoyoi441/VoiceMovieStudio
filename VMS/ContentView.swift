import SwiftUI
import VMSCore

struct ContentView: View {
    @Environment(ProjectStore.self) private var store
    @State private var playbackController = PlaybackController()
    @AppStorage("tutorial.hasCompleted.v1") private var hasCompletedTutorial = false
    @AppStorage("editor.mode") private var editorMode = "timeline"
    @State private var isShowingVersionManagement = false

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            SceneTabBar()
            Picker("編集モード", selection: $editorMode) {
                Text("タイムライン").tag("timeline")
                Text("絵コンテ").tag("storyboard")
            }.pickerStyle(.segmented).padding(.horizontal, 12).padding(.vertical, 6)
            if editorMode == "storyboard" {
                StoryboardEditorView()
                playbackControls.padding(12)
            } else {
            TimelineToolbar()

            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 8) {
                    PreviewCanvasView()
                        .padding()
                        .overlay(alignment: .topTrailing) {
                            if let message = store.materialImportMessage {
                                Text(message)
                                    .font(.caption)
                                    .padding(8)
                                    .background(.regularMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .padding()
                            }
                        }
                    playbackControls
                        .padding(.bottom, 8)
                }
                InspectorView()
            }

            VoicePanelView()

            Divider()

            TimelineView()
                .frame(minHeight: 220)
            }
        }
        .sheet(isPresented: $store.isShowingCharacterManager) {
            CharacterManagerView()
        }
        .sheet(isPresented: $store.isShowingExport) {
            ExportView()
        }
        .sheet(isPresented: $store.isShowingProjectSettings) {
            ProjectSettingsView()
        }
        .sheet(isPresented: $store.isShowingCredits) {
            CreditDescriptionView()
        }
        .sheet(isPresented: $store.isShowingHelp) {
            HelpCenterView()
        }
        .sheet(isPresented: $store.isShowingTutorial) {
            TutorialView(hasCompleted: $hasCompletedTutorial)
        }
        .sheet(isPresented: $store.isShowingRemoteAI) {
            RemoteAIView()
        }
        .sheet(isPresented: $store.isShowingBulkEdit) {
            BulkEditView()
        }
        .sheet(isPresented: $isShowingVersionManagement) {
            VersionManagementView()
        }
        .alert("エラー", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onChange(of: store.isPlaying) { _, isPlaying in
            if isPlaying {
                let timeline = store.currentTimeline
                let assetsDirectory = store.assetsDirectory
                let startTime = store.playhead
                Task {
                    await playbackController.play(
                        timeline: timeline,
                        assetsDirectory: assetsDirectory,
                        startTime: startTime,
                        frameRate: store.project.frameRate,
                        onTick: { time in store.playhead = time },
                        onFinished: {
                            store.playhead = 0
                            store.isPlaying = false
                        }
                    )
                }
            } else {
                playbackController.pause()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await DroppedMaterialImporter.importURLs(urls, into: store) }
            return true
        } isTargeted: { targeted in
            if targeted { store.materialImportMessage = "素材を判定しています…" }
        }
        .onAppear {
            if !hasCompletedTutorial { store.isShowingTutorial = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showTutorial)) { _ in
            store.isShowingTutorial = true
        }
    }

    private var playbackControls: some View {
        HStack {
            Button {
                CommandRegistry.command(.togglePlayback).perform(EditorContext(store: store))
            } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
            }
            .help(CommandRegistry.command(.togglePlayback).tooltipWithShortcut)
            Text(String(format: "%.2fs / %.2fs", store.playhead, store.currentTimeline.duration))
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
            Spacer()
            Button("クレジット") { store.isShowingCredits = true }
            Button("AI") { store.isShowingRemoteAI = true }
            Button {
                isShowingVersionManagement = true
            } label: {
                Label("バージョンアップ", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("現在のバージョンを確認して更新します")
            Button {
                store.isShowingHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .help("ヘルプセンター")
        }
    }
}

#Preview {
    ContentView()
        .environment(ProjectStore())
        .frame(width: 1100, height: 750)
}
