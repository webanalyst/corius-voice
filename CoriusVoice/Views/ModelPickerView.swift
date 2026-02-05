import SwiftUI

// MARK: - Model Picker View

struct ModelPickerView: View {
    @ObservedObject var openRouterService: OpenRouterService
    @Binding var selectedModelId: String
    @Binding var selectedModelName: String
    let onRefresh: () -> Void

    @State private var searchText = ""
    @State private var expandedProviders: Set<String> = []

    private var filteredModels: [OpenRouterModel] {
        if searchText.isEmpty {
            return openRouterService.cachedModels
        }
        let query = searchText.lowercased()
        return openRouterService.cachedModels.filter { model in
            model.name.lowercased().contains(query) ||
            model.id.lowercased().contains(query) ||
            model.provider.lowercased().contains(query)
        }
    }

    private var groupedModels: [String: [OpenRouterModel]] {
        Dictionary(grouping: filteredModels, by: { $0.providerDisplayName })
    }

    private var sortedProviders: [String] {
        groupedModels.keys.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search and refresh header
            HStack {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search models...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Refresh button
                Button(action: onRefresh) {
                    if openRouterService.isLoadingModels {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(openRouterService.isLoadingModels)
                .help("Refresh model list")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Models list
            if openRouterService.cachedModels.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    if openRouterService.isLoadingModels {
                        ProgressView("Loading models...")
                    } else {
                        Image(systemName: "cube.transparent")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No models loaded")
                            .foregroundColor(.secondary)
                        Button("Load Models") {
                            onRefresh()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if filteredModels.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No models match '\(searchText)'")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(sortedProviders, id: \.self) { provider in
                            ProviderSection(
                                provider: provider,
                                models: groupedModels[provider] ?? [],
                                selectedModelId: selectedModelId,
                                isExpanded: expandedProviders.contains(provider) || !searchText.isEmpty,
                                onToggle: { toggleProvider(provider) },
                                onSelectModel: selectModel
                            )
                        }
                    }
                    .padding()
                }
            }

            // Selected model display
            if !selectedModelId.isEmpty {
                Divider()
                SelectedModelBar(
                    modelId: selectedModelId,
                    modelName: selectedModelName,
                    model: openRouterService.getModel(byId: selectedModelId),
                    onClear: clearSelection
                )
            }
        }
    }

    private func toggleProvider(_ provider: String) {
        if expandedProviders.contains(provider) {
            expandedProviders.remove(provider)
        } else {
            expandedProviders.insert(provider)
        }
    }

    private func selectModel(_ model: OpenRouterModel) {
        selectedModelId = model.id
        selectedModelName = model.name
    }

    private func clearSelection() {
        selectedModelId = ""
        selectedModelName = ""
    }
}

// MARK: - Provider Section

struct ProviderSection: View {
    let provider: String
    let models: [OpenRouterModel]
    let selectedModelId: String
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSelectModel: (OpenRouterModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Provider header
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text(provider)
                        .font(.headline)
                    Text("(\(models.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Models list
            if isExpanded {
                ForEach(models) { model in
                    ModelRowView(
                        model: model,
                        isSelected: model.id == selectedModelId,
                        onSelect: { onSelectModel(model) }
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

// MARK: - Model Row View

struct ModelRowView: View {
    let model: OpenRouterModel
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.body)

                // Model info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.name)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        Spacer()

                        // Tier badge
                        TierBadge(tier: model.tier)
                    }

                    // Model ID
                    Text(model.id)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Metadata row
                    HStack(spacing: 12) {
                        MetadataTag(
                            icon: "doc.text",
                            text: model.formattedContextLength
                        )
                        MetadataTag(
                            icon: "arrow.down.circle",
                            text: model.formattedPromptPrice
                        )
                        MetadataTag(
                            icon: "arrow.up.circle",
                            text: model.formattedCompletionPrice
                        )
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tier Badge

struct TierBadge: View {
    let tier: ModelTier

    var body: some View {
        Text(tier.displayName)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(hex: tier.color)?.opacity(0.2) ?? Color.gray.opacity(0.2))
            .foregroundColor(Color(hex: tier.color) ?? .gray)
            .cornerRadius(4)
    }
}

// MARK: - Metadata Tag

struct MetadataTag: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .foregroundColor(.secondary)
    }
}

// MARK: - Selected Model Bar

struct SelectedModelBar: View {
    let modelId: String
    let modelName: String
    let model: OpenRouterModel?
    let onClear: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Selected:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(modelName.isEmpty ? modelId : modelName)
                    .fontWeight(.medium)
            }

            Spacer()

            if let model = model {
                TierBadge(tier: model.tier)
            }

            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.accentColor.opacity(0.1))
    }
}

// NOTE: Color(hex:) extension is defined in SessionRecordingView.swift

// MARK: - Preview

#Preview {
    ModelPickerView(
        openRouterService: OpenRouterService.shared,
        selectedModelId: .constant(""),
        selectedModelName: .constant(""),
        onRefresh: {}
    )
    .frame(width: 500, height: 600)
}
