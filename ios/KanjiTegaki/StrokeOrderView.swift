import SwiftUI

/// お手本の1画（0〜1 の点列）を、なめらかな線にする
struct StrokePath: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard !points.isEmpty else { return p }
        let pts = points.map {
            CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height)
        }
        p.move(to: pts[0])
        if pts.count < 3 {
            for q in pts.dropFirst() { p.addLine(to: q) }
            return p
        }
        for i in 1..<(pts.count - 1) {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2,
                              y: (pts[i].y + pts[i + 1].y) / 2)
            p.addQuadCurve(to: mid, control: pts[i])
        }
        p.addLine(to: pts[pts.count - 1])
        return p
    }
}

/// 書き順アニメーション
struct StrokeOrderView: View {
    let kanji: String
    @Environment(\.dismiss) private var dismiss

    @State private var progress: Double = 0
    @State private var current = -1
    @State private var slow = false
    @State private var task: Task<Void, Never>?

    private var strokes: [[CGPoint]] { StrokeRecognizer.shared.rawStrokes(for: kanji) }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("「\(kanji)」の かきじゅん")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Spacer()
                Button("とじる") { dismiss() }
                    .font(.title3.bold())
            }
            Text("\(strokes.count)かく")
                .font(.title2)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ZStack(alignment: .topLeading) {
                    WritingGrid()
                    // うすい お手本
                    ForEach(strokes.indices, id: \.self) { i in
                        StrokePath(points: strokes[i])
                            .stroke(Color.gray.opacity(0.18), style: strokeStyle(side))
                    }
                    // 書いていく 線
                    ForEach(strokes.indices, id: \.self) { i in
                        StrokePath(points: strokes[i])
                            .trim(from: 0, to: min(max(progress - Double(i), 0), 1))
                            .stroke(i == current ? Color.red : Color.black, style: strokeStyle(side))
                    }
                    // 書きはじめの 番号
                    ForEach(strokes.indices, id: \.self) { i in
                        if progress > Double(i), let start = strokes[i].first {
                            Text("\(i + 1)")
                                .font(.system(size: side * 0.045, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: side * 0.075, height: side * 0.075)
                                .background(Circle().fill(Color.orange))
                                .position(x: start.x * side, y: start.y * side)
                        }
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.brown.opacity(0.6), lineWidth: 3))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 16) {
                Button { play() } label: {
                    Label("もういちど", systemImage: "arrow.counterclockwise")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button { step() } label: {
                    Label("1かくずつ", systemImage: "forward.frame")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Toggle("ゆっくり", isOn: $slow)
                    .font(.title3.bold())
                    .frame(width: 170)
            }
        }
        .padding(28)
        .background(Color(red: 0.98, green: 0.96, blue: 0.90))
        .onAppear { play() }
        .onDisappear { task?.cancel() }
    }

    private func strokeStyle(_ side: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: side * 0.055, lineCap: .round, lineJoin: .round)
    }

    private func play() {
        task?.cancel()
        progress = 0
        current = -1
        let count = strokes.count
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            for i in 0..<count {
                if Task.isCancelled { return }
                current = i
                let duration = slow ? 1.2 : 0.6
                withAnimation(.linear(duration: duration)) {
                    progress = Double(i + 1)
                }
                try? await Task.sleep(for: .milliseconds(Int(duration * 1000) + 250))
            }
            if !Task.isCancelled { current = -1 }
        }
    }

    private func step() {
        task?.cancel()
        if progress >= Double(strokes.count) { progress = 0 }
        let i = Int(progress.rounded(.down))
        current = i
        withAnimation(.linear(duration: slow ? 1.2 : 0.6)) {
            progress = Double(i + 1)
        }
    }
}
