import SwiftUI

struct YisiWordmark: View {
    let size: CGFloat
    var isLight = false

    var body: some View {
        Text(verbatim: "YISI")
            .font(YisiType.archivo(size: size, weight: isLight ? 300 : 650, width: 125).map { Font($0) }
                  ?? .system(size: size, weight: isLight ? .light : .semibold).width(.expanded))
            .fixedSize()
    }
}
