"use client";

import { useState } from "react";
import Link from "next/link";
import { HbarInput, HederaPortalFaucet } from "@scaffold-hbar-ui/components";
import { Address, Hex, erc20Abi, formatUnits, zeroAddress } from "viem";
import { useAccount, useConfig, useReadContract, useWriteContract } from "wagmi";
import { HederaAddress } from "~~/components/scaffold-hbar";
import {
  useDeployedContractInfo,
  useScaffoldReadContract,
  useTargetNetwork,
  useTransactor,
} from "~~/hooks/scaffold-hbar";
import { useSale } from "~~/hooks/useSale";
import { useWatchedBalance } from "~~/hooks/useWatchedBalance";
import { TINYBAR_DECIMALS, formatAmount, hbarToTinybars, minTokensOut, tinybarsToWeibars } from "~~/utils/sale/units";
import { AllowedChainIds } from "~~/utils/scaffold-hbar";
import { simulateContractWriteAndNotifyError } from "~~/utils/scaffold-hbar/contract";
import { erc6538RegistryAbi, stealthBuyAbi } from "~~/utils/stealth/abi";
import { SCHEME_ID, decodeMetaAddress, generateStealthAddress, parseRecipient } from "~~/utils/stealth/stealthAddress";

/** Accept up to 1% fewer tokens than quoted if the oracle moves before the transaction lands. */
const SLIPPAGE_BPS = 100n;
/** Pays the stealth account's first transaction, the sweep, which cost about 0.03 HBAR on testnet. */
const DEFAULT_STIPEND_HBAR = "0.5";
/** Below this the stealth address may not afford its sweep, and topping it up from a known wallet links the two. */
const MIN_STIPEND_TINYBARS = 10_000_000n;
/**
 * Lazy-creating the stealth account and delivering the token used 1,433,536 gas on testnet, only 5% under the relay's
 * estimate. Hedera charges the gas used, but the payer must hold the whole limit's worth up front, so keep it close.
 */
const BUY_FOR_GAS = 2_000_000n;

/** Buys the sale's token for someone who registered a meta-address, delivering it to a fresh stealth address. */
export const BuyPrivatelyCard = () => {
  const { address } = useAccount();
  const { targetNetwork } = useTargetNetwork();
  const sale = useSale();
  const { data: diamond } = useDeployedContractInfo({ contractName: "Diamond" });
  const [recipient, setRecipient] = useState("");
  const [hbar, setHbar] = useState("");
  const [stipendHbar, setStipendHbar] = useState(DEFAULT_STIPEND_HBAR);
  const [delivered, setDelivered] = useState<Address>();
  const payment = hbarToTinybars(hbar);
  const stipend = hbarToTinybars(stipendHbar);
  const isStipendTooLow = stipend !== undefined && stipend < MIN_STIPEND_TINYBARS;

  const parsedRecipient = parseRecipient(recipient);
  const recipientAddress = parsedRecipient && "address" in parsedRecipient ? parsedRecipient.address : undefined;
  const { data: registered } = useReadContract({
    chainId: targetNetwork.id,
    address: diamond?.address,
    abi: erc6538RegistryAbi,
    functionName: "stealthMetaAddressOf",
    args: [recipientAddress ?? zeroAddress, SCHEME_ID],
    query: { enabled: diamond !== undefined && recipientAddress !== undefined },
  });
  const metaAddress = parsedRecipient && "metaAddress" in parsedRecipient ? parsedRecipient.metaAddress : registered;
  const metaAddressError = metaAddress === undefined || metaAddress === "0x" ? undefined : invalidReason(metaAddress);

  const { data: quote } = useScaffoldReadContract({
    contractName: "Diamond",
    functionName: "quote",
    args: [payment],
    query: { enabled: sale.isLaunched && payment !== undefined },
  });
  const { data: isStopped } = useScaffoldReadContract({ contractName: "Diamond", functionName: "isStopped" });
  const { data: symbol } = useReadContract({
    chainId: targetNetwork.id,
    address: sale.token,
    abi: erc20Abi,
    functionName: "symbol",
    query: { enabled: sale.isLaunched },
  });
  const { data: walletBalance } = useWatchedBalance(address);
  // The relay cannot simulate a transaction from an address Hedera has no account for.
  const isUnfunded = walletBalance?.value === 0n;

  const wagmiConfig = useConfig();
  const transactor = useTransactor();
  const { writeContractAsync } = useWriteContract();
  const [isBuying, setIsBuying] = useState(false);

  const canBuy =
    address !== undefined &&
    !isUnfunded &&
    isStopped !== true &&
    metaAddress !== undefined &&
    metaAddress !== "0x" &&
    metaAddressError === undefined &&
    payment !== undefined &&
    stipend !== undefined &&
    !isStipendTooLow &&
    quote !== undefined;

  const buy = async () => {
    if (!diamond || !metaAddress || payment === undefined || stipend === undefined || quote === undefined) return;
    const { stealthAddress, ephemeralPublicKey, viewTag } = generateStealthAddress(metaAddress);
    const request = {
      chainId: targetNetwork.id,
      address: diamond.address,
      abi: stealthBuyAbi,
      functionName: "buyFor",
      args: [stealthAddress, ephemeralPublicKey, viewTag, minTokensOut(quote, SLIPPAGE_BPS), stipend],
      // The contract sees tinybars; a transaction's value is denominated in weibars.
      value: tinybarsToWeibars(payment + stipend),
      gas: BUY_FOR_GAS,
    } as const;
    try {
      setIsBuying(true);
      await simulateContractWriteAndNotifyError({
        wagmiConfig,
        writeContractParams: request,
        chainId: targetNetwork.id as AllowedChainIds,
      });
      const hash = await transactor(() => writeContractAsync(request));
      if (hash) setDelivered(stealthAddress);
    } catch {
      // The simulation or the transactor has already shown the error.
    } finally {
      setIsBuying(false);
    }
  };

  if (sale.isLoading) return null;

  return (
    <div className="bg-base-100 rounded-2xl shadow-md p-8 border border-base-300">
      <h2 className="font-bold text-xl m-0">Buy for someone privately</h2>
      <p className="text-sm text-base-content/70 mt-1">
        The tokens go to a one-time address derived from the recipient&apos;s meta-address. Only the recipient can tell
        it is theirs. Your address, the amount and the time stay public.
      </p>

      {!sale.isLaunched ? (
        <p className="text-sm m-0 mt-4">
          No token on sale yet. The diamond&apos;s admin launches the sale on the{" "}
          <Link href="/sale" className="link">
            Sale page
          </Link>
          .
        </p>
      ) : (
        <>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
            <label className="flex flex-col gap-1 text-sm md:col-span-2">
              <span className="font-medium">Recipient</span>
              <input
                className="input input-bordered w-full font-mono text-sm"
                placeholder="0x… their wallet address, or their stealth meta-address"
                value={recipient}
                onChange={event => {
                  setRecipient(event.target.value.trim());
                  setDelivered(undefined);
                }}
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              <span className="font-medium">Pay with HBAR</span>
              <HbarInput
                name="private-hbar-amount"
                placeholder="0.0"
                onValueChange={({ valueInNative }) => setHbar(valueInNative)}
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              <span className="font-medium">Stipend for the recipient&apos;s gas (HBAR)</span>
              <input
                className="input input-bordered w-full"
                value={stipendHbar}
                onChange={event => setStipendHbar(event.target.value)}
              />
            </label>
          </div>

          {isStipendTooLow && (
            <p className="text-sm text-warning mt-3 mb-0">
              The stipend must be at least {formatUnits(MIN_STIPEND_TINYBARS, TINYBAR_DECIMALS)} HBAR: the stealth
              address pays for its sweep from it.
            </p>
          )}
          {recipient !== "" && parsedRecipient === undefined && (
            <p className="text-sm text-warning mt-3 mb-0">
              Enter the recipient&apos;s wallet address, or the stealth meta-address their Receive privately card shows.
            </p>
          )}
          {recipientAddress && registered === "0x" && (
            <p className="text-sm text-warning mt-3 mb-0">
              This address has not registered a meta-address here. Ask for their stealth meta-address instead.
            </p>
          )}
          {metaAddressError && (
            <p className="text-sm text-error mt-3 mb-0">
              {recipientAddress
                ? "This address registered a meta-address this page cannot use."
                : "This is not a stealth meta-address this page can use."}{" "}
              {metaAddressError}.
            </p>
          )}

          <p className="text-sm text-base-content/70 mt-3 mb-4">
            Sends {formatUnits((payment ?? 0n) + (stipend ?? 0n), TINYBAR_DECIMALS)} HBAR (payment + stipend)
            {quote !== undefined &&
              ` · The recipient receives about ${formatAmount(quote, sale.decimals)} ${symbol ?? ""}`}
          </p>

          <button className="btn btn-primary btn-sm" onClick={buy} disabled={!canBuy || isBuying}>
            {isBuying && <span className="loading loading-spinner loading-xs" />}
            Buy privately
          </button>

          {delivered && (
            <div className="flex flex-wrap items-center gap-2 text-sm mt-4">
              <span>Delivered to</span>
              <HederaAddress address={delivered} chain={targetNetwork} />
            </div>
          )}
          {isStopped && <p className="text-sm text-warning mt-4 mb-0">Sales are paused.</p>}
          {isUnfunded && (
            <p className="text-sm text-warning mt-4 mb-0">
              This wallet holds no HBAR, so it cannot pay for a transaction. Fund it first:{" "}
              <HederaPortalFaucet variant="link" label="Use the faucet" showIcon={false} />
            </p>
          )}
        </>
      )}
    </div>
  );
};

function invalidReason(metaAddress: Hex): string | undefined {
  try {
    decodeMetaAddress(metaAddress);
    return undefined;
  } catch (error) {
    return (error as Error).message;
  }
}
