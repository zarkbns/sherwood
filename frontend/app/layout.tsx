import type { Metadata } from "next";
import { Providers } from "./Providers";
import "./globals.css";

export const metadata: Metadata = {
  title: "SherwoodNotes — Keep the upside. Cap your losses.",
  description:
    "Put a floor under the stocks you own on Robinhood Chain. Every gain above the floor stays yours; if the price falls through it, the vault pays you the gap.",
  // Resolves the relative OG/icon paths below into absolute URLs for link crawlers.
  metadataBase: new URL("https://sherwoodnotes.vercel.app"),
  openGraph: {
    title: "SherwoodNotes — Keep the upside. Cap your losses.",
    description:
      "Pick a floor price for a stock you hold. Keep everything above it, get paid the gap below it, and settle against prices read from the chain.",
    url: "https://sherwoodnotes.vercel.app",
    siteName: "SherwoodNotes",
    type: "website",
    images: [{ url: "/og.png", width: 2048, height: 762, alt: "SherwoodNotes — protection for the stocks you hold" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "SherwoodNotes — Keep the upside. Cap your losses.",
    description: "Put a floor under the stocks you own on Robinhood Chain.",
    images: ["/og.png"],
  },
  icons: {
    icon: "/black-logo.png",
    apple: "/black-logo.png",
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
