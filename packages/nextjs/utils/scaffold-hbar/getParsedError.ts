import { BaseError as BaseViemError, ContractFunctionRevertedError, hexToBigInt, isHex, size } from "viem";

/** The Hedera Token Service response codes a buyer can run into, in words. */
const HTS_RESPONSE_CODES: Record<string, string> = {
  "178": "Not enough tokens left",
  "184": "The recipient has not associated this token",
  "194": "This account has already associated this token",
};

/**
 * When an HTS call fails, Hedera reverts with the response code as one 32-byte word and no error selector, which
 * no ABI decodes. Returns the code in words, or undefined when `data` is anything else.
 */
const htsResponseCode = (data: unknown): string | undefined => {
  if (typeof data !== "string" || !isHex(data) || size(data) !== 32) return undefined;
  const code = hexToBigInt(data);
  if (code === 0n || code > 0x7fffffffn) return undefined;
  return HTS_RESPONSE_CODES[code.toString()] ?? `Hedera Token Service response code ${code}`;
};

/**
 * The Hedera JSON-RPC relay starts its messages with "[Request ID: …]", and an error the relay answers with an HTTP
 * error status reaches viem as the JSON of the JSON-RPC error object. Keeps only the message.
 */
const readable = (text: string): string => {
  let message = text;
  try {
    const parsed = JSON.parse(text);
    if (typeof parsed?.message === "string") message = parsed.message;
  } catch {}
  return message.replace(/\[Request ID: [^\]]*\]\s*/g, "").trim() || "An unknown error occurred";
};

/**
 * Parses an viem/wagmi error to get a displayable string
 * @param e - error object
 * @returns parsed error string
 */
export const getParsedError = (error: any): string => {
  for (let cause = error; cause && typeof cause === "object"; cause = cause.cause) {
    const hts = htsResponseCode(cause.raw) ?? htsResponseCode(cause.data);
    if (hts) return hts;
  }

  const parsedError = error?.walk ? error.walk() : error;

  if (parsedError instanceof BaseViemError) {
    if (parsedError.details) {
      return readable(parsedError.details);
    }

    if (parsedError.shortMessage) {
      if (
        parsedError instanceof ContractFunctionRevertedError &&
        parsedError.data &&
        parsedError.data.errorName !== "Error"
      ) {
        const customErrorArgs = parsedError.data.args?.toString() ?? "";
        return `${parsedError.shortMessage.replace(/reverted\.$/, "reverted with the following reason:")}\n${
          parsedError.data.errorName
        }(${customErrorArgs})`;
      }

      return readable(parsedError.shortMessage);
    }

    return readable(parsedError.message ?? parsedError.name ?? "An unknown error occurred");
  }

  return readable(parsedError?.message ?? "An unknown error occurred");
};
