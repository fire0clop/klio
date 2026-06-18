import SwiftUI

// Экран загрузки в фирменном стекле: рисующаяся дуга + самоцвет-жемчужина + вордмарк.
// Перекликается с иконкой приложения (капля-кристалл в кольце прогресса).

struct KlioSplash: View {
    @State private var draw = false
    @State private var spin = false
    @State private var pulse = false
    @State private var appear = false

    private let pink = Color(hex: 0xFF7EB3)
    private let purple = Color(hex: 0x8A7BFF)

    var body: some View {
        ZStack {
            KlioMeshBg().ignoresSafeArea()

            // мягкое розово-фиолетовое свечение за знаком
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFF9ECF).opacity(0.35), .clear],
                                     center: .center, startRadius: 0, endRadius: 190))
                .frame(width: 380, height: 380)
                .scaleEffect(pulse ? 1.08 : 0.92)
                .blur(radius: 12)

            VStack(spacing: 26) {
                ZStack {
                    Circle().stroke(.white.opacity(0.5), lineWidth: 8)
                        .frame(width: 104, height: 104)

                    // рисующаяся дуга в бренд-градиенте, бесконечно вращается
                    Circle()
                        .trim(from: 0, to: draw ? 1 : 0)
                        .stroke(
                            AngularGradient(gradient: Gradient(colors: [pink, purple, pink]),
                                            center: .center,
                                            startAngle: .degrees(-90), endAngle: .degrees(270)),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 104, height: 104)
                        .rotationEffect(.degrees(spin ? 360 : 0))

                    // центральный самоцвет-жемчужина с бликом
                    GemDrop()
                        .fill(LinearGradient(colors: [pink, Color(hex: 0xB07BE8), Color(hex: 0x7E6BFF)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(
                            Capsule().fill(.white.opacity(0.55))
                                .frame(width: 5, height: 16)
                                .rotationEffect(.degrees(-20))
                                .offset(x: -6, y: -3)
                                .blur(radius: 1)
                                .clipShape(GemDrop())
                        )
                        .frame(width: 42, height: 54)
                        .scaleEffect(pulse ? 1.12 : 0.92)
                        .shadow(color: purple.opacity(0.35), radius: 9, y: 3)
                }
                .scaleEffect(appear ? 1 : 0.85)

                Text("Klio")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x2B2545))
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 8)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { appear = true }
            withAnimation(.easeInOut(duration: 0.9)) { draw = true }
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
