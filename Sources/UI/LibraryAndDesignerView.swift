import SwiftUI
import UniformTypeIdentifiers

struct LibraryAndDesignerView: View {
    @EnvironmentObject var watchSync: WatchSyncManager
    @EnvironmentObject var catalog: LunaPackageCatalogManager
    @EnvironmentObject var designer: WatchFaceDesignerManager
    @EnvironmentObject var faceManager: WatchFaceManager
    @EnvironmentObject var weather: WeatherManager

    @State private var selectedKind: LunaCatalogKind = .roundWatchfaces
    @State private var showCatalogImporter = false
    @State private var newDraftName = "My Face"

    var body: some View {
        NavigationStack {
            List {
                Section("CATALOG") {
                    Picker("Source", selection: $selectedKind) {
                        ForEach(LunaCatalogKind.allCases, id: \.self) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    Button("Load Prebuilt Catalog") {
                        catalog.loadCatalog(kind: selectedKind)
                    }
                    Button("Import Catalog JSON…") {
                        showCatalogImporter = true
                    }

                    Text(catalog.statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let err = catalog.importError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section("PREBUILT APPS / WATCHFACES") {
                    if catalog.packages.isEmpty {
                        Text("No packages loaded.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(catalog.packages.prefix(120)) { pkg in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pkg.name).font(.headline)
                                        Text("\(pkg.appType) • id \(pkg.id)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button("Send") {
                                        watchSync.installPackage(pkg, catalog: catalog)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!(watchSync.ble?.isConnected == true))
                                }
                                Text(pkg.uuid)
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("TRANSFER STATUS") {
                    Text(watchSync.vftpStateLabel)
                        .font(.system(.subheadline, design: .monospaced))
                    Text("Queue depth: \(watchSync.vftpQueueDepth)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("WATCHFACE DESIGNER") {
                    HStack {
                        TextField("Draft name", text: $newDraftName)
                        Button("Create") {
                            let trimmed = newDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
                            designer.createDraft(name: trimmed.isEmpty ? "My Face" : trimmed)
                        }
                        .buttonStyle(.bordered)
                    }

                    if designer.drafts.isEmpty {
                        Text("Create a draft to start designing.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(designer.drafts) { draft in
                            DesignerDraftRow(draft: draft)
                        }
                        .onDelete(perform: designer.remove)
                    }
                }
            }
            .navigationTitle("Library")
            .fileImporter(
                isPresented: $showCatalogImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    catalog.importCatalogFromSecurityScopedURL(url)
                }
            }
        }
    }
}

private struct DesignerDraftRow: View {
    let draft: DesignedWatchFace
    @EnvironmentObject var designer: WatchFaceDesignerManager
    @EnvironmentObject var faceManager: WatchFaceManager
    @EnvironmentObject var watchSync: WatchSyncManager
    @EnvironmentObject var weather: WeatherManager
    @State private var editable: DesignedWatchFace

    init(draft: DesignedWatchFace) {
        self.draft = draft
        _editable = State(initialValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $editable.name)
                .onChange(of: editable.name) { _ in designer.update(editable) }

            Picker("Mode", selection: $editable.clockMode) {
                ForEach(ClockMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: editable.clockMode) { _ in designer.update(editable) }

            Toggle("Invert", isOn: $editable.invertDisplay)
                .onChange(of: editable.invertDisplay) { _ in designer.update(editable) }
            Toggle("Show Date", isOn: $editable.showDate)
                .onChange(of: editable.showDate) { _ in designer.update(editable) }
            Toggle("Show Weather", isOn: $editable.showWeather)
                .onChange(of: editable.showWeather) { _ in designer.update(editable) }

            HStack {
                Button("Preview in Watch Tab") {
                    designer.applyToCurrentWatchFace(editable, faceManager: faceManager)
                }
                .buttonStyle(.bordered)

                Button("Send Face PNG via VFTP") {
                    let imageData = faceManager.renderFaceImage(
                        weatherText: editable.showWeather ? weather.condition?.watchText : nil
                    ).pngData() ?? Data()
                    let generatedID = Int32(abs(editable.id.hashValue % 2_000_000_000))
                    watchSync.sendDesignedFaceImage(imageData, fileId: generatedID)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!(watchSync.ble?.isConnected == true))
            }
        }
        .padding(.vertical, 4)
    }
}
