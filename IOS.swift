import SwiftUI
import Combine

struct GlowEffect: View {
    @State private var gradientStops: [Gradient.Stop] = GlowEffect.generateGradientStops()
    @State private var timer: AnyCancellable?

    var body: some View {
        ZStack {
            EffectNoBlur(gradientStops: gradientStops, width: 6)
            Effect(gradientStops: gradientStops, width: 9, blur: 4)
            Effect(gradientStops: gradientStops, width: 11, blur: 12)
            Effect(gradientStops: gradientStops, width: 15, blur: 15)
        }
        .drawingGroup() // Composite layers into a single render pass
        .onAppear {
            // Use a single timer for all layers to avoid redundant updates
            timer = Timer.publish(every: 0.5, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    withAnimation(.easeInOut(duration: 1.0)) {
                        gradientStops = GlowEffect.generateGradientStops()
                    }
                }
        }
        .onDisappear {
            // Cancel timer to prevent memory leaks
            timer?.cancel()
            timer = nil
        }
    }
    
    // Function to generate random gradient stops
    static func generateGradientStops() -> [Gradient.Stop] {
        [
            Gradient.Stop(color: Color(hex: "BC82F3"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "F5B9EA"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "8D9FFF"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "FF6778"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "FFBA71"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "C686FF"), location: Double.random(in: 0...1))
        ].sorted { $0.location < $1.location }
    }
}

struct Effect: View {
    var gradientStops: [Gradient.Stop]
    var width: CGFloat
    var blur: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 55)
            .strokeBorder(
                AngularGradient(
                    gradient: Gradient(stops: gradientStops),
                    center: .center
                ),
                lineWidth: width
            )
            .frame(
                width: UIScreen.main.bounds.width,
                height: UIScreen.main.bounds.height
            )
            .padding(.top, -17)
            .blur(radius: blur)
            .compositingGroup() // Optimize blur rendering
    }
}

struct EffectNoBlur: View {
    var gradientStops: [Gradient.Stop]
    var width: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 55)
            .strokeBorder(
                AngularGradient(
                    gradient: Gradient(stops: gradientStops),
                    center: .center
                ),
                lineWidth: width
            )
            .frame(
                width: UIScreen.main.bounds.width,
                height: UIScreen.main.bounds.height
            )
            .padding(.top, -26)
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        _ = scanner.scanString("#")
        
        var hexNumber: UInt64 = 0
        scanner.scanHexInt64(&hexNumber)
        
        let r = Double((hexNumber & 0xff0000) >> 16) / 255
        let g = Double((hexNumber & 0x00ff00) >> 8) / 255
        let b = Double(hexNumber & 0x0000ff) / 255
        
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    GlowEffect()
}
