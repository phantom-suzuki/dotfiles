---
name: ui-compare
description: スクリーンショットの Before/After 比較レポート（HTML）を生成する。「スクショを比較して」「Before/After を見たい」「UI変更のレポートを作って」「画像を並べて比較」などの依頼時に使用。スクリーンショット撮影後の検証レポート作成にも適用する。
argument-hint: "[画像ディレクトリ]"
---

# UI Compare — Before/After 比較レポート生成

スクリーンショット群から、Before/After を横並びで比較できるHTMLレポートを生成してブラウザで開く。

## いつ使うか

- 機能のON/OFF切り替え前後のUI比較
- デザイン変更前後のBefore/After確認
- バグ修正前後の画面比較
- 複数状態（ユーザー種別、デバイス幅など）の横断比較

## Procedure

### 1. 画像の収集

引数でディレクトリが指定された場合はそこを使う。指定がなければユーザーに確認するか、会話の文脈から推定する。

```bash
# 対象ディレクトリ内の画像を一覧
ls <dir>/*.{png,jpg,jpeg,gif,webp} 2>/dev/null
```

画像が見つからなければユーザーに場所を確認する。

### 2. 画像のグルーピング

ファイル名や会話の文脈から、以下を判断する：

- **比較軸**: 何と何を比べるか（例: ON/OFF、Before/After、旧/新）
- **ペア**: どの画像同士がペアか
- **セクション**: 画面カテゴリによるグループ分け（例: スタッフ側 / ゲスト側）
- **単独画像**: ペアにならないもの（片方の状態しかない場合）

ファイル名のパターン例：
- `01-画面名-before.png` / `02-画面名-after.png` — 番号+サフィックスで対応
- `画面名-on.png` / `画面名-off.png` — サフィックスで対応
- 番号の連番で暗黙的に奇数=Before、偶数=After

パターンが不明な場合はユーザーに確認する。

### 3. HTML生成

以下の構造でHTMLファイルを生成する。画像と同じディレクトリに `compare.html` として保存する（既存ファイルがあれば上書き確認）。

#### 必須要素

- **タイトル**: 比較の概要（例: 「EQ診断トグル Before/After 比較」）
- **サブタイトル**: 比較軸の説明（例: 「enableEq: ON（左） vs OFF（右）」）
- **セクション**: 画面カテゴリごとに `<h2>` で区切る
- **比較ペア**: 横並び2カラム。各カードにラベル（Before/After の区別）
- **単独画像**: `max-width: 50%` で表示
- **注記**: 問題点や気づきがあれば黄色の注記ブロックで表示
- **ライトボックス**: 画像クリックで拡大、Escで閉じる

#### HTMLテンプレート構造

```html
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<title>{{TITLE}}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f5f5f5; color: #333; padding: 24px; }
  h1 { text-align: center; margin-bottom: 8px; font-size: 1.6rem; }
  .subtitle { text-align: center; color: #666; margin-bottom: 32px; font-size: 0.9rem; }
  .section { margin-bottom: 48px; }
  .section h2 { font-size: 1.2rem; margin-bottom: 16px; padding-bottom: 8px; border-bottom: 2px solid #4f46e5; color: #4f46e5; }
  .pair-title { margin-bottom: 8px; margin-top: 24px; font-size: 0.95rem; }
  .pair-title:first-of-type { margin-top: 0; }
  .pair { display: flex; gap: 16px; margin-bottom: 32px; align-items: flex-start; }
  .pair .card { flex: 1; background: #fff; border-radius: 8px; box-shadow: 0 1px 4px rgba(0,0,0,0.1); overflow: hidden; }
  .pair .card img { width: 100%; display: block; cursor: zoom-in; }
  .pair .card .label { padding: 8px 12px; font-weight: 600; font-size: 0.85rem; text-align: center; }
  .label-before { background: #dbeafe; color: #1e40af; }
  .label-after { background: #fef3c7; color: #92400e; }
  .label-single { background: #fce7f3; color: #9d174d; }
  .note { background: #fff7ed; border-left: 4px solid #f59e0b; padding: 12px 16px; border-radius: 4px; margin-top: 8px; margin-bottom: 16px; font-size: 0.85rem; }
  .note strong { color: #b45309; }
  .single { max-width: 50%; }
  @media (max-width: 900px) { .pair { flex-direction: column; } .single { max-width: 100%; } }
  .lightbox { display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.85); z-index: 1000; justify-content: center; align-items: center; cursor: zoom-out; }
  .lightbox.active { display: flex; }
  .lightbox img { max-width: 95vw; max-height: 95vh; object-fit: contain; border-radius: 4px; }
</style>
</head>
<body>

<h1>{{TITLE}}</h1>
<p class="subtitle">{{SUBTITLE}}</p>

<!-- セクションとペアをここに展開 -->

<div class="lightbox" id="lightbox" onclick="closeLightbox()">
  <img id="lightbox-img" src="" alt="">
</div>
<script>
function openLightbox(el) {
  document.getElementById('lightbox-img').src = el.src;
  document.getElementById('lightbox').classList.add('active');
}
function closeLightbox() {
  document.getElementById('lightbox').classList.remove('active');
}
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeLightbox(); });
</script>
</body>
</html>
```

#### ペアの記述パターン

**横並び比較（通常）:**
```html
<h3 class="pair-title">1. 画面名</h3>
<div class="pair">
  <div class="card">
    <div class="label label-before">Before ラベル</div>
    <img src="before.png" alt="説明" onclick="openLightbox(this)">
  </div>
  <div class="card">
    <div class="label label-after">After ラベル</div>
    <img src="after.png" alt="説明" onclick="openLightbox(this)">
  </div>
</div>
```

**単独画像:**
```html
<div class="pair single">
  <div class="card">
    <div class="label label-single">ラベル</div>
    <img src="image.png" alt="説明" onclick="openLightbox(this)">
  </div>
</div>
```

**注記（問題点・気づき）:**
```html
<div class="note"><strong>問題点:</strong> 説明テキスト</div>
```

### 4. ラベルのカスタマイズ

比較軸に応じてラベル名とCSSクラスを調整する：

| 比較軸 | Before ラベル例 | After ラベル例 |
|--------|----------------|---------------|
| ON/OFF | `ON` | `OFF` |
| Before/After | `変更前` | `変更後` |
| 旧/新 | `旧デザイン` | `新デザイン` |
| デバイス | `モバイル` | `デスクトップ` |

CSSクラス名（`label-before`, `label-after`）は共通で使い、表示テキストだけ変える。

### 5. ブラウザで開く

```bash
open <dir>/compare.html
```

### 6. ユーザーへの報告

生成後、以下を簡潔に伝える：
- 比較ペア数と画像枚数
- 注記がある場合はその概要
- ファイルの保存場所
