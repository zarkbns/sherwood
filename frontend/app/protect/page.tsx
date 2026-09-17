"use client";

import { Header } from "@/components/Header";
import { EmptyState, Eyebrow, IconShield } from "@/components/ui";
import { ProtectFlow } from "@/components/ProtectFlow";
import { useDeployed, useAssets } from "@/lib/protocol";

export default function Protect() {
  const { deployed } = useDeployed();
  const { assets } = useAssets();

  if (!deployed) {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-5xl px-5 pb-28 pt-8 sm:px-6 sm:pb-14 sm:pt-12">
          <EmptyState
            icon={<IconShield className="h-6 w-6" />}
            title="Not deployed on this network"
            body="Switch to Robinhood Chain testnet where Sherwood is deployed."
          />
        </main>
      </>
    );
  }

  return (
    <>
      <Header />
      <main className="mx-auto max-w-5xl px-5 pb-28 pt-8 sm:px-6 sm:pb-14 sm:pt-12">
        <section className="rise">
          <Eyebrow>New protection</Eyebrow>
          <h1 className="mt-2 font-display text-3xl font-bold tracking-tight sm:text-4xl">
            Define the downside<span className="text-action">.</span>
          </h1>
          <p className="mt-2 text-sm text-mist">
            Hold it, protect it, keep the upside. Terms are priced live by the contract and never change after creation.
          </p>
        </section>

        {assets.length === 0 ? (
          <div className="mt-8">
            <EmptyState
              icon={<IconShield className="h-6 w-6" />}
              title="No registered assets"
              body="No stock tokens are registered on this chain yet."
            />
          </div>
        ) : (
          <div className="mt-8">
            <ProtectFlow variant="page" />
          </div>
        )}
      </main>
    </>
  );
}
