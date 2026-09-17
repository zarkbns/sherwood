"use client";

import { useState } from "react";

/**
 * A token's mark in a wallet-style row.
 *
 * Drop a file at `public/tokens/<SYMBOL>.png` (e.g. `TSLA.png`) and it is used
 * automatically; anything without one falls back to a monogram tile, so a newly
 * registered asset always renders something recognisable. SYMBOL is upper-cased and comes
 * from the registry, so no per-asset code is needed to add or remove one.
 *
 * Deliberately a plain <img> rather than next/image: the file is optional, so a missing
 * one must fail in the browser (where onError can swap in the monogram) instead of going
 * through the image optimizer, which answers 404 for an absent local asset.
 */
export function TokenLogo({ symbol, className = "h-9 w-9" }: { symbol: string; className?: string }) {
  const [failed, setFailed] = useState(false);
  const src = `/tokens/${symbol.toUpperCase()}.png`;

  if (failed) {
    return (
      <span
        aria-hidden
        className={`${className} flex shrink-0 items-center justify-center rounded-xl bg-surface-2 font-display text-xs font-bold text-fog`}
      >
        {symbol.slice(0, 2).toUpperCase()}
      </span>
    );
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element -- see the note above: the file is optional
    <img
      src={src}
      alt=""
      onError={() => setFailed(true)}
      loading="lazy"
      className={`${className} shrink-0 rounded-xl bg-surface-2 object-cover`}
    />
  );
}
