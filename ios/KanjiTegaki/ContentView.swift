import SwiftUI
import PencilKit

/// メイン画面：左（または上）が手書きマス、右（または下）が結果
/// 開く画面の しゅるい
enum ActiveSheet: Identifiable {
    case search
    case history
    case strokeOrder(String)
    case practice(String)
    case test

    var id: String {
        switch self {
        case .search: return "search"
        case .history: return "history"
        case .strokeOrder(let k): return "order-\(k)"
        case .practice(let k): return "practice-\(k)"
        case .test: return "test"
        }
    }
}

struct ContentView: View {
    @ObservedObject private var store = UserStore.shared
    @State private var sheet: ActiveSheet?
    @State private var clearToken = 0
    @State private var undoToken = 0
    @State private var drawing = PKDrawing()
    @State private var candidates: [String] = []
    @State private var selected: String?
    @State private var isRecognizing = false
    @State private var recognizeTask: Task<Void, Never>?
    @State private var message = ContentView.startMessage

    private static let startMessage = "マスの なかに かんじを 1もじ かいてね"

    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width > geo.size.height
            let layout = isWide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                : AnyLayout(VStackLayout(spacing: 20))

            layout {
                writingArea
                    .frame(maxWidth: isWide ? geo.size.width * 0.46 : .infinity,
                           maxHeight: isWide ? .infinity : geo.size.height * 0.55)
                resultArea
            }
            .padding(24)
        }
        .background(Color(red: 0.98, green: 0.96, blue: 0.90).ignoresSafeArea())
        .preferredColorScheme(.light)
        .onChange(of: selected) { _, newValue in
            if let k = newValue { store.record(k) }
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .search:
                SearchView { selected = $0 }
            case .history:
                HistoryView { selected = $0 }
            case .strokeOrder(let k):
                StrokeOrderView(kanji: k)
            case .practice(let k):
                PracticeView(kanji: k, mode: .trace)
            case .test:
                TestSessionView()
            }
        }
    }

    /// 左上の メニュー（さがす・りれき・テスト）
    private var menuButton: some View {
        Menu {
            Button { sheet = .search } label: {
                Label("かんじを さがす", systemImage: "square.grid.3x3")
            }
            Button { sheet = .history } label: {
                Label("りれき・おきにいり", systemImage: "clock.arrow.circlepath")
            }
            Button { sheet = .test } label: {
                Label("かきとり テスト", systemImage: "pencil.and.list.clipboard")
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.brown)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Color.white))
                .overlay(Circle().stroke(Color.brown.opacity(0.4), lineWidth: 2))
        }
        .accessibilityLabel("メニュー")
    }

    // MARK: - 手書きエリア

    private var writingArea: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                menuButton
                Text("かんじ てがき じしょ")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }

            ZStack {
                WritingGrid()
                HandwritingCanvas(clearToken: clearToken, undoToken: undoToken) { newDrawing in
                    drawing = newDrawing
                    if newDrawing.strokes.isEmpty {
                        recognizeTask?.cancel()
                        candidates = []
                        message = Self.startMessage
                    } else {
                        scheduleRecognition()
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.brown.opacity(0.6), lineWidth: 3)
            )

            HStack(spacing: 16) {
                Button {
                    clearCanvas()
                } label: {
                    Label("けす", systemImage: "eraser")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button {
                    undoToken += 1
                } label: {
                    Label("1かく もどす", systemImage: "arrow.uturn.backward")
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(drawing.strokes.isEmpty)

                Button {
                    recognizeNow()
                } label: {
                    Label("しらべる", systemImage: "magnifyingglass")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(drawing.strokes.isEmpty)
            }

            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - 結果エリア

    private var resultArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isRecognizing {
                ProgressView("かんがえちゅう…")
                    .font(.title3)
            }

            if !candidates.isEmpty {
                Text("これかな？")
                    .font(.title3.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(candidates, id: \.self) { c in
                            CandidateButton(
                                kanji: c,
                                isSelected: c == selected,
                                inDictionary: KanjiDictionary.shared.lookup(c) != nil
                            ) {
                                selected = c
                            }
                        }
                    }
                    .padding(4)
                }
            }

            if let selected {
                KanjiCardView(kanji: selected,
                              entry: KanjiDictionary.shared.lookup(selected),
                              onSelectKanji: { self.selected = $0 },
                              onStrokeOrder: { sheet = .strokeOrder(selected) },
                              onPractice: { sheet = .practice(selected) })
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - 認識処理

    /// 書き終わってから少し待って自動で認識する
    private func scheduleRecognition() {
        recognizeTask?.cancel()
        guard !drawing.strokes.isEmpty else { return }
        recognizeTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await recognize()
        }
    }

    private func recognizeNow() {
        recognizeTask?.cancel()
        recognizeTask = Task { await recognize() }
    }

    private func recognize() async {
        guard !drawing.strokes.isEmpty else { return }
        isRecognizing = true

        // ① 書き順データとの比較（手書き1文字に強い）
        let strokeResult = StrokeRecognizer.shared.recognize(drawing)

        // ② Apple の文字認識（読めたときだけ参考にする）
        var visionResult: [String] = []
        if let data = RecognitionImage.make(from: drawing) {
            visionResult = await Task.detached(priority: .userInitiated) {
                KanjiRecognizer.recognize(pngData: data)
            }.value
        }
        isRecognizing = false
        guard !Task.isCancelled else { return }

        // 両方の結果に入っている字を先頭に、そのあと書き順比較の結果を並べる
        var result: [String] = []
        for k in visionResult where strokeResult.contains(k) && !result.contains(k) {
            result.append(k)
        }
        for k in strokeResult where !result.contains(k) {
            result.append(k)
        }
        result = Array(result.prefix(8))

        candidates = result
        if result.isEmpty {
            selected = nil
            message = "うまく よめなかったよ。マスいっぱいに 大きく かいてみてね"
        } else {
            // 辞書にある候補を優先して選ぶ
            selected = result.first { KanjiDictionary.shared.lookup($0) != nil } ?? result.first
            message = "ちがう ときは「これかな？」から えらんでね"
        }
    }

    private func clearCanvas() {
        recognizeTask?.cancel()
        clearToken += 1
        drawing = PKDrawing()
        candidates = []
        selected = nil
        isRecognizing = false
        message = Self.startMessage
    }
}

// MARK: - 部品

/// 習字マスのような背景（十字の点線）
struct WritingGrid: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Color.white
                Path { p in
                    p.move(to: CGPoint(x: w / 2, y: 0))
                    p.addLine(to: CGPoint(x: w / 2, y: h))
                    p.move(to: CGPoint(x: 0, y: h / 2))
                    p.addLine(to: CGPoint(x: w, y: h / 2))
                }
                .stroke(Color.red.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
            }
        }
    }
}

/// 認識候補のボタン（辞書にない字はうすく表示）
struct CandidateButton: View {
    let kanji: String
    let isSelected: Bool
    let inDictionary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(kanji)
                .font(.custom("HiraMinProN-W6", size: 40))
                .foregroundStyle(inDictionary ? Color.primary : Color.secondary)
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isSelected ? Color.yellow.opacity(0.5) : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isSelected ? Color.orange : Color.gray.opacity(0.4),
                                lineWidth: isSelected ? 4 : 1)
                )
        }
        .buttonStyle(.plain)
    }
}
