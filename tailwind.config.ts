import type { Config } from "tailwindcss";
const config: Config = {
  content: [
    "./src/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        gai: {
          dark: "#0a0a0f",
          card: "#12121a",
          border: "#1e1e2e",
          purple: "#9333ea",
          cyan: "#06b6d4",
          magenta: "#d946ef",
          text: "#e2e8f0",
          muted: "#94a3b8",
        },
      },
      fontFamily: {
        display: ['"Noto Sans JP"', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'monospace'],
      },
    },
  },
  plugins: [],
};
export default config;
