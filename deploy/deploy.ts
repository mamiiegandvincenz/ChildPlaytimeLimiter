// deploy/deploy_child_playtime_limiter.ts
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, log, read, execute } = deployments;
  const { deployer, parent: parentNamed, child: childNamed } = await getNamedAccounts();

  log(`Deploying ChildPlaytimeLimiter from ${deployer} on ${network.name}...`);

  const deployed = await deploy("ChildPlaytimeLimiter", {
    from: deployer,
    args: [], // конструктор без аргументов
    log: true,
    waitConfirmations: network.live ? 3 : 1,
  });

  log(`ChildPlaytimeLimiter contract: ${deployed.address}`);

  // ── Пост-деплой: установить роли (владелец = deployer)
  // Возьмём namedAccounts.parent/child, если заданы, иначе — deployer (для дев-окружения).
  const parent = parentNamed ?? deployer;
  const child = childNamed ?? deployer;

  try {
    const curParent = await read("ChildPlaytimeLimiter", "parent");
    const curChild = await read("ChildPlaytimeLimiter", "child");

    const ZERO = "0x0000000000000000000000000000000000000000";
    if (curParent === ZERO || curChild === ZERO) {
      log(`Configuring roles: parent=${parent}, child=${child} ...`);
      await execute("ChildPlaytimeLimiter", { from: deployer, log: true }, "setRoles", parent, child);
      log("Roles configured.");
    } else {
      log(`Roles already set: parent=${curParent}, child=${curChild}`);
    }
  } catch (e: any) {
    log(`⚠️ Skipping role setup (read/execute failed): ${e?.message ?? e}`);
  }
};

export default func;
func.id = "deploy_child_playtime_limiter"; // уникальный id, чтобы не переисполнялся
func.tags = ["ChildPlaytimeLimiter", "Limiter"];
