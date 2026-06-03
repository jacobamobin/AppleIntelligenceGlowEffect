import SwiftUI
import WatchKit
import Combine

// THIS VERSION SUPPORTS ALL APPLE WATCHES COMPATIBLE WITH WATCHOS 11
// MARK: The Apple intelligence glow effect function
// It is made up of 4 different layers.
struct GlowEffect: View {
    @State private var gradientStops: [Gradient.Stop] = GlowEffect.generateGradientStops()
    @State private var timer: AnyCancellable?

    var freeze: Bool

    // Fetch the combined device properties
    let deviceProperties = DeviceConfig.deviceProperties

    var body: some View {
        ZStack {
            // First layer is the border around the edge
            // The next 3 layers are the blurry layers closer to the middle of the screen
            EffectNoBlur(gradientStops: gradientStops, width: 5, deviceProperties: deviceProperties)
            Effect(gradientStops: gradientStops, width: 7, blur: 4, deviceProperties: deviceProperties)
            Effect(gradientStops: gradientStops, width: 9, blur: 12, deviceProperties: deviceProperties)
            Effect(gradientStops: gradientStops, width: 12, blur: 15, deviceProperties: deviceProperties)
        }
        .drawingGroup() // Composite layers into a single render pass
        .onAppear {
            if !freeze {
                startTimer()
            }
        }
        .onChange(of: freeze) { isFrozen in
            if isFrozen {
                stopTimer()
            } else {
                startTimer()
            }
        }
        .onDisappear {
            stopTimer()
        }
    }

    // MARK: Function to start the timer for the gradients
    private func startTimer() {
        stopTimer() // Ensure no existing timer is running
        // Optimized for WatchOS battery life - slightly slower updates
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                withAnimation(.easeInOut(duration: 1.0)) {
                    gradientStops = GlowEffect.generateGradientStops()
                }
            }
    }

    // MARK: Function to stop the timer for the gradients
    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // Function to generate random gradient stops on an Angular Gradient
    // MARK: Function to generate the colours of the Glow Effect
    // Change the hex codes to change the colours
    static func generateGradientStops() -> [Gradient.Stop] {
        [
            Gradient.Stop(color: Color(hex: "BC82F3"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "F5B9EA"), location: Double.random(in: 0...1)),
            //Gradient.Stop(color: Color(hex: "8D9FFF"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "FF6778"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "FFBA71"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "C686FF"), location: Double.random(in: 0...1))
        ].sorted { $0.location < $1.location }
    }
}

// MARK: These Effect Functions generate the different layers that make up the gradient effect

// Effect with blur for the inner layers
struct Effect: View {
    var gradientStops: [Gradient.Stop]
    var width: Double
    var blur: Double
    var deviceProperties: (cornerRoundness: Int, screenOffset: Int)

    var body: some View {
        RoundedRectangle(cornerRadius: CGFloat(deviceProperties.cornerRoundness))
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
            .padding(.top, -1 * CGFloat(deviceProperties.screenOffset))
            .blur(radius: blur)
            .compositingGroup() // Optimize blur rendering
    }
}

// Effect without blur for the outermost layer
struct EffectNoBlur: View {
    var gradientStops: [Gradient.Stop]
    var width: Double
    var deviceProperties: (cornerRoundness: Int, screenOffset: Int)

    var body: some View {
        RoundedRectangle(cornerRadius: CGFloat(deviceProperties.cornerRoundness))
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
            .padding(.top, -1 * CGFloat(deviceProperties.screenOffset))
    }
}

// MARK: Color extension that converts HEX values into RGB for SwiftUI
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

// MARK: Screen Dimension and Offset Constants
struct DeviceConfig {
    static let width = WKInterfaceDevice.current().screenBounds.width
    static let height = WKInterfaceDevice.current().screenBounds.height

    // MARK: Combined cornerRoundness and screenOffset
    static let deviceProperties: (cornerRoundness: Int, screenOffset: Int) = {
        print("Device Width: \(Int(width)), Height: \(Int(height))")
        switch (Int(width), Int(height)) {
        case (205, 251): // Apple Watch Ultra 1, 2 (49mm)
            return (55, 17)
        case (208, 248): // Apple Watch Series 10 (46mm)
            return (50, 17)
        case (187, 223): // Apple Watch Series 10 (42mm)
            return (45, 17)
        case (198,242):  // Apple Watch Series 9, 8, 7 (45mm)
            return (42, 24)
        case (176,215):  // Apple Watch Series 9, 8, 7 (41mm)
            return (40, 20)
        case (184, 224): // Apple Watch Series 6 (44mm) + SE (44mm)
            return (35, 25)
        case (162, 197): // Apple Watch Series 6 (40mm) + SE (40mm)
            return (28, 20)
        default: // Fallback for unknown screen sizes
            return (50, 17)
        }
    }()
}

// Preview
#Preview {
    GlowEffect(freeze: false) // Toggle `freeze` to test behavior
}
