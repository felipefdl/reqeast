//
//  ProtoZipArchive.swift
//  Reqeast
//

import Compression
import Foundation

/// Store-only ZIP pack/unpack for proto bundle CKAsset upload. No external zip dependency.
enum ProtoZipArchive {
    private static let localHeaderSignature: UInt32 = 0x0403_4b50
    private static let centralHeaderSignature: UInt32 = 0x0201_4b50
    private static let endSignature: UInt32 = 0x0605_4b50

    static func packDirectory(
        _ sourceDirectory: URL,
        to destinationZip: URL,
        excluding: Set<String> = []
    ) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ProtoBundleError.zipFailed("Could not enumerate bundle directory.")
        }

        var entries: [(relativePath: String, data: Data)] = []
        let prefix = sourceDirectory.path.hasSuffix("/") ? sourceDirectory.path : sourceDirectory.path + "/"

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            let relativePath = String(fileURL.path.dropFirst(prefix.count))
            if excluding.contains(relativePath) || excluding.contains(fileURL.lastPathComponent) {
                continue
            }

            let data = try Data(contentsOf: fileURL)
            entries.append((relativePath, data))
        }

        entries.sort { $0.relativePath < $1.relativePath }

        if fileManager.fileExists(atPath: destinationZip.path) {
            try fileManager.removeItem(at: destinationZip)
        }

        var archive = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.relativePath.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)

            var local = Data()
            local.appendUInt32(localHeaderSignature)
            local.appendUInt16(20) // version needed
            local.appendUInt16(0) // flags
            local.appendUInt16(0) // store
            local.appendUInt16(0) // mod time
            local.appendUInt16(0) // mod date
            local.appendUInt32(crc)
            local.appendUInt32(size)
            local.appendUInt32(size)
            local.appendUInt16(UInt16(nameData.count))
            local.appendUInt16(0) // extra length
            local.append(nameData)
            local.append(entry.data)

            archive.append(local)

            var central = Data()
            central.appendUInt32(centralHeaderSignature)
            central.appendUInt16(20) // version made by
            central.appendUInt16(20) // version needed
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(crc)
            central.appendUInt32(size)
            central.appendUInt32(size)
            central.appendUInt16(UInt16(nameData.count))
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(0)
            central.appendUInt32(offset)
            central.append(nameData)
            centralDirectory.append(central)

            offset += UInt32(local.count)
        }

        archive.append(centralDirectory)

        var end = Data()
        end.appendUInt32(endSignature)
        end.appendUInt16(0) // disk number
        end.appendUInt16(0) // central disk
        end.appendUInt16(UInt16(entries.count))
        end.appendUInt16(UInt16(entries.count))
        end.appendUInt32(UInt32(centralDirectory.count))
        end.appendUInt32(offset)
        end.appendUInt16(0) // comment length
        archive.append(end)

        try archive.write(to: destinationZip, options: .atomic)
    }

    static func extract(zipURL: URL, to destinationDirectory: URL) throws {
        let fileManager = FileManager.default
        let zipData = try Data(contentsOf: zipURL)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        var offset = 0
        while offset + 30 <= zipData.count {
            let signature = zipData.readUInt32(at: offset)
            if signature == endSignature || signature == centralHeaderSignature {
                break
            }
            guard signature == localHeaderSignature else {
                throw ProtoBundleError.zipFailed("Invalid ZIP local header.")
            }

            let compression = zipData.readUInt16(at: offset + 8)
            let crc = zipData.readUInt32(at: offset + 14)
            let compressedSize = Int(zipData.readUInt32(at: offset + 18))
            let uncompressedSize = Int(zipData.readUInt32(at: offset + 22))
            let nameLength = Int(zipData.readUInt16(at: offset + 26))
            let extraLength = Int(zipData.readUInt16(at: offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + nameLength
            guard nameEnd <= zipData.count else {
                throw ProtoBundleError.zipFailed("Truncated ZIP filename.")
            }
            let relativePath = String(data: zipData[nameStart..<nameEnd], encoding: .utf8)
                ?? String(decoding: zipData[nameStart..<nameEnd], as: UTF8.self)

            let dataStart = nameEnd + extraLength
            let dataEnd = dataStart + compressedSize
            guard dataEnd <= zipData.count else {
                throw ProtoBundleError.zipFailed("Truncated ZIP file data.")
            }

            let compressed = zipData[dataStart..<dataEnd]
            let uncompressed: Data
            switch compression {
            case 0:
                uncompressed = Data(compressed)
            case 8:
                uncompressed = try inflateDeflate(Data(compressed), expectedSize: uncompressedSize)
            default:
                throw ProtoBundleError.zipFailed("Unsupported ZIP compression method \(compression).")
            }

            guard uncompressed.count == uncompressedSize, crc32(uncompressed) == crc else {
                throw ProtoBundleError.zipFailed("ZIP checksum mismatch for \(relativePath).")
            }

            let destination = destinationDirectory.appendingPathComponent(relativePath)
            let parent = destination.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parent.path) {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            try uncompressed.write(to: destination, options: .atomic)

            offset = dataEnd
        }
    }

    private static func inflateDeflate(_ data: Data, expectedSize: Int) throws -> Data {
        var output = Data(count: max(expectedSize, 64))
        var produced = 0
        let result = data.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                compression_decode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    outputBuffer.count,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    inputBuffer.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard result > 0 else {
            throw ProtoBundleError.zipFailed("Failed to decompress ZIP entry.")
        }
        produced = result
        output.count = produced
        if expectedSize > 0, produced != expectedSize {
            throw ProtoBundleError.zipFailed("Decompressed size mismatch.")
        }
        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ crcTable[index]
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                if value & 1 == 1 {
                    value = 0xEDB8_8320 ^ (value >> 1)
                } else {
                    value >>= 1
                }
            }
            return value
        }
    }()
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func readUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func readUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}