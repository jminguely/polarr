import SwiftUI

public struct RatingView: View {
    @Binding public var rating: Int?
    public var maxRating: Int = 5
    public var isInteractive: Bool = true
    public var starSize: CGFloat = 18

    public init(rating: Binding<Int?>, maxRating: Int = 5, isInteractive: Bool = true, starSize: CGFloat = 18) {
        self._rating = rating
        self.maxRating = maxRating
        self.isInteractive = isInteractive
        self.starSize = starSize
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(1...maxRating, id: \.self) { index in
                Image(systemName: starIconName(for: index))
                    .font(.system(size: starSize, weight: .semibold))
                    .foregroundStyle(index <= (rating ?? 0) ? BrandTheme.amber : BrandTheme.textMuted.opacity(0.4))
                    .onTapGesture {
                        if isInteractive {
                            if rating == index {
                                rating = nil
                            } else {
                                rating = index
                            }
                        }
                    }
            }
        }
    }

    private func starIconName(for index: Int) -> String {
        if index <= (rating ?? 0) {
            return "star.fill"
        }
        return "star"
    }
}
