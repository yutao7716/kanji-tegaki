import Foundation

/// 四字熟語・ことわざ 1つぶん
struct Idiom: Codable, Identifiable, Hashable {
    let text: String     // 例：一石二鳥
    let reading: String  // 例：いっせきにちょう
    let meaning: String  // 子ども向けの意味
    let kind: String     // "yoji"（四字熟語） または "kotowaza"（ことわざ）

    var id: String { text }
    var isYoji: Bool { kind == "yoji" }
}

/// 画数・部首
struct KanjiInfo: Codable, Hashable {
    let strokes: Int
    let radical: String
    let radicalName: String
}

/// extras.json（画数・部首・反対の意味の漢字・四字熟語・ことわざ）を読み込む
@MainActor
final class ExtrasStore {
    static let shared = ExtrasStore()

    private struct FileFormat: Codable {
        let antonyms: [String: [String]]
        let idioms: [Idiom]
        let info: [String: KanjiInfo]
    }

    private var antonymMap: [String: [String]] = [:]
    private var idiomMap: [String: [Idiom]] = [:]
    private var infoMap: [String: KanjiInfo] = [:]

    func info(of kanji: String) -> KanjiInfo? {
        infoMap[kanji]
    }

    private init() {
        guard let url = Bundle.main.url(forResource: "extras", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(FileFormat.self, from: data) else {
            print("extras.json が読み込めません")
            return
        }
        antonymMap = file.antonyms
        infoMap = file.info
        // 漢字 → その字を ふくむ 熟語・ことわざ（ファイルの順番＝よく知られている順）
        for idiom in file.idioms {
            var added = Set<Character>()
            for ch in idiom.text where !added.contains(ch) {
                added.insert(ch)
                idiomMap[String(ch), default: []].append(idiom)
            }
        }
    }

    func antonyms(of kanji: String) -> [String] {
        antonymMap[kanji] ?? []
    }

    func yoji(for kanji: String, limit: Int = 3) -> [Idiom] {
        Array((idiomMap[kanji] ?? []).filter(\.isYoji).prefix(limit))
    }

    func kotowaza(for kanji: String, limit: Int = 2) -> [Idiom] {
        Array((idiomMap[kanji] ?? []).filter { !$0.isYoji }.prefix(limit))
    }
}
