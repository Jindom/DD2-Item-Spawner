# DD2 Item Spawner — 龙之信条2 刷物品 + 全物品清单导出 + 穿墙飞天

一个 [REFramework](https://github.com/praydog/REFramework) Lua 脚本，适用于《龙之信条2》（含 Dark Arisen）。

- **导出全物品清单**：直接读取游戏内物品数据库，导出 CSV / JSON，名称为你当前的游戏语言。
- **刷物品**：按 ID 添加，或按名称搜索后单个 / 批量添加到背包。
- **穿墙飞天**：F6 开关，沿镜头方向自由飞行，无视碰撞和重力。

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

### 穿墙飞天

| 按键 | 作用 |
|---|---|
| **F6** | 开 / 关（菜单里的「启用穿墙飞天」勾选框效果相同） |
| W / S | 沿镜头方向前进 / 后退（镜头朝上看就往上飞） |
| A / D | 左 / 右平移 |
| Space / Ctrl | 垂直上升 / 下降 |
| Shift | 加速（默认 ×4） |

速度（默认 12 米/秒）和加速倍率可在菜单「穿墙飞天」里调整。REFramework 菜单打开时不会移动，避免在输入框打字时乱飞。

- 飞行中游戏自身的移动 / 跳跃 / 攻击输入会被屏蔽，镜头（鼠标）不受影响。
- **防摔伤**：飞行中持续重置摔落高度；关闭后默认再保护 10 秒，空中关闭也能安全落地（可在菜单关掉）。
- 飞行中角色可能保持跳跃 / 下落动作，属正常现象。
- 读档、死亡、切换角色后会自动关闭。
- 飞到地图边界外或地形内部关闭，可能卡在模型里；重新开启飞出来即可。

## 注意事项

- ⚠️ **先备份存档**。DD2 只有一个主存档：
  `Steam\userdata\<你的Steam ID>\2054970\remote\win64_save`
- ⚠️ **不要刷任务物品 / 钥匙类物品**，可能导致任务进度异常或卡死。
- **注意负重**：一次别刷太多，超重会严重拖慢移动，刷完存进仓库。
- **名称显示为 `?`**：物品名取自游戏的本地化文本，字段为自动识别；名称为空不影响按 ID 添加。
- **游戏更新后失效**：先更新 REFramework；仍不行请看下方排错。
- 仅限单机使用。修改物品 / 穿墙属于作弊行为，后果自负。

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
| 飞天状态显示「未找到碰撞组件」 | 能飞但可能无法穿墙；把日志里 `fly on` 那行发 issue |
| 只有镜头在动，模型不动 / 状态显示「位置被游戏拉回」 | `Character.warp` 不可用（游戏更新），日志里会有对应行，请发 issue |
| 飞天自动关闭并提示「出错」 | 查看日志里 `fly error:` 那行 |

## 实现说明

- 物品数据：`app.ItemManager.getItemData(System.Int32)`，扫描 ID 0–70000，每帧 3000 个，避免卡顿。
- 添加物品：优先 `getItem(System.Int32, System.Int32, app.Character)`，回退到带 `app.ItemDefine.GetItemOption` 的重载。
- 名称：从物品数据中找到名称 GUID 字段，通过 `via.gui.message.get(System.Guid)` 取本地化文本。
- 穿墙飞天：DD2 的角色有位置历史（PosRotContext），直接 `set_Position` 只会移动镜头、模型会被拉回。所以在 `app.UserInputManager.updateInput` 之后（玩家输入处理时）调用游戏自带的 `app.Character.warp(via.vec3, via.Quaternion, app.CharacterWarpOption.ResetPosRotContext)`；同时关闭 `<CharaController>`（碰撞 + 重力），清空玩家输入的按键 / 左摇杆，并每帧重置 `<FallInfo>` 防摔伤。输入钩子失效时退回 `UpdateBehavior` 执行；`warp` 不可用时退回 `set_Position` 并在状态栏报警。单帧被外部移动 >30 m 视为游戏传送，跟随而不拉回。
- 所有游戏方法调用都在游戏线程（`UpdateBehavior` / `LateUpdateBehavior`）中执行，并用 `pcall` 包裹；UI 线程只写请求标志。

## 测试

`tests/mock_test.lua` 用模拟的 REFramework API 离线测试脚本逻辑（不需要游戏）：

```bash
lua tests/mock_test.lua reframework/autorun/DD2_ItemSpawner.lua
```

模拟器还原了 DD2 的位置历史（直接改 Transform 会被拉回）、动作阶段取模型位置、重力与摔伤、游戏自身的走路 / 跳跃输入。覆盖：模型跟随（v1 的「只动镜头」bug 在此复现）、开关边沿触发、六方向移动与速度、Shift 加速、斜向归一化、镜头朝向、帧时间上限、抵抗重力漂移、传送跟随、碰撞组件保持关闭与恢复、游戏输入屏蔽与恢复、防摔伤开 / 关对比、菜单打开时不移动、warp / 输入钩子不可用时的兜底、玩家对象变化自动关闭、异常不崩溃，以及刷物品功能回归。

## 致谢

- [praydog/REFramework](https://github.com/praydog/REFramework)
- [Zharay/DD2-LUAModFixes](https://github.com/Zharay/DD2-LUAModFixes) —— Dark Arisen 后的 `getItem` 签名参考
- [ntgoten/dimension-door](https://github.com/ntgoten/dimension-door) —— DD2 正确移动角色的方式（`Character.warp` + `ResetPosRotContext`、输入时机、`FallInfo`）
- [alphazolam/EMV-Engine](https://github.com/alphazolam/EMV-Engine) —— RE 引擎 CharacterController / 相机矩阵用法参考

## License

Apache License 2.0，见 [LICENSE](LICENSE)。
