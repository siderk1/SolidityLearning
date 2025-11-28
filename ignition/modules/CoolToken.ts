import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const TOKEN_NAME = "Cool Token";
const TOKEN_SYMBOL = "COOL";
const VOTING_TIME_LENGTH = 600n;
const INITIAL_PRICE = 10n ** 18n;
const FEE_BPS = 50n;
const INITIAL_OWNER_INDEX = 0;

export default buildModule("CoolTokenModule", (m) => {
  const initialOwner = m.getAccount(INITIAL_OWNER_INDEX);

  const coolTokenImplementation = m.contract("CoolToken");

  const initData = m.encodeFunctionCall(coolTokenImplementation, "initialize", [
    TOKEN_NAME,
    TOKEN_SYMBOL,
    VOTING_TIME_LENGTH,
    INITIAL_PRICE,
    FEE_BPS,
    initialOwner,
  ]);

  const coolTokenProxy = m.contract("BasicProxy", [
    coolTokenImplementation,
    initData,
  ]);

  const coolToken = m.contractAt("CoolToken", coolTokenProxy, {
    id: "CoolTokenProxyInterface",
  });

  return { coolToken };
});
