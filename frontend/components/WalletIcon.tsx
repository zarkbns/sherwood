import { walletIconDataUri } from "@/lib/walletIcons";

/**
 * A generated mark for a wallet row, a connected address, or a decorative badge —
 * deterministic per seed (see lib/walletIcons). Plain <img> on purpose: the src is an
 * inline SVG data URI, so there is nothing for the image optimizer or the network to do.
 */
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
