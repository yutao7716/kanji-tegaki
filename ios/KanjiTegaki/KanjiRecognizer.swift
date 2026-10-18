import Foundation
import Vision

/// Apple 標準の Vision フレームワークで手書き文字を認識する（オフラインで動作）
enum KanjiRecognizer {

    /// 漢字と見まちがえやすいカタカナ・記号 → 漢字 の対応表
    private static let lookAlikes: [Character: Character] = [
        "カ": "力", "ロ": "口", "ニ": "二", "ハ": "八", "タ": "夕",
        "エ": "工", "ー": "一", "-": "一", "+": "十", "□": "口"
    ]

    /// PNG 画像から漢字の候補を返す（よさそうな順、最大8個）
    nonisolated static func recognize(pngData: Data) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP"]
        request.usesLanguageCorrection = false   // 1文字なので言語補正は使わない

        let handler = VNImageRequestHandler(data: pngData, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        var found: [String] = []
        for observation in request.results ?? [] {
            for candidate in observation.topCandidates(10) {
                for raw in candidate.string {
                    let ch = lookAlikes[raw] ?? raw
                    guard isKanji(ch) else { continue }
                    let s = String(ch)
                    if !found.contains(s) {
                        found.append(s)
                    }
                }
            }
        }
        return Array(found.prefix(8))
    }

    nonisolated private static func isKanji(_ ch: Character) -> Bool {
        ch.unicodeScalars.allSatisfy { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)      // CJK統合漢字
                || (0x3400...0x4DBF).contains(scalar.value) // 拡張A
                || (0xF900...0xFAFF).contains(scalar.value) // 互換漢字
        }
    }
}
