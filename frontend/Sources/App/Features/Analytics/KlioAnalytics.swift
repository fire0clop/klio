import SwiftUI

// Полный разбор от ИИ (пилляр «аналитика») на языке Klio.

struct KlioAnalytics: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var insights: [InsightResponse] = []
    @State private var loading = true
    @State private var refreshing = false

    var body: some View {
        ZStack(alignment: .top) {
            Klio.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 14) {
                        if loading {
                            ProgressView().tint(Klio.tint(3)).padding(.top, 60)
                        } else if insights.isEmpty {
                            emptyState
                        } else {
                            ForEach(Array(insights.enumerated()), id: \.element.id) { i, item in
                                insightCard(item, i)
                            }
                        }
                        Spacer().frame(height: 24)
                    }
                    .padding(.horizontal, 20).padding(.top, 16)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task { await load() }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Klio.gradient(3)
                .overlay(
                    GeometryReader { geo in
                        Circle().fill(.white.opacity(0.12)).frame(width: 120, height: 120)
                            .offset(x: geo.size.width - 70, y: -30)
                    }
                )
            VStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 24)).foregroundStyle(.white)
                Text("Разбор от ИИ").font(.klioTitle(22, .bold)).foregroundStyle(.white)
                Text("на основе твоих целей и самочувствия")
                    .font(.klioText(12, .medium)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(.top, 16).padding(.bottom, 24)

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white).frame(width: 32, height: 32)
                            .background(.white.opacity(0.22)).clipShape(Circle())
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .frame(maxWidth: .infinity).frame(height: 190)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous))
        .ignoresSafeArea(edges: .top)
    }

    private func insightCard(_ item: InsightResponse, _ i: Int) -> some View {
        KlioCard {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(Klio.tint(i).opacity(0.14)).frame(width: 36, height: 36)
                    Image(systemName: "lightbulb.fill").font(.system(size: 14)).foregroundStyle(Klio.tint(i))
                }
                Text(item.content).font(.klioText(14)).foregroundStyle(Klio.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 40)
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 42)).foregroundStyle(Klio.tint(3).opacity(0.6))
            Text("Пока недостаточно данных")
                .font(.klioTitle(17, .semibold)).foregroundStyle(Klio.ink)
            Text("Отмечай цели и самочувствие несколько дней —\nИИ найдёт закономерности и покажет их здесь.")
                .font(.klioText(13)).foregroundStyle(Klio.inkSoft).multilineTextAlignment(.center)
            Button { Task { await refresh() } } label: {
                HStack(spacing: 6) {
                    if refreshing { ProgressView().tint(.white).scaleEffect(0.8) }
                    else { Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold)) }
                    Text("Обновить").font(.klioText(14, .semibold))
                }
                .foregroundStyle(.white).padding(.horizontal, 22).padding(.vertical, 12)
                .background(Klio.gradient(3)).clipShape(Capsule())
            }
            .buttonStyle(.plain).disabled(refreshing)
            .padding(.top, 6)
        }
    }

    // MARK: Data

    private func load() async {
        loading = true
        if Demo.enabled { insights = Demo.insights(); loading = false; return }
        insights = (try? await APIClient.shared.request("analytics/insights", token: session.token)) ?? []
        loading = false
    }

    private func refresh() async {
        refreshing = true
        let fresh: [InsightResponse]? = try? await APIClient.shared.request(
            "analytics/insights/refresh", method: "POST", token: session.token)
        if let fresh { insights = fresh }
        refreshing = false
    }
}
