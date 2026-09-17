import type { Metadata } from "next";
import { Providers } from "./Providers";
import "./globals.css";

export const metadata: Metadata = {
  title: "SherwoodNotes — Keep the upside. Define the downside.",
  description: "Programmable downside protection for tokenized stocks on Robinhood Chain.",
  // Resolves the relative OG/icon paths below into absolute URLs for link crawlers.
  metadataBase: new URL("https://sherwoodnotes.vercel.app"),
  openGraph: {
    title: "SherwoodNotes — Keep the upside. Define the downside.",
    description:
      "Buy a floor price on a tokenized stock, keep every gain above it, and settle the downside against verified prices.",
    url: "https://sherwoodnotes.vercel.app",
    siteName: "SherwoodNotes",
    type: "website",
    images: [{ url: "/og.png", width: 2048, height: 762, alt: "SherwoodNotes — programmable downside protection" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "SherwoodNotes — Keep the upside. Define the downside.",
    description: "Programmable downside protection for tokenized stocks on Robinhood Chain.",
    images: ["/og.png"],
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
