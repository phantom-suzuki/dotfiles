# Artifact のテーマ切り替えボタンの雛形と共有手順

`rules/artifact-conventions.md` の詳細。常時読み込みはされない。Artifact を作るときに読む。

## 雛形

見た目はページの意匠に合わせて作り直してよい。変えてはいけないのは、`data-theme` を切り替える仕組みと、`localStorage` の読み書きを `try` / `catch` で囲うことの 2 点。

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

保存値の復元はページ本文より前に置く。保存値が無いときは属性を書かず、閲覧者のテーマをそのまま使う。

## 共有設定の手順

1. Claude in Chrome でアーティファクトの URL を開く
2. ページ右上の共有（Share）メニューを開く
3. General access を「Everyone in Tameny」に変え、編集可の選択肢があれば有効にする
4. 設定後の状態をユーザーに報告する。編集権限の選択肢が無かった場合はその旨を明記する

共有メニューの文言は claude.ai の更新で変わる。実際の画面にある選択肢の中で「組織全員がアクセスでき、可能なら Claude 経由で編集できる」に最も近いものを選ぶ。他人のアーティファクトは対象外（共有設定を変えられるのは所有者だけ）。
