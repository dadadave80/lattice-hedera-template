import Link from "next/link";
import type { NextPage } from "next";
import { PrivatePurchases } from "~~/components/private/PrivatePurchases";

const Private: NextPage = () => {
  return (
    <div className="w-full max-w-4xl mx-auto px-5 py-10 flex flex-col gap-6">
      <div>
        <h1 className="text-3xl font-bold m-0">Private purchases</h1>
        <p className="text-base-content/70 m-0 mt-2">
          Buy tokens for someone who has no Hedera account, no token association and no HBAR, in one transaction: a
          gift, a grant, a payroll run. The tokens go to a one-time ERC-5564 stealth address. Hedera creates the account
          the moment HBAR reaches it, and the HBAR sent with the tokens pays for moving them on.
        </p>
        <p className="text-base-content/70 m-0 mt-2">
          Tokens sell at a USD price read live from Chainlink HBAR/USD. To buy for yourself, use the{" "}
          <Link href="/sale" className="link">
            Sale
          </Link>{" "}
          page.
        </p>
      </div>
      <PrivatePurchases />
    </div>
  );
};

export default Private;
