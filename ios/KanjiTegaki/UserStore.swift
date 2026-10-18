import Foundation
import SwiftUI

/// しらべた りれき（さいきんの 100字）と おきにいり を iPad の中に ほぞんする
@MainActor
final class UserStore: ObservableObject {
    static let shared = UserStore()

    @Published private(set) var history: [String] = []
    @Published private(set) var favorites: [String] = []

    private let historyKey = "history"
    private let favoritesKey = "favorites"
    private let maxHistory = 100

    private init() {
        history = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
        favorites = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
    }

    func record(_ kanji: String) {
        history.removeAll { $0 == kanji }
        history.insert(kanji, at: 0)
        if history.count > maxHistory {
            history.removeLast(history.count - maxHistory)
        }
        save()
    }

    func isFavorite(_ kanji: String) -> Bool {
        favorites.contains(kanji)
    }

    func toggleFavorite(_ kanji: String) {
        if let i = favorites.firstIndex(of: kanji) {
            favorites.remove(at: i)
        } else {
            favorites.insert(kanji, at: 0)
        }
        save()
    }

    func clearHistory() {
        history = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(history, forKey: historyKey)
        UserDefaults.standard.set(favorites, forKey: favoritesKey)
    }
}
