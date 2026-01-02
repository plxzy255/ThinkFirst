import SwiftUI

struct TwitterWidgetView: View {
    let bookmark: TwitterBookmark

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Profile Image
            AsyncImage(url: URL(string: bookmark.profileImageUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                // Header
                HStack {
                    Text(bookmark.authorName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("@\(bookmark.authorUsername)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Text
                Text(bookmark.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                // Image (if any)
                if let imageUrl = bookmark.imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 200) // Default height placeholder
                    }
                    .frame(maxWidth: .infinity)
                    .cornerRadius(12)
                    .padding(.top, 8)
                }
            }
        }
        .padding(16)
        .frame(width: 350)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}
