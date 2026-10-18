# かんじ てがき じしょ

手書き（指・Apple Pencil・マウス）で漢字を1文字書くと、読み・意味・書き順・反対語・四字熟語・ことわざがわかる、小学生向けの漢字じしょです。

**▶ ブラウザで使う：https://yutao7716.github.io/kanji-tegaki/**

iPad・スマホ・パソコンのブラウザで、インストールせずに使えます。iPad や iPhone では Safari の共有メニューから「ホーム画面に追加」を選ぶと、アプリのように使えます。一度ひらいたあとはオフラインでも動きます。

## できること

- **手書きで調べる**：書いた線を書き順データと比べて、候補を表示します（認識はすべてブラウザの中で行い、どこにも送信しません）
- **漢字カード**：学年・画数・部首・音読み・訓読み・子ども向けの意味・つかいかた・にた意味のことば・反対の意味の漢字・四字熟語・ことわざ
- **書き順アニメーション**：1画ずつ番号つきで表示
- **なぞり練習／見ないで書く練習**：1画ごとに「向きが逆」「書き順がちがう」などを判定
- **書き取りテスト**：学年を選んで5問
- **さがす**：学年別の一覧、読みからの検索
- **りれき・おきにいり**：この端末の中だけに保存

収録：小学校で習う漢字 1,026字（2020年度からの学年別漢字配当表）

## フォルダ構成

| 場所 | 内容 |
|---|---|
| `index.html` `app.js` `style.css` `sw.js` | Web版（GitHub Pages でそのまま公開） |
| `data/` | 辞書・書き順・熟語データ（Web版用） |
| `ios/` | iPad版（Swift / SwiftUI の Xcode プロジェクト） |

### iPad版をビルドするには

1. `ios/KanjiTegaki.xcodeproj` を Xcode で開く
2. TARGETS → KanjiTegaki → Signing & Capabilities で自分の Team を選ぶ（無料の Apple アカウントでも可）
3. iPad をつないで ▶ Run

### Web版を手元で動かすには

```sh
python3 -m http.server 8000
# → http://localhost:8000 をひらく
```

## ご注意

- 意味・例・類義語・四字熟語・ことわざの説明は下書きです。まちがいを見つけたら Issue で教えてください。
- 書き順は KanjiVG のデータにもとづいています。学校で習う筆順と一部ちがう場合があります。
- とめ・はね・はらいの判定はしていません。

## ライセンスと出典

- プログラム（`*.html` `*.js` `*.css` `*.swift`）：MIT License（[LICENSE](LICENSE)）
- データ（`data/` と `ios/KanjiTegaki/*.json`）：CC BY-SA 3.0（[data/LICENSE-DATA.md](data/LICENSE-DATA.md)）
  - 書き順データは [KanjiVG](https://kanjivg.tagaini.net/)（© Ulrich Apel, CC BY-SA 3.0）をもとに作成
  - 読みは KANJIDIC2（© Electronic Dictionary Research and Development Group, CC BY-SA 4.0）と照合
