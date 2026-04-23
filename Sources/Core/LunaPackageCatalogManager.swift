import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct LunaPackageResource: Codable, Hashable {
    let id: Int32
    let base64: String
    let compressed: Bool
    let realSize: UInt16?
}

struct LunaPackageDescriptor: Identifiable, Codable, Hashable {
    let id: Int32
    let uuid: String
    let name: String
    let appType: String
    let appFileBase64: String?
    let appFileCompressed: Bool
    let appFileRealSize: UInt16?
    let resources: [LunaPackageResource]
}

enum LunaCatalogKind: String, CaseIterable {
    case roundWatchfaces
    case squareWatchfaces
    case roundApps
    case squareApps
}

final class LunaPackageCatalogManager: ObservableObject {
    @Published private(set) var packages: [LunaPackageDescriptor] = []
    @Published var selectedPackage: LunaPackageDescriptor?
    @Published var importError: String?
    @Published var statusText: String = "No catalog loaded"

    private let decoder = JSONDecoder()
    private let fm = FileManager.default

    private struct RawCatalogItem: Decodable {
        struct RawContent: Decodable {
            struct RawAppFile: Decodable {
                let data: String?
                let compressed: Bool?
                let realSize: UInt16?
            }
            struct RawResource: Decodable {
                let id: Int32?
                let content: String?
                let compressed: Bool?
                let decompressedSize: UInt16?
            }
            let appFile: RawAppFile?
            let localResources: [RawResource]?
        }

        let id: Int32?
        let uuid: String?
        let name: String?
        let appType: String?
        let content: RawContent?
    }

    func loadCatalog(kind: LunaCatalogKind) {
        importError = nil
        let defaultPaths: [LunaCatalogKind: String] = [
            .roundWatchfaces: "/Users/arakirley/Vibes/Vector_resurrection/output/resources/assets/offline/OfflineRoundWatchfaces.json",
            .squareWatchfaces: "/Users/arakirley/Vibes/Vector_resurrection/output/resources/assets/offline/OfflineSquareWatchfaces.json",
            .roundApps: "/Users/arakirley/Vibes/Vector_resurrection/output/resources/assets/offline/OfflineRoundApps.json",
            .squareApps: "/Users/arakirley/Vibes/Vector_resurrection/output/resources/assets/offline/OfflineSquareApps.json",
        ]
        guard let path = defaultPaths[kind] else { return }
        let url = URL(fileURLWithPath: path)
        loadCatalog(from: url, label: kind.rawValue)
    }

    func loadCatalog(from url: URL, label: String? = nil) {
        importError = nil
        do {
            let data = try Data(contentsOf: url)
            let raw = try decoder.decode([RawCatalogItem].self, from: data)
            let parsed = raw.compactMap(parse)
            packages = parsed
            selectedPackage = parsed.first
            let source = label ?? url.lastPathComponent
            statusText = "Loaded \(parsed.count) packages from \(source)"
        } catch {
            importError = "Failed to import catalog: \(error.localizedDescription)"
            statusText = "Import failed"
        }
    }

    func importCatalogFromSecurityScopedURL(_ url: URL) {
        let allowed = url.startAccessingSecurityScopedResource()
        defer { if allowed { url.stopAccessingSecurityScopedResource() } }

        do {
            let docs = try documentsDirectory()
            let target = docs.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: url, to: target)
            loadCatalog(from: target, label: target.lastPathComponent)
        } catch {
            importError = "Copy/import failed: \(error.localizedDescription)"
        }
    }

    func buildTransferPayloads(for pkg: LunaPackageDescriptor) -> [LunaVFTPFilePayload] {
        var files: [LunaVFTPFilePayload] = []

        if let appBase64 = pkg.appFileBase64,
           let appData = Data(base64Encoded: appBase64) {
            files.append(LunaVFTPFilePayload(
                fileId: pkg.id,
                fileType: .application,
                data: appData,
                uncompressedSize: pkg.appFileRealSize ?? UInt16(appData.count),
                compressed: pkg.appFileCompressed,
                force: true
            ))
        }

        for r in pkg.resources {
            guard let data = Data(base64Encoded: r.base64) else { continue }
            files.append(LunaVFTPFilePayload(
                fileId: r.id,
                fileType: .resource,
                data: data,
                uncompressedSize: r.realSize ?? UInt16(data.count),
                compressed: r.compressed,
                force: true
            ))
        }
        return files
    }

    func importSinglePackageJSON(_ url: URL) {
        let allowed = url.startAccessingSecurityScopedResource()
        defer { if allowed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let pkg = try decoder.decode(LunaPackageDescriptor.self, from: data)
            packages.insert(pkg, at: 0)
            selectedPackage = pkg
            statusText = "Imported package \(pkg.name)"
        } catch {
            importError = "Invalid package JSON: \(error.localizedDescription)"
        }
    }

    private func parse(_ raw: RawCatalogItem) -> LunaPackageDescriptor? {
        guard let id = raw.id,
              let uuid = raw.uuid,
              let name = raw.name else { return nil }

        let appType = raw.appType ?? "APP"
        let appFileBase64 = raw.content?.appFile?.data
        let appCompressed = raw.content?.appFile?.compressed ?? false
        let appRealSize = raw.content?.appFile?.realSize

        let resources: [LunaPackageResource] = (raw.content?.localResources ?? []).compactMap { r in
            guard let rid = r.id, let content = r.content else { return nil }
            return LunaPackageResource(
                id: rid,
                base64: content,
                compressed: r.compressed ?? false,
                realSize: r.decompressedSize
            )
        }

        return LunaPackageDescriptor(
            id: id,
            uuid: uuid,
            name: name,
            appType: appType,
            appFileBase64: appFileBase64,
            appFileCompressed: appCompressed,
            appFileRealSize: appRealSize,
            resources: resources
        )
    }

    private func documentsDirectory() throws -> URL {
        guard let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "LunaCatalog", code: 1, userInfo: [NSLocalizedDescriptionKey: "No documents dir"])
        }
        return dir
    }
}

extension UTType {
    static let lunaPackageJSON = UTType(exportedAs: "com.lunawatch.package-json")
}
