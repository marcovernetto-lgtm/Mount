import SwiftUI

struct VolumeRowView: View {
    let volume: VolumeItem
    let isBusy: Bool
    let onOpenFinder: () -> Void
    let onMount: () -> Void
    let onEject: () -> Void

    @State private var isHovered = false

    private var statusColor: Color {
        volume.isMounted
            ? Color(red: 0.06, green: 0.73, blue: 0.51) // Emerald
            : Color(red: 0.96, green: 0.62, blue: 0.04) // Amber
    }

    var body: some View {
        HStack(spacing: 7) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: volume.category.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(volume.isMounted ? Color.primary : Color.secondary)
                    .frame(width: 18, height: 18)

                Circle()
                    .fill(statusColor)
                    .frame(width: 5.5, height: 5.5)
                    .overlay(
                        Circle()
                            .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1)
                    )
                    .offset(x: 1.5, y: 1.5)
            }

            Text(volume.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(volume.isMounted ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if isBusy {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 20, height: 18)
            } else if volume.isMounted {
                if volume.category != .internalDrive {
                    Button(action: onEject) {
                        Image(systemName: "eject.fill")
                            .font(.system(size: 10.5, weight: .medium))
                            .frame(width: 20, height: 18)
                    }
                    .buttonStyle(RowIconButtonStyle())
                    .help("Espelli")
                }
            } else {
                Button(action: onMount) {
                    Text("Monta")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(.white)
                        .background(
                            Color(red: 0.04, green: 0.52, blue: 1.0),
                            in: RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help("Monta disco")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.07) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            if volume.isMounted {
                onOpenFinder()
            } else if !isBusy {
                onMount()
            }
        }
    }
}

private struct RowIconButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? .primary : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(hovered || configuration.isPressed ? Color.primary.opacity(0.10) : Color.clear)
            )
            .onHover { hovered = $0 }
    }
}
