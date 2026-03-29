import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "AI Document Reverse | gaipack",
  description: "レガシーコードからAIでドキュメントを自動生成するデモ",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ja">
      <body className="min-h-screen">{children}</body>
    </html>
  );
}
