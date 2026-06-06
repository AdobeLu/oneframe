//
//  MediaStorageManager.swift
//  OneFrame
//
//  媒体文件沙盒存储管理
//

import UIKit

enum MediaType: String, Codable {
    case photo
    case video
}

struct MediaEntry: Codable {
    let id: String
    let type: MediaType
    let fileName: String
    let thumbFileName: String
    let createdAt: Date
    var fileSize: Int64 = 0
}

final class MediaStorageManager {

    static let shared = MediaStorageManager()

    // MARK: - Directories

    private var baseDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("OneFrame")
    }

    var photosDirectory: URL {
        let dir = baseDirectory.appendingPathComponent("Photos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var videosDirectory: URL {
        let dir = baseDirectory.appendingPathComponent("Videos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var metadataURL: URL {
        baseDirectory.appendingPathComponent("metadata.json")
    }

    // MARK: - Entries

    private(set) var entries: [MediaEntry] = []

    private init() {
        createDirectories()
        loadMetadata()
    }

    // MARK: - Public

    func addMediaEntry(type: MediaType, originalURL: URL, thumbnailURL: URL) {
        let entry = MediaEntry(
            id: UUID().uuidString,
            type: type,
            fileName: originalURL.lastPathComponent,
            thumbFileName: thumbnailURL.lastPathComponent,
            createdAt: Date(),
            fileSize: fileSize(at: originalURL)
        )
        entries.insert(entry, at: 0)
        saveMetadata()
    }

    func deleteMedia(_ entry: MediaEntry) {
        let directory = entry.type == .photo ? photosDirectory : videosDirectory
        let originalURL = directory.appendingPathComponent(entry.fileName)
        let thumbURL = directory.appendingPathComponent(entry.thumbFileName)

        try? FileManager.default.removeItem(at: originalURL)
        try? FileManager.default.removeItem(at: thumbURL)

        entries.removeAll { $0.id == entry.id }
        saveMetadata()
    }

    func originalURL(for entry: MediaEntry) -> URL {
        let directory = entry.type == .photo ? photosDirectory : videosDirectory
        return directory.appendingPathComponent(entry.fileName)
    }

    func thumbnailURL(for entry: MediaEntry) -> URL {
        let directory = entry.type == .photo ? photosDirectory : videosDirectory
        return directory.appendingPathComponent(entry.thumbFileName)
    }

    /// 按类型筛选媒体
    func entries(ofType type: MediaType) -> [MediaEntry] {
        entries.filter { $0.type == type }
    }

    /// 总存储大小 (bytes)
    var totalStorageSize: Int64 {
        entries.reduce(0) { $0 + $1.fileSize }
    }

    // MARK: - Private

    private func createDirectories() {
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL) else { return }
        entries = (try? JSONDecoder().decode([MediaEntry].self, from: data)) ?? []
    }

    private func saveMetadata() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: metadataURL)
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return 0
        }
        return attrs[.size] as? Int64 ?? 0
    }
}
