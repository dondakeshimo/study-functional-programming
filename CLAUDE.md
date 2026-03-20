# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

関数型プログラミングを学習するためのリポジトリ。

## 言語・ツールチェイン

主要言語: Haskell (GHC 9.6.7)
ビルドツール: Cabal
パッケージ名: study-fp

## ビルド・実行コマンド

```bash
cabal build        # ビルド
cabal run study-fp # 実行
cabal test         # テスト
cabal clean        # ビルド成果物の削除
```

## プロジェクト構成

- `src/` — ライブラリモジュール（ビジネスロジック）
- `app/` — 実行ファイル（エントリーポイント）
- `lessons/` — 学習記録
