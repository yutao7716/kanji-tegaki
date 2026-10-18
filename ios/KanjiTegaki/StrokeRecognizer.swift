import Foundation
import PencilKit
import CoreGraphics

/// 手書きの「線（ストローク）」を、お手本の書き順データ（strokes.json）と比べて漢字を当てる。
/// お手本データは KanjiVG（CC BY-SA 3.0, Ulrich Apel）をもとに作成。
/// 画数・線の形・位置・向きをくらべるので、子どもの手書き1文字に強い。
@MainActor
final class StrokeRecognizer {
    static let shared = StrokeRecognizer()

    typealias Stroke = [CGPoint]
    private nonisolated static let sampleCount = 16

    /// 漢字 → 正規化ずみのお手本ストローク
    private var templates: [String: [Stroke]] = [:]
    /// 漢字 → マスの中の位置そのままのお手本（0〜1）。書き順アニメーションと練習で使う
    private var raw: [String: [Stroke]] = [:]

    func rawStrokes(for kanji: String) -> [Stroke] {
        raw[kanji] ?? []
    }

    private init() {
        guard let url = Bundle.main.url(forResource: "strokes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [[[Double]]]].self, from: data) else {
            print("strokes.json が読み込めません")
            return
        }
        for (kanji, strokes) in decoded {
            let s: [Stroke] = strokes.map { stroke in
                stroke.map { CGPoint(x: $0[0], y: $0[1]) }
            }
            self.raw[kanji] = s
            templates[kanji] = Self.normalize(s)
        }
    }

    /// PKDrawing から候補を「よさそうな順」に返す
    func recognize(_ drawing: PKDrawing, limit: Int = 8) -> [String] {
        let strokes: [Stroke] = drawing.strokes.compactMap { stroke in
            let pts = stroke.path.map { $0.location.applying(stroke.transform) }
            return pts.count >= 1 ? pts : nil
        }
        guard !strokes.isEmpty else { return [] }
        let input = Self.normalize(strokes.map { Self.resample($0) })
        // 画数が近い字だけを比べる（1,026字すべてを毎回くらべないため）
        let n = input.count
        let range = max(3, n / 3)
        var pool = templates.filter { abs($0.value.count - n) <= range }
        if pool.isEmpty { pool = templates }
        return pool
            .map { ($0.key, Self.score(input, $0.value)) }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    // MARK: - 計算

    /// 全体を中心 (0,0)、大きさ 1 にそろえる（縦横比は保つ）
    private static func normalize(_ strokes: [Stroke]) -> [Stroke] {
        let all = strokes.flatMap { $0 }
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
              let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return strokes }
        let scale = max(maxX - minX, maxY - minY, 0.001)
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        return strokes.map { s in
            s.map { CGPoint(x: ($0.x - cx) / scale, y: ($0.y - cy) / scale) }
        }
    }

    /// 1本の線を等間隔の 16 点にする
    nonisolated static func resample(_ s: Stroke) -> Stroke {
        let n = sampleCount
        guard s.count > 1 else { return Array(repeating: s.first ?? .zero, count: n) }
        var cum: [CGFloat] = [0]
        for i in 1..<s.count {
            cum.append(cum[i - 1] + hypot(s[i].x - s[i - 1].x, s[i].y - s[i - 1].y))
        }
        let total = cum.last!
        guard total > 0 else { return Array(repeating: s[0], count: n) }
        var out: Stroke = []
        var j = 0
        for i in 0..<n {
            let t = total * CGFloat(i) / CGFloat(n - 1)
            while j < s.count - 2 && cum[j + 1] < t { j += 1 }
            let seg = cum[j + 1] - cum[j]
            let r = seg == 0 ? 0 : (t - cum[j]) / seg
            out.append(CGPoint(x: s[j].x + (s[j + 1].x - s[j].x) * r,
                               y: s[j].y + (s[j + 1].y - s[j].y) * r))
        }
        return out
    }

    /// 2本の線の平均のずれ
    nonisolated static func strokeDistance(_ a: Stroke, _ b: Stroke) -> CGFloat {
        var sum: CGFloat = 0
        for (p, q) in zip(a, b) { sum += hypot(p.x - q.x, p.y - q.y) }
        return sum / CGFloat(min(a.count, b.count))
    }

    /// 小さいほど似ている。書き順ちがい・向きちがいも少しのペナルティで許す
    private static func score(_ input: [Stroke], _ template: [Stroke]) -> CGFloat {
        let n = input.count, m = template.count
        let k = max(n, m)
        let miss: CGFloat = 0.5
        var cost = Array(repeating: Array(repeating: miss, count: k), count: k)
        for i in 0..<n {
            for j in 0..<m {
                let forward = strokeDistance(input[i], template[j])
                let backward = strokeDistance(Array(input[i].reversed()), template[j]) + 0.08
                cost[i][j] = min(forward, backward) + CGFloat(abs(i - j)) * 0.02
            }
        }
        return hungarian(cost) / CGFloat(k) + 0.12 * CGFloat(abs(n - m))
    }

    /// いちばん合計コストが小さい「線どうしの組み合わせ」を求める（ハンガリアン法）
    private static func hungarian(_ c: [[CGFloat]]) -> CGFloat {
        let n = c.count
        let inf = CGFloat.greatestFiniteMagnitude / 4
        var u = Array(repeating: CGFloat(0), count: n + 1)
        var v = Array(repeating: CGFloat(0), count: n + 1)
        var p = Array(repeating: 0, count: n + 1)
        var way = Array(repeating: 0, count: n + 1)
        for i in 1...n {
            p[0] = i
            var j0 = 0
            var minv = Array(repeating: inf, count: n + 1)
            var used = Array(repeating: false, count: n + 1)
            repeat {
                used[j0] = true
                let i0 = p[j0]
                var delta = inf
                var j1 = 0
                for j in 1...n where !used[j] {
                    let cur = c[i0 - 1][j - 1] - u[i0] - v[j]
                    if cur < minv[j] { minv[j] = cur; way[j] = j0 }
                    if minv[j] < delta { delta = minv[j]; j1 = j }
                }
                for j in 0...n {
                    if used[j] { u[p[j]] += delta; v[j] -= delta } else { minv[j] -= delta }
                }
                j0 = j1
            } while p[j0] != 0
            repeat {
                let j1 = way[j0]
                p[j0] = p[j1]
                j0 = j1
            } while j0 != 0
        }
        var total: CGFloat = 0
        for j in 1...n { total += c[p[j] - 1][j - 1] }
        return total
    }
}
