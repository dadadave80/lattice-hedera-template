import {
  StealthKeys,
  checkAnnouncement,
  computeStealthPrivateKey,
  decodeMetaAddress,
  deriveStealthKeys,
  encodeMetaAddress,
  generateStealthAddress,
  parseMetadata,
  stealthAddressFrom,
  stealthPrivateKeyFrom,
} from "./stealthAddress";
import { secp256k1 } from "@noble/curves/secp256k1";
import { Hex, bytesToHex, concat, numberToHex, pad, slice, toHex } from "viem";
import { privateKeyToAddress } from "viem/accounts";
import { describe, expect, it } from "vitest";

const N = secp256k1.CURVE.n;

const randomSignature = (): Hex => bytesToHex(crypto.getRandomValues(new Uint8Array(65)));
const randomPrivateKey = (): Hex => bytesToHex(secp256k1.utils.randomPrivateKey());
const publicKeyOf = (privateKey: Hex): Hex => bytesToHex(secp256k1.getPublicKey(privateKey.slice(2), true));

/**
 * The keys of ScopeLift's stealth-address-sdk tests (src/utils/crypto/test/computeStealthKey.test.ts at commit
 * 88bcc27c3b6163080ee18f330dfd6336dc8bd2e2), whose spending key is written there with 63 hex digits. The stealth
 * addresses, ephemeral public keys, view tags and stealth keys below were computed with that SDK's
 * generateStealthAddress and computeStealthKey at the same commit, from these keys and the listed ephemeral keys.
 */
const SCOPELIFT = {
  metaAddress:
    "0x033404e82cd2a92321d51e13064ec13a0fb0192a9fdaaca1cfb47b37bd27ec13970390ad5eca026c05ab5cf4d620a2ac65241b11df004ddca360e954db1b26e3846e",
  spendingPrivateKey: pad("0x363721eb9e981558c748b824cb32a840da2b3e8957c2fc3bcb8d9c86cb87456"),
  viewingPrivateKey: "0xb52a0555f6a8663d89f00365893b1ef9e38eaf2e8bc48a63319c9ea5cb4a27c5",
  spendingPublicKey: "0x033404e82cd2a92321d51e13064ec13a0fb0192a9fdaaca1cfb47b37bd27ec1397",
  viewingPublicKey: "0x0390ad5eca026c05ab5cf4d620a2ac65241b11df004ddca360e954db1b26e3846e",
  payments: [
    {
      ephemeralPrivateKey: "0xd952fe0740d9d14011fc8ead3ab7de3c739d3aa93ce9254c10b0134d80d26a30",
      stealthAddress: "0x547A8b82CA05686c1099A9CBA53E521D4063b80A",
      ephemeralPublicKey: "0x03312f36039e1479d10ba17eef98bba5f9a299af277c1dfac2e9134f352892b166",
      viewTag: "0xf8",
      stealthPrivateKey: "0xfbc7e42c14849b59a1b84c37bc02e4e94bdd51c72142292c003cdddcf75bbc40",
    },
    {
      ephemeralPrivateKey: "0x1f6a1d2b0e8c9d4f3a5b7c6e8d9f0a1b2c3d4e5f60718293a4b5c6d7e8f90a1b",
      stealthAddress: "0xa4B6Bdb9416D3586a99Fb54cF0C11049607A7aa2",
      ephemeralPublicKey: "0x029ee34f92cbfe7765d1915c050b2b9842d85020c46ef0bc62f1b8dfa76104460f",
      viewTag: "0x1c",
      stealthPrivateKey: "0x205871ddff4b83f00765cb53d8917157c94ce51f3b43c3235332488fca458641",
    },
  ],
} as const;

describe("ERC-5564 scheme 1 against ScopeLift's stealth-address-sdk", () => {
  it("splits the SDK's meta-address into its spending and viewing keys", () => {
    expect(decodeMetaAddress(SCOPELIFT.metaAddress)).toEqual({
      spendingPublicKey: SCOPELIFT.spendingPublicKey,
      viewingPublicKey: SCOPELIFT.viewingPublicKey,
    });
  });

  it.each(SCOPELIFT.payments)("pays the SDK's stealth address for ephemeral key $ephemeralPrivateKey", payment => {
    expect(generateStealthAddress(SCOPELIFT.metaAddress, payment.ephemeralPrivateKey)).toEqual({
      stealthAddress: payment.stealthAddress,
      ephemeralPublicKey: payment.ephemeralPublicKey,
      viewTag: payment.viewTag,
    });
  });

  it.each(SCOPELIFT.payments)("finds and spends the payment to $stealthAddress", payment => {
    expect(checkAnnouncement(payment, SCOPELIFT)).toBe(true);
    const stealthPrivateKey = computeStealthPrivateKey(payment.ephemeralPublicKey, SCOPELIFT);
    expect(stealthPrivateKey).toBe(payment.stealthPrivateKey);
    expect(privateKeyToAddress(stealthPrivateKey)).toBe(payment.stealthAddress);
  });
});

/**
 * The proof of concept published with ERC-5564 (ethereum/ERCs, assets/erc-5564/minimal_poc.ipynb at commit
 * 365b4c02879f3e882b91281d42b4f57b406205e9): viewing key 2, spending key 3. It hashes the shared secret as x ‖ y, where
 * the SDK hashes the compressed point, so it checks the steps after the hash: the hashed secret is its p_stealth - 3.
 */
const ERC_POC = {
  spendingPrivateKey: numberToHex(3n, { size: 32 }),
  hashedSharedSecret: "0x569058e4fc044dda07c8ddccecb8008b2ebb1f7d8062b1a1b57416f263389037",
  stealthAddress: "0xfEd69Df0a27F1daE0D7430EAd82aaEdfAD6332bb",
  stealthPrivateKey: 39153944482575822531387237249775711740128993925789544779866399859639729033274n,
  viewTag: 86,
} as const;

describe("ERC-5564 scheme 1 against the ERC's proof of concept", () => {
  it("derives the stealth address from the spending key and the hashed secret", () => {
    expect(stealthAddressFrom(publicKeyOf(ERC_POC.spendingPrivateKey), ERC_POC.hashedSharedSecret)).toBe(
      ERC_POC.stealthAddress,
    );
  });

  it("derives the stealth private key from the spending key and the hashed secret", () => {
    expect(stealthPrivateKeyFrom(ERC_POC.spendingPrivateKey, ERC_POC.hashedSharedSecret)).toBe(
      numberToHex(ERC_POC.stealthPrivateKey, { size: 32 }),
    );
  });

  it("takes the view tag from the first byte of the hashed secret", () => {
    expect(Number(slice(ERC_POC.hashedSharedSecret, 0, 1))).toBe(ERC_POC.viewTag);
  });
});

describe("stealthPrivateKeyFrom", () => {
  it("wraps a sum past the curve order", () => {
    const hashedSharedSecret = numberToHex(5n, { size: 32 });
    expect(stealthPrivateKeyFrom(numberToHex(N - 1n, { size: 32 }), hashedSharedSecret)).toBe(
      numberToHex(4n, { size: 32 }),
    );
  });
});

describe("deriveStealthKeys", () => {
  it("gives the same keys for the same signature", () => {
    const signature = randomSignature();
    expect(deriveStealthKeys(signature)).toEqual(deriveStealthKeys(signature));
  });

  it("separates the spending key from the viewing key", () => {
    const keys = deriveStealthKeys(randomSignature());
    expect(keys.spendingPrivateKey).not.toBe(keys.viewingPrivateKey);
  });

  it("gives other keys for another signature", () => {
    expect(deriveStealthKeys(randomSignature()).spendingPrivateKey).not.toBe(
      deriveStealthKeys(randomSignature()).spendingPrivateKey,
    );
  });

  it("ignores how the wallet encodes v", () => {
    const rs = slice(randomSignature(), 0, 64);
    expect(deriveStealthKeys(concat([rs, "0x1b"]))).toEqual(deriveStealthKeys(concat([rs, "0x00"])));
  });

  it("returns private keys inside the curve order and the public keys that match them", () => {
    for (let i = 0; i < 20; i++) {
      const keys = deriveStealthKeys(randomSignature());
      for (const privateKey of [keys.spendingPrivateKey, keys.viewingPrivateKey]) {
        expect(BigInt(privateKey)).toBeGreaterThan(0n);
        expect(BigInt(privateKey)).toBeLessThan(N);
      }
      expect(keys.spendingPublicKey).toBe(publicKeyOf(keys.spendingPrivateKey));
      expect(keys.viewingPublicKey).toBe(publicKeyOf(keys.viewingPrivateKey));
    }
  });
});

describe("encodeMetaAddress and decodeMetaAddress", () => {
  it("round-trips a recipient's public keys through 66 bytes", () => {
    const keys = deriveStealthKeys(randomSignature());
    const metaAddress = encodeMetaAddress(keys.spendingPublicKey, keys.viewingPublicKey);

    expect((metaAddress.length - 2) / 2).toBe(66);
    expect(decodeMetaAddress(metaAddress)).toEqual({
      spendingPublicKey: keys.spendingPublicKey,
      viewingPublicKey: keys.viewingPublicKey,
    });
  });

  it("rejects bytes that are not two compressed keys", () => {
    expect(() => decodeMetaAddress("0x")).toThrow("two compressed public keys");
    expect(() => decodeMetaAddress(SCOPELIFT.spendingPublicKey)).toThrow("two compressed public keys");
    expect(() => decodeMetaAddress(concat([SCOPELIFT.metaAddress, "0x00"]))).toThrow("two compressed public keys");
  });

  it("rejects a key that is not on the curve", () => {
    const notOnCurve = concat(["0x02", pad("0x05")]);
    expect(() => decodeMetaAddress(concat([notOnCurve, SCOPELIFT.viewingPublicKey]))).toThrow("not on secp256k1");
    expect(() => decodeMetaAddress(concat([SCOPELIFT.spendingPublicKey, notOnCurve]))).toThrow("not on secp256k1");
  });
});

describe("a payment, round trip", () => {
  const recipient = (): StealthKeys => deriveStealthKeys(randomSignature());
  const metaAddressOf = (keys: StealthKeys) => encodeMetaAddress(keys.spendingPublicKey, keys.viewingPublicKey);

  it("lets the recipient find the payment and spend from the stealth address", () => {
    for (let i = 0; i < 25; i++) {
      const keys = recipient();
      const payment = generateStealthAddress(metaAddressOf(keys));

      expect(checkAnnouncement(payment, keys)).toBe(true);
      expect(privateKeyToAddress(computeStealthPrivateKey(payment.ephemeralPublicKey, keys))).toBe(
        payment.stealthAddress,
      );
    }
  });

  it("uses a fresh ephemeral key, and so a fresh stealth address, for every payment", () => {
    const metaAddress = metaAddressOf(recipient());
    const first = generateStealthAddress(metaAddress);
    const second = generateStealthAddress(metaAddress);

    expect(first.ephemeralPublicKey).not.toBe(second.ephemeralPublicKey);
    expect(first.stealthAddress).not.toBe(second.stealthAddress);
  });

  it("is deterministic for a given ephemeral key", () => {
    const metaAddress = metaAddressOf(recipient());
    const ephemeralPrivateKey = randomPrivateKey();

    expect(generateStealthAddress(metaAddress, ephemeralPrivateKey)).toEqual(
      generateStealthAddress(metaAddress, ephemeralPrivateKey),
    );
  });

  it("is not found by anyone else", () => {
    for (let i = 0; i < 25; i++) {
      const payment = generateStealthAddress(metaAddressOf(recipient()));
      expect(checkAnnouncement(payment, recipient())).toBe(false);
    }
  });
});

describe("checkAnnouncement", () => {
  const keys = deriveStealthKeys(randomSignature());
  const payment = generateStealthAddress(encodeMetaAddress(keys.spendingPublicKey, keys.viewingPublicKey));

  it("skips an announcement whose view tag is not the recipient's", () => {
    const otherTag = toHex((Number(payment.viewTag) + 1) % 256, { size: 1 });
    expect(checkAnnouncement({ ...payment, viewTag: otherTag }, keys)).toBe(false);
  });

  it("rejects an announcement whose view tag matches but whose address does not", () => {
    const stealthAddress = privateKeyToAddress(randomPrivateKey());
    expect(checkAnnouncement({ ...payment, stealthAddress }, keys)).toBe(false);
  });

  it("matches the stealth address in any letter case", () => {
    const stealthAddress = payment.stealthAddress.toLowerCase() as Hex;
    expect(checkAnnouncement({ ...payment, stealthAddress }, keys)).toBe(true);
  });

  it("treats an ephemeral key that is not a public key as someone else's announcement", () => {
    for (const ephemeralPublicKey of ["0x", "0x1234", concat(["0x02", pad("0x05")])] as Hex[]) {
      expect(checkAnnouncement({ ...payment, ephemeralPublicKey }, keys)).toBe(false);
    }
  });
});

describe("parseMetadata", () => {
  const token = "0x00000000000000000000000000000000006e0B3a";
  const tokenLayout = concat(["0x5c", "0xa9059cbb", token, numberToHex(123_456_789n, { size: 32 })]);

  it("reads the view tag, token and amount of the ERC-5564 token layout", () => {
    expect(parseMetadata(tokenLayout)).toEqual({ viewTag: "0x5c", token, amount: 123_456_789n });
  });

  it("reads only the view tag when the metadata holds nothing else", () => {
    expect(parseMetadata("0x5c")).toEqual({ viewTag: "0x5c" });
  });

  it("reads only the view tag when the rest is not a token transfer", () => {
    const native = concat([
      "0x5c",
      "0xeeeeeeee",
      "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
      numberToHex(1n, { size: 32 }),
    ]);
    expect(parseMetadata(native)).toEqual({ viewTag: "0x5c" });
    expect(parseMetadata(slice(tokenLayout, 0, 56))).toEqual({ viewTag: "0x5c" });
  });

  it("returns nothing for empty metadata, which has no view tag", () => {
    expect(parseMetadata("0x")).toBeUndefined();
  });
});
