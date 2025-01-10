import SwiftUI
import WatchKit

// MARK: V2 of the WatchOS.swift file however has the ability to freeze the animation, also updated performance and merging of some layers
// I left V1 Up in case anyone wants to take a look still
struct GlowEffect: View {
    @State private var gradientStops: [Gradient.Stop] = GlowEffect.generateGradientStops()
    @State private var timers: [Timer] = []
    var freeze: Bool

    var body: some View {
        ZStack {
            EffectNoBlur(gradientStops: gradientStops, width: 5)
            Effect(gradientStops: gradientStops, width: 7, blur: 4)
            Effect(gradientStops: gradientStops, width: 9, blur: 12)
            Effect(gradientStops: gradientStops, width: 12, blur: 15)
        }
        .onAppear {
            if !freeze {
                startTimers()
            }
        }
        .onChange(of: freeze) { isFrozen in
            if isFrozen {
                stopTimers()
            } else {
                startTimers()
            }
        }
        .onDisappear {
            stopTimers()
        }
    }

    private func startTimers() {
        stopTimers() // Ensure no existing timers are running
        timers.append(
            Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.6)) {
                    gradientStops = GlowEffect.generateGradientStops()
                }
            }
        )
    }

    private func stopTimers() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
    }

    // Function to generate random gradient stops on an Angular Gradient
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

// MARK: These Effect Functions generate the different layers that make up the gradient effect
//Effect means the layers have a Blur (inner 3 layers)
struct Effect: View {
    var gradientStops: [Gradient.Stop]
    var width: Double
    var blur: Double

    var body: some View {
        RoundedRectangle(cornerRadius: 50)
            .strokeBorder(
                AngularGradient(
                    gradient: Gradient(stops: gradientStops),
                    center: .center
                ),
                lineWidth: width
            )
            .frame(
                width: WKInterfaceDevice.current().screenBounds.width,
                height: WKInterfaceDevice.current().screenBounds.height
            )
            .padding(.top, -17)
            .blur(radius: blur)
    }
}

//Effect no blur if for the last layer on the very edge of the screen
struct EffectNoBlur: View {
    var gradientStops: [Gradient.Stop]
    var width: Double

    var body: some View {
        RoundedRectangle(cornerRadius: 50)
            .strokeBorder(
                AngularGradient(
                    gradient: Gradient(stops: gradientStops),
                    center: .center
                ),
                lineWidth: width
            )
            .frame(
                width: WKInterfaceDevice.current().screenBounds.width,
                height: WKInterfaceDevice.current().screenBounds.height
            )
            .padding(.top, -17)
    }
}

// MARK: Color function that converts HEX (From figma) into RGB values for SwiftUI
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

// Preview
#Preview {
    GlowEffect(freeze: false) // Toggle `freeze` to test behavior
}
