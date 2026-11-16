import Foundation
import Testing
@testable import Mount

@Suite("DiskModels & Formatting Tests")
struct DiskModelsTests {
    @Test("Identifies EFI and Microsoft Reserved as system partitions")
    func systemPartitionDetection() {
        #expect(DiskFormatting.isSystemPartition(
            volumeName: "EFI",
            mediaName: "EFI",
            mediaContent: "C12A7328-F81F-11D2-BA4B-00A0C93EC93B",
            mountPoint: nil,
            isInternal: false
        ) == true)

        #expect(DiskFormatting.isSystemPartition(
            volumeName: nil,
            mediaName: "Microsoft Reserved",
            mediaContent: "E3C9E316-0B5C-4DB8-817D-F92DF00215AE",
            mountPoint: nil,
            isInternal: false
        ) == true)

        #expect(DiskFormatting.isSystemPartition(
            volumeName: "Preboot",
            mediaName: "Preboot",
            mediaContent: "Apple_APFS",
            mountPoint: URL(fileURLWithPath: "/System/Volumes/Preboot"),
            isInternal: true
        ) == true)

        #expect(DiskFormatting.isSystemPartition(
            volumeName: "2Tb",
            mediaName: "2Tb",
            mediaContent: "Apple_APFS",
            mountPoint: URL(fileURLWithPath: "/Volumes/2Tb"),
            isInternal: false
        ) == false)
    }

    @Test("Normalizes filesystem names cleanly")
    func filesystemDisplay() {
        #expect(DiskFormatting.displayFilesystem("apfs") == "APFS")
        #expect(DiskFormatting.displayFilesystem("hfs") == "HFS+")
        #expect(DiskFormatting.displayFilesystem("exfat") == "ExFAT")
        #expect(DiskFormatting.displayFilesystem("msdos") == "FAT32")
        #expect(DiskFormatting.displayFilesystem("smbfs") == "SMB")
        #expect(DiskFormatting.displayFilesystem(nil) == "Volume")
    }

    @Test("Computes used bytes and usage ratio safely")
    func volumeUsageCalculation() {
        let item = VolumeItem(
            id: "disk7s1",
            bsdName: "disk7s1",
            name: "2Tb",
            mountPoint: URL(fileURLWithPath: "/Volumes/2Tb"),
            category: .external,
            filesystem: "APFS",
            totalBytes: 2_000_000_000_000,
            availableBytes: 300_000_000_000,
            deviceProtocol: "USB",
            isInternal: false,
            isEjectable: true,
            isRemovable: false,
            isSystemPartition: false
        )

        #expect(item.isMounted == true)
        #expect(item.usedBytes == 1_700_000_000_000)
        #expect(item.usageRatio == 0.85)
    }
}
