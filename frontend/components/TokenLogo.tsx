"use client";

import { useState } from "react";

/**
 * A token's mark in a wallet-style row.
 *
 * Drop a file at `public/tokens/<SYMBOL>` and it is used automatically; anything without
 * one falls back to a monogram tile, so a newly registered asset always renders something
 * recognisable. SYMBOL is upper-cased and comes from the registry, so no per-asset code is
 * needed to add or remove one.
 *
 * Extensions are tried in order rather than requiring one format: the brand set that came
 * in mixes PNG and JPEG, and renaming a JPEG to .png to satisfy the convention would be a
 * lie about the bytes. First candidate that loads wins; once they are exhausted, monogram.
 *
 * Deliberately a plain <img> rather than next/image: the file is optional, so a missing one
 * must fail in the browser (where onError can step to the next candidate) instead of going
 * through the image optimizer, which answers 404 for an absent local asset.
 */
const EXTENSIONS = ["png", "jpeg", "jpg", "webp"] as const;

export function TokenLogo({ symbol, className = "h-9 w-9" }: { symbol: string; className?: string }) {
  const [attempt, setAttempt] = useState(0);
  const symbolUpper = symbol.toUpperCase();

  if (attempt >= EXTENSIONS.length) {
    return (
      <span
        aria-hidden
        title={symbolUpper}
        className={`${className} flex shrink-0 items-center justify-center rounded-xl bg-surface-2 font-display text-xs font-bold text-fog`}
      >
        {symbolUpper.slice(0, 2)}
      </span>
    );
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element -- see the note above: the file is optional
    <img
      src={`/tokens/${symbolUpper}.${EXTENSIONS[attempt]}`}
      alt=""
      onError={() => setAttempt((a) => a + 1)}
      loading="lazy"
      className={`${className} shrink-0 rounded-xl bg-surface-2 object-cover`}
    />
  );
}
