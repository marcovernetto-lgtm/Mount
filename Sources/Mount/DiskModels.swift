import Foundation

/// Logical category of a storage volume shown in the menu bar popover.
enum VolumeCategory: String, Sendable, CaseIterable, Comparable {
    case external
    case diskImage
    case network
    case internalDrive

    var sortOrder: Int {
        switch self {
        case .external: return 0
        case .diskImage: return 1
        case .network: return 2
        case .internalDrive: return 3
        }
    }

    static func < (lhs: VolumeCategory, rhs: VolumeCategory) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var badgeLabel: String {
        switch self {
        case .external: return "Esterno"
        case .diskImage: return "Immagine"
        case .network: return "Rete"
        case .internalDrive: return "Interno"
        }
    }

    var symbolName: String {
        switch self {
        case .external: return "externaldrive.fill"
        case .diskImage: return "opticaldiscdrive.fill"
        case .network: return "externaldrive.connected.to.line.below.fill"
        case .internalDrive: return "internaldrive.fill"
        }
    }
}

/// Snapshot representation of a mounted or offline-connected volume.
struct VolumeItem: Identifiable, Hashable, Sendable {
    let id: String
    let bsdName: String?
    let name: String
    let mountPoint: URL?
    let category: VolumeCategory
    let filesystem: String
    let totalBytes: Int64?
    let availableBytes: Int64?
    let deviceProtocol: String?
    let isInternal: Bool
    let isEjectable: Bool
    let isRemovable: Bool
    let isSystemPartition: Bool

    var isMounted: Bool { mountPoint != nil }

    var usedBytes: Int64? {
        guard let total = totalBytes, let available = availableBytes else { return nil }
        return max(0, total - available)
    }

    /// Usage ratio in 0.0...1.0 when both total and available bytes are known.
    var usageRatio: Double? {
        guard let total = totalBytes, total > 0, let used = usedBytes else { return nil }
        return min(1.0, max(0.0, Double(used) / Double(total)))
    }
}

/// Pure helpers for classifying, filtering, and formatting disk metadata.
enum DiskFormatting {
    private static let hiddenMediaContentUUIDs: Set<String> = [
        "C12A7328-F81F-11D2-BA4B-00A0C93EC93B", // EFI System Partition
        "E3C9E316-0B5C-4DB8-817D-F92DF00215AE", // Microsoft Reserved
        "DE94BBA4-06D1-4D40-A16A-BFD50179D6AC"  // Windows Recovery
    ]

    private static let hiddenMediaContentNames: Set<String> = [
        "EFI",
        "Microsoft Reserved",
        "Windows Recovery",
        "Apple_APFS_ISC",
        "Apple_APFS_Recovery",
        "Apple_Boot"
    ]

    private static let internalSystemVolumeNames: Set<String> = [
        "Preboot",
        "Recovery",
        "VM",
        "Update",
        "xART",
        "iSCPreboot",
        "Hardware",
        "Macintosh HD"
    ]

    /// Returns true when a partition is a hidden system/firmware partition (EFI, Recovery, Preboot, VM, etc.).
    static func isSystemPartition(
        volumeName: String?,
        mediaName: String?,
        mediaContent: String?,
        mountPoint: URL?,
        isInternal: Bool
    ) -> Bool {
        if let content = mediaContent {
            if hiddenMediaContentUUIDs.contains(content) || hiddenMediaContentNames.contains(content) {
                return true
            }
        }

        let candidateNames = [volumeName, mediaName].compactMap { $0 }
        if candidateNames.contains(where: {
            $0 == "EFI" ||
            $0 == "Microsoft Reserved" ||
            $0 == "Windows Recovery" ||
            $0.hasPrefix("com.apple.os.update-")
        }) {
            return true
        }

        if isInternal {
            if candidateNames.contains(where: { internalSystemVolumeNames.contains($0) }) {
                return true
            }
            if let path = mountPoint?.path {
                if path == "/" || path.hasPrefix("/System/Volumes/") && path != "/System/Volumes/Data" {
                    return true
                }
            }
        }

        return false
    }

    /// Normalizes raw `DAVolumeKind` / filesystem strings for compact display.
    static func displayFilesystem(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return "Volume"
        }
        switch raw.lowercased() {
        case "apfs": return "APFS"
        case "hfs": return "HFS+"
        case "exfat": return "ExFAT"
        case "msdos", "fat32": return "FAT32"
        case "ntfs": return "NTFS"
        case "smbfs": return "SMB"
        case "afpfs": return "AFP"
        case "nfs": return "NFS"
        case "udf": return "UDF"
        case "cd9660": return "ISO"
        default: return raw.uppercased()
        }
    }

    /// Formats byte counts using decimal storage units (matching macOS Finder).
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useTB, .useMB, .useKB]
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }
}
