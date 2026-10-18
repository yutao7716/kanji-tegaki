import SwiftUI

/// 漢字を マス目に ならべる（タップで えらぶ）
struct KanjiGrid: View {
    let kanjiList: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                ForEach(kanjiList, id: \.self) { k in
                    Button { onSelect(k) } label: {
                        Text(k)
                            .font(.custom("HiraMinProN-W6", size: 44))
                            .foregroundStyle(Color.primary)
                            .frame(width: 76, height: 76)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
    }
}

/// さがす：学年べつの一覧と、よみからの さがしかた
struct SearchView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var grade = 1
    @State private var query = ""

    private var results: [String] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return KanjiDictionary.shared.entries(grade: grade).map(\.kanji)
        }
        return KanjiDictionary.shared.search(reading: query).map(\.kanji)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("かんじを さがす")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Spacer()
                Button("とじる") { dismiss() }
                    .font(.title3.bold())
            }

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                TextField("よみで さがす（れい：やま、さん）", text: $query)
                    .font(.title2)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Picker("がくねん", selection: $grade) {
                    ForEach(1...6, id: \.self) { g in
                        Text("\(g)ねんせい").tag(g)
                    }
                }
                .pickerStyle(.segmented)
                Text("\(grade)ねんせいで ならう かんじ（\(results.count)じ）")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                Text("「\(query)」と よむ かんじ（\(results.count)じ）")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if results.isEmpty {
                Text("みつからなかったよ")
                    .font(.title2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                KanjiGrid(kanjiList: results) { k in
                    onSelect(k)
                    dismiss()
                }
            }
        }
        .padding(28)
        .background(Color(red: 0.98, green: 0.96, blue: 0.90))
    }
}

/// りれき と おきにいり
struct HistoryView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = UserStore.shared
    @State private var tab = 0
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(tab == 0 ? "しらべた かんじ" : "おきにいり")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Spacer()
                Button("とじる") { dismiss() }
                    .font(.title3.bold())
            }

            Picker("", selection: $tab) {
                Text("りれき").tag(0)
                Text("おきにいり ★").tag(1)
            }
            .pickerStyle(.segmented)

            let list = tab == 0 ? store.history : store.favorites
            if list.isEmpty {
                Text(tab == 0 ? "まだ しらべた かんじは ないよ"
                              : "カードの ☆ を おすと ここに あつまるよ")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                KanjiGrid(kanjiList: list) { k in
                    onSelect(k)
                    dismiss()
                }
            }

            if tab == 0 && !store.history.isEmpty {
                Button(role: .destructive) { confirmClear = true } label: {
                    Label("りれきを けす", systemImage: "trash")
                        .font(.headline)
                }
                .confirmationDialog("りれきを ぜんぶ けしますか？",
                                    isPresented: $confirmClear,
                                    titleVisibility: .visible) {
                    Button("けす", role: .destructive) { store.clearHistory() }
                    Button("やめる", role: .cancel) {}
                }
            }
        }
        .padding(28)
        .background(Color(red: 0.98, green: 0.96, blue: 0.90))
    }
}
