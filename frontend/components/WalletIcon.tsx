/**
 * Deterministic per-seed identicon — no external avatar library.
 * A 5×5 grid derived from the seed, rendered as an inline SVG data URI.
 */

function hashString(str: string): number {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash) + str.charCodeAt(i);
    hash |= 0;
  }
  return Math.abs(hash);
}

const PALETTES = {
  brand: "#c0ff00",
  ink: "#0a0a0a",
} as const;

export function walletIconDataUri(
  seed: string,
  opts: { background?: string | null; palette?: keyof typeof PALETTES } = {}
): string {
  const hash = hashString(seed);
  const size = 40;
  const cellSize = size / 5;
  const color = PALETTES[opts.palette ?? "brand"];

  let rects = "";
  for (let y = 0; y < 5; y++) {
    for (let x = 0; x < 5; x++) {
      const idx = y * 5 + x;
      if ((hash >> idx) & 1) {
        rects += `<rect x="${x * cellSize}" y="${y * cellSize}" width="${cellSize}" height="${cellSize}" fill="${color}" />`;
      }
    }
  }

  const bg = opts.background === undefined ? "transparent" : opts.background;
  const backgroundRect =
    bg !== "transparent" ? `<rect width="${size}" height="${size}" fill="${bg}" />` : "";

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}" shape-rendering="crispEdges">${backgroundRect}${rects}</svg>`;
  return `data:image/svg+xml,${encodeURIComponent(svg)}`;
}

export function WalletIcon({
  seed,
  className = "h-6 w-6",
  background,
  palette,
}: {
  seed: string;
  className?: string;
  background?: string | null;
  palette?: "brand" | "ink";
}) {
  return (
    <img
      src={walletIconDataUri(seed, { background, palette })}
      alt=""
      aria-hidden
      className={`${className} shrink-0 object-contain`}
    />
  );
}
