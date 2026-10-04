"use client";

import { useEffect, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { formatUnits, zeroHash } from "viem";
import { useAccount, useBalance, useBlockNumber } from "wagmi";
import {
  useDeployedContractInfo,
  useScaffoldReadContract,
  useScaffoldWriteContract,
  useTargetNetwork,
} from "~~/hooks/scaffold-hbar";
import { useSale } from "~~/hooks/useSale";
import { formatAmount, hbarToTinybars, parsePositive, tinybarsToWeibars } from "~~/utils/sale/units";

/** Lattice's `DEFAULT_ADMIN_ROLE`. */
const ADMIN_ROLE = zeroHash;
const TOKEN_DECIMALS = 8;
/** HTS charges about $1 to create a token. Hedera deducts only the fee, and the rest stays in the diamond. */
const CREATION_FEE_HBAR = "20";

export const AdminCard = () => {
  const { address } = useAccount();
  const { targetNetwork } = useTargetNetwork();
  const sale = useSale();
  const { data: diamond } = useDeployedContractInfo({ contractName: "Diamond" });
  const { data: isAdmin } = useScaffoldReadContract({
    contractName: "Diamond",
    functionName: "hasRole",
    args: [ADMIN_ROLE, address],
  });
  const queryClient = useQueryClient();
  const {
    data: balance,
    refetch: refetchBalance,
    queryKey: balanceQueryKey,
  } = useBalance({ address: diamond?.address, chainId: targetNetwork.id });
  const { data: blockNumber } = useBlockNumber({ watch: true, chainId: targetNetwork.id });

  useEffect(() => {
    queryClient.invalidateQueries({ queryKey: balanceQueryKey });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [blockNumber]);

  const { writeContractAsync, isMining } = useScaffoldWriteContract({ contractName: "Diamond" });

  const [name, setName] = useState("Lattice Sale Token");
  const [symbol, setSymbol] = useState("LST");
  const [supply, setSupply] = useState("1000000");
  const [typedPrice, setTypedPrice] = useState<string>();
  const [withdrawal, setWithdrawal] = useState("");

  if (!isAdmin || sale.isLoading) return null;

  const price = typedPrice ?? (sale.isLaunched ? formatUnits(sale.priceUsd, 18) : "0.05");
  const priceUsd = parsePositive(price, 18);
  const supplyUnits = parsePositive(supply, TOKEN_DECIMALS);
  const withdrawalTinybars = hbarToTinybars(withdrawal);

  const launch = async () => {
    if (priceUsd === undefined || supplyUnits === undefined) return;
    await writeContractAsync({
      functionName: "launchSale",
      args: [name, symbol, "Launched with Lattice Hedera Template", TOKEN_DECIMALS, supplyUnits, priceUsd],
      value: tinybarsToWeibars(hbarToTinybars(CREATION_FEE_HBAR) ?? 0n),
    });
  };

  const setSalePrice = async () => {
    if (priceUsd === undefined) return;
    const hash = await writeContractAsync({ functionName: "setSalePrice", args: [priceUsd] });
    if (hash) setTypedPrice(undefined);
  };

  const withdraw = async () => {
    if (withdrawalTinybars === undefined) return;
    // `withdrawProceeds` takes tinybars as an argument; it is not a payable call.
    await writeContractAsync({ functionName: "withdrawProceeds", args: [address, withdrawalTinybars] });
    setWithdrawal("");
    await refetchBalance();
  };

  return (
    <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-primary/40">
      <h2 className="font-bold text-xl m-0">Admin</h2>
      <p className="text-sm text-base-content/70 mt-1">
        You hold the diamond&apos;s admin role. Every action here is a call to a facet of the same contract.
      </p>

      {!sale.isLaunched ? (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
          <Field label="Token name" value={name} onChange={setName} />
          <Field label="Symbol" value={symbol} onChange={setSymbol} />
          <Field label="Supply (whole tokens)" value={supply} onChange={setSupply} />
          <Field label="Price per token (USD)" value={price} onChange={setTypedPrice} />
          <div className="md:col-span-2">
            <button
              className="btn btn-primary btn-sm"
              onClick={launch}
              disabled={isMining || priceUsd === undefined || supplyUnits === undefined}
            >
              Create the token and open the sale
            </button>
            <p className="text-xs text-base-content/60 mt-2 mb-0">
              Sends {CREATION_FEE_HBAR} HBAR to cover the Hedera Token Service creation fee. Only the fee is deducted.
              The rest stays in the diamond, where you can withdraw it.
            </p>
          </div>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mt-4">
          <div>
            <Field label="Price per token (USD)" value={price} onChange={setTypedPrice} />
            <button
              className="btn btn-primary btn-sm mt-3"
              onClick={setSalePrice}
              disabled={isMining || priceUsd === undefined}
            >
              Set price
            </button>
          </div>
          <div>
            <Field
              label={`Withdraw HBAR (diamond holds ${balance ? formatAmount(balance.value, balance.decimals) : "…"})`}
              value={withdrawal}
              onChange={setWithdrawal}
            />
            <button
              className="btn btn-primary btn-sm mt-3"
              onClick={withdraw}
              disabled={isMining || withdrawalTinybars === undefined}
            >
              Withdraw to my wallet
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

type FieldProps = { label: string; value: string; onChange: (value: string) => void };

const Field = ({ label, value, onChange }: FieldProps) => (
  <label className="flex flex-col gap-1 text-sm">
    <span className="font-medium">{label}</span>
    <input className="input input-bordered w-full" value={value} onChange={event => onChange(event.target.value)} />
  </label>
);
