import Foundation
import SwiftUI

struct DesignedWatchFace: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var clockMode: ClockMode
    var invertDisplay: Bool
    var showDate: Bool
    var showWeather: Bool
    var createdAt: Date
}

final class WatchFaceDesignerManager: ObservableObject {
    @Published var drafts: [DesignedWatchFace] = []
    @Published var selectedDraftID: UUID?

    private let key = "luna.watchface.designer.drafts.v1"

    init() {
        load()
    }

    func createDraft(name: String) {
        let draft = DesignedWatchFace(
            id: UUID(),
            name: name,
            clockMode: .digital,
            invertDisplay: false,
            showDate: true,
            showWeather: true,
            createdAt: Date()
        )
        drafts.insert(draft, at: 0)
        selectedDraftID = draft.id
        save()
    }

    func update(_ draft: DesignedWatchFace) {
        guard let i = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
        drafts[i] = draft
        save()
    }

    func remove(at offsets: IndexSet) {
        drafts.remove(atOffsets: offsets)
        if let id = selectedDraftID, !drafts.contains(where: { $0.id == id }) {
            selectedDraftID = drafts.first?.id
        }
        save()
    }

    func applyToCurrentWatchFace(_ draft: DesignedWatchFace, faceManager: WatchFaceManager) {
        faceManager.settings.clockMode = draft.clockMode
        faceManager.settings.invertDisplay = draft.invertDisplay
        faceManager.settings.showDate = draft.showDate
        faceManager.settings.showWeather = draft.showWeather
    }

    private func save() {
        if let data = try? JSONEncoder().encode(drafts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DesignedWatchFace].self, from: data) else {
            drafts = []
            return
        }
        drafts = decoded
        selectedDraftID = drafts.first?.id
    }
}
