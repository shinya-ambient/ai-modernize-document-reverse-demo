# AI Document Reverse — gaipack デモアプリ

レガシーコード（RPG/COBOL）からAIでドキュメントを自動生成するデモアプリケーション。

## デモの流れ

1. **コードアップロード** — RPGソースコードをアップロード（サンプル付き）
2. **ドキュメント生成** — AIがコードを解析し、処理フロー（Mermaid）・CRUD図・業務ロジック説明書を自動生成
3. **AIレビュー** — 生成されたドキュメントをAIが自己チェックし、違和感・確認すべき点を検出
4. **（口頭説明）** — レビュー結果をもとに関係者へヒアリングを実施し、ドキュメント精度を60%→90%に引き上げる流れを説明

## セットアップ

### 1. 依存関係のインストール

```bash
npm install
```

### 2. 環境変数の設定

```bash
cp .env.example .env.local
```

`.env.local` を編集して Anthropic API Key を設定:

```
ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxxx
```

### 3. ローカル開発

```bash
npm run dev
```

http://localhost:3000 でアクセス

## Vercel デプロイ

### 方法1: Vercel CLI

```bash
npm i -g vercel
vercel
```

### 方法2: GitHub連携

1. このリポジトリをGitHubにpush
2. [vercel.com](https://vercel.com) でプロジェクトをインポート
3. 環境変数 `ANTHROPIC_API_KEY` を設定
4. デプロイ

### 重要な設定

- **Environment Variables**: Vercelのプロジェクト設定で `ANTHROPIC_API_KEY` を必ず設定
- **Function Duration**: `vercel.json` でAPI routeのmaxDurationを120秒に設定済み（Proプラン推奨）
- **Region**: 日本からのアクセスが多い場合、Function Regionを `hnd1`（東京）に設定推奨

## サンプルファイル

`public/` ディレクトリに以下のサンプルRPGコードが含まれています：

| ファイル | 概要 |
|---------|------|
| ORDENTR.RPGLE | 受注入力処理（RPG IV Free形式） |
| INVBATCH.RPGLE | 在庫引当・補充計算バッチ（RPG IV Free形式） |
| BILPRT.RPG | 月次請求書発行処理（RPG III 固定形式） |

## 技術スタック

- **Next.js 14** (App Router)
- **TypeScript**
- **Tailwind CSS**
- **Anthropic Claude API** (claude-sonnet-4-20250514)
- **Mermaid.js** (フローチャート描画)
- **react-markdown** (Markdown表示)
