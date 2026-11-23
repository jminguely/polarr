import SwiftUI

public struct AsyncArtworkView: View {
    public let urlString: String?
    public var size: CGFloat? = 56
    public var cornerRadius: CGFloat = 12

    public init(urlString: String?, size: CGFloat? = 56, cornerRadius: CGFloat = 12) {
        self.urlString = urlString
        self.size = size
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Group {
            if let str = urlString, let url = URL(string: str) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderView
                    case .empty:
                        ZStack {
                            BrandTheme.bgCard
                            ProgressView()
                                .tint(BrandTheme.cyan)
                                .scaleEffect(0.7)
                        }
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
        )
    }

    private var placeholderView: some View {
        ZStack {
            BrandTheme.bgCard
            Image(systemName: "headphones")
                .font(.system(size: (size ?? 56) * 0.4, weight: .semibold))
                .foregroundStyle(BrandTheme.cyan.opacity(0.8))
        }
    }
}
