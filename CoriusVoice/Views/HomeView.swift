import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            quickActions
            emptyState
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Sections

private extension HomeView {
    var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome back")
                .font(.largeTitle).bold()
            Text("Graba con Fn/Globe o con el menú superior. Aquí verás tus sesiones recientes y accesos rápidos.")
                .foregroundColor(.secondary)
                .font(.subheadline)
        }
    }

    var quickActions: some View {
        HStack(spacing: 16) {
            actionCard(
                icon: "record.circle.fill",
                title: "Nueva grabación",
                subtitle: "Opción + Fn/Globe",
                action: { NotificationCenter.default.post(name: .uiStartRecording, object: nil) }
            )
            actionCard(
                icon: "note.text",
                title: "Nueva nota de voz",
                subtitle: "Guarda ideas rápidas",
                action: { NotificationCenter.default.post(name: .uiStartVoiceNote, object: nil) }
            )
            actionCard(
                icon: "text.badge.plus",
                title: "Añadir snippet",
                subtitle: "Atajos de texto",
                action: { NotificationCenter.default.post(name: .uiOpenSnippets, object: nil) }
            )
        }
    }

    var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 52))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Aún no tienes sesiones recientes")
                .font(.title2).fontWeight(.semibold)
            Text("Empieza una grabación o crea una nota de voz para verlas aquí.")
                .foregroundColor(.secondary)
                .font(.subheadline)

            HStack(spacing: 12) {
                Button(action: { NotificationCenter.default.post(name: .uiStartRecording, object: nil) }) {
                    Label("Empezar a grabar", systemImage: "record.circle.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(action: { NotificationCenter.default.post(name: .uiStartVoiceNote, object: nil) }) {
                    Label("Nota rápida", systemImage: "mic.fill")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    func actionCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.footnote)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState.shared)
        .frame(width: 600, height: 400)
}
