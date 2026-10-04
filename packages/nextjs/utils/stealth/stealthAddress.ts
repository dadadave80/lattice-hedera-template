import { secp256k1 } from "@noble/curves/secp256k1";
import {
  Address,
  Hex,
  bytesToHex,
  concat,
  getAddress,
  hexToBigInt,
  hexToBytes,
  isAddress,
  isAddressEqual,
  isHex,
  keccak256,
  numberToHex,
  size,
  slice,
  toHex,
} from "viem";
import { publicKeyToAddress } from "viem/accounts";

/**
 * ERC-5564 scheme 1: stealth addresses on secp256k1 with view tags. A recipient publishes a meta-address, two public
 * keys. A payer derives a one-time address from it that only the recipient can find and spend from.
 */
export const SCHEME_ID = 1n;

/** The message a wallet signs to derive its stealth keys. Changing it changes every user's keys. */
export const STEALTH_KEYS_MESSAGE =
  "Lattice Hedera Template: private purchases\n\n" +
  "Sign to derive your stealth keys. Anyone who holds this signature can find and spend what was sent to you " +
  "privately, so sign it only on this site.";

const SPENDING_KEY_TAG = toHex("lattice-hedera-template/stealth/spending");
const VIEWING_KEY_TAG = toHex("lattice-hedera-template/stealth/viewing");
const COMPRESSED_KEY_BYTES = 33;
/** The selector of ERC-20 `transfer`, which ERC-5564 puts in the metadata of a token payment. */
const TRANSFER_SELECTOR = "0xa9059cbb";
const N = secp256k1.CURVE.n;
const { ProjectivePoint } = secp256k1;

export type StealthKeys = {
  spendingPrivateKey: Hex;
  viewingPrivateKey: Hex;
  spendingPublicKey: Hex;
  viewingPublicKey: Hex;
};

export type StealthPayment = { stealthAddress: Address; ephemeralPublicKey: Hex; viewTag: Hex };

/** Derives a recipient's spending and viewing keys from their wallet's signature of `STEALTH_KEYS_MESSAGE`. */
export function deriveStealthKeys(signature: Hex): StealthKeys {
  // r ‖ s only: wallets encode v as 0/1 or 27/28, and the same wallet key must always give the same stealth keys.
  const rs = slice(signature, 0, 64);
  const spendingPrivateKey = privateKeyFromHash(keccak256(concat([SPENDING_KEY_TAG, rs])));
  const viewingPrivateKey = privateKeyFromHash(keccak256(concat([VIEWING_KEY_TAG, rs])));
  return {
    spendingPrivateKey,
    viewingPrivateKey,
    spendingPublicKey: publicKeyOf(spendingPrivateKey),
    viewingPublicKey: publicKeyOf(viewingPrivateKey),
  };
}

/** The 66-byte meta-address a recipient registers: the compressed spending key, then the compressed viewing key. */
export function encodeMetaAddress(spendingPublicKey: Hex, viewingPublicKey: Hex): Hex {
  return concat([spendingPublicKey, viewingPublicKey]);
}

/**
 * What a payer typed as the recipient: a wallet address, to look up in the registry, or the stealth meta-address itself,
 * bare or in ERC-5564's `st:<chain>:0x…` form. Undefined for anything else.
 */
export function parseRecipient(input: string): { address: Address } | { metaAddress: Hex } | undefined {
  const value = input.trim().replace(/^st:[a-z0-9-]+:/i, "");
  if (isAddress(value)) return { address: value };
  if (isHex(value) && size(value) === 2 * COMPRESSED_KEY_BYTES) return { metaAddress: value };
  return undefined;
}

export function decodeMetaAddress(metaAddress: Hex): { spendingPublicKey: Hex; viewingPublicKey: Hex } {
  if (size(metaAddress) !== 2 * COMPRESSED_KEY_BYTES) {
    throw new Error("A stealth meta-address is two compressed public keys, 66 bytes");
  }
  const spendingPublicKey = slice(metaAddress, 0, COMPRESSED_KEY_BYTES);
  const viewingPublicKey = slice(metaAddress, COMPRESSED_KEY_BYTES);
  for (const key of [spendingPublicKey, viewingPublicKey]) {
    try {
      ProjectivePoint.fromHex(key.slice(2));
    } catch {
      throw new Error(`Stealth meta-address key ${key} is not on secp256k1`);
    }
  }
  return { spendingPublicKey, viewingPublicKey };
}

/**
 * Derives a fresh one-time address for the owner of `metaAddress`, with what the payer announces so the owner can find
 * it. Pass `ephemeralPrivateKey` only to reproduce a known payment: reusing one links the payments that share it.
 */
export function generateStealthAddress(metaAddress: Hex, ephemeralPrivateKey?: Hex): StealthPayment {
  const { spendingPublicKey, viewingPublicKey } = decodeMetaAddress(metaAddress);
  const ephemeral = ephemeralPrivateKey ?? bytesToHex(secp256k1.utils.randomPrivateKey());
  const hashedSecret = hashedSharedSecret(ephemeral, viewingPublicKey);
  return {
    stealthAddress: stealthAddressFrom(spendingPublicKey, hashedSecret),
    ephemeralPublicKey: publicKeyOf(ephemeral),
    viewTag: slice(hashedSecret, 0, 1),
  };
}

/**
 * Whether an announced payment belongs to the holder of `keys`. The view tag rules out all but 1 in 256 announcements
 * for the price of one multiplication; only those that pass are checked in full.
 */
export function checkAnnouncement(
  announcement: StealthPayment,
  keys: Pick<StealthKeys, "viewingPrivateKey" | "spendingPublicKey">,
): boolean {
  let hashedSecret: Hex;
  try {
    hashedSecret = hashedSharedSecret(keys.viewingPrivateKey, announcement.ephemeralPublicKey);
  } catch {
    // Anyone can announce, so an ephemeral key may not be a point at all.
    return false;
  }
  if (Number(slice(hashedSecret, 0, 1)) !== Number(announcement.viewTag)) return false;
  return isAddressEqual(stealthAddressFrom(keys.spendingPublicKey, hashedSecret), announcement.stealthAddress);
}

/** The private key of the stealth address an announcement with `ephemeralPublicKey` paid. */
export function computeStealthPrivateKey(
  ephemeralPublicKey: Hex,
  keys: Pick<StealthKeys, "spendingPrivateKey" | "viewingPrivateKey">,
): Hex {
  return stealthPrivateKeyFrom(keys.spendingPrivateKey, hashedSharedSecret(keys.viewingPrivateKey, ephemeralPublicKey));
}

/** The stealth address: `spendingPublicKey + hashedSecret · G`. */
export function stealthAddressFrom(spendingPublicKey: Hex, hashedSecret: Hex): Address {
  const stealthPublicKey = ProjectivePoint.fromHex(spendingPublicKey.slice(2)).add(
    ProjectivePoint.BASE.multiply(hexToBigInt(hashedSecret)),
  );
  return publicKeyToAddress(bytesToHex(stealthPublicKey.toRawBytes(false)));
}

/** The stealth private key: `spendingPrivateKey + hashedSecret` modulo the curve order. */
export function stealthPrivateKeyFrom(spendingPrivateKey: Hex, hashedSecret: Hex): Hex {
  return numberToHex((hexToBigInt(spendingPrivateKey) + hexToBigInt(hashedSecret)) % N, { size: 32 });
}

/**
 * Reads ERC-5564 metadata: the view tag in byte 0 and, for a token payment, `transfer`'s selector, the token and the
 * amount. Undefined for empty metadata, which has no view tag.
 */
export function parseMetadata(metadata: Hex): { viewTag: Hex; token?: Address; amount?: bigint } | undefined {
  if (size(metadata) === 0) return undefined;
  const viewTag = slice(metadata, 0, 1);
  if (size(metadata) < 57 || slice(metadata, 1, 5) !== TRANSFER_SELECTOR) return { viewTag };
  return { viewTag, token: getAddress(slice(metadata, 5, 25)), amount: hexToBigInt(slice(metadata, 25, 57)) };
}

/** keccak256 of the compressed shared point, the encoding ScopeLift's stealth-address-sdk hashes. */
function hashedSharedSecret(privateKey: Hex, publicKey: Hex): Hex {
  return keccak256(secp256k1.getSharedSecret(hexToBytes(privateKey), hexToBytes(publicKey), true));
}

function privateKeyFromHash(hash: Hex): Hex {
  return numberToHex((hexToBigInt(hash) % (N - 1n)) + 1n, { size: 32 });
}

function publicKeyOf(privateKey: Hex): Hex {
  return bytesToHex(secp256k1.getPublicKey(hexToBytes(privateKey), true));
}
