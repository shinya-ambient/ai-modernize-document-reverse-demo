import { NextRequest } from "next/server";
import Anthropic from "@anthropic-ai/sdk";

export const maxDuration = 120;

export async function POST(req: NextRequest) {
  const { document, code, filename } = await req.json();

  const client = new Anthropic();

  const stream = await client.messages.stream({
    model: "claude-sonnet-4-20250514",
    max_tokens: 4000,
    messages: [
      {
        role: "user",
        content: `あなたはレガシーシステムのモダナイゼーション専門のレビュアーです。
以下のRPGソースコードと、そこから自動生成されたドキュメントを照合・レビューしてください。

## 元のソースコード（${filename}）
\`\`\`
${code}
\`\`\`

## 生成されたドキュメント
${document}

---

以下の観点でレビューし、**違和感や確認が必要な点**を指摘してください：

各項目について、以下のJSON配列形式で出力してください。必ずJSON配列のみを出力し、他のテキストは一切含めないでください：

[
  {
    "id": 1,
    "severity": "critical" | "warning" | "info",
    "category": "カテゴリ名",
    "title": "短いタイトル",
    "description": "詳細な説明",
    "source_reference": "該当するコード箇所や行の参照",
    "question_for_stakeholder": "関係者に確認すべき質問"
  }
]

## レビュー観点：
1. **業務ロジックの解釈の正確性** - ドキュメントの業務ロジック説明がコードの実際の処理と一致しているか
2. **ハードコード値の業務的意味** - マジックナンバーや定数の業務的な意図が正しく解釈されているか
3. **暫定対応・TODO** - コメントに「暫定」「TODO」「後で直す」等の記述があり、現在も残っている箇所
4. **属人化リスク** - 特定の担当者名が記載されており、その人しか知らないロジックがある箇所
5. **テスト不足の懸念** - 「テスト不十分」等のコメントがある箇所
6. **エラーハンドリングの欠落** - 異常系の処理が不十分な箇所
7. **依存関係の不明点** - 外部プログラムやファイルへの依存で、実体が不明な箇所
8. **業務ルールの曖昧さ** - 条件分岐のロジックが複雑で、業務的な意図が不明確な箇所

severity の基準：
- critical: 本番障害やデータ不整合のリスクがある、または業務ロジックの解釈が誤っている可能性が高い
- warning: 確認が必要だが即座にリスクにはならない、暫定対応や属人化の問題
- info: 改善推奨だが現行運用に影響しない`,
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
