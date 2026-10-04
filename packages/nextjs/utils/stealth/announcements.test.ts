import { announcementAbi } from "./abi";
import { ANNOUNCEMENT_TOPIC, MirrorLog, decodeAnnouncement, fetchAnnouncements, searchWindows } from "./announcements";
import { Address, Hex, encodeAbiParameters, encodeEventTopics } from "viem";
import { describe, expect, it } from "vitest";

const DIAMOND = "0x4Eb94355872aB90ab258B940eE98B706dC9B2aa9";
const MIRROR = "https://testnet.mirrornode.hedera.com";
const STEALTH = "0x547A8b82CA05686c1099A9CBA53E521D4063b80A";
const BUYER = "0x1111111111111111111111111111111111111111";
const EPHEMERAL = "0x03312f36039e1479d10ba17eef98bba5f9a299af277c1dfac2e9134f352892b166";
const METADATA = "0xf8a9059cbb";
const DAY = 24 * 60 * 60;

const announcementLog = (schemeId: bigint, transactionHash: Hex, timestamp: string): MirrorLog => ({
  address: DIAMOND.toLowerCase(),
  topics: encodeEventTopics({
    abi: announcementAbi,
    eventName: "Announcement",
    args: { schemeId, stealthAddress: STEALTH, caller: BUYER },
  }) as Hex[],
  data: encodeAbiParameters([{ type: "bytes" }, { type: "bytes" }], [EPHEMERAL, METADATA]),
  transaction_hash: transactionHash,
  timestamp,
});

describe("ANNOUNCEMENT_TOPIC", () => {
  it("is the topic the canonical ERC5564Announcer emits", () => {
    // PUSH32 in the announcer bytecode of ScopeLift's stealth-address-sdk, src/config/bytecode.ts at commit 88bcc27.
    expect(ANNOUNCEMENT_TOPIC).toBe("0x5f0eab8057630ba7676c49b4f21a0231414e79474595be8e4c432fbf6bf0f4e7");
  });
});

describe("searchWindows", () => {
  it("covers the range with back-to-back windows of at most 7 days", () => {
    const from = 1_790_000_000;
    const to = from + 20 * DAY + 5;

    expect(searchWindows(from, to)).toEqual([
      { gte: from, lt: from + 7 * DAY },
      { gte: from + 7 * DAY, lt: from + 14 * DAY },
      { gte: from + 14 * DAY, lt: to },
    ]);
  });

  it("returns one window for a range shorter than 7 days", () => {
    expect(searchWindows(100, 200)).toEqual([{ gte: 100, lt: 200 }]);
  });

  it("returns no window for an empty range", () => {
    expect(searchWindows(200, 200)).toEqual([]);
  });
});

describe("decodeAnnouncement", () => {
  it("reads the event's fields and where it was emitted", () => {
    expect(decodeAnnouncement(announcementLog(1n, "0xabcd", "1791095245.327786388"))).toEqual({
      schemeId: 1n,
      stealthAddress: STEALTH,
      caller: BUYER,
      ephemeralPublicKey: EPHEMERAL,
      metadata: METADATA,
      transactionHash: "0xabcd",
      timestamp: "1791095245.327786388",
    });
  });

  it("returns nothing for a log that is not an announcement", () => {
    const log = announcementLog(1n, "0xabcd", "1");
    expect(decodeAnnouncement({ ...log, topics: [log.topics[0]] })).toBeUndefined();
    expect(decodeAnnouncement({ ...log, data: "0x" })).toBeUndefined();
  });
});

describe("fetchAnnouncements", () => {
  const created = 1_790_000_000;
  const now = (created + 10 * DAY) * 1000;
  const logsUrl = (gte: number, lt: number) =>
    `${MIRROR}/api/v1/contracts/${DIAMOND}/results/logs?topic0=${ANNOUNCEMENT_TOPIC}&timestamp=gte:${gte}&timestamp=lt:${lt}&limit=100&order=asc`;
  const nextPath = `/api/v1/contracts/${DIAMOND}/results/logs?topic0=${ANNOUNCEMENT_TOPIC}&index=gt:2`;

  const responses: Record<string, unknown> = {
    [`${MIRROR}/api/v1/contracts/${DIAMOND}`]: { created_timestamp: `${created}.767910806` },
    [logsUrl(created, created + 7 * DAY)]: {
      logs: [announcementLog(1n, "0x01", "1"), announcementLog(2n, "0x02", "2")],
      links: { next: nextPath },
    },
    [`${MIRROR}${nextPath}`]: { logs: [announcementLog(1n, "0x03", "3")], links: { next: null } },
    [logsUrl(created + 7 * DAY, created + 10 * DAY + 1)]: {
      logs: [announcementLog(1n, "0x04", "4")],
      links: { next: null },
    },
  };
  const requested: string[] = [];
  const fetchJson = async (url: string) => {
    requested.push(url);
    if (!(url in responses)) throw new Error(`unexpected request ${url}`);
    return responses[url];
  };

  it("searches every window since the contract was created, follows each page, and keeps scheme 1", async () => {
    const announcements = await fetchAnnouncements(MIRROR, DIAMOND as Address, now, fetchJson);

    expect(announcements.map(announcement => announcement.transactionHash)).toEqual(["0x01", "0x03", "0x04"]);
    expect(requested).toHaveLength(4);
  });
});
