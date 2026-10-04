import { announcementAbi } from "./abi";
import { SCHEME_ID } from "./stealthAddress";
import { Address, Hex, decodeEventLog, toEventSelector } from "viem";

export const ANNOUNCEMENT_TOPIC = toEventSelector(announcementAbi[0]);

/** The mirror node searches a topic only within a timestamp range of at most 7 days. */
const MAX_WINDOW_SECONDS = 7 * 24 * 60 * 60;
const PAGE_SIZE = 100;

/** A contract log as the mirror node's `/api/v1/contracts/{id}/results/logs` returns it. */
export type MirrorLog = { address: string; topics: Hex[]; data: Hex; transaction_hash: Hex; timestamp: string };

export type Announcement = {
  schemeId: bigint;
  stealthAddress: Address;
  caller: Address;
  ephemeralPublicKey: Hex;
  metadata: Hex;
  transactionHash: Hex;
  /** Consensus time, seconds.nanoseconds. */
  timestamp: string;
};

type FetchJson = (url: string) => Promise<unknown>;

/** Splits `[from, to)`, in seconds, into back-to-back ranges the mirror node accepts with a topic filter. */
export function searchWindows(from: number, to: number): { gte: number; lt: number }[] {
  const windows = [];
  for (let gte = from; gte < to; gte += MAX_WINDOW_SECONDS) {
    windows.push({ gte, lt: Math.min(gte + MAX_WINDOW_SECONDS, to) });
  }
  return windows;
}

export function decodeAnnouncement(log: MirrorLog): Announcement | undefined {
  try {
    const { args } = decodeEventLog({
      abi: announcementAbi,
      topics: log.topics as [Hex, ...Hex[]],
      data: log.data,
    });
    return {
      schemeId: args.schemeId,
      stealthAddress: args.stealthAddress,
      caller: args.caller,
      ephemeralPublicKey: args.ephemeralPubKey,
      metadata: args.metadata,
      transactionHash: log.transaction_hash,
      timestamp: log.timestamp,
    };
  } catch {
    return undefined;
  }
}

/**
 * Every scheme-1 announcement `contract` has emitted, oldest first. It reads them all, so the mirror node does not
 * learn which ones the reader is looking for.
 */
export async function fetchAnnouncements(
  mirrorNodeUrl: string,
  contract: Address,
  now = Date.now(),
  fetchJson: FetchJson = getJson,
): Promise<Announcement[]> {
  const { created_timestamp } = (await fetchJson(`${mirrorNodeUrl}/api/v1/contracts/${contract}`)) as {
    created_timestamp: string;
  };
  const announcements: Announcement[] = [];
  for (const { gte, lt } of searchWindows(Math.floor(Number(created_timestamp)), Math.floor(now / 1000) + 1)) {
    let url: string | undefined =
      `${mirrorNodeUrl}/api/v1/contracts/${contract}/results/logs?topic0=${ANNOUNCEMENT_TOPIC}` +
      `&timestamp=gte:${gte}&timestamp=lt:${lt}&limit=${PAGE_SIZE}&order=asc`;
    while (url) {
      const page = (await fetchJson(url)) as { logs: MirrorLog[]; links?: { next: string | null } };
      for (const log of page.logs) {
        const announcement = decodeAnnouncement(log);
        if (announcement?.schemeId === SCHEME_ID) announcements.push(announcement);
      }
      url = page.links?.next ? `${mirrorNodeUrl}${page.links.next}` : undefined;
    }
  }
  return announcements;
}

/** The public mirror node of a Hedera network. */
export function mirrorNodeUrl(chainId: number): string {
  return chainId === 295 ? "https://mainnet.mirrornode.hedera.com" : "https://testnet.mirrornode.hedera.com";
}

async function getJson(url: string): Promise<unknown> {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`The mirror node answered ${response.status} for ${url}`);
  return response.json();
}
