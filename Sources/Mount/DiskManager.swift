import AppKit
import DiskArbitration
import Foundation
import Observation

/// Live disk and volume monitor + action runner backed by DiskArbitration and `diskutil`.
@MainActor
@Observable
final class DiskManager {
    private(set) var volumes: [VolumeItem] = []
    private(set) var busyVolumeIDs: Set<String> = []
    private(set) var isBulkBusy: Bool = false
    var lastError: String?

    // User preferences persisted in UserDefaults
    var showInternalVolumes: Bool {
        didSet { UserDefaults.standard.set(showInternalVolumes, forKey: Keys.showInternal) }
    }
    var showSystemPartitions: Bool {
        didSet { UserDefaults.standard.set(showSystemPartitions, forKey: Keys.showSystem) }
    }
    var showMenuBarCount: Bool {
        didSet { UserDefaults.standard.set(showMenuBarCount, forKey: Keys.showCount) }
    }

    private enum Keys {
        static let showInternal = "Mount.showInternalVolumes"
        static let showSystem = "Mount.showSystemPartitions"
        static let showCount = "Mount.showMenuBarCount"
    }

    private var daSession: DASession?
    private var daDisks: [String: DADisk] = [:]
    private var observers: [NSObjectProtocol] = []

    init() {
        self.showInternalVolumes = UserDefaults.standard.bool(forKey: Keys.showInternal)
        self.showSystemPartitions = UserDefaults.standard.bool(forKey: Keys.showSystem)
        if UserDefaults.standard.object(forKey: Keys.showCount) == nil {
            self.showMenuBarCount = true
        } else {
            self.showMenuBarCount = UserDefaults.standard.bool(forKey: Keys.showCount)
        }

        startMonitoring()
    }

    // MARK: - Filtered Views

    var visibleVolumes: [VolumeItem] {
        volumes.filter { item in
            !item.isSystemPartition && item.category != .internalDrive
        }
    }

    var mountedVolumes: [VolumeItem] {
        visibleVolumes
            .filter(\.isMounted)
            .sorted { lhs, rhs in
                if lhs.category != rhs.category { return lhs.category < rhs.category }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    var offlineVolumes: [VolumeItem] {
        visibleVolumes
            .filter { !$0.isMounted }
            .sorted { lhs, rhs in
                if lhs.category != rhs.category { return lhs.category < rhs.category }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// Count shown in the menu bar badge (mounted external, disk image, and network volumes).
    var mountedExternalCount: Int {
        mountedVolumes.filter { $0.category != .internalDrive }.count
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return }
        daSession = session

        let context = Unmanaged.passUnretained(self).toOpaque()

        DARegisterDiskAppearedCallback(session, nil, { disk, ctx in
            guard let ctx else { return }
            let manager = Unmanaged<DiskManager>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated {
                manager.handleDiskAppearedOrChanged(disk)
            }
        }, context)

        DARegisterDiskDisappearedCallback(session, nil, { disk, ctx in
            guard let ctx else { return }
            let manager = Unmanaged<DiskManager>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated {
                manager.handleDiskDisappeared(disk)
            }
        }, context)

        DARegisterDiskDescriptionChangedCallback(session, nil, nil, { disk, _, ctx in
            guard let ctx else { return }
            let manager = Unmanaged<DiskManager>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated {
                manager.handleDiskAppearedOrChanged(disk)
            }
        }, context)

        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let wsCenter = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification
        ]
        for name in names {
            let token = wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshAll()
                }
            }
            observers.append(token)
        }

        refreshAll()
    }

    private func handleDiskAppearedOrChanged(_ disk: DADisk) {
        guard let bsdPtr = DADiskGetBSDName(disk) else { return }
        let bsdName = String(cString: bsdPtr)
        daDisks[bsdName] = disk
        rebuildVolumeList()
    }

    private func handleDiskDisappeared(_ disk: DADisk) {
        guard let bsdPtr = DADiskGetBSDName(disk) else { return }
        let bsdName = String(cString: bsdPtr)
        daDisks.removeValue(forKey: bsdName)
        rebuildVolumeList()
    }

    func refreshAll() {
        rebuildVolumeList()
    }

    private func rebuildVolumeList() {
        var items: [VolumeItem] = []
        var mountedPathsSeen: Set<String> = []

        for (bsdName, disk) in daDisks {
            guard let desc = DADiskCopyDescription(disk) as? [String: Any] else { continue }
            guard let item = makeVolumeItem(bsdName: bsdName, desc: desc) else { continue }
            items.append(item)
            if let path = item.mountPoint?.path {
                mountedPathsSeen.insert(path)
            }
        }

        // Also include mounted network shares (SMB/AFP/NFS) which don't have a local BSD DADisk.
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsLocalKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        if let mountedURLs = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) {
            for url in mountedURLs where !mountedPathsSeen.contains(url.path) {
                let values = try? url.resourceValues(forKeys: Set(keys))
                let isLocal = values?.volumeIsLocal ?? true
                guard !isLocal else { continue }

                let name = values?.volumeName ?? url.lastPathComponent
                let total = values?.volumeTotalCapacity.map { Int64($0) }
                let avail = values?.volumeAvailableCapacityForImportantUsage ?? values?.volumeAvailableCapacity.map { Int64($0) }

                items.append(VolumeItem(
                    id: "net:\(url.path)",
                    bsdName: nil,
                    name: name,
                    mountPoint: url,
                    category: .network,
                    filesystem: "Rete",
                    totalBytes: total,
                    availableBytes: avail,
                    deviceProtocol: "Network",
                    isInternal: false,
                    isEjectable: true,
                    isRemovable: false,
                    isSystemPartition: false
                ))
            }
        }

        self.volumes = items
    }

    private func makeVolumeItem(bsdName: String, desc: [String: Any]) -> VolumeItem? {
        let isMountable = (desc[kDADiskDescriptionVolumeMountableKey as String] as? Bool) ?? false
        let volumeKind = desc[kDADiskDescriptionVolumeKindKey as String] as? String
        let mediaWhole = (desc[kDADiskDescriptionMediaWholeKey as String] as? Bool) ?? false

        // Skip partition tables / APFS containers / non-mountable raw whole disks.
        guard isMountable else { return nil }
        if mediaWhole && volumeKind == nil { return nil }

        let mountPoint = desc[kDADiskDescriptionVolumePathKey as String] as? URL
        let volumeName = desc[kDADiskDescriptionVolumeNameKey as String] as? String
        let mediaName = desc[kDADiskDescriptionMediaNameKey as String] as? String
        let mediaContent = desc[kDADiskDescriptionMediaContentKey as String] as? String
        let deviceProtocol = desc[kDADiskDescriptionDeviceProtocolKey as String] as? String
        let deviceModel = desc[kDADiskDescriptionDeviceModelKey as String] as? String
        let isInternal = (desc[kDADiskDescriptionDeviceInternalKey as String] as? Bool) ?? false
        let isEjectable = (desc[kDADiskDescriptionMediaEjectableKey as String] as? Bool) ?? false
        let isRemovable = (desc[kDADiskDescriptionMediaRemovableKey as String] as? Bool) ?? false
        let isNetwork = (desc[kDADiskDescriptionVolumeNetworkKey as String] as? Bool) ?? false
        let mediaSize = (desc[kDADiskDescriptionMediaSizeKey as String] as? NSNumber)?.int64Value

        let isSystem = DiskFormatting.isSystemPartition(
            volumeName: volumeName,
            mediaName: mediaName,
            mediaContent: mediaContent,
            mountPoint: mountPoint,
            isInternal: isInternal
        )

        let category: VolumeCategory
        if isNetwork {
            category = .network
        } else if deviceProtocol == "Disk Image" || deviceModel == "Disk Image" {
            category = .diskImage
        } else if isInternal {
            category = .internalDrive
        } else {
            category = .external
        }

        let displayName = [volumeName, mediaName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? bsdName

        var totalBytes: Int64? = mediaSize
        var availableBytes: Int64? = nil

        if let url = mountPoint {
            let resourceKeys: Set<URLResourceKey> = [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ]
            if let values = try? url.resourceValues(forKeys: resourceKeys) {
                if let total = values.volumeTotalCapacity {
                    totalBytes = Int64(total)
                }
                if let importantAvail = values.volumeAvailableCapacityForImportantUsage, importantAvail > 0 {
                    availableBytes = importantAvail
                } else if let avail = values.volumeAvailableCapacity {
                    availableBytes = Int64(avail)
                }
            }
        }

        return VolumeItem(
            id: bsdName,
            bsdName: bsdName,
            name: displayName,
            mountPoint: mountPoint,
            category: category,
            filesystem: DiskFormatting.displayFilesystem(volumeKind),
            totalBytes: totalBytes,
            availableBytes: availableBytes,
            deviceProtocol: deviceProtocol,
            isInternal: isInternal,
            isEjectable: isEjectable,
            isRemovable: isRemovable,
            isSystemPartition: isSystem
        )
    }

    // MARK: - Actions

    func openInFinder(_ volume: VolumeItem) {
        guard let url = volume.mountPoint else { return }
        NSWorkspace.shared.open(url)
    }

    func mount(_ volume: VolumeItem) async {
        guard let bsdName = volume.bsdName else { return }
        await performDiskAction(for: volume.id, args: ["mount", bsdName])
    }

    func unmount(_ volume: VolumeItem, force: Bool = false) async {
        var args = ["unmount"]
        if force { args.append("force") }

        if let bsdName = volume.bsdName {
            args.append(bsdName)
        } else if let path = volume.mountPoint?.path {
            args.append(path)
        } else {
            return
        }

        await performDiskAction(for: volume.id, args: args)
    }

    func eject(_ volume: VolumeItem) async {
        if let bsdName = volume.bsdName {
            await performDiskAction(for: volume.id, args: ["eject", bsdName])
        } else if let url = volume.mountPoint {
            busyVolumeIDs.insert(volume.id)
            defer { busyVolumeIDs.remove(volume.id) }
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                lastError = nil
            } catch {
                lastError = "Impossibile espellere \(volume.name): \(error.localizedDescription)"
            }
            refreshAll()
        }
    }

    func mountAllOffline() async {
        let targets = offlineVolumes
        guard !targets.isEmpty else { return }
        isBulkBusy = true
        defer { isBulkBusy = false }

        for volume in targets {
            await mount(volume)
        }
    }

    func unmountAllExternal() async {
        let targets = mountedVolumes.filter { $0.category != .internalDrive }
        guard !targets.isEmpty else { return }
        isBulkBusy = true
        defer { isBulkBusy = false }

        for volume in targets {
            await unmount(volume)
        }
    }

    func ejectAllExternal() async {
        let targets = mountedVolumes.filter { $0.category != .internalDrive }
        guard !targets.isEmpty else { return }
        isBulkBusy = true
        defer { isBulkBusy = false }

        for volume in targets {
            await eject(volume)
        }
    }

    private func performDiskAction(for volumeID: String, args: [String]) async {
        busyVolumeIDs.insert(volumeID)
        defer { busyVolumeIDs.remove(volumeID) }

        let result = await runDiskutil(args: args)
        if result.exitCode != 0 {
            let message = result.errorOutput.isEmpty ? result.standardOutput : result.errorOutput
            lastError = message.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            lastError = nil
        }

        // DiskArbitration callbacks usually fire immediately, but refresh explicitly as a safety net.
        refreshAll()
    }

    private func runDiskutil(args: [String]) async -> (exitCode: Int32, standardOutput: String, errorOutput: String) {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = args

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()
                let out = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return (process.terminationStatus, out, err)
            } catch {
                return (-1, "", error.localizedDescription)
            }
        }.value
    }
}
