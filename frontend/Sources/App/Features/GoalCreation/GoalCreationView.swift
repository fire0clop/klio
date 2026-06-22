import SwiftUI

private let gcInk = Color(hex: 0x2B2545)
private let gcSoft = Color(hex: 0x474264)
private let gcFaint = Color(hex: 0x726C92)
private func gcGrad() -> LinearGradient {
    LinearGradient(colors: [Color(hex: 0xFF7EB3), Color(hex: 0x8A7BFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct GoalCreationView: View {
    var onDone: () -> Void

    @EnvironmentObject var session: SessionStore
    @State private var phase: Phase = .input
    @State private var titleText = ""
    @State private var goalId: UUID?
    @State private var messages: [Message] = []
    @State private var answerText = ""
    @State private var isLoading = false
    @State private var aiSummary: String?
    @State private var error: String?
    @State private var lastFailedAnswer: String?
    @FocusState private var inputFocused: Bool

    enum Phase { case input, dialog, done }

    struct Message: Identifiable {
        let id = UUID()
        let text: String
        let isAI: Bool
    }

    private let suggestions = [
        "Читать 30 минут в день", "Бросить курить", "10 000 шагов",
        "Пить 2 литра воды", "Зарядка по утрам", "Меньше часа в телефоне",
    ]

    var body: some View {
        ZStack {
            KlioMeshBg()
                .onTapGesture { UIApplication.shared.dismissKeyboard() }
            VStack(spacing: 0) {
                topBar
                switch phase {
                case .input:  inputPhase
                case .dialog: dialogPhase
                case .done:   donePhase
                }
            }
            .klioReadable()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 14) {
            HStack {
                Button { onDone() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(gcSoft)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                }
                Spacer()
                Text(navTitle).font(.system(size: 16, weight: .heavy)).foregroundStyle(gcInk)
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            if phase != .done { stepBar }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
    }

    private var stepBar: some View {
        let active = phase == .input ? 0 : 1
        return HStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { i in
                Capsule()
                    .fill(i <= active ? AnyShapeStyle(gcGrad()) : AnyShapeStyle(Color(hex: 0x786EAA).opacity(0.14)))
                    .frame(height: 5)
            }
        }
    }

    private var navTitle: String {
        switch phase {
        case .input:  return L("Новая цель")
        case .dialog: return L("Уточнение")
        case .done:   return L("Готово")
        }
    }

    // MARK: - Input phase

    private var inputPhase: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle().fill(Color(hex: 0x8A7BFF).opacity(0.16)).frame(width: 88, height: 88).blur(radius: 14)
                            Circle().fill(gcGrad()).frame(width: 74, height: 74)
                                .shadow(color: Color(hex: 0x8A7BFF).opacity(0.4), radius: 15, y: 7)
                            Image(systemName: "target").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                        }
                        .padding(.top, 20)

                        Text("Какую цель поставим?")
                            .font(.system(size: 23, weight: .heavy)).foregroundStyle(gcInk)
                        Text("Напиши своими словами — ИИ\nразберёт и сделает её персональной")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(gcSoft)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Например: пробегать 5 км три раза в неделю", text: $titleText, axis: .vertical)
                            .font(.system(size: 16, weight: .medium)).foregroundStyle(gcInk).tint(Color(hex: 0x8A7BFF))
                            .padding(16)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .background(Color(hex: 0x8A7BFF).opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(inputFocused ? Color(hex: 0x8A7BFF).opacity(0.6) : Color(hex: 0x8A7BFF).opacity(0.28), lineWidth: inputFocused ? 1.8 : 1.3))
                            .shadow(color: Color(hex: 0x785AA0).opacity(inputFocused ? 0.18 : 0.12), radius: inputFocused ? 14 : 10, y: 5)
                            .animation(.easeInOut(duration: 0.2), value: inputFocused)
                            .lineLimit(3...6)
                            .focused($inputFocused)

                        if let error {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Color(hex: 0xCB5A4A))
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("ИДЕИ").font(.system(size: 11, weight: .heavy)).tracking(1.3).foregroundStyle(gcSoft)
                            .padding(.horizontal, 4)
                        FlowChips(items: suggestions) { titleText = $0 }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)

            bottomButton(title: "Продолжить",
                         disabled: isLoading || titleText.trimmingCharacters(in: .whitespaces).isEmpty) {
                Task { await startGoal() }
            }
        }
        .onAppear { inputFocused = true }
    }

    // MARK: - Dialog phase

    private var dialogPhase: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles").font(.system(size: 13)).foregroundStyle(Color(hex: 0x8A7BFF))
                            Text("ИИ задаёт пару вопросов для точности")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(gcSoft)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1))
                        .padding(.top, 10)

                        ForEach(messages) { msg in messageBubble(msg).id(msg.id) }
                        if isLoading { typingIndicator }
                        if lastFailedAnswer != nil { retryBubble }
                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
                .onChange(of: isLoading) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
            }
            replyBar
        }
    }

    private func messageBubble(_ msg: Message) -> some View {
        HStack {
            if !msg.isAI { Spacer(minLength: 48) }
            Text(msg.text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(msg.isAI ? gcInk : .white)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(
                    Group {
                        if msg.isAI {
                            AnyView(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial)
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.5), lineWidth: 1)))
                        } else {
                            AnyView(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(gcGrad()))
                        }
                    }
                )
                .shadow(color: Color(hex: 0x785AA0).opacity(msg.isAI ? 0.1 : 0.25), radius: 6, y: 3)
            if msg.isAI { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 16)
    }

    private var retryBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Label("Сеть прервалась", systemImage: "wifi.slash")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: 0xCB5A4A))
                Button {
                    Task {
                        if let failed = lastFailedAnswer {
                            lastFailedAnswer = nil
                            await retrySendAnswer(failed)
                        }
                    }
                } label: {
                    Label("Отправить снова", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color(hex: 0xCB5A4A)).foregroundStyle(.white).clipShape(Capsule())
                }
            }
            .padding(12).background(Color(hex: 0xCB5A4A).opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer(minLength: 48)
        }
        .padding(.horizontal, 16)
    }

    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(gcFaint).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.5), lineWidth: 1))
            Spacer(minLength: 48)
        }
        .padding(.horizontal, 16)
    }

    private var replyBar: some View {
        HStack(spacing: 10) {
            TextField("Ответить…", text: $answerText, axis: .vertical)
                .font(.system(size: 15, weight: .medium)).foregroundStyle(gcInk).tint(Color(hex: 0x8A7BFF))
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.55), lineWidth: 1))
                .lineLimit(1...4)

            let inactive = answerText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading
            Button { Task { await sendAnswer() } } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(inactive ? gcFaint : .white)
                    .frame(width: 44, height: 44)
                    .background(inactive ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(gcGrad()), in: Circle())
            }
            .disabled(inactive)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Done phase

    private var donePhase: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle().fill(Color(hex: 0x4FB89A).opacity(0.18)).frame(width: 150, height: 150).blur(radius: 22)
                Circle().fill(LinearGradient(colors: [Color(hex: 0x8FD9B5), Color(hex: 0x4FB89A)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 116, height: 116)
                    .shadow(color: Color(hex: 0x4FB89A).opacity(0.4), radius: 18, y: 8)
                Image(systemName: "checkmark").font(.system(size: 44, weight: .heavy)).foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                Text("Цель создана!").font(.system(size: 24, weight: .heavy)).foregroundStyle(gcInk)
                Text(aiSummary ?? "ИИ разобрал твою цель и готов отслеживать прогресс")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(gcSoft)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }

            Button { onDone() } label: {
                Text("Начать отслеживание")
                    .font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 17)
                    .background(gcGrad(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color(hex: 0x8A7BFF).opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(KlioPress(scale: 0.97))
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    // MARK: - Bottom button

    private func bottomButton(title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if isLoading { ProgressView().tint(.white) }
                else { Text(LocalizedStringKey(title)).font(.system(size: 16, weight: .heavy)) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 17)
            .foregroundStyle(disabled && !isLoading ? gcFaint.opacity(0.8) : .white)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(disabled && !isLoading ? AnyShapeStyle(Color.white.opacity(0.22)) : AnyShapeStyle(gcGrad()))
            )
            .overlay(disabled && !isLoading ? RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.5), lineWidth: 1) : nil)
            .shadow(color: disabled ? .clear : Color(hex: 0x8A7BFF).opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(KlioPress(scale: 0.97))
        .disabled(disabled)
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: - Network

    private func startGoal() async {
        if Demo.enabled {
            messages.append(Message(text: "Сколько страниц в день хочешь читать?", isAI: true))
            withAnimation { phase = .dialog }
            return
        }
        isLoading = true; error = nil
        do {
            struct Body: Encodable { let title: String }
            let resp: GoalStartResponse = try await APIClient.shared.request(
                "goals/start", method: "POST", body: Body(title: titleText), token: session.token)
            goalId = resp.goalId
            if resp.questionIndex == -1 {
                aiSummary = resp.summary
                withAnimation { phase = .done }
            } else {
                messages.append(Message(text: resp.question, isAI: true))
                withAnimation { phase = .dialog }
            }
        } catch {
            self.error = "Не удалось создать цель. Проверь соединение."
        }
        isLoading = false
    }

    private func sendAnswer() async {
        guard goalId != nil else { return }
        let answer = answerText.trimmingCharacters(in: .whitespaces)
        messages.append(Message(text: answer, isAI: false))
        answerText = ""
        await retrySendAnswer(answer)
    }

    private func retrySendAnswer(_ answer: String) async {
        if Demo.enabled {
            aiSummary = "Готово! Буду каждый день спрашивать, сколько страниц ты прочитал, и подстраивать цель под твой прогресс."
            withAnimation { phase = .done }
            return
        }
        guard let id = goalId else { return }
        isLoading = true; lastFailedAnswer = nil
        do {
            struct Body: Encodable { let answer: String }
            let resp: GoalAnswerResponse = try await APIClient.shared.request(
                "goals/\(id)/answer", method: "POST", body: Body(answer: answer), token: session.token)
            if resp.done {
                aiSummary = resp.summary
                withAnimation { phase = .done }
            } else if let q = resp.question {
                messages.append(Message(text: q, isAI: true))
            }
        } catch {
            lastFailedAnswer = answer
        }
        isLoading = false
    }
}

// MARK: - Wrapping chips

struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        var width: CGFloat = 0
        var rows: [[String]] = [[]]
        let limit: CGFloat = UIScreen.main.bounds.width - 40
        for item in items {
            let w = item.size(withAttributes: [.font: UIFont.systemFont(ofSize: 14, weight: .medium)]).width + 46
            if width + w > limit {
                rows.append([item]); width = w
            } else {
                rows[rows.count - 1].append(item); width += w
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        Button { onTap(item) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color(hex: 0x8A7BFF))
                                Text(LocalizedStringKey(item)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0x2B2545))
                            }
                            .padding(.horizontal, 13).padding(.vertical, 9)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color(hex: 0x8A7BFF).opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(KlioPress(scale: 0.96))
                    }
                }
            }
        }
    }
}
