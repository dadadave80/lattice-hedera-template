import { parseAbi } from "viem";

/**
 * `IStealthBuy`. A diamond deployed before StealthBuy gains it by a cut, so the generated `Diamond` ABI may not list
 * it. The errors are here so a failed simulation names them.
 */
export const stealthBuyAbi = parseAbi([
  "function buyFor(address stealthAddress, bytes ephemeralPubKey, bytes1 viewTag, int64 minTokensOut, uint256 stipend) payable returns (int64 tokens)",
  "event StealthDelivery(address indexed stealthAddress, int64 tokens, uint256 paidTinybars, uint256 stipendTinybars)",
  "error StealthBuyZeroAddress()",
  "error StealthBuyStipendTooHigh(uint256 stipend, uint256 value)",
  "error StealthBuyStipendFailed(address stealthAddress)",
]);

/** ERC-5564's event, emitted by Lattice's `ERC5564Announcer` facet and by `buyFor`. */
export const announcementAbi = parseAbi([
  "event Announcement(uint256 indexed schemeId, address indexed stealthAddress, address indexed caller, bytes ephemeralPubKey, bytes metadata)",
]);

/** The calls this app makes to Lattice's `ERC6538Registry` facet. */
export const erc6538RegistryAbi = parseAbi([
  "function registerKeys(uint256 schemeId, bytes stealthMetaAddress)",
  "function stealthMetaAddressOf(address registrant, uint256 schemeId) view returns (bytes)",
]);
