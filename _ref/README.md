# _ref —— 饥荒联机版 scripts 只读参考

这里放的是 DST 的 `scripts/` 源码快照，用来回答「这个 API 存不存在 / 长什么样」。**只读，不要改。**

## scripts-2026/

- 来源：`https://gitee.com/U1405/scripts`（`main` 分支归档）
- 快照日期：2026-05-13
- 抓取日期：2026-11-08
- 文件数：3982 个 `.lua`

## 用法

查 API 一律先 grep 这里，不要上网搜：

```
grep -rn "GetAveragePing" _ref/scripts-2026/
```

这一条命令替代了原先 6 次 404 的网络往返，而且答案更准——网页版镜像会被截断，本地文件不会。

## 已知局限

**这不是当前游戏版本。** 快照是 2026-05-13 的，如果游戏之后更新过，个别函数可能已经改了。判断方法：看 `components/playercontroller.lua` 的 `CanLocomote`，如果结构和快照一致，大概率没大改。

**要拿到确定准确的版本**：从游戏安装目录解出 `data/databundles/scripts.zip`，替换掉 `scripts-2026/`。路径通常是：

```
Steam/steamapps/common/Don't Starve Together/data/databundles/scripts.zip
```

## 目录结构

和官方 `scripts.zip` 一致：`components/`、`prefabs/`、`stategraphs/`、`widgets/`、`screens/`、`brains/` 等。注意 `player_classified` 在 `prefabs/` 下，不是 `components/`。
