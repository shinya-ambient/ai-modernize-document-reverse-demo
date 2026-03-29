"use client";

import { useState, useRef, useCallback, useEffect } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

type Step = "upload" | "generating" | "document" | "reviewing" | "review";

interface ReviewItem {
  id: number;
  severity: "critical" | "warning" | "info";
  category: string;
  title: string;
  description: string;
  source_reference: string;
  question_for_stakeholder: string;
}

export default function Home() {
  const [step, setStep] = useState<Step>("upload");
  const [fileName, setFileName] = useState("");
  const [code, setCode] = useState("");
  const [document, setDocument] = useState("");
  const [reviewItems, setReviewItems] = useState<ReviewItem[]>([]);
  const [isDragging, setIsDragging] = useState(false);
  const [isStreaming, setIsStreaming] = useState(false);
  const [mermaidSvgs, setMermaidSvgs] = useState<Record<string, string>>({});
  const fileInputRef = useRef<HTMLInputElement>(null);
  const docRef = useRef<HTMLDivElement>(null);

  // Mermaid rendering
  useEffect(() => {
    if (!document || step === "generating") return;

    const mermaidBlocks = document.match(/```mermaid\n([\s\S]*?)```/g);
    if (!mermaidBlocks) return;

    const renderMermaid = async () => {
      const mermaid = (await import("mermaid")).default;
      mermaid.initialize({
        startOnLoad: false,
        theme: "dark",
        themeVariables: {
          primaryColor: "#9333ea",
          primaryTextColor: "#e2e8f0",
          primaryBorderColor: "#6b21a8",
          lineColor: "#06b6d4",
          secondaryColor: "#1e1e2e",
          tertiaryColor: "#12121a",
          fontFamily: "Noto Sans JP, sans-serif",
        },
      });

      const svgs: Record<string, string> = {};
      for (let i = 0; i < mermaidBlocks.length; i++) {
        const code = mermaidBlocks[i]
          .replace(/```mermaid\n/, "")
          .replace(/```$/, "")
          .trim();
        try {
          const { svg } = await mermaid.render(`mermaid-${i}`, code);
          svgs[i.toString()] = svg;
        } catch (e) {
          console.error("Mermaid render error:", e);
          svgs[i.toString()] = `<pre style="color: #f87171;">Mermaid rendering error</pre>`;
        }
      }
      setMermaidSvgs(svgs);
    };

    renderMermaid();
  }, [document, step]);

  const handleFile = useCallback(async (file: File) => {
    const text = await file.text();
    setCode(text);
    setFileName(file.name);
    setStep("upload");
  }, []);

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      setIsDragging(false);
      const file = e.dataTransfer.files[0];
      if (file) handleFile(file);
    },
    [handleFile]
  );

  const handleFileInput = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (file) handleFile(file);
    },
    [handleFile]
  );

  // SSE streaming helper
  const streamResponse = async (
    url: string,
    body: object,
    onText: (text: string) => void,
    onDone: () => void
  ) => {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    const reader = res.body?.getReader();
    const decoder = new TextDecoder();

    if (!reader) return;

    let buffer = "";
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() || "";

      for (const line of lines) {
        if (line.startsWith("data: ")) {
          const data = line.slice(6);
          if (data === "[DONE]") {
            onDone();
            return;
          }
          try {
            const { text } = JSON.parse(data);
            onText(text);
          } catch {}
        }
      }
    }
    onDone();
  };

  const startGeneration = async () => {
    setStep("generating");
    setDocument("");
    setIsStreaming(true);
    setMermaidSvgs({});

    await streamResponse(
      "/api/generate",
      { code, filename: fileName },
      (text) => setDocument((prev) => prev + text),
      () => {
        setIsStreaming(false);
        setStep("document");
      }
    );
  };

  const startReview = async () => {
    setStep("reviewing");
    setReviewItems([]);
    setIsStreaming(true);

    let fullText = "";
    await streamResponse(
      "/api/review",
      { document, code, filename: fileName },
      (text) => {
        fullText += text;
      },
      () => {
        try {
          // Extract JSON array from response
          const jsonMatch = fullText.match(/\[[\s\S]*\]/);
          if (jsonMatch) {
            const items = JSON.parse(jsonMatch[0]);
            setReviewItems(items);
          }
        } catch (e) {
          console.error("Review parse error:", e);
        }
        setIsStreaming(false);
        setStep("review");
      }
    );
  };

  const loadSample = async (filename: string) => {
    const res = await fetch(`/${filename}`);
    const text = await res.text();
    setCode(text);
    setFileName(filename);
  };

  const reset = () => {
    setStep("upload");
    setCode("");
    setFileName("");
    setDocument("");
    setReviewItems([]);
    setMermaidSvgs({});
  };

  const stepConfig = [
    { key: "upload", label: "コードアップロード", icon: "📁" },
    { key: "generating", label: "ドキュメント生成", icon: "⚡" },
    { key: "document", label: "生成結果", icon: "📄" },
    { key: "reviewing", label: "AIレビュー", icon: "🔍" },
    { key: "review", label: "レビュー結果", icon: "✅" },
  ];

  const getStepState = (stepKey: string) => {
    const order = stepConfig.map((s) => s.key);
    const currentIdx = order.indexOf(step);
    const itemIdx = order.indexOf(stepKey);
    if (itemIdx < currentIdx) return "done";
    if (itemIdx === currentIdx) return "active";
    return "pending";
  };

  // Render markdown with mermaid support
  const renderDocument = () => {
    if (!document) return null;

    let mermaidIdx = 0;
    const parts = document.split(/(```mermaid\n[\s\S]*?```)/g);

    return parts.map((part, i) => {
      if (part.startsWith("```mermaid")) {
        const idx = mermaidIdx.toString();
        mermaidIdx++;
        if (mermaidSvgs[idx]) {
          return (
            <div
              key={i}
              className="my-6 p-4 bg-[#0d0d15] rounded-lg border border-gai-border overflow-x-auto"
              dangerouslySetInnerHTML={{ __html: mermaidSvgs[idx] }}
            />
          );
        }
        return (
          <div key={i} className="my-6 p-4 bg-[#0d0d15] rounded-lg border border-gai-border">
            <div className="text-gai-muted text-sm gai-pulse">
              フローチャートを描画中...
            </div>
          </div>
        );
      }
      return (
        <ReactMarkdown key={i} remarkPlugins={[remarkGfm]} className="markdown-body">
          {part}
        </ReactMarkdown>
      );
    });
  };

  const severityConfig = {
    critical: {
      bg: "bg-red-500/10",
      border: "border-red-500/30",
      badge: "bg-red-500",
      label: "重大",
      icon: "🔴",
    },
    warning: {
      bg: "bg-amber-500/10",
      border: "border-amber-500/30",
      badge: "bg-amber-500",
      label: "警告",
      icon: "🟡",
    },
    info: {
      bg: "bg-blue-500/10",
      border: "border-blue-500/30",
      badge: "bg-blue-500",
      label: "情報",
      icon: "🔵",
    },
  };

  return (
    <div className="min-h-screen flex flex-col">
      {/* Header */}
      <header className="sticky top-0 z-50 bg-[#0a0a0f]/90 backdrop-blur-md border-b border-gai-border">
        <div className="gai-gradient-line" />
        <div className="max-w-7xl mx-auto px-6 py-4 flex items-center justify-between">
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2">
              <div className="w-8 h-8 rounded-full bg-gradient-to-br from-gai-purple to-gai-cyan flex items-center justify-center text-sm font-bold">
                G
              </div>
              <span className="text-lg font-bold tracking-wide">
                gai<span className="text-gai-purple">pack</span>
              </span>
            </div>
            <div className="h-6 w-px bg-gai-border" />
            <h1 className="text-sm font-medium text-gai-muted">
              AI Document Reverse — ドキュメントリバース デモ
            </h1>
          </div>
          {step !== "upload" && (
            <button
              onClick={reset}
              className="text-sm text-gai-muted hover:text-white transition-colors px-3 py-1.5 rounded-md hover:bg-white/5"
            >
              最初からやり直す
            </button>
          )}
        </div>
      </header>

      {/* Step Indicator */}
      <div className="bg-[#0d0d15] border-b border-gai-border">
        <div className="max-w-7xl mx-auto px-6 py-4">
          <div className="flex items-center gap-2">
            {stepConfig.map((s, i) => {
              const state = getStepState(s.key);
              return (
                <div key={s.key} className="flex items-center gap-2">
                  <div
                    className={`flex items-center gap-2 px-3 py-1.5 rounded-full text-sm font-medium transition-all duration-300 ${
                      state === "active"
                        ? "bg-gradient-to-r from-gai-purple to-gai-cyan text-white shadow-lg shadow-gai-purple/20"
                        : state === "done"
                        ? "bg-gai-purple/20 text-purple-300 border border-gai-purple/30"
                        : "bg-gai-border/50 text-gai-muted/50"
                    }`}
                  >
                    <span>{s.icon}</span>
                    <span className="hidden sm:inline">{s.label}</span>
                  </div>
                  {i < stepConfig.length - 1 && (
                    <div
                      className={`w-8 h-px ${
                        state === "done" ? "bg-gai-purple" : "bg-gai-border"
                      }`}
                    />
                  )}
                </div>
              );
            })}
          </div>
        </div>
      </div>

      {/* Main Content */}
      <main className="flex-1 max-w-7xl mx-auto w-full px-6 py-8">
        {/* Upload Step */}
        {step === "upload" && (
          <div className="max-w-3xl mx-auto">
            <div className="text-center mb-8">
              <h2 className="text-3xl font-bold mb-3">
                <span className="bg-gradient-to-r from-gai-purple via-gai-cyan to-gai-magenta bg-clip-text text-transparent">
                  レガシーコード解析
                </span>
              </h2>
              <p className="text-gai-muted text-lg">
                RPG / COBOL / CL のソースコードをアップロードして、
                <br />
                AIがドキュメントを自動生成します
              </p>
            </div>

            <div
              className={`gai-card p-12 text-center cursor-pointer transition-all duration-200 ${
                isDragging ? "dropzone-active border-gai-cyan" : ""
              } ${code ? "border-gai-purple/50" : "hover:border-gai-purple/30"}`}
              onDragOver={(e) => {
                e.preventDefault();
                setIsDragging(true);
              }}
              onDragLeave={() => setIsDragging(false)}
              onDrop={handleDrop}
              onClick={() => fileInputRef.current?.click()}
            >
              <input
                ref={fileInputRef}
                type="file"
                className="hidden"
                accept=".rpgle,.rpg,.clle,.clp,.pf,.lf,.dds,.cbl,.cob,.txt"
                onChange={handleFileInput}
              />

              {code ? (
                <div>
                  <div className="text-4xl mb-4">✅</div>
                  <p className="text-lg font-medium text-white mb-1">{fileName}</p>
                  <p className="text-gai-muted text-sm mb-1">
                    {code.split("\n").length} 行 · {(code.length / 1024).toFixed(1)} KB
                  </p>
                  <p className="text-gai-muted text-xs mt-3">
                    クリックして別のファイルを選択
                  </p>
                </div>
              ) : (
                <div>
                  <div className="text-5xl mb-4 opacity-50">📄</div>
                  <p className="text-lg font-medium text-gai-muted mb-2">
                    ソースコードをドラッグ＆ドロップ
                  </p>
                  <p className="text-sm text-gai-muted/70">
                    または クリックしてファイルを選択
                  </p>
                  <p className="text-xs text-gai-muted/50 mt-3">
                    対応形式: .rpgle, .rpg, .clle, .clp, .pf, .lf, .dds, .cbl, .cob
                  </p>
                </div>
              )}
            </div>

            {/* Sample files for demo */}
            <div className="mt-4 flex items-center gap-3 justify-center flex-wrap">
              <span className="text-xs text-gai-muted/50">サンプル:</span>
              {[
                { file: "ORDENTR.RPGLE", label: "受注入力（RPG IV）" },
                { file: "INVBATCH.RPGLE", label: "在庫バッチ（RPG IV）" },
                { file: "BILPRT.RPG", label: "請求書発行（RPG III）" },
              ].map((s) => (
                <button
                  key={s.file}
                  onClick={(e) => {
                    e.stopPropagation();
                    loadSample(s.file);
                  }}
                  className="text-xs px-3 py-1.5 rounded-md border border-gai-border text-gai-muted hover:text-gai-cyan hover:border-gai-cyan/30 transition-colors"
                >
                  {s.label}
                </button>
              ))}
            </div>

            {code && (
              <div className="mt-6">
                {/* Code preview */}
                <div className="gai-card mb-6">
                  <div className="px-4 py-2 border-b border-gai-border flex items-center justify-between">
                    <span className="text-sm font-mono text-gai-muted">{fileName}</span>
                    <span className="text-xs text-gai-muted/50">プレビュー</span>
                  </div>
                  <pre className="p-4 text-sm font-mono text-gai-text/80 max-h-64 overflow-auto leading-relaxed">
                    {code.slice(0, 3000)}
                    {code.length > 3000 && (
                      <span className="text-gai-muted">
                        {"\n"}... ({code.split("\n").length}行中の一部を表示)
                      </span>
                    )}
                  </pre>
                </div>

                <button
                  onClick={startGeneration}
                  className="w-full py-4 rounded-xl font-bold text-lg bg-gradient-to-r from-gai-purple to-gai-cyan text-white hover:shadow-lg hover:shadow-gai-purple/25 transition-all duration-200 active:scale-[0.99]"
                >
                  ⚡ AIドキュメント生成を開始
                </button>
              </div>
            )}
          </div>
        )}

        {/* Generating / Document Step */}
        {(step === "generating" || step === "document") && (
          <div>
            <div className="flex items-center justify-between mb-6">
              <div>
                <h2 className="text-2xl font-bold flex items-center gap-2">
                  📄 生成ドキュメント
                  {isStreaming && (
                    <span className="text-sm font-normal text-gai-cyan gai-pulse">
                      生成中...
                    </span>
                  )}
                </h2>
                <p className="text-gai-muted text-sm mt-1">
                  {fileName} から自動生成されたドキュメント
                </p>
              </div>
              {step === "document" && (
                <button
                  onClick={startReview}
                  className="px-6 py-3 rounded-xl font-bold bg-gradient-to-r from-gai-cyan to-gai-purple text-white hover:shadow-lg hover:shadow-gai-cyan/25 transition-all duration-200"
                >
                  🔍 AIレビューを実行
                </button>
              )}
            </div>

            <div className="gai-card p-8" ref={docRef}>
              <div className={isStreaming ? "streaming-cursor" : ""}>
                {renderDocument()}
              </div>
            </div>
          </div>
        )}

        {/* Reviewing Step */}
        {step === "reviewing" && (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <div>
              <h2 className="text-2xl font-bold mb-4">📄 生成ドキュメント</h2>
              <div className="gai-card p-6 max-h-[70vh] overflow-auto">
                {renderDocument()}
              </div>
            </div>
            <div>
              <h2 className="text-2xl font-bold mb-4 flex items-center gap-2">
                🔍 AIレビュー
                <span className="text-sm font-normal text-gai-cyan gai-pulse">
                  解析中...
                </span>
              </h2>
              <div className="gai-card p-8 flex flex-col items-center justify-center min-h-[300px]">
                <div className="relative">
                  <div className="w-16 h-16 rounded-full border-2 border-gai-purple/30 border-t-gai-cyan animate-spin" />
                  <div className="absolute inset-0 flex items-center justify-center">
                    <span className="text-xl">🔍</span>
                  </div>
                </div>
                <p className="text-gai-muted mt-4">
                  ドキュメントとソースコードを照合しています...
                </p>
                <p className="text-gai-muted/50 text-sm mt-1">
                  業務ロジック・技術的負債・リスクを分析中
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Review Results */}
        {step === "review" && (
          <div className="grid grid-cols-1 lg:grid-cols-5 gap-6">
            <div className="lg:col-span-3">
              <h2 className="text-2xl font-bold mb-4">📄 生成ドキュメント</h2>
              <div className="gai-card p-6 max-h-[75vh] overflow-auto">
                {renderDocument()}
              </div>
            </div>
            <div className="lg:col-span-2">
              <div className="flex items-center justify-between mb-4">
                <h2 className="text-2xl font-bold">🔍 AIレビュー結果</h2>
                <div className="flex items-center gap-2 text-sm">
                  <span className="px-2 py-0.5 rounded bg-red-500/20 text-red-300">
                    重大 {reviewItems.filter((r) => r.severity === "critical").length}
                  </span>
                  <span className="px-2 py-0.5 rounded bg-amber-500/20 text-amber-300">
                    警告 {reviewItems.filter((r) => r.severity === "warning").length}
                  </span>
                  <span className="px-2 py-0.5 rounded bg-blue-500/20 text-blue-300">
                    情報 {reviewItems.filter((r) => r.severity === "info").length}
                  </span>
                </div>
              </div>

              <div className="space-y-3 max-h-[75vh] overflow-auto pr-1">
                {reviewItems.map((item) => {
                  const config = severityConfig[item.severity];
                  return (
                    <div
                      key={item.id}
                      className={`gai-card ${config.bg} border ${config.border} p-4`}
                    >
                      <div className="flex items-start gap-3">
                        <span className="text-lg mt-0.5">{config.icon}</span>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-1">
                            <span
                              className={`px-1.5 py-0.5 rounded text-xs font-bold text-white ${config.badge}`}
                            >
                              {config.label}
                            </span>
                            <span className="text-xs text-gai-muted">{item.category}</span>
                          </div>
                          <h3 className="font-bold text-sm text-white mb-1.5">
                            {item.title}
                          </h3>
                          <p className="text-sm text-gai-text/80 mb-2 leading-relaxed">
                            {item.description}
                          </p>
                          {item.source_reference && (
                            <div className="text-xs font-mono text-gai-muted bg-black/30 rounded px-2 py-1 mb-2 break-all">
                              📍 {item.source_reference}
                            </div>
                          )}
                          {item.question_for_stakeholder && (
                            <div className="text-sm bg-gai-purple/10 border border-gai-purple/20 rounded-lg px-3 py-2 mt-2">
                              <span className="text-xs text-gai-purple font-bold block mb-0.5">
                                💬 関係者への確認事項
                              </span>
                              <span className="text-gai-text/90">
                                {item.question_for_stakeholder}
                              </span>
                            </div>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>

              {/* Next steps hint */}
              <div className="mt-6 gai-card p-5 border-gai-cyan/30">
                <h3 className="font-bold text-gai-cyan text-sm mb-2">
                  📋 次のステップ：ヒアリング（Step 2）
                </h3>
                <p className="text-sm text-gai-muted leading-relaxed">
                  上記のレビュー結果をもとに、業務担当者・有識者へのヒアリングを実施します。
                  「関係者への確認事項」を質問リストとして活用し、
                  AIが検出した不明点にコンテキスト（業務知識・運用ルール）を注入することで、
                  ドキュメントの精度を <span className="text-gai-cyan font-bold">60% → 90%</span> に引き上げます。
                </p>
              </div>
            </div>
          </div>
        )}
      </main>

      {/* Footer */}
      <footer className="border-t border-gai-border py-4 px-6">
        <div className="max-w-7xl mx-auto flex items-center justify-between text-xs text-gai-muted/50">
          <span>AI Document Reverse Demo — gaipack AI Modernization</span>
          <span>Powered by Claude API</span>
        </div>
      </footer>
    </div>
  );
}
