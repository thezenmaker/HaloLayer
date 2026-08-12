// FileMetadataProvider.swift
// Reads file size using URLResourceValues with caching and cache invalidation.

import Foundation
import ImageIO
import AVFoundation

final class FileMetadataProvider {

    // MARK: — Singleton

    static let shared = FileMetadataProvider()

    // MARK: — Cache

    private var cache: [URL: (size: Int, timestamp: TimeInterval)] = [:]
    private var folderCache: [URL: (size: Int64?, timestamp: TimeInterval)] = [:]
    private var dimensionCache: [URL: (value: String?, timestamp: TimeInterval)] = [:]
    private var folderCalculationsInFlight: Set<URL> = []
    private let cacheDispatchQueue = DispatchQueue(label: "com.korwerks.halolayer.metadata-cache")
    private let folderSizeQueue = DispatchQueue(
        label: "com.korwerks.halolayer.folder-size",
        qos: .utility
    )
    private let cacheTTL: TimeInterval = 2 // seconds
    private let folderCacheTTL: TimeInterval = 30
    private let dimensionCacheTTL: TimeInterval = 60

    // MARK: — Public API

    /// Get the logical file size for a URL. Returns nil if the file doesn't exist or can't be read.
    func fileSize(at url: URL) -> Int64? {
        // Check cache first
        var cachedSize: Int64?
        cacheDispatchQueue.sync {
            if let entry = cache[url],
               entry.timestamp + cacheTTL > Date().timeIntervalSinceReferenceDate {
                cachedSize = Int64(entry.size)
            }
        }
        if let cachedSize = cachedSize {
            return cachedSize
        }

        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            let size = resourceValues.fileSize ?? 0
            cacheDispatchQueue.sync {
                cache[url] = (size: size, timestamp: Date().timeIntervalSinceReferenceDate)
            }
            return Int64(size)
        } catch {
            return nil
        }
    }

    /// Get a human-readable size string using ByteCountFormatter.
    func formattedSize(at url: URL) -> String? {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return formattedFolderSize(at: url)
        }
        guard let size = fileSize(at: url) else { return nil }
        return formatByteCount(size)
    }

    /// Folder totals are recursive and may be expensive. Return a cached value
    /// immediately, or `nil` (displayed as “—”) while work happens off-main.
    private func formattedFolderSize(at url: URL) -> String? {
        let standardizedURL = url.standardizedFileURL
        let now = Date().timeIntervalSinceReferenceDate
        var cachedResult: Int64??
        var shouldCalculate = false

        cacheDispatchQueue.sync {
            if let entry = folderCache[standardizedURL],
               entry.timestamp + folderCacheTTL > now {
                cachedResult = .some(entry.size)
            } else if !folderCalculationsInFlight.contains(standardizedURL) {
                folderCalculationsInFlight.insert(standardizedURL)
                shouldCalculate = true
            }
        }

        if shouldCalculate {
            calculateFolderSize(at: standardizedURL)
        }
        guard let result = cachedResult, let size = result else { return nil }
        return formatByteCount(size)
    }

    private func calculateFolderSize(at folderURL: URL) {
        folderSizeQueue.async { [weak self] in
            guard let self else { return }
            let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
            var encounteredReadError = false
            guard let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: keys,
                options: [],
                errorHandler: { _, _ in
                    encounteredReadError = true
                    return true
                }
            ) else {
                self.storeFolderSize(nil, for: folderURL)
                return
            }

            var total: Int64 = 0
            for case let childURL as URL in enumerator {
                guard let values = try? childURL.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else { continue }
                total += Int64(values.fileSize ?? 0)
            }
            self.storeFolderSize(
                encounteredReadError ? nil : total,
                for: folderURL
            )
        }
    }

    private func storeFolderSize(_ size: Int64?, for url: URL) {
        cacheDispatchQueue.sync {
            folderCache[url] = (
                size: size,
                timestamp: Date().timeIntervalSinceReferenceDate
            )
            folderCalculationsInFlight.remove(url)
        }
    }

    private func formatByteCount(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: size)
    }

    /// Read image pixel dimensions without decoding the full image bitmap.
    func formattedPixelDimensions(at url: URL) -> String? {
        let standardizedURL = url.standardizedFileURL
        let now = Date().timeIntervalSinceReferenceDate
        var cachedValue: String??
        cacheDispatchQueue.sync {
            if let entry = dimensionCache[standardizedURL],
               entry.timestamp + dimensionCacheTTL > now {
                cachedValue = .some(entry.value)
            }
        }
        if let cachedValue { return cachedValue }

        let result: String?
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber {
            result = formattedDimensions(width: width, height: height)
        } else {
            let asset = AVURLAsset(url: url)
            if let track = asset.tracks(withMediaType: .video).first {
                let transformedSize = track.naturalSize.applying(track.preferredTransform)
                let width = NSNumber(value: Double(abs(transformedSize.width)))
                let height = NSNumber(value: Double(abs(transformedSize.height)))
                result = width.doubleValue > 0 && height.doubleValue > 0
                    ? formattedDimensions(width: width, height: height)
                    : nil
            } else {
                result = nil
            }
        }
        cacheDispatchQueue.sync {
            dimensionCache[standardizedURL] = (result, now)
        }
        return result
    }

    private func formattedDimensions(width: NSNumber, height: NSNumber) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        guard let widthText = formatter.string(from: width),
              let heightText = formatter.string(from: height) else {
            return nil
        }
        return "\(widthText) × \(heightText)"
    }

    /// Invalidate the cache for a specific URL.
    func invalidateCache(for url: URL) {
        cacheDispatchQueue.sync {
            cache[url] = nil
            folderCache[url.standardizedFileURL] = nil
            dimensionCache[url.standardizedFileURL] = nil
            folderCalculationsInFlight.remove(url.standardizedFileURL)
        }
    }

    /// Invalidate the entire cache.
    func invalidateAllCache() {
        cacheDispatchQueue.sync {
            cache.removeAll()
            folderCache.removeAll()
            dimensionCache.removeAll()
            folderCalculationsInFlight.removeAll()
        }
    }

    /// Invalidate cache for all URLs that share a common parent directory.
    func invalidateCache(forDirectory directoryURL: URL) {
        cacheDispatchQueue.sync {
            cache = cache.filter { !($0.key.deletingLastPathComponent().path == directoryURL.path) }
            folderCache = folderCache.filter {
                $0.key.deletingLastPathComponent().path != directoryURL.path &&
                $0.key.path != directoryURL.path
            }
            dimensionCache = dimensionCache.filter {
                $0.key.deletingLastPathComponent().path != directoryURL.path
            }
        }
    }
}
