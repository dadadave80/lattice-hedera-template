import { getParsedError } from "./getParsedError";
import {
  ContractFunctionExecutionError,
  ContractFunctionRevertedError,
  Hex,
  HttpRequestError,
  RpcRequestError,
  encodeErrorResult,
  pad,
  parseAbi,
  toHex,
} from "viem";
import { describe, expect, it } from "vitest";

const abi = parseAbi([
  "function buy(int64 minTokensOut) payable",
  "error TokenSaleSlippage(int64 tokens, int64 minTokens)",
]);

/** The error wagmi throws when a simulated `buy` reverts with `data`. */
const reverted = (data: Hex) =>
  new ContractFunctionExecutionError(new ContractFunctionRevertedError({ abi, data, functionName: "buy" }), {
    abi,
    args: [99n],
    functionName: "buy",
  });

const responseCode = (code: number) => pad(toHex(code));

describe("getParsedError", () => {
  it("names the HTS response code a revert carries as one word with no selector", () => {
    expect(getParsedError(reverted(responseCode(184)))).toBe("The recipient has not associated this token");
    expect(getParsedError(reverted(responseCode(178)))).toBe("Not enough tokens left");
  });

  it("gives the number of an HTS response code it has no words for", () => {
    expect(getParsedError(reverted(responseCode(167)))).toBe("Hedera Token Service response code 167");
  });

  it("reads an HTS response code from the RPC error when no ABI decoded it", () => {
    const error = new RpcRequestError({
      body: {},
      error: { code: 3, message: "execution reverted", data: responseCode(184) },
      url: "https://testnet.hashio.io/api",
    });

    expect(getParsedError(error)).toBe("The recipient has not associated this token");
  });

  it("still names a custom error the ABI knows", () => {
    const data = encodeErrorResult({ abi, errorName: "TokenSaleSlippage", args: [90n, 99n] });

    expect(getParsedError(reverted(data))).toBe(
      'The contract function "buy" reverted with the following reason:\nTokenSaleSlippage(90,99)',
    );
  });

  it("shows only the message of a JSON-RPC error object, without the relay's request ID", () => {
    const error = new HttpRequestError({
      url: "https://testnet.hashio.io/api",
      status: 400,
      details: JSON.stringify({
        code: -32000,
        message: "[Request ID: 0b9f2c4e-7a1d-4c3b-9e8f-2d6a5b4c3e21] Insufficient funds for transfer",
      }),
    });

    expect(getParsedError(error)).toBe("Insufficient funds for transfer");
  });

  it("drops the relay's request ID from a plain message", () => {
    expect(getParsedError(new Error("[Request ID: 0b9f2c4e] Nonce too low"))).toBe("Nonce too low");
  });
});
