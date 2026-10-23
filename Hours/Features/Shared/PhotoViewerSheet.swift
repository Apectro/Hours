import SwiftUI
import UIKit

/// One photo, large: what a tap on a thumbnail opens. Looking is the reason
/// people tap a photo, so removing it is a separate, confirmed button at the
/// bottom, away from Done.
///
/// Shared by the extra-work editor; the site diary has the same viewer of
/// its own (`DiaryPhotoViewer`) and can move to this one.
struct PhotoViewerSheet: View {
    /// The stored JPEG, drawn at full size.
    let data: Data
    /// What VoiceOver calls the picture, e.g. "Extra work photo".
    let spokenName: String
    /// `nil` when the photo cannot be removed here (a read-only site).
    let onRemove: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var confirmsRemoval = false

    var body: some View {
        NavigationStack {
            Group {
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(spokenName)
                } else {
                    Color.hoursCanvas
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hoursCanvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Only shows: Done, top right.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("photo-viewer-done")
                }
                if onRemove != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            confirmsRemoval = true
                        } label: {
                            Label("Remove photo", systemImage: "trash")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityIdentifier("photo-viewer-remove")
                    }
                }
            }
            .confirmationDialog("Remove this photo?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("Remove photo", role: .destructive) {
                    onRemove?()
                    dismiss()
                }
            }
        }
    }
}
