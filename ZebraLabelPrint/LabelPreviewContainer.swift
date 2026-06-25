import AppKit
import SwiftUI

struct LabelPreviewContainer: View {
    let images: [NSImage]
    let labelSizeInches: CGSize

    private static let pointsPerInch: CGFloat = 100
    private static let labelSpacing: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let padding: CGFloat = 32
            let bounds = CGSize(
                width: max(geometry.size.width - padding * 2, 1),
                height: max(geometry.size.height - padding * 2, 1)
            )
            let labelDisplay = Self.labelDisplaySize(
                labelSizeInches: labelSizeInches,
                labelCount: images.count,
                in: bounds
            )

            ZStack {
                LinearGradient(
                    colors: [
                        Color(nsColor: NSColor(calibratedWhite: 0.28, alpha: 1)),
                        Color(nsColor: NSColor(calibratedWhite: 0.38, alpha: 1))
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 12) {
                    rollStrip(width: labelDisplay.width + 20)

                    ScrollView {
                        VStack(spacing: Self.labelSpacing) {
                            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                                labelFrame(image: image, size: labelDisplay, index: index + 1)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Text("Label backing")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func labelFrame(image: NSImage, size: CGSize, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 16, alignment: .trailing)

            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(nsColor: NSColor(calibratedWhite: 0.92, alpha: 1)))
                    .frame(width: size.width + 8, height: size.height + 8)
                    .shadow(color: .black.opacity(0.28), radius: 4, x: 0, y: 2)

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.14), lineWidth: 1)
                    }
                    .frame(width: size.width, height: size.height)

                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
        }
    }

    private func rollStrip(width: CGFloat) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color(nsColor: NSColor(calibratedWhite: 0.55, alpha: 1)),
                        Color(nsColor: NSColor(calibratedWhite: 0.42, alpha: 1))
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: min(width, 240), height: 8)
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            }
    }

    private static func labelDisplaySize(
        labelSizeInches: CGSize,
        labelCount: Int,
        in bounds: CGSize
    ) -> CGSize {
        guard labelSizeInches.width > 0, labelSizeInches.height > 0, labelCount > 0 else {
            return CGSize(width: 200, height: 100)
        }

        let naturalWidth = labelSizeInches.width * pointsPerInch
        let naturalHeight = labelSizeInches.height * pointsPerInch
        let spacing = labelSpacing * CGFloat(max(labelCount - 1, 0))
        let stripHeight = naturalHeight * CGFloat(labelCount) + spacing

        let widthScale = (bounds.width * 0.85) / (naturalWidth + 24)
        let heightScale = bounds.height / stripHeight
        let scale = min(widthScale, heightScale, 1.5)

        return CGSize(
            width: max(naturalWidth * scale, 40),
            height: max(naturalHeight * scale, 20)
        )
    }
}
