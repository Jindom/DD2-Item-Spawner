# DD2 Item Spawner

《龙之信条2》（含 Dark Arisen）的 [REFramework](https://github.com/praydog/REFramework) Lua 脚本：**全物品清单导出 · 刷物品 · 穿墙飞天 · 秒杀全场**。

| 功能 | 说明 |
|---|---|
| 📋 导出全物品清单 | 直接读取游戏内物品数据库，导出 CSV / JSON，名称为当前游戏语言 |
| 🎒 刷物品 | 按 ID 添加，或按名称搜索后单个 / 批量添加到背包 |
| 🕊️ 穿墙飞天 | F6 开关，沿镜头方向自由飞行，无视碰撞和重力，自带防摔伤 |
| ⚔️ 秒杀全场 | F7 秒杀所有已加载的敌人（含 BOSS）；F8 一击必杀模式 |

> **为什么不附带静态 ID 表？** Dark Arisen（2026-10-09）更新后物品和 `getItem` 签名都有变化，网上旧表和旧脚本大量失效。由脚本从游戏里导出，清单永远与你当前的游戏版本一致。

---

## 快速开始

1. 安装最新版 **REFramework**（Dark Arisen 建议使用 [nightly 版](https://github.com/praydog/REFramework-nightly/releases)），**只把 `dinput8.dll`** 解压到游戏根目录。
2. 安装脚本，二选一：
   - **手动**：下载 [`DD2_ItemSpawner.lua`](https://github.com/Jindom/DD2-Item-Spawner/raw/main/reframework/autorun/DD2_ItemSpawner.lua)，放到 `<游戏目录>\reframework\autorun\`。
   - **Fluffy Mod Manager**：到 [Releases](https://github.com/Jindom/DD2-Item-Spawner/releases) 下载 `DD2-Item-Spawner-vX.Y.Z.zip`，直接拖进 Fluffy 启用。
3. 启动游戏、读档进入游戏世界，按 **Insert** 打开 REFramework 菜单 → **Script Generated UI** → **DD2 刷物品**。

升级：用新版 `DD2_ItemSpawner.lua` 覆盖旧文件（或在 Fluffy 里替换），已导出的物品清单会保留。

## 刷物品

| 操作 | 方法 |
|---|---|
| 导出全物品清单 | 点「导出全物品清单（CSV/JSON）」，约数秒完成。输出到 `<游戏目录>\reframework\data\DD2_ItemList.csv`（Excel 可直接打开）和 `DD2_ItemList.json` |
| 单个添加 | 填「物品ID」和「数量」（1–999），点「添加到背包」 |
| 搜索 | 在「搜索（名称/ID）」输入关键词，点击结果自动填入 ID |
| 批量添加 | 搜索结果 ≤100 条时出现「把这 N 个全部各加 xN」按钮 |

导出过一次后，清单会在下次启动时自动加载，无需重复扫描。

## 穿墙飞天

| 按键 | 作用 |
|---|---|
| **F6** | 开 / 关（菜单「穿墙飞天」里的「启用穿墙飞天」勾选框效果相同） |
| W / S | 沿镜头方向前进 / 后退（镜头朝上看就往上飞） |
| A / D | 左 / 右平移 |
| Space / Ctrl | 垂直上升 / 下降 |
| Shift | 加速 |

菜单「穿墙飞天」中的设置：

| 设置 | 默认 | 说明 |
|---|---|---|
| 速度 (米/秒) | 12 | 1–100 |
| Shift 加速倍率 | ×4 | 1–10 |
| 关闭后 10 秒内防摔伤 | 开 | 在空中关闭也能安全落地 |

- 飞行中游戏自身的移动 / 跳跃 / 攻击输入会被屏蔽，鼠标转镜头不受影响。
- REFramework 菜单打开时不会移动，避免在输入框打字时乱飞。
- 飞行中角色可能保持跳跃 / 下落动作，属正常现象。
- 读档、死亡、切换角色后自动关闭。
- 在地形内部或地图边界外关闭可能卡进模型里，重新开启飞出来即可。

## 秒杀全场

| 按键 / 按钮 | 作用 |
|---|---|
| **F7** / 「秒杀全场（含 BOSS）」 | 把范围内所有存活敌人的 HP 设为 0 |
| **F8** / 「一击必杀模式」勾选框 | 每 0.5 秒把存活敌人的 HP 压到 1，任何一击都会死；对之后刷出的怪、多阶段 BOSS 同样有效 |

| 设置 | 默认 | 说明 |
|---|---|---|
| 范围 (米) | 0 | 0 = 所有已加载的敌人；设为 50 只影响 50 米内 |

- 敌人列表来自游戏的 `EnemyManager`，包含 BOSS（龙、美杜莎、独眼巨人等），不包含队友、随从和 NPC。
- 已死亡的敌人会被跳过，不会把尸体「复活」。
- 状态栏会显示处理了多少个敌人。
- **如果 F7 后敌人 HP 归零却没有倒下**：先用 F8 一击必杀模式代替（随便打一下就死），再点「诊断：导出 HP/伤害相关方法」，把 `reframework\data\DD2_HitMethods.txt` 发 issue，以便接入游戏真正的死亡流程。
- 不死系敌人在游戏里本身会复活，可能需要火 / 神圣属性补刀。
- 远处秒杀的敌人是否掉落经验和物品由游戏决定。

## 注意事项

- ⚠️ **先备份存档**。DD2 只有一个主存档：`Steam\userdata\<你的Steam ID>\2054970\remote\win64_save`
- ⚠️ **不要刷任务物品 / 钥匙类物品**，可能导致任务进度异常或卡死。
- **注意负重**：一次别刷太多，超重会严重拖慢移动，刷完存进仓库。
- **名称显示为 `?`**：物品名取自游戏的本地化文本，字段为自动识别；名称为空不影响按 ID 添加。
- **游戏更新后失效**：先更新 REFramework，仍不行请看下方排错并提 [issue](https://github.com/Jindom/DD2-Item-Spawner/issues)。
- 仅限单机使用。刷物品 / 穿墙 / 秒杀属于作弊行为，后果自负。
- 秒杀可能影响剧情战斗（例如需要演出才能结束的 BOSS 战），重要战斗前请先存档。

## 排错

脚本加载时会在 `<游戏目录>\re2_framework_log.txt` 中输出：

```
[DD2 刷物品] loaded v1.2.0. getItem3=true getItem4=true msgGet=true
```

开启飞天时还会输出 `fly on, cc=true warpOpt=true inputHook=true`，秒杀时输出 `kill all: alive=… zeroed=… inRange=… errors=…`。提 issue 时请附上所有带 `[DD2 刷物品]` 的日志行。

| 现象 | 原因 / 处理 |
|---|---|
| 菜单里看不到「DD2 刷物品」 | 脚本未放对目录，或 REFramework 未加载（菜单 ScriptRunner 里查看报错） |
| `getItem3=false` 且 `getItem4=false` | 游戏更新改了方法签名，等待 REFramework / 脚本更新 |
| 提示「未进入游戏或找不到玩家」 | 需在读档进入游戏世界后使用，标题画面无效 |
| 提示「无效物品ID」 | 该 ID 在当前版本不存在，请先导出清单查找 |
| 飞天状态显示「未找到碰撞组件」 | 能飞但可能无法穿墙（日志里 `cc=false`） |
| 只有镜头在动，模型不动 / 状态显示「位置被游戏拉回」 | `Character.warp` 不可用（日志里 `warpOpt=false` 或 `Character.warp 不可用`） |
| 飞天自动关闭并提示「出错」 | 查看日志里 `fly error:` 那行 |
| 秒杀提示「找不到 EnemyManager」 | 需在读档进入游戏世界后使用 |
| 秒杀后状态显示「N 个 HP 未变为 0」 | `setHpValue` 对这些敌人无效，用 F8 并导出诊断文件发 issue |
| 敌人 HP 为 0 但没死 | 用 F8 一击必杀代替，并导出诊断文件发 issue（见上文） |

## 实现说明

**物品**
- 物品数据：`app.ItemManager.getItemData(System.Int32)`，扫描 ID 0–70000，每帧 3000 个，避免卡顿。
- 添加物品：优先 `getItem(System.Int32, System.Int32, app.Character)`，回退到带 `app.ItemDefine.GetItemOption` 的重载。
- 名称：从物品数据中找到名称 GUID 字段，通过 `via.gui.message.get(System.Guid)` 取本地化文本。

**穿墙飞天**
- DD2 的角色有位置历史（PosRotContext），直接 `Transform.set_Position` 只会移动镜头，模型每帧会被拉回原处。
- 因此在 `app.UserInputManager.updateInput` 之后（玩家输入处理时）调用游戏自带的 `app.Character.warp(via.vec3, via.Quaternion, app.CharacterWarpOption)`，选项为 `ResetPosRotContext`，模型、镜头和位置历史保持一致。
- 关闭角色的 `<CharaController>`（`via.physics.CharacterController`：碰撞 + 重力）；关闭飞天时恢复原状态并 `warp()` 同步物理胶囊。
- 清空玩家输入对象的按键标志和左摇杆，阻止游戏自身的走路 / 跳跃 / 攻击。
- 每帧重置 `<FallInfo>`（基准高度、空中最高点、摔落高度），关闭后继续 10 秒，实现防摔伤。
- 兜底：输入钩子 0.2 秒未触发时改在 `UpdateBehavior` 执行；`warp` 不可用时退回 `set_Position` 并在状态栏报警；单帧被外部移动 >30 m 视为游戏传送（如渡石），跟随而不拉回。

**秒杀全场**
- 敌人：`app.EnemyManager:getAllEnemies()` → `get_Chara()`；距离用 `Character.get_DistanceSqFromPlayer()`。
- HP：`Character.get_Hit()` 得到 `app.HitController`，调用 `setHpValue(System.Single, System.Boolean)`；读 `Character.get_Hp()` 跳过已死亡（HP≤0）的敌人。
- 每个敌人单独 `pcall`，一个出错不影响其他敌人。
- 诊断按钮用反射列出 `app.HitController` / `app.Character` 中名字含 hp / dead / die / damage / kill 的方法及参数类型。

**线程**：所有游戏方法调用都在游戏线程（输入钩子 / `UpdateBehavior`）中执行，并用 `pcall` 包裹；UI 线程只写请求标志。

## 测试

`tests/mock_test.lua` 用模拟的 REFramework API 和 DD2 角色行为离线测试脚本逻辑，不需要游戏：

```bash
lua tests/mock_test.lua reframework/autorun/DD2_ItemSpawner.lua
```

模拟器还原了 DD2 的位置历史（直接改 Transform 会被拉回）、动作阶段取模型位置、重力与摔伤、游戏自身的走路 / 跳跃输入，以及带血量的敌人（含 BOSS、尸体、远处敌人、出错的敌人），共 88 项检查：

- **飞天**：模型跟随（v1.1.0 之前「只动镜头」的 bug 在此复现）、开关边沿触发、六方向移动与速度、Shift 加速、斜向归一化、镜头朝向、帧时间上限、悬停、传送跟随、碰撞组件保持关闭与恢复、游戏输入屏蔽与恢复、防摔伤开 / 关对比、菜单打开时不移动、`warp` / 输入钩子不可用时的兜底、玩家对象变化自动关闭、异常不崩溃。
- **秒杀全场**：F7 秒杀含远处 BOSS、按键边沿触发、尸体不被复活、单个敌人出错不影响其他、范围过滤、F8 一击必杀（压血、任意一击致死、新刷怪、BOSS 回血 / 换阶段后重新压血、节流、关闭后停止）、勾选框、无 EnemyManager 时不崩溃、诊断导出内容与过滤、飞行中秒杀。
- **刷物品回归**：清单导出、名称解析、添加物品、飞行中添加物品。

## 文件结构

```
modinfo.ini                               Fluffy Mod Manager 元数据
reframework/autorun/DD2_ItemSpawner.lua   脚本本体
tests/mock_test.lua                       离线模拟测试
CHANGELOG.md                              更新日志
```

## 更新日志

见 [CHANGELOG.md](CHANGELOG.md)。

## 致谢

- [praydog/REFramework](https://github.com/praydog/REFramework)
- [Zharay/DD2-LUAModFixes](https://github.com/Zharay/DD2-LUAModFixes) —— Dark Arisen 后的 `getItem` 签名参考
- [ntgoten/dimension-door](https://github.com/ntgoten/dimension-door) —— DD2 正确移动角色的方式（`Character.warp` + `ResetPosRotContext`、输入时机、`FallInfo`）
- [kagenocookie/dd2-content-editor](https://github.com/kagenocookie/dd2-content-editor) —— `HitController.setHpValue` 用法参考
- [JumpmanSr/Simple-ESP-Dragons-Dogma-2](https://github.com/JumpmanSr/Simple-ESP-Dragons-Dogma-2) —— `EnemyManager.getAllEnemies` 敌人枚举参考
- [alphazolam/EMV-Engine](https://github.com/alphazolam/EMV-Engine) —— RE 引擎 CharacterController / 相机矩阵用法参考

## License

Apache License 2.0，见 [LICENSE](LICENSE)。
