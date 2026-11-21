import Foundation
import Observation

/// Native offline audio download manager. Saves MP3 audio files to local storage for airplane mode and offline playback.
@Observable
public final class DownloadManager: NSObject {
    public static let shared = DownloadManager()

    public enum DownloadState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded(fileURL: URL)
    }

    public var downloadStates: [String: DownloadState] = [:]

    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var taskToGuid: [Int: String] = [:]
    private var session: URLSession!

    private let fileManager = FileManager.default

    private var downloadsFolder: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent("PolarrDownloads", isDirectory: true)
        if !fileManager.fileExists(atPath: folder.path) {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        scanExistingDownloads()
    }

    public func scanExistingDownloads() {
        guard let files = try? fileManager.contentsOfDirectory(at: downloadsFolder, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension.lowercased() == "mp3" {
            let guidName = file.deletingPathExtension().lastPathComponent
            downloadStates[guidName] = .downloaded(fileURL: file)
        }
    }

    public func safeFileName(for guid: String) -> String {
        let clean = guid.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        return clean.isEmpty ? "\(guid.hashValue)" : (clean.count > 48 ? String(clean.prefix(48)) : clean)
    }

    public func localFileURL(for guid: String) -> URL? {
        let name = safeFileName(for: guid) + ".mp3"
        let target = downloadsFolder.appendingPathComponent(name)
        if fileManager.fileExists(atPath: target.path) {
            return target
        }
        return nil
    }

    public func isDownloaded(guid: String) -> Bool {
        return localFileURL(for: guid) != nil
    }

    public func startDownload(guid: String, urlString: String) {
        guard let url = URL(string: urlString) else { return }
        if isDownloaded(guid: guid) { return }

        downloadStates[guid] = .downloading(progress: 0.0)
        let task = session.downloadTask(with: url)
        activeTasks[guid] = task
        taskToGuid[task.taskIdentifier] = guid
        task.resume()
    }

    public func deleteDownload(guid: String) {
        if let localURL = localFileURL(for: guid) {
            try? fileManager.removeItem(at: localURL)
        }
        downloadStates[guid] = .notDownloaded
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let guid = taskToGuid[downloadTask.taskIdentifier] else { return }
        if totalBytesExpectedToWrite > 0 {
            let pct = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            downloadStates[guid] = .downloading(progress: pct)
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let guid = taskToGuid[downloadTask.taskIdentifier] else { return }
        let targetURL = downloadsFolder.appendingPathComponent(safeFileName(for: guid) + ".mp3")
        try? fileManager.removeItem(at: targetURL)
        do {
            try fileManager.moveItem(at: location, to: targetURL)
            downloadStates[guid] = .downloaded(fileURL: targetURL)
        } catch {
            print("Failed to save download: \(error)")
            downloadStates[guid] = .notDownloaded
        }
        activeTasks.removeValue(forKey: guid)
        taskToGuid.removeValue(forKey: downloadTask.taskIdentifier)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, let guid = taskToGuid[task.taskIdentifier] {
            print("Download failed: \(error)")
            downloadStates[guid] = .notDownloaded
            activeTasks.removeValue(forKey: guid)
            taskToGuid.removeValue(forKey: task.taskIdentifier)
        }
    }
}
