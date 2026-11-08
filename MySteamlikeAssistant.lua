------------------------------------------------------------------
-- MySteamlikeAssistant —— 鼠标视角助手（WoW 3.3.5a / WLK）
------------------------------------------------------------------
-- 作用：
--   接收两个特殊按键 F11 / F12（一般由手柄映射软件或安卓模拟器注入），
--   用来控制游戏的“鼠标视角”（Mouselook，等价于按住鼠标右键拖动视角）。
--
--   注意：F11 / F12 的映射由「按键映射」开关控制，**默认关闭**（不占用这两个键）。
--   需要先在设置面板勾选，或输入 /msa bind 开启。
--
--      按 F11  -> 若当前不在鼠标视角，则开启（MouselookStart）
--      按 F12  -> 关闭鼠标视角（MouselookStop）
--
--   另外提供一个「标记骷髅」功能（默认关闭，按键在设置面板里录制）：
--   按一下把当前目标标记为骷髅（团队标记 8 号），需在小队 / 团队中生效。
--
--   另外提供一个「移动自动锁视角」功能（默认关闭，可用 /msa wasd 开关）：
--   当玩家用 W/A/S/D 方向键开始移动时，若当前不在鼠标视角，则自动开启，
--   让相机跟随角色移动。实现方式见下方“移动自动锁视角”一节。
--
--   另外提供一个「组合键提示」功能（Ctrl / Alt / Shift 各自独立开关，默认全开）：
--   按住修饰键时，在绑定了对应组合（+1 ~ +0）的动作条按钮上浮出「Ctrl+N」角标
--   并描一圈亮边，松开即消失；只读展示，不改动任何按键绑定。
--
-- 原理：
--   使用 SetBindingClick 把 F11/F12 绑定到两个“隐藏按钮”的点击事件上。
--   按键触发时，客户端会调用对应按钮的 OnClick 脚本，从而执行开启/关闭逻辑。
--   这样既不需要 Bindings.xml，也不会出现在游戏“按键设置”界面里，
--   但绑定是真实生效的（用 /msa 可看到 “CLICK MSA_Btn_F20:LeftButton”）。
--
-- 相关 API（3.3.5a 客户端均已验证存在）：
--   IsMou1selooking()  -> 返回当前是否处于鼠标视角
--   MouselookStart()  -> 开启鼠标视角
--   MouselookStop()   -> 关闭鼠标视角
------------------------------------------------------------------

-- 需要接收的两个按键。当前先用 F11 / F12，如需更换直接改这里即可。
local START_KEY = "F11"
local STOP_KEY = "F12"

-- 两个隐藏按钮的全局名（仅作内部标识，与具体按键无关）。
-- 注意：SetBindingClick 是“按名字”找按钮的，所以名字必须全局且唯一，不能是 local。
local BTN_START = "MSA_Btn_F20"
local BTN_STOP = "MSA_Btn_F21"

-- 「标记骷髅」功能的隐藏按钮名与团队标记编号（8 = 骷髅）。
local BTN_SKULL = "MSA_Btn_Skull"
local SKULL_ICON = 8

-- 「按键映射」开关：开启后才把 F11 / F12 绑到上面两个隐藏按钮上。
-- 关闭时不占用这两个键（之前绑定过的会自动解绑），/msa start / stop 仍然可用。
-- 可在设置面板勾选，或用 /msa bind 切换。**默认关闭**（首次安装不占用任何按键）。
local keyMappingEnabled = false

-- 「移动自动锁视角」开关：开启后，用 W/A/S/D 方向键开始移动时，
-- 若当前不在鼠标视角，则自动开启。用 /msa wasd 切换。**默认关闭**。
-- 该开关会写入存档，重载界面后保持上次的状态。
local wasdAutoLock = false

-- 「标记骷髅」功能：按一下把当前目标标记为指定编号的团队标记。
-- 由独立开关控制，**默认关闭**；默认按键是 \（回车键上面那个键），默认 8 号（骷髅）。
-- 按键与编号都可在设置面板里改。
local SKULL_DEFAULT_KEY = "\\"
local SKULL_ICON_DEFAULT = 8
local skullEnabled = false
local skullKey = SKULL_DEFAULT_KEY
local skullIcon = SKULL_ICON_DEFAULT

-- 1~8 号团队标记的形状说明（编号顺序与客户端一致）。
local SKULL_ICON_NAMES = {
	"1 - 星形（黄色五角星）",
	"2 - 圆形（橙色圆环）",
	"3 - 菱形（紫色菱形）",
	"4 - 三角（绿色三角）",
	"5 - 月亮（银白弯月）",
	"6 - 方块（蓝色方块）",
	"7 - 十字（红色叉形）",
	"8 - 骷髅（白色骷髅头）",
}

-- 「登录时自动应用聊天窗口布局」开关：开启后，每次登录 / 重载界面时
-- 自动把存档里的聊天窗口布局（位置、尺寸、锁定、字号）写回聊天框。
-- 手机端与电脑端分辨率不同，聊天窗口会跑到不合适的位置，用它就不用每次手动拖。
-- **默认关闭**，可在设置面板勾选，或用 /msa chat auto 切换。
local chatAutoApply = false

-- 「组合键提示」开关：按住 Ctrl / Alt / Shift 时，在绑定了对应组合（+1 ~ +0）的
-- 动作条按钮上浮出「Ctrl+N」角标并描边，松开即消失。只读展示，不改动任何按键绑定。
-- 三个修饰键各有独立开关，**默认全部开启**；
-- 可在设置面板勾选，或用 /msa ctrl、/msa alt、/msa shift 分别切换。
local ctrlHintEnabled = true
local altHintEnabled = true
local shiftHintEnabled = true

-- WASD 本次“已锁定”标记：一旦通过方向键锁上视角，就把后续按键直接短路，
-- 不再每次按键都调用 IsMouselooking() 判断，避免无谓的重复检查。
-- 以下情况会重置该标记，以便下次移动能重新判断并锁定：
--   * 按 F12 / 输入 /msa stop 停止视角；
--   * 按下或松开鼠标右键（手动转向 / 看视角）；
--   * 低频兜底检测发现客户端已自行退出鼠标视角（见下方“视角状态兜底检测”）。
-- 该标记统一通过 SetWASDLocked() 读写，以便顺带开关兜底检测。
local wasdLocked = false

------------------------------------------------------------------
-- 聊天框输出与调试日志
------------------------------------------------------------------

-- 调试日志开关：用 /msa debug 切换，默认关闭，避免正常游玩时刷屏。
-- 打开后，每次收到开始/停止键都会在聊天框打印一行，用来确认按键到底有没有送达。
local debugEnabled = false

-- 统一格式的聊天框消息，带 [MSA] 前缀和颜色。
local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[MSA]|r " .. tostring(msg))
end

-- 仅在调试开关打开时输出。
local function Debug(msg)
	if debugEnabled then
		Print(msg)
	end
end

------------------------------------------------------------------
-- 视角状态兜底检测（自愈）
------------------------------------------------------------------
-- 为什么需要它：wasdLocked 为 true 时，方向键钩子会直接短路（不再判断视角状态）。
-- 但客户端还有很多“非右键”的停视角路径，插件完全看不到，例如：
--   * 打开会捕获鼠标的界面（背包 / 角色 / 地图 / Esc 菜单 / 回车打字）；
--   * 切出游戏窗口后再切回；
--   * 触摸或点击到界面元素。
-- 这些情况下客户端已经退出鼠标视角，而 wasdLocked 仍是 true，于是之后
-- 按 W/A/S/D 全被短路，视角再也锁不回来 —— 外部表现就是“相机不转，
-- 但光标可见、划过界面还会弹提示框”。
-- 解决办法：只在 wasdLocked 为 true 期间挂一个低频（0.5 秒）检测，
-- 一旦发现已不在鼠标视角，就重置标记，让下一次方向键移动重新自动锁定。
-- 按方向键本身仍然只判断一次，不受影响。
local LOCK_CHECK_INTERVAL = 0.5

-- 1x1 的空框架，只用来跑 OnUpdate；隐藏时不消耗任何性能。
local lockCheckFrame = CreateFrame("Frame", nil, UIParent)
lockCheckFrame:SetSize(1, 1)
local lockCheckElapsed = 0

-- 统一设置 wasdLocked：为 true 时顺带开启兜底检测，为 false 时关闭。
-- 由于检测框架只在锁定期间显示，未锁定时没有任何额外开销。
local function SetWASDLocked(locked)
	wasdLocked = locked
	lockCheckElapsed = 0
	if locked then
		lockCheckFrame:Show()
	else
		lockCheckFrame:Hide()
	end
end

lockCheckFrame:SetScript("OnUpdate", function(_, elapsed)
	lockCheckElapsed = lockCheckElapsed + elapsed
	if lockCheckElapsed < LOCK_CHECK_INTERVAL then
		return
	end
	lockCheckElapsed = 0
	if not IsMouselooking() then
		SetWASDLocked(false)
		Debug("视角已被客户端关闭（非右键途径），自动锁定标记已重置，下次移动可重新锁定")
	end
end)

------------------------------------------------------------------
-- 临时诊断（/msa diag）：排查鼠标输入层问题时使用
------------------------------------------------------------------
-- 用途：卡住的那一刻，看「客户端内部到底看到了什么」。
-- 开启后每秒打印一行，并在视角状态 / 鼠标焦点变化时立即补打一行；
-- 鼠标焦点变化正是 tooltip 跟着切换的对应物。
-- 注意：这是临时排查手段，问题定位后应整段删除，并同时去掉 /msa diag 命令。
local diagEnabled = false
local DIAG_INTERVAL = 1

local diagFrame = CreateFrame("Frame", nil, UIParent)
diagFrame:SetSize(1, 1)
local diagElapsed = 0
local diagLastMouselook = nil
local diagLastFocus = nil

-- 鼠标当前所在框体的名字；不在框体上（指向 3D 世界）时返回 WorldFrame 或无。
local function FocusName()
	local f = GetMouseFocus()
	if not f or not f.GetName then
		return "无"
	end
	return f:GetName() or "(匿名框体)"
end

-- 一行完整状态：视角是否开启、客户端看到的光标坐标、鼠标在哪个框体、左右键是否按下。
local function DiagLine(tag)
	local x, y = GetCursorPosition()
	Print(string.format(
		"[诊断] %s 视角=%s 坐标=(%d, %d) 焦点=%s 左键=%s 右键=%s",
		tag,
		IsMouselooking() and "开启" or "关闭",
		math.floor(x or -1), math.floor(y or -1),
		FocusName(),
		IsMouseButtonDown("LeftButton") and "按下" or "松开",
		IsMouseButtonDown("RightButton") and "按下" or "松开"
	))
end

diagFrame:SetScript("OnUpdate", function(_, elapsed)
	if not diagEnabled then
		return
	end
	-- 变化即时打印：视角状态、鼠标焦点。
	local mLock = IsMouselooking()
	local focus = FocusName()
	if mLock ~= diagLastMouselook then
		diagLastMouselook = mLock
		DiagLine("视角变化")
	end
	if focus ~= diagLastFocus then
		diagLastFocus = focus
		DiagLine("焦点变化")
	end
	-- 周期性打印一行，便于卡住时看坐标是否还在动。
	diagElapsed = diagElapsed + elapsed
	if diagElapsed < DIAG_INTERVAL then
		return
	end
	diagElapsed = 0
	DiagLine("周期")
end)

local function ToggleDiag()
	diagEnabled = not diagEnabled
	if diagEnabled then
		diagElapsed = 0
		-- 置空让首个 OnUpdate 立刻以「视角变化」打到当前状态。
		diagLastMouselook = nil
		diagLastFocus = nil
		diagFrame:Show()
		Print("诊断已开启：每秒打印一行客户端内部鼠标状态，视角/焦点变化时立即补一行。")
		Print("卡住时直接看聊天框最近几行即可（无需再输入命令）。再输入一次 /msa diag 关闭。")
	else
		diagFrame:Hide()
		Print("诊断已关闭")
	end
end

------------------------------------------------------------------
-- 业务逻辑
------------------------------------------------------------------

-- 开启鼠标视角。
-- 先判断 IsMouselooking()，避免在已经处于鼠标视角时重复调用 MouselookStart。
local function StartMouselook()
	if not IsMouselooking() then
		MouselookStart()
	end
end

-- 关闭鼠标视角。
-- 停止时清掉 WASD 的“已锁定”标记，让下次方向键移动可以重新判断并锁定。
local function StopMouselook()
	MouselookStop()
	SetWASDLocked(false)
end

------------------------------------------------------------------
-- 隐藏按钮：仅用于接收按键“点击”，不参与任何界面显示
------------------------------------------------------------------

-- CreateFrame 创建的框架默认就是隐藏的，无需 Show()。
-- OnClick 就是按键触发时真正执行的入口。
-- 这里在动作执行后顺便打一条调试日志（含触发来源与当前视角状态），方便排查输入是否送达。
-- 把触发来源（鼠标按键）一并写进日志：SetBindingClick 用的是左键，
-- 正常应显示“左键点击”，也方便确认注入的输入究竟有没有送到。
local function ClickText(button)
	if button == "LeftButton" then
		return "左键点击"
	elseif button == "RightButton" then
		return "右键点击"
	elseif button == "MiddleButton" then
		return "中键点击"
	end
	return tostring(button) .. " 点击"
end

local btnStart = CreateFrame("Button", BTN_START)
btnStart:SetScript("OnClick", function(_, button)
	StartMouselook()
	Debug("收到按键 " .. START_KEY .. "（" .. ClickText(button) .. "，鼠标视角: " .. (IsMouselooking() and "开启" or "关闭") .. "）")
end)

local btnStop = CreateFrame("Button", BTN_STOP)
btnStop:SetScript("OnClick", function(_, button)
	StopMouselook()
	Debug("收到按键 " .. STOP_KEY .. "（" .. ClickText(button) .. "，鼠标视角: " .. (IsMouselooking() and "开启" or "关闭") .. "）")
end)

------------------------------------------------------------------
-- 标记骷髅
------------------------------------------------------------------
-- 把当前目标标记为所选编号的团队标记（默认 8 = 骷髅）。
-- 团队标记需要在小队 / 团队中才能生效；没有目标或单人时在这里提示，避免“按了没反应”。
local function MarkTargetSkull()
	if not UnitExists("target") then
		Print("没有选中目标，无法标记")
		return
	end
	if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then
		Print("需在小队或团队中才能使用团队标记")
		return
	end
	SetRaidTarget("target", skullIcon)
end

local btnSkull = CreateFrame("Button", BTN_SKULL)
btnSkull:SetScript("OnClick", function(_, button)
	MarkTargetSkull()
	Debug("收到标记按键 " .. (skullKey or "(未设置)") .. "（" .. ClickText(button) .. "，编号: " .. skullIcon .. "）")
end)

------------------------------------------------------------------
-- 移动自动锁视角（W/A/S/D 方向键）
------------------------------------------------------------------
-- 思路（参考 ConsolePort 的实现）：不去重绑 W/A/S/D（那会破坏移动功能），
-- 而是用 hooksecurefunc 给游戏的“开始移动”函数挂一个后置钩子。
-- 玩家按 W/A/S/D 时，客户端会调用下列函数，钩子在原函数执行后再触发，
-- 于是我们可以在不改变移动行为的前提下，顺带把鼠标视角打开。
--
-- WoW 默认键位下，方向键对应的函数是：
--   MoveForwardStart  -> 按 W（前进）
--   MoveBackwardStart -> 按 S（后退）
--   TurnLeftStart     -> 按 A（左转）      <-- 注意：默认 A 是“转向”，不是“平移”
--   TurnRightStart    -> 按 D（右转）      <-- 默认 D 是“转向”，不是“平移”
--   StrafeLeftStart   -> 按 Q（左平移）
--   StrafeRightStart  -> 按 E（右平移）
-- （若你把 A/D 改绑成了平移，对应的仍是 Strafe 系列，所以这里一并挂钩，全覆盖。）
--
-- hooksecurefunc 保证钩子一定在原函数之后执行，且不会覆盖原函数，
-- 因此对移动本身没有任何副作用。
local MOVE_FUNCS = {
	"MoveForwardStart",
	"MoveBackwardStart",
	"TurnLeftStart",
	"TurnRightStart",
	"StrafeLeftStart",
	"StrafeRightStart",
}
for _, funcName in ipairs(MOVE_FUNCS) do
	hooksecurefunc(funcName, function()
		if not wasdAutoLock then
			return
		end
		-- 已经锁过一次：直接跳过，不再每次按键都判断视角状态。
		if wasdLocked then
			return
		end
		StartMouselook()
		SetWASDLocked(true)
		Debug("方向键移动触发自动锁视角（" .. funcName .. "）")
	end)
end

------------------------------------------------------------------
-- 鼠标右键：重置 WASD 自动锁定标记
------------------------------------------------------------------
-- 客户端默认把鼠标右键绑定为 TURNORACTION（手动转向 / 看视角），
-- 其处理函数就是 TurnOrActionStart（按下）和 TurnOrActionStop（松开）。
-- 这里给两者挂上钩子：只要玩家按 / 松右键，就清掉 wasdLocked，
-- 这样用右键手动看过视角后，下一次方向键移动仍能重新自动锁定。
-- hooksecurefunc 只做后置钩子，不会改变右键原有的转向/选中行为。
hooksecurefunc("TurnOrActionStart", function()
	SetWASDLocked(false)
end)
hooksecurefunc("TurnOrActionStop", function()
	SetWASDLocked(false)
end)

------------------------------------------------------------------
-- 按键绑定
------------------------------------------------------------------

-- 把 F11/F12 挂到两个隐藏按钮上，并写入磁盘持久化。
-- 必须调用 SaveBindings，否则绑定只存在于内存，重载界面后会丢失。
-- GetCurrentBindingSet() 返回当前生效的按键方案编号（1 或 2）。
local function ApplyBindings()
	SetBindingClick(START_KEY, BTN_START)
	SetBindingClick(STOP_KEY, BTN_STOP)
	SaveBindings(GetCurrentBindingSet())
end

-- 判断某个键当前是否仍指向本插件的按钮。
-- 用于解绑前确认“这是自己占用的键”，避免误删玩家自己的按键绑定。
local function IsOurBinding(key, btnName)
	local action = GetBindingAction(key)
	return action ~= nil and action ~= "" and string.find(action, btnName, 1, true) ~= nil
end

-- 解除单个键的绑定。SetBinding 的第二个参数传 nil 即为解绑；
-- 个别客户端只认空串，这里补一次兜底。返回是否真的做过处理。
local function UnbindKey(key, btnName)
	if not IsOurBinding(key, btnName) then
		return false
	end
	pcall(SetBinding, key, nil)
	if IsOurBinding(key, btnName) then
		pcall(SetBinding, key, "")
	end
	return true
end

-- 解除本插件占用的 F11/F12（关闭「按键映射」时调用）。
-- 只有当前绑定确实指向自己的按钮时才处理，玩家的自定义绑定不受影响。
local function ClearBindings()
	local changed = UnbindKey(START_KEY, BTN_START)
	if UnbindKey(STOP_KEY, BTN_STOP) then
		changed = true
	end
	if changed then
		SaveBindings(GetCurrentBindingSet())
	end
end

-- 统一开关「按键映射」：开启则绑定并落盘，关闭则解绑并落盘，同时写入存档。
local function SetKeyMapping(enabled)
	keyMappingEnabled = enabled
	if MySteamlikeAssistantDB then
		MySteamlikeAssistantDB.keyMappingEnabled = enabled
	end
	if enabled then
		ApplyBindings()
	else
		ClearBindings()
	end
end

------------------------------------------------------------------
-- 标记骷髅：按键绑定
------------------------------------------------------------------
-- 只有「开关开启 + 已设置按键」时才真正绑定；任一条件不满足就解绑，
-- 保证关闭状态下不占用玩家的按键。

local function ApplySkullBinding()
	if not skullEnabled or not skullKey or skullKey == "" then
		return false
	end
	SetBindingClick(skullKey, BTN_SKULL)
	SaveBindings(GetCurrentBindingSet())
	-- 返回是否真的绑上了：个别客户端不认某些键（例如反斜杠），此时绑定会静默失败。
	return IsOurBinding(skullKey, BTN_SKULL)
end

-- 解除标记骷髅的按键绑定（仅当该键确实指向本插件的骷髅按钮）。
local function ClearSkullBinding()
	if not skullKey or skullKey == "" then
		return
	end
	if UnbindKey(skullKey, BTN_SKULL) then
		SaveBindings(GetCurrentBindingSet())
	end
end

-- 设置标记骷髅的按键（由设置面板的按键录制按钮调用）。
local function SetSkullKey(key)
	-- 与鼠标视角的两个键冲突时直接拒绝，避免把视角绑定覆盖掉。
	if key == START_KEY or key == STOP_KEY then
		Print("该按键已用于鼠标视角映射（" .. START_KEY .. " / " .. STOP_KEY .. "），请换一个")
		return
	end
	-- 先解绑旧键，再绑新键，避免换键后旧键仍然生效。
	if skullKey and skullKey ~= "" and skullKey ~= key then
		ClearSkullBinding()
	end
	skullKey = key
	if MySteamlikeAssistantDB then
		MySteamlikeAssistantDB.skullKey = key
	end
	if not skullEnabled then
		Print("标记骷髅按键已设为 " .. key .. "（开关当前为关闭，开启后生效）")
	elseif ApplySkullBinding() then
		Print("标记骷髅按键已设为 " .. key)
	else
		Print("按键 " .. key .. " 未能生效（客户端可能不识别该键），请换一个")
	end
end

-- 统一开关「标记骷髅」：开启则绑定（需先设好按键），关闭则解绑，同时写入存档。
local function SetSkullEnabled(enabled)
	skullEnabled = enabled
	if MySteamlikeAssistantDB then
		MySteamlikeAssistantDB.skullEnabled = enabled
	end
	if enabled then
		if not skullKey or skullKey == "" then
			Print("请先在设置面板点击「设置按键」，按下一个键后再开启")
		elseif not ApplySkullBinding() then
			Print("按键 " .. skullKey .. " 未能生效（客户端可能不识别该键），请在设置面板重新设置")
		end
	else
		ClearSkullBinding()
	end
end

------------------------------------------------------------------
-- 状态查询（诊断用）
------------------------------------------------------------------

-- 查询某个按键当前绑定的动作。
-- 正常生效时返回类似 "CLICK MSA_Btn_F20:LeftButton"；
-- 若返回 nil 或空字符串，说明该键未被客户端接受（未生效）。
local function BindingState(key)
	local action = GetBindingAction(key)
	if action == nil or action == "" then
		return "未生效"
	end
	return action
end

-- 输出当前状态：按键映射开关 + 两个按键的绑定情况 + 当前是否在鼠标视角 + 调试开关。
local function Status()
	Print("按键映射: " .. (keyMappingEnabled and "开启" or "关闭"))
	Print(START_KEY .. " 绑定: " .. BindingState(START_KEY))
	Print(STOP_KEY .. " 绑定: " .. BindingState(STOP_KEY))
	Print("当前鼠标视角: " .. (IsMouselooking() and "开启" or "关闭"))
	Print("移动自动锁视角: " .. (wasdAutoLock and "开启" or "关闭"))
	Print("标记骷髅: " .. (skullEnabled and "开启" or "关闭")
		.. "（按键: " .. (skullKey and skullKey ~= "" and skullKey or "未设置")
		.. "，编号: " .. SKULL_ICON_NAMES[skullIcon] .. "）")
	Print("调试日志: " .. (debugEnabled and "开启" or "关闭"))
	Print("组合键提示: Ctrl " .. (ctrlHintEnabled and "开" or "关")
		.. " / Alt " .. (altHintEnabled and "开" or "关")
		.. " / Shift " .. (shiftHintEnabled and "开" or "关"))
	Print("输入 /msa help 查看全部命令")
end

------------------------------------------------------------------
-- 聊天窗口布局存档（位置 / 尺寸 / 锁定 / 字号）
------------------------------------------------------------------
-- 用途：手机端（模拟器）与电脑端的屏幕分辨率差别很大，客户端自带的
-- Chat-cache 只记住“最后一次”的聊天窗口状态，换分辨率后窗口经常跑到屏幕外
-- 或者被挡住，只能手动拖回来、重新解/锁、重新调字号。
--
-- 这里额外存一份“常用布局快照”：把当前所有聊天窗口（包括停靠在一起的标签页组合）
-- 的位置、宽高、锁定状态、字号写进插件存档；
-- 切换设备后点一下「应用布局」，或勾选「登录时自动应用」，就整体恢复。
--
-- 注意：停靠在其它聊天窗口上的子窗口，位置由主窗口控制，
-- 所以只恢复它们的字号与锁定，不动位置和尺寸。
local CHAT_WINDOW_FALLBACK_MAX = 10

-- 取第 index 个聊天窗口（ChatFrame1 ~ ChatFrame10）。
local function GetChatFrame(index)
	local name = "ChatFrame" .. index
	return _G[name]
end

-- 读取第 index 个聊天窗口当前停靠到哪个窗口（返回自己的编号或 0 表示独立）。
local function ReadChatDockIndex(index)
	if type(index) ~= "number" or type(FCF_GetChatWindowInfo) ~= "function" then
		return nil
	end
	local ok, _, _, _, _, _, _, _, _, docked = pcall(FCF_GetChatWindowInfo, index)
	if ok and type(docked) == "number" then
		return docked
	end
	return nil
end

-- 判断某个窗口是否是停靠在其它聊天窗口上的子窗口。
-- 3.3.5 的 FCF_GetChatWindowInfo 第 9 个返回值是“停靠到哪个窗口”：
-- 独立窗口返回自己的编号（或 0），停靠子窗口返回主窗口编号，用它判断最准。
-- 读不到时（旧存档 / API 差异）退回按锚点是否指向 ChatFrameX 判断。
local function IsDockedChatChild(frame, info, index)
	index = index or frame:GetID()
	local docked = ReadChatDockIndex(index)
	if docked == nil and type(info) == "table" then
		docked = info.docked
	end
	if type(docked) == "number" and type(index) == "number" then
		-- docked 为 0 或等于自己的编号，都说明它是独立窗口（不是别人的停靠子窗口）。
		return docked ~= 0 and docked ~= index
	end
	local _, relativeTo = frame:GetPoint(1)
	if not relativeTo or type(relativeTo.GetName) ~= "function" then
		return false
	end
	local relativeName = relativeTo:GetName()
	if type(relativeName) ~= "string" then
		return false
	end
	return string.find(relativeName, "ChatFrame", 1, true) ~= nil
end

-- 把窗口当前的位置 / 尺寸写进客户端的聊天缓存（WTF 下的 chat-cache.txt）。
-- 客户端只在自己拖动聊天窗口时才记录位置；插件用 SetPoint 摆好之后必须显式调一次，
-- 否则完全退出再登录，客户端仍按旧缓存把窗口摆回原来的地方。
local function PersistChatFramePosition(frame)
	if type(FCF_SavePositionAndDimensions) ~= "function" then
		return false
	end
	return (pcall(FCF_SavePositionAndDimensions, frame))
end

-- 收集当前聊天窗口布局。返回 nil 表示客户端不支持读取聊天窗口信息。
local function CaptureChatLayout()
	if type(FCF_GetChatWindowInfo) ~= "function" then
		return nil
	end
	local maxWindows = NUM_CHAT_WINDOWS or CHAT_WINDOW_FALLBACK_MAX
	local windows = {}
	local count = 0
	local lockedCount = 0
	for i = 1, maxWindows do
		local f = GetChatFrame(i)
		if f then
			-- 3.3.5：name, fontSize, r, g, b, alpha, shown, locked, docked, uninteractable
			local name, fontSize, _, _, _, _, shown, locked, docked = FCF_GetChatWindowInfo(i)
			local info = {}
			info.name = type(name) == "string" and name or (f:GetName() or tostring(i))
			info.fontSize = type(fontSize) == "number" and fontSize or nil
			-- 记下停靠关系：应用时用它区分主窗口与停靠子窗口，比看锚点可靠。
			info.docked = type(docked) == "number" and docked or nil
			-- 锁定状态：优先用 API 的返回值（布尔或 0/1 数字），取不到时读聊天框自身的 isLocked 字段。
			if type(locked) == "boolean" then
				info.locked = locked
			elseif type(locked) == "number" then
				info.locked = (locked ~= 0)
			elseif type(f.isLocked) == "boolean" then
				info.locked = f.isLocked
			elseif type(f.isLocked) == "number" then
				info.locked = (f.isLocked ~= 0)
			end
			if info.locked then
				lockedCount = lockedCount + 1
			end
			info.shown = type(shown) == "boolean" and shown or f:IsShown()
			-- 只有显示中的窗口才有有效的位置与尺寸，隐藏的窗口取不到几何信息。
			if f:IsShown() then
				local left, top = f:GetLeft(), f:GetTop()
				local width, height = f:GetWidth(), f:GetHeight()
				if left and top and width and height then
					info.left = math.floor(left)
					info.top = math.floor(top)
					info.width = math.floor(width)
					info.height = math.floor(height)
				end
			end
			windows[i] = info
			count = count + 1
		end
	end
	if count == 0 then
		return nil
	end
	return {
		windows = windows,
		count = count,
		lockedCount = lockedCount,
		savedAt = date("%m-%d %H:%M"),
	}
end

-- 把存档里的布局写回聊天窗口。silent 为 true 时不打印结果（用于登录自动应用）。
local function ApplyChatLayout(silent)
	local layout = MySteamlikeAssistantDB and MySteamlikeAssistantDB.chatLayout
	if not layout or type(layout.windows) ~= "table" then
		if not silent then
			Print("还没有保存过聊天窗口布局，请先点「保存布局」")
		end
		return false
	end

	local applied = 0
	local persisted = 0
	for i, info in pairs(layout.windows) do
		local f = GetChatFrame(tonumber(i))
		if f and type(info) == "table" then
			-- 1) 先解锁：锁定状态下部分客户端不允许改动窗口位置 / 尺寸。
			if type(FCF_SetLocked) == "function" then
				pcall(FCF_SetLocked, f, false)
			end
			f.isLocked = false

			-- 2) 字号：每个窗口单独生效（停靠在一起的窗口也可以各用各的字号）。
			-- 注意 3.3.5 的签名是 (chatFrame, editBox, size)，必须把聊天框同时传成 editBox。
			if info.fontSize and info.fontSize > 0 then
				pcall(FCF_SetChatWindowFontSize, f, f, info.fontSize)
			end

			-- 3) 位置与尺寸：只处理"不依附于其它聊天窗口"的窗口（即停靠组合的主窗口）。
			if not IsDockedChatChild(f, info, tonumber(i)) and info.left and info.top then
				local parentWidth = UIParent:GetWidth() or 0
				local parentHeight = UIParent:GetHeight() or 0
				-- 尺寸不超过当前屏幕，换到更小的分辨率时窗口也不会被裁掉。
				local width = math.min(math.max(50, info.width or (f:GetWidth() or 0)), math.max(50, parentWidth))
				local height = math.min(math.max(20, info.height or (f:GetHeight() or 0)), math.max(20, parentHeight))
				f:SetWidth(width)
				f:SetHeight(height)

				-- 分辨率换小以后，存档坐标可能跑到屏幕外，这里夹回可见区域。
				local left = math.min(math.max(0, info.left), math.max(0, parentWidth - width))
				local top = math.min(math.max(height, info.top), math.max(height, parentHeight))
				f:ClearAllPoints()
				f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", math.floor(left), math.floor(top - height))

				-- 位置摆好后写进客户端聊天缓存：不写的话，完全退出再登录时
				-- 客户端会按旧缓存把窗口摆回原处，等于这次应用白做。
				if PersistChatFramePosition(f) then
					persisted = persisted + 1
				end
			end

			-- 4) 位置摆好后再恢复存档里的锁定状态。
			if info.locked ~= nil then
				if type(FCF_SetLocked) == "function" then
					pcall(FCF_SetLocked, f, info.locked)
				end
				-- 少数客户端只认聊天框自身的字段，这里再补齐一次，确保真的锁上 / 解锁。
				f.isLocked = info.locked
			end

			applied = applied + 1
		end
	end

	if applied == 0 then
		if not silent then
			Print("没有找到可恢复的聊天窗口")
		end
		return false
	end
	if not silent then
		Print("已应用聊天窗口布局（" .. applied .. " 个窗口）")
		if type(FCF_SavePositionAndDimensions) ~= "function" then
			Print("当前客户端不支持写入聊天缓存，位置可能无法在退出后保持；建议在设置里勾选「登录时自动应用」")
		elseif persisted > 0 then
			Debug("已写入客户端聊天缓存（" .. persisted .. " 个窗口），退出后位置会保持")
		end
	end
	return true
end

-- 保存当前聊天窗口布局到插件存档。
local function SaveChatLayout()
	local layout = CaptureChatLayout()
	if not layout then
		Print("无法读取聊天窗口信息，当前客户端可能不支持（需要 FCF_GetChatWindowInfo）")
		return false
	end
	if MySteamlikeAssistantDB then
		MySteamlikeAssistantDB.chatLayout = layout
	end
	Print("聊天窗口布局已保存（" .. layout.count .. " 个窗口，" .. (layout.lockedCount or 0) .. " 个锁定，" .. layout.savedAt .. "）")
	return true
end

-- 开/关「登录时自动应用聊天窗口布局」。
local function SetChatAutoApply(enabled)
	chatAutoApply = enabled
	if MySteamlikeAssistantDB then
		MySteamlikeAssistantDB.chatAutoApply = enabled
	end
end

-- 输出聊天窗口布局的存档状态（/msa chat）。
local function PrintChatLayoutStatus()
	local layout = MySteamlikeAssistantDB and MySteamlikeAssistantDB.chatLayout
	if layout and type(layout.windows) == "table" then
		Print("聊天窗口布局: 已保存（" .. (layout.savedAt or "?") .. "，" .. (layout.count or 0) .. " 个窗口，"
			.. (layout.lockedCount or 0) .. " 个锁定）")
	else
		Print("聊天窗口布局: 尚未保存（用 /msa chat save 保存当前布局）")
	end
	Print("登录时自动应用: " .. (chatAutoApply and "开启" or "关闭"))
end

------------------------------------------------------------------
-- 组合键提示（按住 Ctrl / Alt / Shift 时标出绑定了对应组合的动作条按钮）
------------------------------------------------------------------
-- 用途：有些按键是 Ctrl+1 ~ Ctrl+8、Alt+1 ~ Alt+8 这类组合键，平时动作条上
-- 只显示 1~8，记不住某个组合对应哪一格。按住修饰键时在对应按钮上浮出
-- 「Ctrl+N」角标并描一圈亮边，松开即消失；只读展示，不改动任何按键绑定。
-- 同时按住多个修饰键时按真实组合查询（例如 Ctrl+Shift+1 -> "CTRL-SHIFT-1"）。
-- 兼容原版动作条与 Bartender4（BT4 的按钮是 BT4ButtonN，绑定动作形如 CLICK ...）。
--
-- 参与提示的数字键（+1 ~ +9 与 +0）。
local CTRL_HINT_KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }

-- 原生动作条的绑定命令前缀 → 按钮名前缀（3.3.5 的绑定名是全大写）。
local CTRL_HINT_BUTTON_PREFIX = {
	ACTIONBUTTON = "ActionButton",
	BONUSACTIONBUTTON = "BonusActionButton",
	SHAPESHIFTBUTTON = "ShapeshiftButton",
	PETACTIONBUTTON = "PetActionButton",
	MULTIACTIONBAR1BUTTON = "MultiBarBottomLeftButton",
	MULTIACTIONBAR2BUTTON = "MultiBarBottomRightButton",
	MULTIACTIONBAR3BUTTON = "MultiBarRightButton",
	MULTIACTIONBAR4BUTTON = "MultiBarLeftButton",
}

local ctrlHintOverlays = {}

-- 把绑定动作串解析成屏幕上的按钮对象；解析不出返回 nil。
local function ResolveCtrlHintButton(action)
	if type(action) ~= "string" or action == "" then
		return nil
	end
	-- Bartender4 等插件用 "CLICK BT4Button17:LeftButton" 的形式绑定自己的按钮
	if string.find(string.upper(action), "CLICK ", 1, true) == 1 then
		local buttonName = string.match(action, "^[%a]+%s+([^:]+)")
		local button = buttonName and _G[buttonName]
		if button then
			return button
		end
		return nil
	end
	local upper = string.upper(action)
	for bindingPrefix, framePrefix in pairs(CTRL_HINT_BUTTON_PREFIX) do
		local index = string.match(upper, "^" .. bindingPrefix .. "(%d+)$")
		if index then
			-- 装了 Bartender4 后，ACTIONBUTTON1~12 会被它重定向到 BT4Button1~12，
			-- 屏幕上真正显示的是 BT4 的按钮，所以优先取那个。
			if bindingPrefix == "ACTIONBUTTON" and _G["BT4Button" .. index] then
				return _G["BT4Button" .. index]
			end
			return _G[framePrefix .. index]
		end
	end
	return nil
end

-- 为某个按钮创建（或复用）角标 + 描边的提示层。
local function GetCtrlHintOverlay(button)
	local overlay = ctrlHintOverlays[button]
	if overlay then
		return overlay
	end
	overlay = CreateFrame("Frame", nil, UIParent)
	overlay:SetFrameStrata("DIALOG")
	overlay:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
	overlay:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
	overlay:SetBackdrop({
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 10,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	overlay:SetBackdropBorderColor(1, 0.82, 0, 1)
	overlay:Hide()

	-- 底部角标：半透明黑底 +「Ctrl+N」金字，宽度按文字自适应
	-- （组合键如 Ctrl+Shift+1 比按钮还宽，会稍微溢出按钮，但不影响阅读）。
	local badge = CreateFrame("Frame", nil, overlay)
	badge:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 1)
	badge:SetHeight(13)
	badge:SetWidth(30)
	local bg = badge:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(badge)
	bg:SetTexture(0, 0, 0, 0.65)
	local label = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER", badge, "CENTER", 0, 0)
	label:SetTextColor(1, 0.85, 0.2)
	overlay.label = label
	overlay.badge = badge

	ctrlHintOverlays[button] = overlay
	return overlay
end

local function HideCtrlHints()
	for _, overlay in pairs(ctrlHintOverlays) do
		overlay.ctrlHit = nil
		if overlay:IsShown() then
			overlay:Hide()
		end
	end
end

-- ticker 记住的上一次生效前缀（nil 表示当前没有提示）。
-- 提前声明，供 SetHintEnabled 重置，让开关切换能立刻生效。
local ctrlHintActivePrefix = nil

-- 轮询间隔（秒）。要跟手就得短：0.03 秒≈每帧一次，按下/松开修饰键后提示基本立刻响应。
-- 空闲时每次轮询只调 3 个按键状态函数，开销可以忽略。
local HINT_POLL_INTERVAL = 0.03

-- 按钮暂时看不见时的宽限（秒）：切页 / 施放瞬间按钮会短暂隐藏，
-- 这时先留着角标，超过这个时间才收，避免提示闪一下。
local HINT_HIDE_DELAY = 0.15

-- 按当前修饰键组合（prefix 形如 "CTRL-"、"ALT-SHIFT-"）刷新角标内容并显示。
local function ShowCtrlHints(prefix, display)
	for _, overlay in pairs(ctrlHintOverlays) do
		overlay.ctrlHit = nil
		overlay:Hide()
	end
	for i = 1, #CTRL_HINT_KEYS do
		local number = CTRL_HINT_KEYS[i]
		local button = ResolveCtrlHintButton(GetBindingAction(prefix .. number))
		local action = button and button.action
		-- 空格子不提示：按了组合键也没有技能可放。
		if button and (action == nil or (type(action) == "number" and HasAction(action))) then
			local overlay = GetCtrlHintOverlay(button)
			overlay.ctrlHit = true
			overlay.label:SetText(display .. "+" .. number)
			overlay.badge:SetWidth(overlay.label:GetStringWidth() + 8)
			overlay:SetAlpha(1)
			if button:IsVisible() then
				overlay:Show()
			end
		end
	end
end

-- 当前按住的（且对应开关已启用的）修饰键 → 绑定前缀与显示名。
-- 返回 nil 表示没有需要提示的修饰键；同时按住多个时按真实组合查询。
local function GetActiveHintPrefix()
	local prefix = ""
	local display = nil
	if ctrlHintEnabled and IsControlKeyDown() then
		prefix = prefix .. "CTRL-"
		display = "Ctrl"
	end
	if shiftHintEnabled and IsShiftKeyDown() then
		prefix = prefix .. "SHIFT-"
		display = display and (display .. "+Shift") or "Shift"
	end
	if altHintEnabled and IsAltKeyDown() then
		prefix = prefix .. "ALT-"
		display = display and (display .. "+Alt") or "Alt"
	end
	if prefix == "" then
		return nil, nil
	end
	return prefix, display
end

-- kind: "ctrl" / "alt" / "shift"
local function SetHintEnabled(kind, enabled)
	enabled = enabled and true or false
	if kind == "ctrl" then
		ctrlHintEnabled = enabled
	elseif kind == "alt" then
		altHintEnabled = enabled
	else
		shiftHintEnabled = enabled
	end
	if MySteamlikeAssistantDB then
		MySteamlikeAssistantDB[kind .. "HintEnabled"] = enabled
	end
	-- 让轮询立刻按新开关重算
	ctrlHintActivePrefix = nil
	HideCtrlHints()
end

-- 3.3.5 没有修饰键事件，用一个 OnUpdate 轮询修饰键状态（间隔见 HINT_POLL_INTERVAL）。
-- 只在按下的组合变化时重建提示；按住期间同步可见性，切页 / 切姿态时提示跟着按钮走。
-- 收起提示带小宽限，避免按住修饰键连按数字键时提示闪断。
local ctrlHintTicker = CreateFrame("Frame", nil, UIParent)
local ctrlHintCheckElapsed = 0
ctrlHintTicker:SetScript("OnUpdate", function(_, elapsed)
	ctrlHintCheckElapsed = ctrlHintCheckElapsed + elapsed
	if ctrlHintCheckElapsed < HINT_POLL_INTERVAL then
		return
	end
	local step = ctrlHintCheckElapsed
	ctrlHintCheckElapsed = 0

	local prefix, display = GetActiveHintPrefix()
	if prefix ~= ctrlHintActivePrefix then
		ctrlHintActivePrefix = prefix
		if prefix then
			ShowCtrlHints(prefix, display) -- 修饰键按下：立刻显示
		else
			HideCtrlHints() -- 修饰键松开：立刻收起
		end
		return
	end

	if not prefix then
		return
	end

	-- 按住修饰键期间：按钮可见就显示提示；暂时看不见（切页、施放瞬间的刷新）先留着，
	-- 超过宽限时间才收，这样按数字键放技能时提示不会消失或闪一下。
	for button, overlay in pairs(ctrlHintOverlays) do
		if overlay.ctrlHit then
			if button:IsVisible() then
				overlay.hiddenFor = nil
				if not overlay:IsShown() then
					overlay:SetAlpha(1)
					overlay:Show()
				end
			else
				overlay.hiddenFor = (overlay.hiddenFor or 0) + step
				if overlay.hiddenFor >= HINT_HIDE_DELAY and overlay:IsShown() then
					overlay:Hide()
				end
			end
		end
	end
end)
ctrlHintTicker:Show()

------------------------------------------------------------------
-- 设置面板（Esc → 界面 → MySteamlikeAssistant）
------------------------------------------------------------------
-- 3.3.5a 没有独立的“插件”标签页，插件设置是用 InterfaceOptions_AddCategory
-- 挂到“界面”设置里的一个分类，与“游戏”“声音”等并列。
-- 勾选框使用 InterfaceOptionsCheckButtonTemplate，外观与暴雪原生设置一致。
local optionsPanel = CreateFrame("Frame", "MSA_OptionsPanel", UIParent)
optionsPanel.name = "MySteamlikeAssistant"
optionsPanel:Hide()

local optionsTitle = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
optionsTitle:SetPoint("TOPLEFT", 16, -16)
optionsTitle:SetText("MySteamlikeAssistant")

local optionsDesc = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
optionsDesc:SetPoint("TOPLEFT", optionsTitle, "BOTTOMLEFT", 0, -8)
optionsDesc:SetPoint("RIGHT", optionsPanel, "RIGHT", -16, 0)
optionsDesc:SetJustifyH("LEFT")
optionsDesc:SetText("接收 F11 / F12 控制鼠标视角。以下设置自动保存，重载后保留。")

-- 给勾选框挂上暴雪风格的鼠标提示。
local function SetOptionTooltip(btn, text)
	btn.tooltipText = text
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

-- 前置声明：面板底部的绑定状态文本由后面的 refreshBindText() 负责刷新，
-- 这里先声明，便于上方勾选框的点击回调直接调用。
local refreshBindText

local cbMapping = CreateFrame("CheckButton", "MSA_CB_Mapping", optionsPanel, "InterfaceOptionsCheckButtonTemplate")
cbMapping:SetPoint("TOPLEFT", optionsDesc, "BOTTOMLEFT", 0, -16)
_G["MSA_CB_MappingText"]:SetText("按键映射（F11 开 / F12 关）")
SetOptionTooltip(cbMapping, "开启后把 F11 绑定为开启鼠标视角、F12 绑定为关闭；关闭时不占用这两个键（已绑定的会自动解除）。/msa start 与 /msa stop 命令始终可用。")
cbMapping:SetScript("OnClick", function(self)
	SetKeyMapping(self:GetChecked() and true or false)
	Print("按键映射已" .. (keyMappingEnabled and "开启" or "关闭"))
	refreshBindText()
end)

-- 标记骷髅：开关 + 按键录制。
-- 3.3.5a 没有提供「运行时往按键设置里加条目」的接口，所以按键由自己录：
-- 点击按钮后用 EnableKeyboard 临时接管键盘，捕获玩家按下的第一个键。
local capturingKey = false

local keyButton = CreateFrame("Button", "MSA_Btn_SetSkullKey", optionsPanel, "UIPanelButtonTemplate")
keyButton:SetSize(160, 22)

local function RefreshKeyText()
	if capturingKey then
		keyButton:SetText("请按下一个键（Esc 取消）")
	else
		keyButton:SetText("设置按键：" .. (skullKey and skullKey ~= "" and skullKey or "未设置"))
	end
end
RefreshKeyText()

local captureFrame = CreateFrame("Frame", "MSA_KeyCapture", UIParent)
captureFrame:SetSize(1, 1)

local function StopKeyCapture(cancelled)
	if not capturingKey then
		return
	end
	capturingKey = false
	captureFrame:EnableKeyboard(false)
	captureFrame:Hide()
	RefreshKeyText()
	if cancelled then
		Print("已取消按键设置")
	end
end

local function StartKeyCapture()
	if capturingKey then
		return
	end
	capturingKey = true
	captureFrame:EnableKeyboard(true)
	captureFrame:Show()
	RefreshKeyText()
	Print("请按下一个要绑定的按键（Esc 或再次点击按钮取消）")
end

captureFrame:SetScript("OnKeyDown", function(_, key)
	if not capturingKey then
		return
	end
	if key == "ESCAPE" then
		StopKeyCapture(true)
		return
	end
	-- 单独按修饰键不算一个完整按键，继续等待主键。
	if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL"
		or key == "RCTRL" or key == "LALT" or key == "RALT" then
		return
	end
	-- OnKeyDown 只给主键，修饰键状态另外查询，拼成 "SHIFT-F10" 这样的绑定键名。
	local combo = key
	if IsShiftKeyDown() then combo = "SHIFT-" .. combo end
	if IsControlKeyDown() then combo = "CTRL-" .. combo end
	if IsAltKeyDown() then combo = "ALT-" .. combo end
	StopKeyCapture(false)
	SetSkullKey(combo)
end)

keyButton:SetScript("OnClick", function()
	if capturingKey then
		StopKeyCapture(true)
	else
		StartKeyCapture()
	end
end)

local cbSkull = CreateFrame("CheckButton", "MSA_CB_Skull", optionsPanel, "InterfaceOptionsCheckButtonTemplate")
cbSkull:SetPoint("TOPLEFT", cbMapping, "BOTTOMLEFT", 0, -4)
_G["MSA_CB_SkullText"]:SetText("标记骷髅")
SetOptionTooltip(cbSkull, "开启后，按下面设置的按键把当前目标标记为骷髅；关闭时不占用该按键。需在小队/团队中才能生效。")
cbSkull:SetScript("OnClick", function(self)
	SetSkullEnabled(self:GetChecked() and true or false)
	Print("标记骷髅已" .. (skullEnabled and "开启" or "关闭"))
	RefreshKeyText()
end)

-- 按键按钮缩进到勾选框文字下方，与暴雪设置面板的层次一致。
keyButton:SetPoint("TOPLEFT", cbSkull, "BOTTOMLEFT", 26, -4)

-- 标记编号下拉框：1~8 号，每项都带形状说明，默认 8 号（骷髅）。
local iconLabel = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
iconLabel:SetText("标记编号")
iconLabel:SetPoint("TOPLEFT", keyButton, "BOTTOMLEFT", 0, -8)

local iconDropdown = CreateFrame("Frame", "MSA_SkullIconDropdown", optionsPanel, "UIDropDownMenuTemplate")
iconDropdown:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", -16, 0)
UIDropDownMenu_SetWidth(iconDropdown, 180)
UIDropDownMenu_SetText(iconDropdown, SKULL_ICON_NAMES[skullIcon])
UIDropDownMenu_Initialize(iconDropdown, function(_, level)
	for i = 1, #SKULL_ICON_NAMES do
		local info = UIDropDownMenu_CreateInfo()
		info.text = SKULL_ICON_NAMES[i]
		info.checked = (skullIcon == i)
		info.func = function()
			skullIcon = i
			if MySteamlikeAssistantDB then
				MySteamlikeAssistantDB.skullIcon = i
			end
			UIDropDownMenu_SetText(iconDropdown, SKULL_ICON_NAMES[i])
			Print("标记编号已设为 " .. SKULL_ICON_NAMES[i])
			CloseDropDownMenus()
		end
		UIDropDownMenu_AddButton(info, level)
	end
end)

local cbWASD = CreateFrame("CheckButton", "MSA_CB_WASD", optionsPanel, "InterfaceOptionsCheckButtonTemplate")
cbWASD:SetPoint("TOPLEFT", iconDropdown, "BOTTOMLEFT", -10, -4)
_G["MSA_CB_WASDText"]:SetText("移动自动锁视角")
SetOptionTooltip(cbWASD, "开启后，按 W/A/S/D 开始移动时若未锁定视角则自动锁定；按 F12 或鼠标右键会重置，下次移动可再次锁定。")
cbWASD:SetScript("OnClick", function(self)
	wasdAutoLock = self:GetChecked() and true or false
	if MySteamlikeAssistantDB then MySteamlikeAssistantDB.wasdAutoLock = wasdAutoLock end
	Print("移动自动锁视角已" .. (wasdAutoLock and "开启" or "关闭"))
end)

local cbDebug = CreateFrame("CheckButton", "MSA_CB_Debug", optionsPanel, "InterfaceOptionsCheckButtonTemplate")
cbDebug:SetPoint("TOPLEFT", cbWASD, "BOTTOMLEFT", 0, -4)
_G["MSA_CB_DebugText"]:SetText("调试日志")
SetOptionTooltip(cbDebug, "开启后，每次收到 F11/F12 或方向键触发时都会在聊天框打印一行，便于确认按键是否送达。")
cbDebug:SetScript("OnClick", function(self)
	debugEnabled = self:GetChecked() and true or false
	if MySteamlikeAssistantDB then MySteamlikeAssistantDB.debugEnabled = debugEnabled end
	Print("调试日志已" .. (debugEnabled and "开启" or "关闭"))
end)

-- 组合键提示的三个独立开关：横排一行，省纵向空间，也不会和下面的文字重叠。
-- 勾选框保持模板原样（不要放大框体，模板的勾选纹理会被拉成长方形），
-- 鼠标提示改用暴雪设置面板的默认锚点（屏幕右下），不会压在勾选框或旁边的文字上。
local function CreateHintCheckButton(name, labelText, tooltip, kind)
	local cb = CreateFrame("CheckButton", name, optionsPanel, "InterfaceOptionsCheckButtonTemplate")
	_G[name .. "Text"]:SetText(labelText)
	cb.tooltipText = tooltip
	cb:SetScript("OnEnter", function(self)
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
		GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	cb:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	cb:SetScript("OnClick", function(self)
		SetHintEnabled(kind, self:GetChecked())
		Print("组合键提示（" .. labelText .. "）已" .. (self:GetChecked() and "开启" or "关闭"))
	end)
	return cb
end

-- 分类说明：与三个勾选框同一行（写在左侧），不额外占纵向空间。
-- 行首留出「说明文字宽度 + 10」的缩进，三个勾选框从那里开始排。
local hintTitle = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
hintTitle:SetText("组合键提示：")
local hintIndent = hintTitle:GetStringWidth() + 10

local cbHintCtrl = CreateHintCheckButton("MSA_CB_HintCtrl", "Ctrl",
	"按住 Ctrl 时，在绑定了 Ctrl+1 ~ Ctrl+0 的动作按钮上浮出角标并描边。只读展示，不改动按键绑定。", "ctrl")
cbHintCtrl:SetPoint("TOPLEFT", cbDebug, "BOTTOMLEFT", hintIndent, -4)
hintTitle:SetPoint("LEFT", cbHintCtrl, "LEFT", -hintIndent, 0)

-- 三个勾选框按各自文字的实际宽度依次排开，互不重叠。
local cbHintAlt = CreateHintCheckButton("MSA_CB_HintAlt", "Alt",
	"按住 Alt 时，在绑定了 Alt+1 ~ Alt+0 的动作按钮上浮出角标并描边。只读展示，不改动按键绑定。", "alt")
cbHintAlt:SetPoint("LEFT", _G["MSA_CB_HintCtrlText"], "RIGHT", 18, 0)

local cbHintShift = CreateHintCheckButton("MSA_CB_HintShift", "Shift",
	"按住 Shift 时，在绑定了 Shift+1 ~ Shift+0 的动作按钮上浮出角标并描边。只读展示，不改动按键绑定。", "shift")
cbHintShift:SetPoint("LEFT", _G["MSA_CB_HintAltText"], "RIGHT", 18, 0)

-- 只读展示：两个按键当前的绑定状态。
-- 只显示“已生效/未生效”，不显示底层动作串（如 CLICK ...:LeftButton），
-- 避免文字过长顶出面板边框；同时加右锚点，万一超长也能在面板内换行。
-- 横向用 -hintIndent 抵消缩进，让状态行与上方的开关左对齐。
local bindText = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
bindText:SetPoint("TOPLEFT", cbHintCtrl, "BOTTOMLEFT", -hintIndent, -6)
bindText:SetPoint("RIGHT", optionsPanel, "RIGHT", -16, 0)
bindText:SetJustifyH("LEFT")

-- 刷新底部只读状态行：映射关闭时提示未占用按键，开启时显示两个键是否生效。
refreshBindText = function()
	if not keyMappingEnabled then
		bindText:SetText("按键映射已关闭：不占用 " .. START_KEY .. " / " .. STOP_KEY .. "，可勾选上方开关启用。")
		return
	end
	local s1 = BindingState(START_KEY)
	local s2 = BindingState(STOP_KEY)
	if s1 ~= "未生效" then
		s1 = "已生效"
	end
	if s2 ~= "未生效" then
		s2 = "已生效"
	end
	bindText:SetText(START_KEY .. " 绑定: " .. s1 .. "    " .. STOP_KEY .. " 绑定: " .. s2)
end

-- 只读的命令速查，省得玩家再打 /msa help；内容与 ShowHelp() 保持一致。
local cmdTitle = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
cmdTitle:SetPoint("TOPLEFT", bindText, "BOTTOMLEFT", 0, -8)
cmdTitle:SetText("斜杠命令（/msa 或 /bridge 均可）")

local cmdText = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
cmdText:SetPoint("TOPLEFT", cmdTitle, "BOTTOMLEFT", 0, -2)
cmdText:SetPoint("RIGHT", optionsPanel, "RIGHT", -16, 0)
cmdText:SetJustifyH("LEFT")
cmdText:SetText(
	"/msa - 查看状态            /msa help - 显示本帮助\n"
	.. "/msa bind - 开/关「按键映射」（" .. START_KEY .. " 开 / " .. STOP_KEY .. " 关）\n"
	.. "/msa skull - 标记骷髅开关  /msa wasd - 移动自动锁视角\n"
	.. "/msa start / stop - 手动开启 / 关闭鼠标视角\n"
	.. "/msa debug / diag - 调试日志 / 临时诊断\n"
	.. "/msa ctrl|alt|shift - 开/关对应修饰键的组合提示\n"
	.. "/msa rebind - 重新挂载并持久化绑定\n"
	.. "/msa chat - 聊天布局存档：save 保存 / load 应用 / auto 自动"
)

------------------------------------------------------------------
-- 设置面板右侧：聊天窗口布局
------------------------------------------------------------------
-- 放在面板右列，避免左侧已有的选项被往下挤、超出面板高度。
-- 控件沿用暴雪原生模板（UIPanelButtonTemplate / InterfaceOptionsCheckButtonTemplate）。
-- 前置声明：右列布局存档的只读说明由后面的 refreshChatLayoutText() 刷新，
-- 先声明便于上方按钮的点击回调直接调用。
local refreshChatLayoutText

local chatPanelTitle = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
chatPanelTitle:SetText("聊天窗口布局")

local chatSaveButton = CreateFrame("Button", "MSA_Btn_ChatSave", optionsPanel, "UIPanelButtonTemplate")
chatSaveButton:SetSize(80, 22)
chatSaveButton:SetText("保存布局")
SetOptionTooltip(chatSaveButton, "把当前聊天窗口（含停靠的标签页组合）的位置、尺寸、锁定状态与字号存入插件存档。")
chatSaveButton:SetScript("OnClick", function()
	SaveChatLayout()
	refreshChatLayoutText()
end)

local chatLoadButton = CreateFrame("Button", "MSA_Btn_ChatLoad", optionsPanel, "UIPanelButtonTemplate")
chatLoadButton:SetSize(80, 22)
chatLoadButton:SetText("应用布局")
SetOptionTooltip(chatLoadButton, "把已保存的聊天窗口布局写回聊天框；分辨率变小后会自动夹回屏幕可见区域。")
chatLoadButton:SetScript("OnClick", function()
	ApplyChatLayout()
	refreshChatLayoutText()
end)

local cbChatAuto = CreateFrame("CheckButton", "MSA_CB_ChatAuto", optionsPanel, "InterfaceOptionsCheckButtonTemplate")
_G["MSA_CB_ChatAutoText"]:SetText("登录时自动应用")
SetOptionTooltip(cbChatAuto, "开启后，每次登录 / 重载界面都会自动套用已保存的聊天窗口布局，切换手机与电脑时不用手动恢复。")
cbChatAuto:SetScript("OnClick", function(self)
	SetChatAutoApply(self:GetChecked() and true or false)
	Print("登录时自动应用聊天布局已" .. (chatAutoApply and "开启" or "关闭"))
end)

local chatStatus = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
chatStatus:SetJustifyH("LEFT")

-- 右列排版：标题与左列第一个开关对齐，整列右边缘贴住面板右边。
-- 面板每次显示时才拿得到真实宽度与行位置，所以在 OnShow 里调用。
local function ReflowChatColumn()
	local panelTop, rowTop = optionsPanel:GetTop(), cbMapping:GetTop()
	local topOffset = -48
	if panelTop and rowTop then
		topOffset = rowTop - panelTop
	end

	chatPanelTitle:ClearAllPoints()
	chatPanelTitle:SetPoint("TOPRIGHT", optionsPanel, "TOPRIGHT", -16, topOffset)

	chatLoadButton:ClearAllPoints()
	chatLoadButton:SetPoint("TOPRIGHT", chatPanelTitle, "BOTTOMRIGHT", 0, -6)

	chatSaveButton:ClearAllPoints()
	chatSaveButton:SetPoint("TOPRIGHT", chatLoadButton, "TOPLEFT", -4, 0)

	cbChatAuto:ClearAllPoints()
	cbChatAuto:SetPoint("TOPLEFT", chatSaveButton, "BOTTOMLEFT", 0, -6)

	chatStatus:ClearAllPoints()
	chatStatus:SetPoint("TOPLEFT", chatSaveButton, "BOTTOMLEFT", 0, -44)
	chatStatus:SetPoint("RIGHT", optionsPanel, "RIGHT", -16, 0)
end

-- 刷新右列只读说明：显示上次保存时间、窗口数量与锁定数量。
refreshChatLayoutText = function()
	local layout = MySteamlikeAssistantDB and MySteamlikeAssistantDB.chatLayout
	if layout and type(layout.windows) == "table" then
		chatStatus:SetText("已保存 " .. (layout.savedAt or "?") .. "\n"
			.. (layout.count or 0) .. " 个窗口，" .. (layout.lockedCount or 0) .. " 个锁定")
	else
		chatStatus:SetText("尚未保存布局，点「保存布局」记录当前状态")
	end
end
refreshChatLayoutText()
ReflowChatColumn()

-- 面板显示时同步控件状态与绑定信息（可能在别处用 /msa 命令改过）。
optionsPanel:SetScript("OnShow", function()
	cbMapping:SetChecked(keyMappingEnabled)
	cbSkull:SetChecked(skullEnabled)
	cbWASD:SetChecked(wasdAutoLock)
	cbDebug:SetChecked(debugEnabled)
	cbHintCtrl:SetChecked(ctrlHintEnabled)
	cbHintAlt:SetChecked(altHintEnabled)
	cbHintShift:SetChecked(shiftHintEnabled)
	cbChatAuto:SetChecked(chatAutoApply)
	RefreshKeyText()
	UIDropDownMenu_SetText(iconDropdown, SKULL_ICON_NAMES[skullIcon])
	refreshBindText()
	refreshChatLayoutText()
	ReflowChatColumn()
	-- 刚显示时面板宽度与文字换行可能还没最终确定，下一帧再排一次，
	-- 保证右列不会压到描述文字、也不会跑到边框外。
	optionsPanel:SetScript("OnUpdate", function(self)
		self:SetScript("OnUpdate", nil)
		ReflowChatColumn()
	end)
end)

-- 面板被关闭时若还在等按键，及时释放键盘，避免键盘一直被插件占用。
optionsPanel:SetScript("OnHide", function()
	StopKeyCapture(false)
end)

InterfaceOptions_AddCategory(optionsPanel)

-- 输出本插件支持的全部斜杠命令。
local function ShowHelp()
	Print("可用命令：")
	Print("  /msa            查看当前状态")
	Print("  /msa start      手动开启鼠标视角（用于验证 API 是否可用）")
	Print("  /msa stop       手动关闭鼠标视角")
	Print("  /msa bind       开/关「按键映射」（F11/F12 → 鼠标视角，默认关闭）")
	Print("  /msa rebind     重新挂载并持久化绑定（同时会开启按键映射）")
	Print("  /msa skull      开/关「标记骷髅」（默认关闭，按键在设置面板里录制）")
	Print("  /msa wasd       开/关「移动自动锁视角」（默认关闭）")
	Print("  /msa debug      开/关调试日志")
	Print("  /msa ctrl|alt|shift  开/关对应修饰键的组合提示（按住该键显示 +数字 角标）")
	Print("  /msa diag       开/关临时诊断（打印客户端内部的鼠标状态，排查输入问题用）")
	Print("  /msa chat       查看聊天窗口布局存档状态")
	Print("  /msa chat save  保存当前聊天窗口布局（位置 / 尺寸 / 锁定 / 字号）")
	Print("  /msa chat load  应用已保存的聊天窗口布局")
	Print("  /msa chat auto  开/关「登录时自动应用聊天窗口布局」")
	Print("  /msa help       显示本帮助")
	Print("  /bridge         与 /msa 完全等价的别名")
	Print("提示：以上设置也可在 Esc → 界面 → MySteamlikeAssistant 中调整")
end

------------------------------------------------------------------
-- 斜杠命令注册
------------------------------------------------------------------
--   /msa           查看状态
--   /msa start     手动开启鼠标视角（用于验证 API 是否可用）
--   /msa stop      手动关闭鼠标视角
--   /msa bind      开/关「按键映射」（F11/F12 是否绑定到鼠标视角）
--   /msa rebind    重新挂载并持久化绑定（同时开启按键映射）
--   /msa skull     开/关「标记骷髅」（当前目标标记为骷髅）
--   /msa wasd      开/关「移动自动锁视角」（W/A/S/D 移动时自动开视角）
--   /msa debug     开/关调试日志（收到开始/停止键时在聊天框打印）
--   /msa help      显示命令帮助
-- /bridge 是等价的别名。
SLASH_MYSTEAMLIKEASSISTANT1 = "/msa"
SLASH_MYSTEAMLIKEASSISTANT2 = "/bridge"
SlashCmdList["MYSTEAMLIKEASSISTANT"] = function(msg)
	msg = string.lower(msg or "")
	if msg == "help" then
		ShowHelp()
	elseif msg == "start" then
		StartMouselook()
	elseif msg == "stop" then
		StopMouselook()
	elseif msg == "rebind" then
		SetKeyMapping(true)
		Status()
	elseif msg == "bind" then
		SetKeyMapping(not keyMappingEnabled)
		Print("按键映射已" .. (keyMappingEnabled and "开启" or "关闭"))
	elseif msg == "skull" then
		SetSkullEnabled(not skullEnabled)
		Print("标记骷髅已" .. (skullEnabled and "开启" or "关闭"))
	elseif msg == "wasd" then
		wasdAutoLock = not wasdAutoLock
		if MySteamlikeAssistantDB then MySteamlikeAssistantDB.wasdAutoLock = wasdAutoLock end
		Print("移动自动锁视角已" .. (wasdAutoLock and "开启" or "关闭"))
	elseif msg == "debug" then
		debugEnabled = not debugEnabled
		if MySteamlikeAssistantDB then MySteamlikeAssistantDB.debugEnabled = debugEnabled end
		Print("调试日志已" .. (debugEnabled and "开启" or "关闭"))
	elseif msg == "ctrl" or msg == "alt" or msg == "shift" then
		local enabled = (msg == "ctrl" and ctrlHintEnabled)
			or (msg == "alt" and altHintEnabled)
			or (msg == "shift" and shiftHintEnabled)
		SetHintEnabled(msg, not enabled)
		Print("组合键提示（" .. msg .. "）已" .. (not enabled and "开启" or "关闭"))
	elseif msg == "diag" then
		ToggleDiag()
	elseif msg == "chat" then
		PrintChatLayoutStatus()
	elseif msg == "chat save" then
		if SaveChatLayout() then
			refreshChatLayoutText()
		end
	elseif msg == "chat load" then
		ApplyChatLayout()
		refreshChatLayoutText()
	elseif msg == "chat auto" then
		SetChatAutoApply(not chatAutoApply)
		Print("登录时自动应用聊天布局已" .. (chatAutoApply and "开启" or "关闭"))
		refreshChatLayoutText()
	else
		Status()
	end
end

------------------------------------------------------------------
-- 事件：加载存档 + 登录后挂钩
------------------------------------------------------------------
-- ADDON_LOADED 时把存档读入内存：首次运行或字段缺失时补默认值。
-- 每次插件加载（登录 / 重载界面）只自动应用一次聊天布局，
-- 用这个标记避免进出副本触发 PLAYER_ENTERING_WORLD 时反复覆盖玩家的手动调整。
local chatLayoutAppliedThisLogin = false

-- 自动应用不能紧跟着 PLAYER_ENTERING_WORLD 立刻执行：客户端在这之后还会按
-- chat-cache.txt 把聊天窗口再摆一次，立刻应用会被它覆盖（表现就是“勾了自动应用却没变化”）。
-- 3.3.5 没有 C_Timer，这里用一个只触发一次的 OnUpdate 计时器，等客户端摆完再套用。
local chatApplyTimer = CreateFrame("Frame", nil, UIParent)
local chatApplyRemaining = 0
chatApplyTimer:Hide()
chatApplyTimer:SetScript("OnUpdate", function(self, elapsed)
	chatApplyRemaining = chatApplyRemaining - elapsed
	if chatApplyRemaining > 0 then
		return
	end
	self:Hide()
	if ApplyChatLayout(true) then
		Print("已自动应用聊天窗口布局")
	end
end)

local function ScheduleChatAutoApply()
	chatApplyRemaining = 1.5
	chatApplyTimer:Show()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == "MySteamlikeAssistant" then
		local d = MySteamlikeAssistantDB
		if type(d) ~= "table" then
			d = {}
			MySteamlikeAssistantDB = d
		end
		if d.keyMappingEnabled == nil then d.keyMappingEnabled = false end
		if d.wasdAutoLock == nil then d.wasdAutoLock = false end
		if d.debugEnabled == nil then d.debugEnabled = false end
		if d.skullEnabled == nil then d.skullEnabled = false end
		if d.skullKey == nil or d.skullKey == "" then d.skullKey = SKULL_DEFAULT_KEY end
		if d.skullIcon == nil or not SKULL_ICON_NAMES[d.skullIcon] then d.skullIcon = SKULL_ICON_DEFAULT end
		if d.chatAutoApply == nil then d.chatAutoApply = false end
		if d.ctrlHintEnabled == nil then d.ctrlHintEnabled = true end
		if d.altHintEnabled == nil then d.altHintEnabled = true end
		if d.shiftHintEnabled == nil then d.shiftHintEnabled = true end
		keyMappingEnabled = d.keyMappingEnabled
		wasdAutoLock = d.wasdAutoLock
		debugEnabled = d.debugEnabled
		skullEnabled = d.skullEnabled
		skullKey = d.skullKey
		skullIcon = d.skullIcon
		chatAutoApply = d.chatAutoApply
		ctrlHintEnabled = d.ctrlHintEnabled
		altHintEnabled = d.altHintEnabled
		shiftHintEnabled = d.shiftHintEnabled
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		-- 此刻按键表已加载完成，挂载绑定时机最稳；随后做一次自检。
		if keyMappingEnabled then
			ApplyBindings()
			if BindingState(START_KEY) == "未生效" then
				Print(START_KEY .. " 未生效，客户端可能不识别该按键。")
			end
		else
			-- 映射关闭时不占用按键：顺便清掉旧版本可能遗留的绑定。
			ClearBindings()
		end
		-- 标记骷髅同理：只有开关开启且设置过按键时才绑定，否则确保解绑。
		if skullEnabled then
			ApplySkullBinding()
		else
			ClearSkullBinding()
		end
		self:UnregisterEvent("PLAYER_LOGIN")
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- 此时聊天窗口还会被客户端按缓存再摆一次，所以只安排延迟应用，等它摆完再套用存档布局。
		if chatAutoApply and not chatLayoutAppliedThisLogin then
			chatLayoutAppliedThisLogin = true
			ScheduleChatAutoApply()
		end
	end
end)
