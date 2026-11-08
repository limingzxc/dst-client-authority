# DST Client Authority

把《饥荒联机版》的移动从「服务端说了算」改成「客户端计算 + 服务端校验」。

灵感来自 Minecraft 的 `handleMovePlayer`：客户端算位置并上报，服务端按「移动速度 × 实际间隔 × 宽容倍数」校验，通过就采纳，超速就丢弃。

## 它解决的问题

原版不是延迟高，是**预测会被整段关掉**。`PlayerController:CanLocomote()` 一关，输入延迟退回整整一个 RTT，而 DST 里砍树、采集、攻击都在关它。

模组做三件事：

| 层 | 原版 | 本模组 |
| --- | --- | --- |
| 一 | `CanLocomote()` 返回 false，客户端停止预测 | 拆掉闸门，永远 true |
| 二 | `RemotePausePrediction()` 让客户端冻结 N 帧 | 覆盖该方法，不再暂停 |
| 三 | 服务端位置直接覆盖客户端 | 服务端先对齐到客户端，覆盖变空操作 |

第三层关不掉（引擎层），但可以让它变成恒等变换。

## 快速开始

```bash
npm install
npm test
```

`npm test` 跑 Lua 语法检查 + 15 组校验逻辑断言（掉帧、超速、传送、击退、载具、序列号、NaN 等边界）。

安装与发布到创意工坊的完整步骤见 [`client_authority/README.md`](client_authority/README.md)。

## 结构

```
client_authority/    模组本体（双端）
docs/dst-api-notes.md 已核实的 DST API 事实，带文件行号
tools/               语法检查与测试
_ref/README.md       如何获取 DST 源码参考
AGENTS.md            给编码 agent 的导航
```

## 已知副作用

- 开启「客户端始终预测」后，可以在砍树、攻击时移动
- 服务端碰撞不再是权威，理论上可以穿墙
- 命中判定、交互距离跟着变成客户端驱动

**仅建议朋友服使用。** 公开服等于送挂。

## 状态

实验性。未在实机验证过，`client_authority/README.md` 末尾列了五条未验证项。

## 许可

MIT
