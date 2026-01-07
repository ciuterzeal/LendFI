
import { describe, expect, it } from "vitest";
import { Cl, ClarityType, type ClarityValue } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer") ?? accounts.get("wallet_1")!;
const borrower = accounts.get("wallet_1") ?? deployer;
const liquidator = accounts.get("wallet_2") ?? deployer;

const lendFiContract = "lendFi";
const lendFiPrincipal = Cl.contractPrincipal(deployer, lendFiContract);

let tokenCounter = 0;

const buildMockSip010 = (name: string, symbol: string) => `
(define-fungible-token token)

(define-constant ERR-UNAUTHORIZED u401)
(define-constant TOKEN-NAME "${name}")
(define-constant TOKEN-SYMBOL "${symbol}")
(define-constant TOKEN-DECIMALS u6)

(define-data-var token-uri (optional (string-utf8 256)) none)
(define-data-var admin principal tx-sender)

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (is-eq tx-sender sender) (err ERR-UNAUTHORIZED))
    (ft-transfer? token amount sender recipient)
  )
)

(define-public (mint (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR-UNAUTHORIZED))
    (ft-mint? token amount recipient)
  )
)

(define-read-only (get-balance (owner principal))
  (ok (ft-get-balance token owner))
)

(define-read-only (get-total-supply)
  (ok (ft-get-supply token))
)

(define-read-only (get-name)
  (ok TOKEN-NAME)
)

(define-read-only (get-symbol)
  (ok TOKEN-SYMBOL)
)

(define-read-only (get-decimals)
  (ok TOKEN-DECIMALS)
)

(define-read-only (get-token-uri)
  (ok (var-get token-uri))
)
`;

const deployMockToken = (prefix: string, name: string, symbol: string) => {
  tokenCounter += 1;
  const contractName = `${prefix}-${tokenCounter}`;
  const result = simnet.deployContract(contractName, buildMockSip010(name, symbol), null, deployer);
  expect(result.result).toBeBool(true);
  return contractName;
};

const contractPrincipal = (contractName: string) =>
  Cl.contractPrincipal(deployer, contractName);

const unwrapOk = (value: ClarityValue) => {
  if (value.type !== ClarityType.ResponseOk) {
    throw new Error(`Expected ok, got ${value.type}`);
  }
  return value.value;
};

const unwrapOkUint = (value: ClarityValue): bigint => {
  const inner = unwrapOk(value);
  if (inner.type !== ClarityType.UInt) {
    throw new Error(`Expected uint, got ${inner.type}`);
  }
  return typeof inner.value === "bigint" ? inner.value : BigInt(inner.value);
};

const unwrapSome = (value: ClarityValue) => {
  if (value.type !== ClarityType.OptionalSome) {
    throw new Error(`Expected some, got ${value.type}`);
  }
  return value.value;
};

const configureLendFi = (
  borrowToken: string,
  collateralToken: string,
  yieldToken: string | null = null,
) => {
  const borrowContract = contractPrincipal(borrowToken);
  const collateralContract = contractPrincipal(collateralToken);
  const yieldContract = contractPrincipal(yieldToken ?? borrowToken);

  const setBorrow = simnet.callPublicFn(
    lendFiContract,
    "set-borrow-token",
    [borrowContract],
    deployer,
  );
  expect(setBorrow.result).toBeOk(Cl.bool(true));

  const setYield = simnet.callPublicFn(
    lendFiContract,
    "set-yield-token",
    [yieldContract],
    deployer,
  );
  expect(setYield.result).toBeOk(Cl.bool(true));

  const setCollateral = simnet.callPublicFn(
    lendFiContract,
    "set-collateral-type",
    [
      collateralContract,
      Cl.uint(8000),
      Cl.uint(12000),
      Cl.uint(2),
      Cl.bool(true),
      Cl.uint(150),
    ],
    deployer,
  );
  expect(setCollateral.result).toBeOk(Cl.bool(true));

  return { borrowContract, collateralContract, yieldContract };
};

const mintToken = (contractName: string, amount: bigint | number, recipient: ClarityValue) => {
  const mint = simnet.callPublicFn(
    contractName,
    "mint",
    [Cl.uint(amount), recipient],
    deployer,
  );
  expect(mint.result).toBeOk(Cl.bool(true));
};

describe("lendFi core flows", () => {
  it("allows admin configuration of tokens and collateral types", () => {
    const borrowToken = deployMockToken("borrow-token", "Mock Borrow", "BRW");
    const collateralToken = deployMockToken("collateral-token", "Mock Collateral", "COL");

    const { borrowContract, collateralContract, yieldContract } = configureLendFi(
      borrowToken,
      collateralToken,
    );

    const collateralInfo = simnet.callReadOnlyFn(
      lendFiContract,
      "get-collateral-type",
      [collateralContract],
      deployer,
    );
    expect(collateralInfo.result).toBeOk(
      Cl.tuple({
        "ltv-ratio": Cl.uint(8000),
        "liquidation-threshold": Cl.uint(12000),
        "risk-tier": Cl.uint(2),
        enabled: Cl.bool(true),
        "interest-multiplier": Cl.uint(150),
      }),
    );

    const contractInfo = simnet.callReadOnlyFn(lendFiContract, "get-contract-info", [], deployer);
    const infoValue = unwrapOk(contractInfo.result);
    expect(infoValue).toBeTuple({
      admin: Cl.standardPrincipal(deployer),
      paused: Cl.bool(false),
      "next-loan-id": expect.anything(),
      "next-liquidation-id": expect.anything(),
      "yield-token": Cl.some(yieldContract),
      "borrow-token": Cl.some(borrowContract),
    });
  });

  it("opens a loan and reports health", () => {
    const borrowToken = deployMockToken("borrow-token", "Mock Borrow", "BRW");
    const collateralToken = deployMockToken("collateral-token", "Mock Collateral", "COL");
    const { borrowContract, collateralContract } = configureLendFi(borrowToken, collateralToken);

    const collateralAmount = 1_000_000;
    const loanAmount = 400_000;

    mintToken(collateralToken, collateralAmount, Cl.principal(borrower));
    mintToken(borrowToken, 5_000_000, lendFiPrincipal);

    const loanId = simnet.getDataVar(lendFiContract, "next-loan-id");
    const openLoan = simnet.callPublicFn(
      lendFiContract,
      "open-loan",
      [Cl.uint(collateralAmount), Cl.uint(loanAmount), collateralContract, borrowContract],
      borrower,
    );
    expect(openLoan.result).toBeOk(loanId);

    const loan = simnet.callReadOnlyFn(lendFiContract, "get-loan", [loanId], borrower);
    const loanValue = unwrapOk(loan.result);
    expect(loanValue).toBeTuple({
      owner: Cl.standardPrincipal(borrower),
      collateral: Cl.uint(collateralAmount),
      borrowed: Cl.uint(loanAmount),
      repaid: Cl.bool(false),
      "start-height": expect.anything(),
      "collateral-type": collateralContract,
    });

    const health = simnet.callReadOnlyFn(
      lendFiContract,
      "calculate-health-factor",
      [loanId],
      borrower,
    );
    const expectedHealth = Math.floor((collateralAmount * 100) / loanAmount);
    expect(health.result).toBeOk(Cl.uint(expectedHealth));
  });

  it("repays a loan and returns collateral", () => {
    const borrowToken = deployMockToken("borrow-token", "Mock Borrow", "BRW");
    const collateralToken = deployMockToken("collateral-token", "Mock Collateral", "COL");
    const { borrowContract, collateralContract } = configureLendFi(borrowToken, collateralToken);

    const collateralAmount = 1_000_000;
    const loanAmount = 200_000;

    mintToken(collateralToken, collateralAmount, Cl.principal(borrower));
    mintToken(borrowToken, 2_000_000, lendFiPrincipal);

    const loanId = simnet.getDataVar(lendFiContract, "next-loan-id");
    const openLoan = simnet.callPublicFn(
      lendFiContract,
      "open-loan",
      [Cl.uint(collateralAmount), Cl.uint(loanAmount), collateralContract, borrowContract],
      borrower,
    );
    expect(openLoan.result).toBeOk(loanId);

    const repayment = simnet.callReadOnlyFn(
      lendFiContract,
      "calculate-repayment-amount",
      [loanId],
      borrower,
    );
    const totalDue = unwrapOkUint(repayment.result);
    const repayAmount = totalDue + 10_000n;

    mintToken(borrowToken, repayAmount, Cl.principal(borrower));

    const repay = simnet.callPublicFn(
      lendFiContract,
      "trigger-repayment",
      [loanId, Cl.uint(repayAmount), borrowContract, collateralContract],
      borrower,
    );
    expect(repay.result).toBeOk(Cl.bool(true));

    const loanAfter = simnet.callReadOnlyFn(lendFiContract, "get-loan", [loanId], borrower);
    const loanAfterValue = unwrapOk(loanAfter.result);
    expect(loanAfterValue).toBeTuple({
      owner: Cl.standardPrincipal(borrower),
      collateral: Cl.uint(0),
      borrowed: Cl.uint(0),
      repaid: Cl.bool(true),
      "start-height": expect.anything(),
      "collateral-type": collateralContract,
    });

    const collateralBalance = simnet.callReadOnlyFn(
      collateralToken,
      "get-balance",
      [Cl.principal(borrower)],
      borrower,
    );
    expect(collateralBalance.result).toBeOk(Cl.uint(collateralAmount));
  });

  it("liquidates an unhealthy loan and records it", () => {
    const borrowToken = deployMockToken("borrow-token", "Mock Borrow", "BRW");
    const collateralToken = deployMockToken("collateral-token", "Mock Collateral", "COL");
    const { borrowContract, collateralContract } = configureLendFi(borrowToken, collateralToken);

    const collateralAmount = 1_000_000;
    const loanAmount = 500_000;
    const liquidationAmount = 100_000;
    const collateralSeized = Math.floor((liquidationAmount * 110) / 100);

    mintToken(collateralToken, collateralAmount, Cl.principal(borrower));
    mintToken(borrowToken, 3_000_000, lendFiPrincipal);

    const loanId = simnet.getDataVar(lendFiContract, "next-loan-id");
    const openLoan = simnet.callPublicFn(
      lendFiContract,
      "open-loan",
      [Cl.uint(collateralAmount), Cl.uint(loanAmount), collateralContract, borrowContract],
      borrower,
    );
    expect(openLoan.result).toBeOk(loanId);

    mintToken(borrowToken, liquidationAmount, Cl.principal(liquidator));

    const liquidationId = simnet.getDataVar(lendFiContract, "next-liquidation-id");
    const liquidate = simnet.callPublicFn(
      lendFiContract,
      "liquidate-loan",
      [loanId, Cl.uint(liquidationAmount), collateralContract, borrowContract],
      liquidator,
    );
    expect(liquidate.result).toBeOk(liquidationId);

    const loanAfter = simnet.callReadOnlyFn(lendFiContract, "get-loan", [loanId], liquidator);
    const loanAfterValue = unwrapOk(loanAfter.result);
    expect(loanAfterValue).toBeTuple({
      owner: Cl.standardPrincipal(borrower),
      collateral: Cl.uint(collateralAmount - collateralSeized),
      borrowed: Cl.uint(loanAmount - liquidationAmount),
      repaid: Cl.bool(false),
      "start-height": expect.anything(),
      "collateral-type": collateralContract,
    });

    const liquidationInfo = simnet.callReadOnlyFn(
      lendFiContract,
      "get-liquidation",
      [liquidationId],
      liquidator,
    );
    const liquidationValue = unwrapSome(liquidationInfo.result);
    expect(liquidationValue).toBeTuple({
      "loan-id": loanId,
      liquidator: Cl.standardPrincipal(liquidator),
      "liquidated-amount": Cl.uint(liquidationAmount),
      "collateral-seized": Cl.uint(collateralSeized),
      timestamp: expect.anything(),
    });
  });

  it("boosts collateral for an active loan", () => {
    const borrowToken = deployMockToken("borrow-token", "Mock Borrow", "BRW");
    const collateralToken = deployMockToken("collateral-token", "Mock Collateral", "COL");
    const { borrowContract, collateralContract } = configureLendFi(borrowToken, collateralToken);

    const collateralAmount = 500_000;
    const extraCollateral = 200_000;
    const loanAmount = 150_000;

    mintToken(collateralToken, collateralAmount + extraCollateral, Cl.principal(borrower));
    mintToken(borrowToken, 2_000_000, lendFiPrincipal);

    const loanId = simnet.getDataVar(lendFiContract, "next-loan-id");
    const openLoan = simnet.callPublicFn(
      lendFiContract,
      "open-loan",
      [Cl.uint(collateralAmount), Cl.uint(loanAmount), collateralContract, borrowContract],
      borrower,
    );
    expect(openLoan.result).toBeOk(loanId);

    const boost = simnet.callPublicFn(
      lendFiContract,
      "boost-collateral",
      [loanId, Cl.uint(extraCollateral), collateralContract],
      borrower,
    );
    expect(boost.result).toBeOk(Cl.uint(collateralAmount + extraCollateral));

    const loanAfter = simnet.callReadOnlyFn(lendFiContract, "get-loan", [loanId], borrower);
    const loanAfterValue = unwrapOk(loanAfter.result);
    expect(loanAfterValue).toBeTuple({
      owner: Cl.standardPrincipal(borrower),
      collateral: Cl.uint(collateralAmount + extraCollateral),
      borrowed: Cl.uint(loanAmount),
      repaid: Cl.bool(false),
      "start-height": expect.anything(),
      "collateral-type": collateralContract,
    });
  });

  it("blocks unauthorized admin calls", () => {
    const borrowToken = deployMockToken("borrow-token", "Mock Borrow", "BRW");
    const collateralToken = deployMockToken("collateral-token", "Mock Collateral", "COL");

    const setBorrow = simnet.callPublicFn(
      lendFiContract,
      "set-borrow-token",
      [contractPrincipal(borrowToken)],
      borrower,
    );
    expect(setBorrow.result).toBeErr(Cl.uint(100));

    const setCollateral = simnet.callPublicFn(
      lendFiContract,
      "set-collateral-type",
      [
        contractPrincipal(collateralToken),
        Cl.uint(8000),
        Cl.uint(12000),
        Cl.uint(2),
        Cl.bool(true),
        Cl.uint(150),
      ],
      borrower,
    );
    expect(setCollateral.result).toBeErr(Cl.uint(100));
  });

  it("rejects open-loan while paused", () => {
    const borrowToken = deployMockToken("borrow-token", "Mock Borrow", "BRW");
    const collateralToken = deployMockToken("collateral-token", "Mock Collateral", "COL");
    const { borrowContract, collateralContract } = configureLendFi(borrowToken, collateralToken);

    const pause = simnet.callPublicFn(lendFiContract, "pause", [], deployer);
    expect(pause.result).toBeOk(Cl.bool(true));

    const openLoan = simnet.callPublicFn(
      lendFiContract,
      "open-loan",
      [Cl.uint(200_000), Cl.uint(50_000), collateralContract, borrowContract],
      borrower,
    );

    const unpause = simnet.callPublicFn(lendFiContract, "unpause", [], deployer);
    expect(unpause.result).toBeOk(Cl.bool(true));

    expect(openLoan.result).toBeErr(Cl.uint(900));
  });
});
