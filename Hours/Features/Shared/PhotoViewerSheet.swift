import SwiftUI
import UIKit

/// One photo, large, on a dark ground (1.2 redesign, mockup 08 "A photo"):
/// what a tap on a thumbnail opens, in the site diary and in the extra-work
/// editor alike. Done and Share at the top, "1 of 2" between them, the date
/// and the site under the picture, and "Remove photo" at the bottom, away
/// from Done and confirmed first.
///
/// Share hands the picture to the system share sheet only when tapped: the
/// stored JPEG, already made small and stripped of its location by
/// `DiaryPhotoProcessor`.
struct PhotoViewerSheet: View {
    /// The stored JPEG, drawn at full size.
    let data: Data
    /// What VoiceOver calls the picture, e.g. "Extra work photo".
    let spokenName: String
    /// `nil` when the photo cannot be removed here (a read-only site).
    let onRemove: (() -> Void)?
    /// "1 of 2" in the bar, when there is more than one.
    var position: (index: Int, count: Int)? = nil
    /// The date and the site under the picture.
    var caption: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var confirmsRemoval = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Metrics.medium) {
                Group {
                    if let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: Metrics.large, style: .continuous))
                            .accessibilityLabel(spokenName)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let caption {
                    Text(verbatim: caption)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("photo-viewer-caption")
                }

                if onRemove != nil {
                    Button(role: .destructive) {
                        confirmsRemoval = true
                    } label: {
                        Text("Remove photo")
                    }
                    .buttonStyle(.bigAction(.destructive))
                    .accessibilityIdentifier("photo-viewer-remove")
                }
            }
            .padding(.horizontal, Metrics.large)
            .padding(.bottom, Metrics.large)
            .background(Color.black.opacity(0.92).ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("photo-viewer-done")
                }
                if let position, position.count > 1 {
                    ToolbarItem(placement: .principal) {
                        Text(String(
                            localized: "Photo \(position.index) of \(position.count)",
                            comment: "VoiceOver, a photo in the site diary; the values are its position and how many there are"
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    }
                }
                if let image = UIImage(data: data) {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview(spokenName, image: Image(uiImage: image))
                        ) {
                            Text("Share")
                        }
                        .accessibilityIdentifier("photo-viewer-share")
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
        .preferredColorScheme(.dark)
    }
}
