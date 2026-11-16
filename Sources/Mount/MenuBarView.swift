import SwiftUI

struct MenuBarView: View {
    @Bindable var manager: DiskManager

    var body: some View {
        VStack(spacing: 0) {
            if let error = manager.lastError, !error.isEmpty {
                errorBanner(error)
            }

            volumeListView

            Divider().opacity(0.4)
            footerView
        }
        .frame(width: 156)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(3)

            Spacer(minLength: 4)

            Button {
                manager.lastError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    // MARK: - Volume List

    private var volumeListView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if manager.mountedVolumes.isEmpty && manager.offlineVolumes.isEmpty {
                Text("Nessun disco")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                if !manager.mountedVolumes.isEmpty {
                    sectionHeader("Collegati")
                    VStack(spacing: 0) {
                        ForEach(manager.mountedVolumes) { volume in
                            volumeRow(for: volume)
                        }
                    }
                }

                if !manager.offlineVolumes.isEmpty {
                    sectionHeader("Offline")
                    VStack(spacing: 0) {
                        ForEach(manager.offlineVolumes) { volume in
                            volumeRow(for: volume)
                        }
                    }
                }
            }
        }
        .padding(4)
    }

    private func volumeRow(for volume: VolumeItem) -> some View {
        VolumeRowView(
            volume: volume,
            isBusy: manager.busyVolumeIDs.contains(volume.id),
            onOpenFinder: { manager.openInFinder(volume) },
            onMount: { Task { await manager.mount(volume) } },
            onEject: { Task { await manager.eject(volume) } }
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
            .padding(.horizontal, 6)
            .padding(.top, 2)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Spacer()
            Button("Esci") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
