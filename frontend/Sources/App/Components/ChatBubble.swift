import SwiftUI

struct ChatBubble: View {
    let text: String
    let isAI: Bool

    var body: some View {
        HStack {
            if !isAI { Spacer(minLength: 48) }
            Text(text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isAI ? Color(.systemGray5) : .indigo)
                .foregroundStyle(isAI ? Color.primary : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if isAI { Spacer(minLength: 48) }
        }
    }
}
