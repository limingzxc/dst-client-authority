# DST API 事实（已核实）

来源：`_ref/scripts-2026/`（2026-05-13 快照）。核实日期 2026-11-08。
行号对应当前快照，游戏更新后会漂移——按函数名 grep，不要按行号找。

## 移动预测

| 事实 | 位置 |
| --- | --- |
| 客户端**不上报**自身坐标 | `networkclientrpc.lua` 的移动类 RPC 只有 `DirectWalking(player, x, z)`（源码注释：`x and z are directions, not positions`）、`PredictWalking(player, x, z, ...)`（目标点）、`DragWalking`、`StartHop`、`SteerBoat(dir_x, dir_z)` |
| 服务端用自己算的位置做范围校验 | `networkclientrpc.lua` 的 `IsPointInRange`：`player.Transform:GetWorldPosition()`，判 `distsq <= 4096` |
| 本地移动预测的总闸 | `components/playercontroller.lua:760` `PlayerController:CanLocomote()` |
| 闸门共四道 | `sg:HasStateTag("busy")` / `inst:HasTag("pausepredict")` / `classified.pausepredictionframes:value() > 0` / `entity:CanPredictMovement()` |
| 暂停预测的唯一收口 | `components/playercontroller.lua:576` `PlayerController:RemotePausePrediction(frames)` → `self.classified:PushPausePredictionFrames(frames or 0)` |
| 调用点约 45 处 | `stategraphs/SGwilson.lua`；另有 `SGwilsonghost.lua` 2 处 |
| `player_classified` 是 **prefab**，不是 component | `prefabs/player_classified.lua`，`PushPausePredictionFrames` 在 :1652 赋值。**`AddComponentPostInit` 挂不上，要用 `AddPrefabPostInit`** |
| `pausepredictionframes` 是 `net_tinybyte` | `prefabs/player_classified.lua` |
| `locomotor` **没有** busy 闸门 | `components/locomotor.lua:1116` `WalkInDirection` 直接设 `wantstomoveforward` 并推 `locomote` 事件，不检查 busy。只有转向会跳过：`FaceMovePoint`(:713)、`SetMoveDir`(:705) |
| 本版本没有 `StartWalking` | 移动入口是 `WalkInDirection` / `WalkForward` / `RunForward`。旧资料里写 `StartWalking` 的，是按更早版本的说法 |

## 动作预测

| 事实 | 位置 |
| --- | --- |
| 起手动画在本地先播，RPC 后发 | `DoAttackButton` 里 `act.preview_cb` 才发 RPC，`locomotor:PreviewAction` 先跑 |
| 客户端状态机含动作状态 | `stategraphs/SGwilson_client.lua` 有 `ACTIONS.CHOP / MINE / PICK / ATTACK` 的 actionhandler |
| 超距攻击不会立刻 miss | 服务端 `OnRemoteActionButton` 重跑 `GetActionButtonAction(target)`，再 `locomotor:PushAction(buffaction, true)`，第二参数 `true` = 先走过去 |

## 战斗

| 事实 | 位置 |
| --- | --- |
| 命中判定 | `components/combat.lua` `CanHitTarget`：`distsq(targetpos, self.inst:GetPosition()) <= self:CalcHitRangeSq(target)` |
| 范围计算 | `CalcHitRangeSq = (target:GetPhysicsRadius(0) + GetHitRange())²`；`GetHitRange = self.hitrange + weapon.hitrange` |
| **没有** `extra_reach`，也**没有** `temprange` | 全树 grep 无结果。放宽只能改 `hitrange` 或包装 `CalcHitRangeSq` |
| miss 时推事件 | `Combat:DoAttack` 里 `PushEvent("onmissother")` 后直接 return |

## 网络 / ping

| 事实 | 位置 |
| --- | --- |
| `TheNet:GetAveragePing()` **存在**，返回数值毫秒 | `widgets/ping.lua:23` |
| `TheNet:GetPing()` **不存在** | 全树 grep 只有 `GetAveragePing` |
| `TheNet:GetNetworkStatistics()` **存在** | `consolecommands.lua` 的 `c_netstats` 遍历打印全部字段 |

## 查证方法

```
grep -rn "函数名" _ref/scripts-2026/
```

## 已否定的外部参考

- 工坊 ID `2283416213` 是 **CaveOnGround**（地表开洞穴的地图模组），不是洞穴动作延迟模组。
- **No More Lag** 关闭移动预测，方向与本模组相反。
