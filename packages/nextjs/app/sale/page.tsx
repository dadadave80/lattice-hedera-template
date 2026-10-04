import Link from "next/link";
import type { NextPage } from "next";
import { AdminCard } from "~~/components/sale/AdminCard";
import { SaleCard } from "~~/components/sale/SaleCard";
import { getMetadata } from "~~/utils/scaffold-hbar/getMetadata";

export const metadata = getMetadata({
  title: "Sale",
  description: "Buy the diamond's HTS token for HBAR at a USD price from Chainlink",
});

const Sale: NextPage = () => {
  return (
    <div className="flex items-center flex-col grow">
      <div className="hedera-gradient dark:bg-none dark:bg-hedera-charcoal w-full py-12 px-5">
        <div className="max-w-2xl mx-auto text-center text-white">
          <h1 className="text-3xl font-bold m-0">An upgradeable token sale on Hedera</h1>
          <p className="m-0 mt-3 text-white/80">
            One Lattice diamond creates an HTS token, sells it for HBAR at a USD price from Chainlink, and can be
            upgraded while it runs.
          </p>
        </div>
      </div>

      <div className="w-full max-w-4xl mx-auto px-5 -mt-6 pb-16 flex flex-col gap-6">
        <SaleCard />
        <AdminCard />

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300">
            <h3 className="font-bold text-lg m-0 mb-2">Inspect and upgrade the diamond</h3>
            <p className="text-base-content/70 text-sm m-0 mb-4">
              See which facet serves each function, then cut a new facet into the live contract.
            </p>
            <Link href="/diamond" className="btn btn-primary btn-sm">
              Open Diamond
            </Link>
          </div>
          <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300">
            <h3 className="font-bold text-lg m-0 mb-2">Call any function</h3>
            <p className="text-base-content/70 text-sm m-0 mb-4">
              Debug Contracts lists every function of every facet under one contract, <code>Diamond</code>.
            </p>
            <Link href="/debug" className="btn btn-primary btn-sm">
              Open Debug
            </Link>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Sale;
