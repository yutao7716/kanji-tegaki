import Foundation

/// 漢字1字ぶんのデータ（kanji.json の1項目）
struct KanjiEntry: Codable, Identifiable, Hashable {
    let kanji: String       // 漢字
    let grade: Int          // ならう学年
    let onyomi: [String]    // 音読み（カタカナ）
    let kunyomi: [String]   // 訓読み（ひらがな。送りがなは ( ) で囲む）
    let meaning: String     // 子ども向けの意味（かんたん）
    let meaningStd: String? // ふつうの説明（中学年以上むけ）
    let examples: [String]  // つかいかた（ことばの例）
    let synonyms: [String]  // にた意味のことば

    var id: String { kanji }

    /// 学年の表示名（7 = 中学・高校）
    var gradeLabel: String { KanjiEntry.gradeLabel(grade) }

    static func gradeLabel(_ g: Int) -> String {
        g >= 7 ? "中学・高校" : "\(g)ねんせい"
    }

    /// せまい所（セグメント）用の短い表示名
    static func gradeShortLabel(_ g: Int) -> String {
        g >= 7 ? "中・高" : "\(g)年"
    }

    /// えらべる学年（1〜6年 と 中学・高校）
    static let allGrades = Array(1...7)

    /// 表示する意味（ふつう説明が なければ かんたん説明）
    func meaningText(standard: Bool) -> String {
        standard ? (meaningStd ?? meaning) : meaning
    }

    /// 読み上げ用の文章
    var speechText: String { speechText(standard: false) }

    func speechText(standard: Bool) -> String {
        let clean: (String) -> String = {
            $0.replacingOccurrences(of: "(", with: "")
              .replacingOccurrences(of: ")", with: "")
        }
        var parts: [String] = []
        if !onyomi.isEmpty {
            parts.append("おんよみは、" + onyomi.joined(separator: "、"))
        }
        if !kunyomi.isEmpty {
            parts.append("くんよみは、" + kunyomi.map(clean).joined(separator: "、"))
        }
        parts.append("いみは、" + meaningText(standard: standard))
        return parts.joined(separator: "。")
    }
}

/// アプリに同梱した kanji.json を読み込む辞書
@MainActor
final class KanjiDictionary {
    static let shared = KanjiDictionary()

    private(set) var entries: [String: KanjiEntry] = [:]
    /// 学年じゅんに ならんだ 全部の漢字
    private(set) var ordered: [KanjiEntry] = []

    private init() {
        guard let url = Bundle.main.url(forResource: "kanji", withExtension: "json") else {
            print("kanji.json が見つかりません。プロジェクトに追加されているか確認してください。")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let list = try JSONDecoder().decode([KanjiEntry].self, from: data)
            entries = Dictionary(list.map { ($0.kanji, $0) },
                                 uniquingKeysWith: { first, _ in first })
            ordered = list.enumerated()
                .sorted { ($0.element.grade, $0.offset) < ($1.element.grade, $1.offset) }
                .map(\.element)
        } catch {
            print("kanji.json の読み込みに失敗しました: \(error)")
        }
    }

    func lookup(_ kanji: String) -> KanjiEntry? {
        entries[kanji]
    }

    func entries(grade: Int) -> [KanjiEntry] {
        ordered.filter { $0.grade == grade }
    }

    /// よみ（ひらがな・カタカナ）で さがす。よみの はじまりが 一致する 字を かえす
    func search(reading query: String) -> [KanjiEntry] {
        let q = Self.hiragana(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return [] }
        return ordered.filter { entry in
            let readings = entry.onyomi.map(Self.hiragana)
                + entry.kunyomi.map { Self.hiragana($0.replacingOccurrences(of: "(", with: "")
                                                     .replacingOccurrences(of: ")", with: "")) }
            return readings.contains { $0.hasPrefix(q) }
        }
    }

    /// カタカナを ひらがなに する
    static func hiragana(_ s: String) -> String {
        s.applyingTransform(.hiraganaToKatakana, reverse: true) ?? s
    }
}
