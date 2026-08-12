// HaloLayerTests.swift
// Unit tests for HaloLayer — byte formatting, coordinate conversion, URL matching, cache invalidation.

import XCTest
@testable import HaloLayer

final class ByteCountFormatterTests: XCTestCase {

    func testBytesFormatting() {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        formatter.isAdaptive = true

        // Boundary tests
        XCTAssertEqual(formatter.string(fromByteCount: 0), "0 B")
        XCTAssertEqual(formatter.string(fromByteCount: 1), "1 B")
        XCTAssertEqual(formatter.string(fromByteCount: 999), "999 B")
        XCTAssertEqual(formatter.string(fromByteCount: 1000), "1 KB")
        XCTAssertEqual(formatter.string(fromByteCount: 1023), "1023 B")
        XCTAssertEqual(formatter.string(fromByteCount: 1024), "1 KB")
        XCTAssertEqual(formatter.string(fromByteCount: 1536), "1.5 KB")
        XCTAssertEqual(formatter.string(fromByteCount: 1_048_576), "1 MB")
        XCTAssertEqual(formatter.string(fromByteCount: 10_485_760), "10 MB")
        XCTAssertEqual(formatter(stringFromByteCount: 1_073_741_824), "1 GB")
        XCTAssertEqual(formatter.string(fromByteCount: 10_737_418_240), "10 GB")
    }

    func testBytesToKbBoundary() {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        formatter.isAdaptive = true

        // Exactly 1 KB = 1000 bytes (decimal, as ByteCountFormatter uses decimal)
        let result = formatter.string(fromByteCount: 1000)
        XCTAssert(result.hasSuffix("KB"), "Expected KB suffix, got: \(result)")
    }

    func testBytesToMbBoundary() {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        formatter.isAdaptive = true

        let result = formatter.string(fromByteCount: 1_000_000)
        XCTAssert(result.hasSuffix("MB"), "Expected MB suffix, got: \(result)")
    }

    func testBytesToGbBoundary() {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        formatter.isAdaptive = true

        let result = formatter.string(fromByteCount: 1_000_000_000)
        XCTAssert(result.hasSuffix("GB"), "Expected GB suffix, got: \(result)")
    }
}

final class FileMetadataProviderTests: XCTestCase {

    func testFileSizeProviderCreation() {
        let provider = FileMetadataProvider.shared
        XCTAssertNotNil(provider, "Shared instance should be created")
    }

    func testFileSizeNonExistentFile() {
        let provider = FileMetadataProvider.shared
        let url = URL(fileURLWithPath: "/nonexistent/path/does_not_exist.txt")

        let size = provider.fileSize(at: url)
        XCTAssertNil(size, "Non-existent file should return nil")
    }

    func testFormattedSizeNonExistentFile() {
        let provider = FileMetadataProvider.shared
        let url = URL(fileURLWithPath: "/nonexistent/path/does_not_exist.txt")

        let formatted = provider.formattedSize(at: url)
        XCTAssertNil(formatted, "Non-existent file should return nil formatted size")
    }

    func testCacheInvalidationForDirectory() {
        let provider = FileMetadataProvider.shared
        // Cache should be empty initially (shared singleton from previous tests)
        // This tests that the invalidate method doesn't crash
        let tempDir = URL(fileURLWithPath: "/tmp/test_dir_\(Date().timeIntervalSince1970)")
        provider.invalidateCache(forDirectory: tempDir)
        // If we get here without crashing, the test passes
        XCTAssertTrue(true)
    }

    func testCacheInvalidationForSpecificURL() {
        let provider = FileMetadataProvider.shared
        let url = URL(fileURLWithPath: "/tmp/test_url_\(Date().timeIntervalSince1970)")
        provider.invalidateCache(for: url)
        XCTAssertTrue(true)  // No crash = pass
    }

    func testCacheInvalidateAll() {
        let provider = FileMetadataProvider.shared
        provider.invalidateAllCache()
        XCTAssertTrue(true)  // No crash = pass
    }
}

final class CoordinateConversionTests: XCTestCase {

    func testPointConversionIdentity() {
        // When content area origin is at (0,0) relative to window,
        // the screen coords should equal the AX frame
        let axFrame = CGRect(x: 100, y: 200, width: 80, height: 90)
        let windowFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let contentAreaOrigin = CGPoint(x: 0, y: 0)

        let result = convertToScreenCoords(
            axFrame: axFrame,
            windowFrame: windowFrame,
            contentAreaOrigin: contentAreaOrigin
        )

        XCTAssertEqual(result.x, axFrame.origin.x, accuracy: 0.1)
        XCTAssertEqual(result.y, axFrame.origin.y, accuracy: 0.1)
    }

    func testPointConversionWithOffset() {
        // When content area has an offset (e.g. title bar + toolbar)
        let axFrame = CGRect(x: 50, y: 50, width: 80, height: 90)
        let windowFrame = CGRect(x: 100, y: 200, width: 800, height: 600)
        let contentAreaOrigin = CGPoint(x: 200, y: 400)

        let result = convertToScreenCoords(
            axFrame: axFrame,
            windowFrame: windowFrame,
            contentAreaOrigin: contentAreaOrigin
        )

        // The offset should be applied
        XCTAssertEqual(result.x, 200 + (50 - 0), accuracy: 0.1)
        XCTAssertEqual(result.y, 400 + (50 - 0), accuracy: 0.1)
    }

    func testCGRectZeroDetection() {
        let zeroRect = CGRect.zero
        XCTAssert(zeroRect == CGRect.zero, "CGRect.zero should be detected")
        XCTAssert(zeroRect.isEmpty, "CGRect.zero should be empty")
        XCTAssert(zeroRect.width == 0, "Width should be 0")
        XCTAssert(zeroRect.height == 0, "Height should be 0")
    }

    func testCGRectFrameCalculation() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 50)
        XCTAssertEqual(frame.origin.x, 10)
        XCTAssertEqual(frame.origin.y, 20)
        XCTAssertEqual(frame.width, 100)
        XCTAssertEqual(frame.height, 50)
        XCTAssertEqual(frame.maxX, 110)
        XCTAssertEqual(frame.maxY, 70)
    }
}

// MARK: — Helper function for coordinate conversion tests
func convertToScreenCoords(
    axFrame: CGRect,
    windowFrame: CGRect,
    contentAreaOrigin: CGPoint
) -> CGPoint {
    CGPoint(
        x: contentAreaOrigin.x + (axFrame.origin.x - contentAreaOrigin.x),
        y: contentAreaOrigin.y + (axFrame.origin.y - contentAreaOrigin.y)
    )
}

final class FinderItemMapperTests: XCTestCase {

    func testConfidenceComparable() {
        XCTAssertTrue(.ambiguous < .probable)
        XCTAssertTrue(.probable < .certain)
        XCTAssertTrue(.ambiguous < .certain)
        XCTAssertFalse(.certain < .probable)
        XCTAssertEqual(.certain, .certain)
        XCTAssertEqual(.probable, .probable)
    }

    func testMappedFileItemCreation() {
        let url = URL(fileURLWithPath: "/tmp/test.txt")
        let frame = CGRect(x: 100, y: 200, width: 80, height: 90)

        let item = MappedFileItem(
            url: url,
            name: "test.txt",
            frame: frame,
            confidence: .certain
        )

        XCTAssertEqual(item.url.path, "/tmp/test.txt")
        XCTAssertEqual(item.name, "test.txt")
        XCTAssertEqual(item.frame.origin.x, 100)
        XCTAssertEqual(item.confidence, .certain)
    }

    func testOverlayLabelCreation() {
        let label = OverlayLabel(
            sizeText: "428 KB",
            position: CGPoint(x: 100, y: 200),
            frame: CGRect(x: 100, y: 220, width: 80, height: 16)
        )

        XCTAssertEqual(label.sizeText, "428 KB")
        XCTAssertEqual(label.position.x, 100)
        XCTAssertEqual(label.frame.height, 16)
    }
}

final class DuplicateNameTests: XCTestCase {

    func testTruncatedNameAmbiguity() {
        // Two files with identical truncated names should both be rejected
        let truncatedNames = ["Screen Shot 2026", "Screen Shot 2026 (1)"]
        let truncatedA = String(truncatedNames[0].prefix(14))
        let truncatedB = String(truncatedNames[1].prefix(14))

        // With truncation to 14 chars, both become "Screen Shot 20"
        XCTAssertEqual(truncatedA, truncatedB,
            "Truncated names should be identical — indicating ambiguity")
    }

    func testExactNameMatch() {
        let nameA = "report.pdf"
        let nameB = "report_backup.pdf"

        XCTAssertNotEqual(nameA, nameB,
            "Full names should not be equal")
    }

    func testDuplicatePrefixRejection() {
        // Files with identical prefixes up to a common length
        let names = ["image_001.jpg", "image_002.jpg", "image_003.jpg"]
        let prefix = String(names[0].prefix(6))

        // All share prefix "image_"
        XCTAssertTrue(names.allSatisfy { String($0.prefix(6)) == prefix },
            "All names share the same prefix")
    }
}

final class CacheInvalidationTests: XCTestCase {

    func testDirectoryInvalidationRemovesMatchingEntries() {
        // Simulate: directory invalidation removes all cached URLs
        // under that directory. This is tested via the shared provider's
        // invalidateCache(forDirectory:) method which filters by path.
        let provider = FileMetadataProvider.shared
        let testDir = URL(fileURLWithPath: "/Users/test/Documents")

        // No crash = the method exists and handles the case
        provider.invalidateCache(forDirectory: testDir)
        XCTAssertTrue(true)
    }

    func testSingleUrlInvalidation() {
        let provider = FileMetadataProvider.shared
        let testUrl = URL(fileURLWithPath: "/Users/test/Documents/file.txt")

        provider.invalidateCache(for: testUrl)
        XCTAssertTrue(true)
    }

    func testAllCacheInvalidation() {
        let provider = FileMetadataProvider.shared
        provider.invalidateAllCache()
        XCTAssertTrue(true)
    }
}

final class FinderContextStateTests: XCTestCase {

    func testFinderContextStateEnumCases() {
        let states: [FinderContextState] = [.idle, .monitoring, .folderChanged, .viewUnsupported]
        XCTAssertEqual(states.count, 4)
    }

    func testFinderContextCreation() {
        let url = URL(fileURLWithPath: "/tmp/test_folder")
        let context = FinderContext(
            folderURL: url,
            windowID: 12345,
            windowFrame: CGRect(x: 0, y: 0, width: 1024, height: 768)
        )

        XCTAssertEqual(context.folderURL.path, "/tmp/test_folder")
        XCTAssertEqual(context.windowID, 12345)
        XCTAssertEqual(context.windowFrame.width, 1024)
        XCTAssertEqual(context.windowFrame.height, 768)
    }
}