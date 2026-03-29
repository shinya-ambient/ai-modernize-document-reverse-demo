import { NextRequest } from "next/server";
import Anthropic from "@anthropic-ai/sdk";

export const maxDuration = 120;

export async function POST(req: NextRequest) {
  const { code, filename } = await req.json();

  const client = new Anthropic();

  const stream = await client.messages.stream({
    model: "claude-sonnet-4-20250514",
    max_tokens: 8000,
    messages: [
      {
        role: "user",
        content: `あなたはレガシーシステムのリバースエンジニアリング専門家です。
以下のRPG/CL/DDSソースコードを解析し、ドキュメントリバースを行ってください。

## ファイル名: ${filename}

\`\`\`
${code}
\`\`\`

以下の形式で出力してください：

---

# 📋 プログラム概要

プログラムの目的、機能概要を記述。

# 🔄 処理フロー（Mermaid）

\`\`\`mermaid
（処理フローをMermaid記法のflowchartで記述。日本語で。ノード名は短く簡潔に。）
\`\`\`

# 📊 CRUD図

| 対象ファイル | Create | Read | Update | Delete | 備考 |
の形式でテーブルを作成。

# 🔍 業務ロジック詳細

## 主要な業務ルール
コードから読み取れる業務ルール（計算式、条件分岐、バリデーション等）を意味のある業務用語で説明。
「変数AをBに移動」のような低レベルな説明ではなく、「税率計算処理」「与信チェック」のように業務観点で記述すること。

## データフロー
入力から出力までのデータの流れを説明。

# ⚠️ 技術的負債・リスク

コードから検出された問題点、ハードコード値、暫定対応、コメントアウトされたコード等を列挙。

---

重要：
- 業務の観点で説明すること（コードの逐語訳ではなく、業務ロジックの意味を抽出する）
- Mermaidフローチャートは読みやすく、主要な分岐を含むこと
- 技術的負債は具体的にコードの箇所を引用して指摘すること
- 日本語で出力すること`,
      },
    ],
  });

  const encoder = new TextEncoder();
  const readable = new ReadableStream({
    async start(controller) {
      for await (const event of stream) {
        if (
          event.type === "content_block_delta" &&
          event.delta.type === "text_delta"
        ) {
          controller.enqueue(
            encoder.encode(`data: ${JSON.stringify({ text: event.delta.text })}\n\n`)
          );
        }
      }
      controller.enqueue(encoder.encode("data: [DONE]\n\n"));
      controller.close();
    },
  });

  return new Response(readable, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  });
}
