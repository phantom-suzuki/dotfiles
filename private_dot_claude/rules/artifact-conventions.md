# Artifact の作成・共有の既定ルール

**適用範囲**: Claude Code がアーティファクト（claude.ai/code/artifact/...）を作成・公開・更新したとき、毎回適用する。

本ファイルは 2 つの規範を持つ。**作成時**の規範（テーマ切り替えの UI）と、**公開後**の規範（共有設定）である。

---

# 第 1 部: 作成時の既定

## テーマ切り替えの UI を必ず付ける（最重要）

**HTML のアーティファクトには、ライトモードとダークモードを画面上で切り替えられるコントロールを必ず入れる。** 例外なく適用する。「今回は不要」と自分で例外を作らない。

**Why**: アーティファクトは閲覧者のテーマ設定で描画される。閲覧者の OS やブラウザの設定が、読みたい見た目と食い違うことがある。ページ上で切り替えられないと、閲覧者は OS の設定を変えるしかない。図表やコードを含むページでは、見え方の切り替えが読みやすさに直結する（ユーザー指示、2026-08-29）。

### 実装の要件

1. **本物のボタンにする**: `<button>` 要素を使う。`div` に `onclick` を付けない。キーボードで操作でき、フォーカスが目に見えること
2. **配置**: ページ上部の右側に置く。スクロールしても届く位置（固定ヘッダーの中など）が望ましい
3. **3 つの状態を持たせる**: 「システムに従う」→「ライト」→「ダーク」の順に切り替える。2 状態だけにする場合も、初期状態は閲覧者のテーマを尊重する
4. **切り替えの実体**: ルート要素の `data-theme` 属性を `"light"` または `"dark"` に設定する。「システムに従う」に戻すときは属性を削除する。この属性は、`artifact-design` スキルが定めるトークンの仕組み（素の `:root` がライト / `@media (prefers-color-scheme: dark)` を `:root:not([data-theme="light"])` で囲う / `:root[data-theme="dark"]` で上書きする）とそのまま噛み合う
5. **記憶する**: 選んだ状態を `localStorage` に保存し、次回の閲覧で復元する。**読み書きは必ず `try` / `catch` で囲う**（プライベートウィンドウやサムネイル生成の環境では例外が飛ぶ）。保存値が無いときは属性を書かず、閲覧者のテーマをそのまま使う
6. **色だけに頼らない**: 現在の状態を、アイコンと文字の両方で示す。`aria-label` を付ける
7. **ちらつきを防ぐ**: 保存値の復元は、ページ本文より前に置いたインラインスクリプトで行う

### 実装の雛形

```html
<button id="theme-toggle" type="button" aria-label="配色を切り替える">
  <span class="theme-icon" aria-hidden="true"></span>
  <span class="theme-label"></span>
</button>

<script>
  (function () {
    var KEY = "artifact-theme";
    var order = ["system", "light", "dark"];
    var labels = { system: "システム", light: "ライト", dark: "ダーク" };
    var icons = { system: "◐", light: "☀", dark: "☾" };
    var mode = "system";

    try { mode = localStorage.getItem(KEY) || "system"; } catch (e) { mode = "system"; }
    if (order.indexOf(mode) === -1) { mode = "system"; }

    function apply() {
      var root = document.documentElement;
      if (mode === "system") { root.removeAttribute("data-theme"); }
      else { root.setAttribute("data-theme", mode); }
      var btn = document.getElementById("theme-toggle");
      if (!btn) { return; }
      btn.querySelector(".theme-icon").textContent = icons[mode];
      btn.querySelector(".theme-label").textContent = labels[mode];
      btn.setAttribute("aria-label", "配色: " + labels[mode] + "。押すと切り替わる");
    }

    apply();

    document.addEventListener("DOMContentLoaded", function () {
      apply();
      document.getElementById("theme-toggle").addEventListener("click", function () {
        mode = order[(order.indexOf(mode) + 1) % order.length];
        try { localStorage.setItem(KEY, mode); } catch (e) { /* 保存できなくても動かす */ }
        apply();
      });
    });
  })();
</script>
```

見た目はページの意匠に合わせて作り直してよい。**変えてはいけないのは 2 点だけである**。`data-theme` を切り替える仕組みと、`localStorage` の読み書きを `try` / `catch` で囲うことである。

### 例外

- **Markdown のアーティファクト**: スクリプトを持てないため対象外。ただし Markdown で公開してよいのは、スキルが明示的に指示した場合だけである
- **単一の見た目に振り切った意匠**: ネオン看板・活版印刷の招待状のように、片方のテーマだけで成立させる設計を意図的に選んだ場合は、切り替えを省いてよい。その場合は**省いた理由をユーザーに 1 行で伝える**。判断を黙って省略しない

## 関連する既定

テーマのトークン設計・配色・書体・レイアウトの規範は `artifact-design` スキルが正本である。本ルールはその上に「切り替え UI を必ず付ける」を足すものであり、トークンの仕組みを置き換えない。

---

# 第 2 部: 公開後の既定

## 既定の共有設定

アーティファクトを公開したら、そのままにせず**共有設定を次の既定に合わせる**:

- **General access（一般アクセス）**: 「Everyone in Tameny」（Tameny 組織の全員がアクセス可）
- **編集権限**: Tameny 所属メンバーが自分の Claude からアーティファクトを編集（remix / edit with Claude）できる設定が UI にあれば有効にする

背景: アーティファクトは公開直後は private（本人のみ）で、Artifact ツールには共有設定を変更するパラメータがない。共有設定はアーティファクトページの共有メニューでしか変更できない。

## 設定手順

1. Claude in Chrome（ユーザーのブラウザ）でアーティファクト URL を開く
2. ページ右上の共有（Share）メニューを開く
3. General access を「Everyone in Tameny」に変更し、編集可の選択肢があれば有効にする
4. 設定後の状態をユーザーに報告する（何がどこまで設定できたか。編集権限の選択肢が無かった場合はその旨を明記）

## フォールバック

- **Claude in Chrome が未接続の場合**: 別ブラウザの自動化（Playwright 等）で代替しない（claude.ai へのログインが必要で、認証情報の入力は禁止操作）。アーティファクト URL と上記手順をユーザーに提示し、手動設定を依頼する
- 共有メニューの文言・選択肢は claude.ai の UI 更新で変わりうる。実際の画面に存在する選択肢の中で、上記の意図（組織全員がアクセス可・可能なら Claude 経由で編集可）に最も近いものを選ぶ

## 注意

- 他人のアーティファクトは対象外（共有設定を変更できるのは所有者のみ）
- センシティブな内容（人事・機密・個人情報を含むレポート）は例外。組織全員への公開が適切か公開前にユーザーに確認する
