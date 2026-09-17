import { createAvatar } from "@dicebear/core";
import { shapes } from "@dicebear/collection";

/**
 * Generated marks for wallets and addresses — DiceBear "shapes", deterministic per seed.
 * The same wallet row or address renders the same icon on the server and in the browser,
 * with no third-party call at render time and no brand assets to maintain. The generator
 * never picks its own colors: both palettes are the app's own (the accent green plus
 * neutrals, or ink tones for light surfaces), so an icon can never arrive off-brand.
 */
const PALETTES = {
  brand: { s1: "c0ff00", s2: "e6e6e6", s3: "9a9a9a" },
  ink: { s1: "0a0a0a", s2: "262626", s3: "9a9a9a" },
} as const;

export function walletIconDataUri(
  seed: string,
  opts: { background?: string | null; palette?: keyof typeof PALETTES } = {}
): string {
  const palette = PALETTES[opts.palette ?? "brand"];
  const background = opts.background === undefined ? "1a1a1a" : opts.background;
  return createAvatar(shapes, {
    seed,
    backgroundColor: [background ?? "transparent"],
    shape1Color: [palette.s1],
    shape2Color: [palette.s2],
    shape3Color: [palette.s3],
  }).toDataUri();
}
