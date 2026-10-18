import SwiftUI
import PencilKit

/// 練習用キャンバス：1画 書くたびに onStroke が よばれる。false を かえすと その1画を けす
struct PracticeCanvas: UIViewRepresentable {
    var resetToken: Int
    /// 書いた1画の点（マスの左上が 0、右下が 1）
    var onStroke: ([CGPoint]) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 18)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.isScrollEnabled = false
        canvas.delegate = context.coordinator
        context.coordinator.onStroke = onStroke
        context.coordinator.lastResetToken = resetToken
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.onStroke = onStroke
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            context.coordinator.isUpdating = true
            canvas.drawing = PKDrawing()
            context.coordinator.isUpdating = false
            context.coordinator.keptCount = 0
        }
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onStroke: (([CGPoint]) -> Bool)?
        var lastResetToken = 0
        var isUpdating = false
        var keptCount = 0

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isUpdating else { return }
            let strokes = canvasView.drawing.strokes
            guard strokes.count > keptCount, let stroke = strokes.last else {
                keptCount = strokes.count
                return
            }
            let size = canvasView.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            let points = stroke.path.map { p -> CGPoint in
                let loc = p.location.applying(stroke.transform)
                return CGPoint(x: loc.x / size.width, y: loc.y / size.height)
            }
            let keep = onStroke?(points) ?? true
            if keep {
                keptCount = strokes.count
            } else {
                keptCount = strokes.count - 1
                DispatchQueue.main.async { [weak self, weak canvasView] in
                    guard let self, let canvasView else { return }
                    self.isUpdating = true
                    canvasView.drawing = PKDrawing(strokes: Array(canvasView.drawing.strokes.prefix(self.keptCount)))
                    self.isUpdating = false
                }
            }
        }
    }
}

enum PracticeMode {
    case trace   // なぞり練習（お手本が うすく 見える）
    case test    // 書き取り（お手本なし）
}

/// なぞり練習・書き取り
struct PracticeView: View {
    let kanji: String
    let mode: PracticeMode
    /// 書き取りテストの 問題文（なければ ふつうの練習）
    var prompt: String? = nil
    /// テストで「つぎへ」を おした ときに よばれる（まちがえた回数）
    var onNext: ((Int) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var done = 0
    @State private var mistakes = 0
    @State private var strokeMistakes = 0
    @State private var feedback = ""
    @State private var feedbackIsGood = true
    @State private var hintIndex: Int?
    @State private var hintProgress: Double = 0
    @State private var resetToken = 0
    @State private var currentMode: PracticeMode

    init(kanji: String, mode: PracticeMode, prompt: String? = nil, onNext: ((Int) -> Void)? = nil) {
        self.kanji = kanji
        self.mode = mode
        self.prompt = prompt
        self.onNext = onNext
        _currentMode = State(initialValue: mode)
    }

    private var strokes: [[CGPoint]] { StrokeRecognizer.shared.rawStrokes(for: kanji) }
    private var finished: Bool { done >= strokes.count && !strokes.isEmpty }
    private var isTestSession: Bool { onNext != nil }

    var body: some View {
        VStack(spacing: 14) {
            header

            if let prompt {
                Text(prompt)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
            }

            Text(feedback.isEmpty ? " " : feedback)
                .font(.title2.bold())
                .foregroundStyle(feedbackIsGood ? Color.green : Color.red)

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ZStack(alignment: .topLeading) {
                    WritingGrid()
                    guideLayer(side: side)
                    PracticeCanvas(resetToken: resetToken) { points in
                        judge(points)
                    }
                    .allowsHitTesting(!finished)
                    if finished {
                        finishedOverlay(side: side)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.brown.opacity(0.6), lineWidth: 3))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Text("\(min(done, strokes.count)) / \(strokes.count) かく")
                .font(.title3)
                .foregroundStyle(.secondary)

            controls
        }
        .padding(24)
        .background(Color(red: 0.98, green: 0.96, blue: 0.90))
    }

    // MARK: - 部品

    private var header: some View {
        HStack {
            Text(isTestSession ? "かきとり テスト" : (currentMode == .trace ? "なぞって れんしゅう" : "見ないで かいてみよう"))
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Spacer()
            if !isTestSession {
                Picker("", selection: $currentMode) {
                    Text("なぞる").tag(PracticeMode.trace)
                    Text("見ないで").tag(PracticeMode.test)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .onChange(of: currentMode) { _, _ in restart() }
                Button("とじる") { dismiss() }
                    .font(.title3.bold())
                    .padding(.leading, 12)
            }
        }
    }

    @ViewBuilder
    private func guideLayer(side: CGFloat) -> some View {
        let style = StrokeStyle(lineWidth: side * 0.06, lineCap: .round, lineJoin: .round)
        ZStack(alignment: .topLeading) {
            if currentMode == .trace {
                ForEach(strokes.indices, id: \.self) { i in
                    StrokePath(points: strokes[i])
                        .stroke(Color.gray.opacity(i < done ? 0.08 : 0.22), style: style)
                }
                // つぎに 書く 線の はじまり
                if done < strokes.count, let start = strokes[done].first {
                    Text("\(done + 1)")
                        .font(.system(size: side * 0.04, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: side * 0.07, height: side * 0.07)
                        .background(Circle().fill(Color.green))
                        .position(x: start.x * side, y: start.y * side)
                }
            }
            // ヒント（赤い線が 書く向きに のびる）
            if let h = hintIndex, h < strokes.count {
                StrokePath(points: strokes[h])
                    .trim(from: 0, to: hintProgress)
                    .stroke(Color.red.opacity(0.7), style: style)
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }

    private func finishedOverlay(side: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(mistakes == 0 ? "💮" : "⭕️")
                .font(.system(size: side * 0.3))
            Text(mistakes == 0 ? "かんぺき！" : "できたね！（まちがい \(mistakes)かい）")
                .font(.system(size: side * 0.05, weight: .bold))
        }
        .frame(width: side, height: side)
        .background(Color.white.opacity(0.75))
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button { restart() } label: {
                Label("さいしょから", systemImage: "arrow.counterclockwise")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button { showHint(done) } label: {
                Label("ヒント", systemImage: "lightbulb")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .disabled(finished)

            if isTestSession {
                Button { onNext?(mistakes) } label: {
                    Label(finished ? "つぎへ" : "わからない", systemImage: "arrow.right")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
    }

    // MARK: - はんてい

    private func judge(_ points: [CGPoint]) -> Bool {
        guard done < strokes.count, points.count >= 2 else { return false }
        let user = StrokeRecognizer.resample(points)
        var length: CGFloat = 0
        for i in 1..<user.count {
            length += hypot(user[i].x - user[i - 1].x, user[i].y - user[i - 1].y)
        }
        if length < 0.03 { return false }   // ちょんと さわっただけ

        // なぞる ときは きびしめ、見ないで 書く ときは ゆるめ
        let threshold: CGFloat = currentMode == .trace ? 0.15 : 0.2
        let target = strokes[done]
        if StrokeRecognizer.strokeDistance(user, target) < threshold {
            done += 1
            strokeMistakes = 0
            hintIndex = nil
            feedbackIsGood = true
            feedback = done >= strokes.count ? "できた！" : ["いいね！", "そのちょうし！", "じょうず！"].randomElement()!
            return true
        }

        mistakes += 1
        strokeMistakes += 1
        feedbackIsGood = false
        if StrokeRecognizer.strokeDistance(Array(user.reversed()), target) < threshold {
            feedback = "かく むきが ぎゃくだよ"
        } else if strokes.indices.contains(where: { $0 > done && StrokeRecognizer.strokeDistance(user, strokes[$0]) < threshold }) {
            feedback = "かきじゅんが ちがうよ"
        } else {
            feedback = "もういちど かいてみよう"
        }
        if currentMode == .trace || strokeMistakes >= 2 {
            showHint(done)
        }
        return false
    }

    private func showHint(_ index: Int) {
        guard index < strokes.count else { return }
        hintIndex = index
        hintProgress = 0
        withAnimation(.linear(duration: 0.8)) {
            hintProgress = 1
        }
    }

    private func restart() {
        done = 0
        mistakes = 0
        strokeMistakes = 0
        feedback = ""
        hintIndex = nil
        resetToken += 1
    }
}

/// 学年を えらんで 5もんの 書き取りテスト
struct TestSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var grade = 1
    @State private var questions: [KanjiEntry] = []
    @State private var index = 0
    @State private var results: [(kanji: String, mistakes: Int)] = []
    @State private var started = false

    private let questionCount = 5

    var body: some View {
        Group {
            if !started {
                setupView
            } else if index < questions.count {
                let q = questions[index]
                PracticeView(kanji: q.kanji, mode: .test, prompt: prompt(for: q)) { m in
                    results.append((q.kanji, m))
                    index += 1
                }
                .id(index)
            } else {
                resultView
            }
        }
        .background(Color(red: 0.98, green: 0.96, blue: 0.90))
    }

    private var setupView: some View {
        VStack(spacing: 28) {
            HStack {
                Text("かきとり テスト")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Spacer()
                Button("とじる") { dismiss() }
                    .font(.title3.bold())
            }
            Text("なんねんせいの かんじに する？")
                .font(.title2)
            Picker("がくねん", selection: $grade) {
                ForEach(1...6, id: \.self) { g in Text("\(g)ねんせい").tag(g) }
            }
            .pickerStyle(.segmented)
            Button { start() } label: {
                Text("\(questionCount)もん スタート！")
                    .font(.title.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            Spacer()
        }
        .padding(28)
    }

    private var resultView: some View {
        VStack(spacing: 20) {
            let perfect = results.filter { $0.mistakes == 0 }.count
            Text("けっか")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("\(results.count)もん中 \(perfect)もん かんぺき！")
                .font(.title)
            HStack(spacing: 16) {
                ForEach(results.indices, id: \.self) { i in
                    VStack(spacing: 6) {
                        Text(results[i].kanji)
                            .font(.custom("HiraMinProN-W6", size: 56))
                        Text(results[i].mistakes == 0 ? "💮" : "⭕️")
                            .font(.title)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                }
            }
            HStack(spacing: 16) {
                Button { start() } label: {
                    Text("もういちど").font(.title2.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent).tint(.orange)
                Button { dismiss() } label: {
                    Text("おわる").font(.title2.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent).tint(.gray)
            }
            Spacer()
        }
        .padding(28)
    }

    private func start() {
        let pool = KanjiDictionary.shared.entries(grade: grade)
            .filter { !StrokeRecognizer.shared.rawStrokes(for: $0.kanji).isEmpty }
        questions = Array(pool.shuffled().prefix(questionCount))
        results = []
        index = 0
        started = true
    }

    /// 「□手（みぎて）」のように、こたえの字を かくした 問題文
    private func prompt(for entry: KanjiEntry) -> String {
        if let example = entry.examples.first {
            let masked = example.replacingOccurrences(of: entry.kanji, with: "□")
            return "「\(masked)」の □ に 入る かんじを かこう"
        }
        let reading = (entry.kunyomi.first ?? entry.onyomi.first ?? "")
        return "「\(reading)」と よむ かんじを かこう"
    }
}
