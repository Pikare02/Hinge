# Hinge

<img src="docs/icon-preview.png" width="96" alt="Hinge のアイコン">

MacBook の蓋を閉じていくと、デスクトップがその場に立ったまま残っているように
見せる macOS アプリ。物理パネルは手前に倒れてくるが、画面に描かれた内容は
開ききった姿勢のまま空間に固定されているように振る舞う。

## ビルド

```
./make_app.sh
```

`Hinge.app` ができる。Swift Package Manager でビルドしたバイナリを .app に
包み、アドホック署名する。Xcode プロジェクトは使わない。

## 実行

```
open Hinge.app
```

画面収録の権限が要る。初回起動時に案内が出るので、
システム設定 → プライバシーとセキュリティ → 画面収録 で許可して開き直す。

アドホック署名はビルドのたびにハッシュが変わり、許可が無効になる。
`make_app.sh` は古い許可を消してから終わるので、再ビルド後は一度許可し直す。

Hinge は常駐する。設定ウィンドウは Dock アイコンかメニューバーの項目から開き、
閉じてもアプリは動き続ける。終了は設定内のボタンか ⌘Q。

オーバーレイは傾きが付いたときだけ出るので、普段の角度ではメニューバーも
Dock もそのまま使える。

## 画面を覆わずに動作を確かめる

```
.build/release/Hinge --selfcheck   # 変換の数式
.build/release/Hinge --probe       # 実機の蓋の角度と権限の状態
```

## 必要なもの

- lid angle sensor を持つ Apple silicon の MacBook
- macOS 14 以降

設計は [docs/spec.md](docs/spec.md) にある。
