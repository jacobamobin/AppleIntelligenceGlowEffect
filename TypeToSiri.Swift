//
//  TypeToSiri.swift
//  WIP
//
//  Created by Jacob Mobin on 1/10/25.
//



import SwiftUI
import Combine

struct TypeToSiri: View {
    @State private var tempText: String = ""
    @State private var x: Int = 0
    @State private var timerCancellable: AnyCancellable?

    private var gradientsPill: [Gradient] = [
        Gradient(colors: [
            Color(hex: "#FF6778"), // PINK
            Color(hex: "#FFBA71")  // YELLOW
        ]),
        Gradient(colors: [
            Color(hex: "#FFBA71"), // YELLOW
            Color(hex: "#8D99FF")  // BLUE
        ]),
        Gradient(colors: [
            Color(hex: "#8D99FF"), // BLUE
            Color(hex: "#F5B9EA")  // WHITE
        ]),
        Gradient(colors: [
            Color(hex: "#F5B9EA"), // WHITE
            Color(hex: "#FF6778")  // PINK
        ])
    ]
    
    private var gradientsKeyboard: [Gradient] = [
        Gradient(colors: [
            Color(hex: "#A0414B"), // Further Darkened Pink
            Color(hex: "#A07749")  // Further Darkened Yellow
        ]),
        Gradient(colors: [
            Color(hex: "#A07749"), // Further Darkened Yellow
            Color(hex: "#5A6299")  // Further Darkened Blue
        ]),
        Gradient(colors: [
            Color(hex: "#5A6299"), // Further Darkened Blue
            Color(hex: "#9E7296")  // Further Darkened White
        ]),
        Gradient(colors: [
            Color(hex: "#9E7296"), // Further Darkened White
            Color(hex: "#A0414B")  // Further Darkened Pink
        ])
    ]
    
    var body: some View {
        ZStack {
            ZStack {
                ZStack {
                    Spacer()
                    Rectangle()
                        .padding(.top, UIScreen.main.bounds.height / 2)
                        .frame(width: UIScreen.main.bounds.width + 50, height: UIScreen.main.bounds.height)
                        .foregroundStyle(
                            LinearGradient(
                                gradient: gradientsKeyboard[x],
                                startPoint: .leading,
                                endPoint: .trailing
                        ))
                        .animation(.smooth(duration: 4), value: x)
                        .blur(radius: 20)
                }.padding(.top, UIScreen.main.bounds.height / 2 + 50)
                
                
                ZStack {
                    ZStack {
                        HStack {
                            Image("Siri_Icon")
                                .padding(.leading, 10)
                                //.brightness()
                            
                            Spacer()
                        }
                        
                    }
                    
                    TextField("Ask Siri...", text: $tempText)
                        .padding(.leading, 30)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color(hex: "#483838").opacity(0.6))
                                .brightness(0.5)
                        )
                        .foregroundColor(.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 25)
                                .stroke(
                                    LinearGradient(
                                        gradient: gradientsPill[x],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 5
                                ).blur(radius: 5)
                                .animation(.smooth(duration: 4), value: x)
                        )
                        .shadow(color: Color.white.opacity(0.3), radius: 5)
                }
                .padding(40)
                .padding(.top, UIScreen.main.bounds.height / 2 + 50)
            }
        }
        .background(Image("Wallpaper"))
        .onAppear {
            // Start timer for gradient cycling
            timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    x = (x + 1) % gradientsPill.count
                }
        }
        .onDisappear {
            // Cancel timer to prevent memory leaks
            timerCancellable?.cancel()
            timerCancellable = nil
        }
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
    TypeToSiri()
}
