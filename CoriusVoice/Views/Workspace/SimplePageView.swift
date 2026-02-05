import SwiftUI

// MARK: - Simple Page View (Compatibility Wrapper)

/// Wrapper to keep legacy references while using the unified PageView editor.
struct SimplePageView: View {
    let itemID: UUID

    init(item: WorkspaceItem) {
        self.itemID = item.id
    }

    var body: some View {
        PageView(itemID: itemID)
    }
}
