# DD2 Item Spawner — 龙之信条2 刷物品 + 全物品清单导出

一个 [REFramework](https://github.com/praydog/REFramework) Lua 脚本，适用于《龙之信条2》（含 Dark Arisen）。

- **导出全物品清单**：直接读取游戏内物品数据库，导出 CSV / JSON，名称为你当前的游戏语言。
- **刷物品**：按 ID 添加，或按名称搜索后单个 / 批量添加到背包。

> 为什么不附带静态 ID 表？Dark Arisen（2026-10-09）更新后物品和 `getItem` 签名都有变化，网上旧表和旧脚本大量失效。由脚本从游戏里导出，清单永远与当前版本一致。

---

## 安装

1. 安装最新版 **REFramework**（Dark Arisen 建议使用 [nightly 版](https://github.com/praydog/REFramework-nightly/releases)），**只把 `dinput8.dll`** 解压到游戏根目录。
2. 安装本脚本，二选一：
   - **手动**：把 `reframework/autorun/DD2_ItemSpawner.lua` 复制到 `<游戏目录>\reframework\autorun\`
   - **Fluffy Mod Manager**：把整个仓库打包成 zip，拖进 Fluffy 安装（已包含 `modinfo.ini`）
3. 启动游戏，读档进入游戏世界。

## 使用

游戏内按 **Insert** 打开 REFramework 菜单 → **Script Generated UI** → **DD2 刷物品**。

| 功能 | 操作 |
|---|---|
| 导出全物品清单 | 点「导出全物品清单（CSV/JSON）」，约数秒完成。输出到 `<游戏目录>\reframework\data\DD2_ItemList.csv`（Excel 可直接打开）和 `DD2_ItemList.json` |
| 单个添加 | 填「物品ID」和「数量」（1–999），点「添加到背包」 |
| 搜索 | 在「搜索（名称/ID）」输入关键词，点击结果自动填入 ID |
| 批量添加 | 搜索结果 ≤100 条时出现「把这 N 个全部各加 xN」按钮 |

导出过一次后，清单会在下次启动时自动加载，无需重复扫描。

## 注意事项

- ⚠️ **先备份存档**。DD2 只有一个主存档：
  `Steam\userdata\<你的Steam ID>\2054970\remote\win64_save`
- ⚠️ **不要刷任务物品 / 钥匙类物品**，可能导致任务进度异常或卡死。
- **注意负重**：一次别刷太多，超重会严重拖慢移动，刷完存进仓库。
- **名称显示为 `?`**：物品名取自游戏的本地化文本，字段为自动识别；名称为空不影响按 ID 添加。
- **游戏更新后失效**：先更新 REFramework；仍不行请看下方排错。
- 仅限单机使用。修改物品属于作弊行为，后果自负。

## 排错

脚本加载时会在 `<游戏目录>\re2_framework_log.txt` 中输出一行：

```
[DD2 刷物品] loaded. getItem3=true getItem4=true msgGet=true
```

| 现象 | 原因 / 处理 |
|---|---|
| 菜单里看不到「DD2 刷物品」 | 脚本未放对目录，或 REFramework 未加载（菜单 ScriptRunner 里查看报错） |
| `getItem3=false` 且 `getItem4=false` | 游戏更新改了方法签名，等待 REFramework / 脚本更新 |
| 提示「未进入游戏或找不到玩家」 | 需在读档进入游戏世界后使用，标题画面无效 |
| 提示「无效物品ID」 | 该 ID 在当前版本不存在，请先导出清单查找 |

## 实现说明

- 物品数据：`app.ItemManager.getItemData(System.Int32)`，扫描 ID 0–70000，每帧 3000 个，避免卡顿。
- 添加物品：优先 `getItem(System.Int32, System.Int32, app.Character)`，回退到带 `app.ItemDefine.GetItemOption` 的重载。
- 名称：从物品数据中找到名称 GUID 字段，通过 `via.gui.message.get(System.Guid)` 取本地化文本。
- 所有游戏方法调用都在 `UpdateBehavior` 游戏线程中执行，并用 `pcall` 包裹，不在 UI 线程直接调用。

## 致谢

- [praydog/REFramework](https://github.com/praydog/REFramework)
- [Zharay/DD2-LUAModFixes](https://github.com/Zharay/DD2-LUAModFixes) —— Dark Arisen 后的 `getItem` 签名参考

## License

Apache License 2.0，见 [LICENSE](LICENSE)。
