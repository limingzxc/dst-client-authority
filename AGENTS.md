# 饥荒延迟优化

DST 双端模组：把移动从「服务端说了算」改成「客户端计算 + 服务端校验」。

## 导航

- `client_authority/` —— 模组本体。改之前读它的 `README.md`，末尾有未验证项清单。
- `_ref/scripts-2026/` —— 饥荒联机版 `scripts/` 快照（2026-05-13）。**任何「这个 API 存不存在」的问题先在这里 grep，不要上网搜。**
- `docs/dst-api-notes.md` —— 已核实的 API 事实，带文件和行号。查之前先看这里，别重复查。
- `tools/` —— Lua 语法检查与校验逻辑测试。

## 改完必做

```
npm install     # 仅首次
npm test
```

`npm test` = luaparse 语法检查 + fengari 跑的 15 条校验逻辑断言。跑不过不要继续。

## 注意

`_ref/` 是只读参考。快照不是当前游戏版本，要准确版本就从游戏安装目录解 `data/databundles/scripts.zip` 替换。
