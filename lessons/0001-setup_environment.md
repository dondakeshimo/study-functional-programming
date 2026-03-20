# 0001: 環境構築

## GHCup のインストール

Haskell の公式ツールチェインマネージャである GHCup をインストールする。

```bash
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
```

対話式インストーラが起動するので、デフォルト設定で進める。
インストール後、PATH を反映する。

```bash
source ~/.ghcup/env
```

## ツールチェインのインストール

GHCup を使って recommended バージョンのツールをインストールする。

```bash
ghcup install ghc recommended
ghcup install cabal recommended
ghcup install hls recommended
```

### インストールされたバージョン（2026-03-20 時点）

| ツール | バージョン |
|--------|-----------|
| GHC    | 9.6.7     |
| Cabal  | 3.14.2.0  |
| HLS    | 2.13.0.0  |

確認コマンド：

```bash
ghcup list
ghc --version
cabal --version
haskell-language-server-wrapper --version
```

## プロジェクトの初期化

Cabal を使ってプロジェクトを初期化する。
`--libandexe` を指定し、ライブラリと実行ファイルの両方を含む構成にした。
Web アプリケーションを作成する想定で、ビジネスロジックを lib に、サーバー起動を exe に分離できるようにするため。

```bash
cabal init --non-interactive --package-name study-fp --libandexe
```

### 生成されたファイル

- `study-fp.cabal` — プロジェクト定義
- `src/MyLib.hs` — ライブラリモジュール
- `app/Main.hs` — エントリーポイント（main 関数）

## ビルドと実行

```bash
cabal build
cabal run study-fp
```

`Hello, Haskell!` と `someFunc` が表示されれば成功。
