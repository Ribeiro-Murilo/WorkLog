import Foundation

nonisolated struct FolderSyncFileBatch: Sendable {
    let operations: [SyncOperation]
    let unavailableFiles: Int
}

nonisolated enum FolderSyncFileError: LocalizedError {
    case unavailableFolder
    case invalidFile(String)
    case oversizedFile(String)

    var errorDescription: String? {
        switch self {
        case .unavailableFolder:
            "A pasta escolhida não está disponível. Conecte o volume ou selecione a pasta novamente."
        case .invalidFile(let name):
            "O arquivo \(name) não pôde ser lido. Seus dados locais e o histórico foram preservados."
        case .oversizedFile(let name):
            "O arquivo \(name) excede o limite de 16 MB por alteração. Seus dados locais foram preservados."
        }
    }
}

/// Access is serialized on this Mac; the journal handles concurrency between Macs.
actor FolderSyncFileStore {
    private let folder: URL
    private let fileManager = FileManager.default
    private let maximumFileSize = 16 * 1024 * 1024

    init(folder: URL) { self.folder = folder }

    private func operationsDirectory() throws -> URL {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FolderSyncFileError.unavailableFolder
        }
        let directory = folder.appendingPathComponent("WorkLog Sync/Operations", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func readOperations() throws -> FolderSyncFileBatch {
        let directory = try operationsDirectory()
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var operations: [SyncOperation] = []
        var unavailable = 0
        for url in urls {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            guard values.isRegularFile == true else { continue }
            if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus == .notDownloaded {
                try fileManager.startDownloadingUbiquitousItem(at: url)
                unavailable += 1
                continue
            }
            if (values.fileSize ?? 0) > maximumFileSize {
                throw FolderSyncFileError.oversizedFile(url.lastPathComponent)
            }
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var result: Result<SyncOperation, Error>?
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
                result = Result {
                    let data = try Data(contentsOf: coordinatedURL)
                    guard data.count <= maximumFileSize else {
                        throw FolderSyncFileError.oversizedFile(url.lastPathComponent)
                    }
                    return try JSONDecoder().decode(SyncOperation.self, from: data)
                }
            }
            if let coordinationError { throw coordinationError }
            guard let result else { throw FolderSyncFileError.invalidFile(url.lastPathComponent) }
            do { operations.append(try result.get()) }
            catch is DecodingError { throw FolderSyncFileError.invalidFile(url.lastPathComponent) }
        }
        return FolderSyncFileBatch(operations: operations, unavailableFiles: unavailable)
    }

    func publish(_ operation: SyncOperation) throws {
        let directory = try operationsDirectory()
        let url = directory.appendingPathComponent("\(operation.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(operation)
        guard data.count <= maximumFileSize else { throw FolderSyncFileError.oversizedFile(url.lastPathComponent) }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result {
                if fileManager.fileExists(atPath: coordinatedURL.path) {
                    let existing = try JSONDecoder().decode(SyncOperation.self, from: Data(contentsOf: coordinatedURL))
                    guard existing == operation else { throw SyncProtocolError.duplicateOperation(operation.id) }
                } else {
                    try data.write(to: coordinatedURL, options: .atomic)
                }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw FolderSyncFileError.invalidFile(url.lastPathComponent) }
        try result.get()
    }
}
