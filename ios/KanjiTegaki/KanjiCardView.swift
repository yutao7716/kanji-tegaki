import SwiftUI
import AVFoundation

/// 漢字カード：読み・意味・つかいかた・にた意味のことば を表示
/// スクロールしなくてすむよう、入りきる大きさの文字を自動でえらぶ
struct KanjiCardView: View {
    let kanji: String
    let entry: KanjiEntry?
    /// 反対の意味の漢字を タップした ときに よばれる
    var onSelectKanji: (String) -> Void = { _ in }
    var onStrokeOrder: () -> Void = {}
    var onPractice: () -> Void = {}

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(.large)
            content(.medium)
            content(.small)
            content(.tiny)
            // それでも入らないときだけスクロール
            ScrollView { content(.tiny) }
        }
    }

    private func content(_ style: CardStyle) -> some View {
        CardContent(kanji: kanji, entry: entry, style: style,
                    onSelectKanji: onSelectKanji,
                    onStrokeOrder: onStrokeOrder,
                    onPractice: onPractice)
    }
}

/// 文字の大きさのセット
struct CardStyle {
    let kanjiBox: CGFloat
    let kanjiFont: CGFloat
    let body: CGFloat
    let label: CGFloat
    let labelWidth: CGFloat
    let spacing: CGFloat
    let padding: CGFloat

    static let large  = CardStyle(kanjiBox: 150, kanjiFont: 118, body: 24, label: 16, labelWidth: 104, spacing: 14, padding: 22)
    static let medium = CardStyle(kanjiBox: 124, kanjiFont: 98,  body: 21, label: 15, labelWidth: 96,  spacing: 11, padding: 18)
    static let small  = CardStyle(kanjiBox: 104, kanjiFont: 82,  body: 18, label: 14, labelWidth: 88,  spacing: 9,  padding: 16)
    static let tiny   = CardStyle(kanjiBox: 88,  kanjiFont: 68,  body: 16, label: 13, labelWidth: 80,  spacing: 7,  padding: 12)
}

private struct CardContent: View {
    let kanji: String
    let entry: KanjiEntry?
    let style: CardStyle
    let onSelectKanji: (String) -> Void
    let onStrokeOrder: () -> Void
    let onPractice: () -> Void
    @ObservedObject private var store = UserStore.shared
    @AppStorage("standardExplanation") private var standard = false

    private var info: KanjiInfo? { ExtrasStore.shared.info(of: kanji) }

    private var antonyms: [String] { ExtrasStore.shared.antonyms(of: kanji) }
    private var yoji: [Idiom] { ExtrasStore.shared.yoji(for: kanji) }
    private var kotowaza: [Idiom] { ExtrasStore.shared.kotowaza(for: kanji) }

    var body: some View {
        VStack(alignment: .leading, spacing: style.spacing) {
            header
            actionRow

            if let entry {
                Divider()
                row("おんよみ", color: .blue) { chips(entry.onyomi, empty: "なし") }
                row("くんよみ", color: .green) { chips(entry.kunyomi, empty: "なし") }
                if !entry.examples.isEmpty {
                    row("つかいかた", color: .purple) { chips(entry.examples) }
                }
                if !entry.synonyms.isEmpty {
                    row("にた ことば", color: .pink) { chips(entry.synonyms) }
                }
                if !antonyms.isEmpty {
                    row("はんたい", color: .red) {
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(antonyms, id: \.self) { k in
                                Button { onSelectKanji(k) } label: {
                                    Text(k)
                                        .font(.custom("HiraMinProN-W6", size: style.body + 4))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.red.opacity(0.12)))
                                        .overlay(Capsule().stroke(Color.red.opacity(0.4)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if !yoji.isEmpty {
                    row("四字じゅくご", color: .teal) { idiomChips(yoji) }
                }
                if !kotowaza.isEmpty {
                    row("ことわざ", color: .indigo) { idiomChips(kotowaza) }
                }
            } else {
                Text("この かんじは まだ じしょに のっていないよ。\nおうちの人と いっしょに しらべてみよう！")
                    .font(.system(size: style.body))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(style.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.9)))
    }

    /// 上の段：大きな漢字 ＋ 学年・いみ・よみあげ
    private var header: some View {
        HStack(alignment: .top, spacing: style.spacing + 6) {
            Text(kanji)
                .font(.custom("HiraMinProN-W6", size: style.kanjiFont))
                .minimumScaleFactor(0.5)
                .frame(width: style.kanjiBox, height: style.kanjiBox)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.brown.opacity(0.4), lineWidth: 2)
                )

            if let entry {
                VStack(alignment: .leading, spacing: style.spacing) {
                    // 説明の切りかえ（かんたん／ふつう）
                    Picker("せつめい", selection: $standard) {
                        Text("かんたん").tag(false)
                        Text("ふつう").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                    // いみ
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        label("いみ", color: .orange)
                        Text(entry.meaningText(standard: standard))
                            .font(.system(size: style.body + 2, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // 学年・画数・部首（入りきらなければ 折り返す）
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        badge(entry.gradeLabel, color: Color.yellow.opacity(0.55))
                        if let info {
                            badge("\(info.strokes)かく", color: Color.blue.opacity(0.12))
                            badge("ぶしゅ \(info.radical)" + (info.radicalName.isEmpty ? "" : "（\(info.radicalName)）"),
                                  color: Color.green.opacity(0.14))
                        }
                    }
                }
            }
        }
    }

    /// ボタンの列（カードの はば いっぱいに ならべる）
    @ViewBuilder
    private var actionRow: some View {
        if let entry {
            HStack(spacing: 10) {
                actionButton("よみあげ", icon: "speaker.wave.2.fill", color: .blue) {
                    Speaker.shared.speak(entry.speechText(standard: standard))
                }
                actionButton("かきじゅん", icon: "play.circle.fill", color: .orange) {
                    onStrokeOrder()
                }
                actionButton("れんしゅう", icon: "pencil.tip", color: .green) {
                    onPractice()
                }
                actionButton("おきにいり",
                             icon: store.isFavorite(kanji) ? "star.fill" : "star",
                             color: .yellow) {
                    store.toggleFavorite(kanji)
                }
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: style.label + 2, weight: .bold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(color))
    }

    private func actionButton(_ title: String, icon: String, color: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: style.body + 2, weight: .bold))
                Text(title)
                    .font(.system(size: style.label + 1, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }

    /// 左に見出し、右に中身 の1行
    @ViewBuilder
    private func row<Content: View>(_ title: String,
                                    color: Color,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            label(title, color: color)
                .frame(width: style.labelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func label(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: style.label, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color))
    }

    /// ことばを丸いチップで、すきまなく折り返して並べる
    @ViewBuilder
    private func chips(_ items: [String], empty: String = "") -> some View {
        if items.isEmpty {
            Text(empty)
                .font(.system(size: style.body))
                .foregroundStyle(.secondary)
        } else {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: style.body))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.gray.opacity(0.12)))
                }
            }
        }
    }
}

extension CardContent {
    /// 四字熟語・ことわざのチップ（タップすると よみと いみが 出る）
    func idiomChips(_ items: [Idiom]) -> some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(items) { idiom in
                IdiomChip(idiom: idiom, fontSize: style.body)
            }
        }
    }
}

private struct IdiomChip: View {
    let idiom: Idiom
    let fontSize: CGFloat
    @State private var showing = false
    @AppStorage("standardExplanation") private var standard = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 4) {
                Text(idiom.text)
                    .font(.system(size: fontSize))
                    .lineLimit(1)
                Image(systemName: "info.circle")
                    .font(.system(size: fontSize * 0.7))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.gray.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(idiom.text)
                    .font(.custom("HiraMinProN-W6", size: 34))
                Text(idiom.reading)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Divider()
                Text(idiom.meaningText(standard: standard))
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Speaker.shared.speak(idiom.reading + "。" + idiom.meaningText(standard: standard))
                } label: {
                    Label("よみあげ", systemImage: "speaker.wave.2.fill")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(width: 380)
        }
    }
}

/// 横にならべて、はみ出したら次の行へ折り返すレイアウト
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// 読み上げ（iPad 内蔵の日本語音声を使用、オフラインで動作）
@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.42
        synthesizer.speak(utterance)
    }
}
