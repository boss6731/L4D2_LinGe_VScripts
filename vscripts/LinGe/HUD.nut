printl("[LinGe] HUD 正在載入");
::LinGe.HUD <- {};
::LinGe.HUD.Config <- {
	HUDShow = {
		all = true,
		time = true,
		players = true,
		hostname = false,
		versusNoHUDRank = true, // 對抗模式是否永遠不顯示擊殺排行
		CompatVSLibHud = true // 是否相容 VSLib.HUD
	},
	playersStyle = {
		// 關鍵詞：{特殊(ob,idle,vac,max),隊伍(sur,spe),真人或BOT(human,bot),生存或死亡(alive,dead),運算(+,-)} 如果不包含某個關鍵詞則不對其限定
		// ob,idle,vac,max 為特殊關鍵詞，當包含該類關鍵詞時其它所有關鍵詞無效
		// 除隊伍可同時包含 sur 與 spe 外，其它型別的關鍵詞若同時出現則只有最後一個有效
		// 可以使用擊殺、傷害數據關鍵字，會顯示為所有玩家的總和
		coop = "活躍:{sur,human}  摸魚:{ob}  空位:{vac}  存活特感:{spe,alive}  本局特感擊殺:{ksi}",
		versus = "生還:{sur,human}  VS  特感:{spe,human}"
	},
	hurt = {
		HUDRank = 4, // HUD排行榜最多顯示多少人
		HUDRankMode = 0, // 0:緊湊式 1:分列式:相容多解析度 2:分列式:不相容多解析度（個人不推薦）
		rankCompact = {
			title = "特感/喪屍擊殺：",
			style = "[{rank}] {ksi}/{kci} <- {name}({state})",
		},
		rankColumnAlign = [
			{
				title = "特感",
				style = "{ksi}/{o_ksi}",
				width = 0.1,
			},
			{
				title = "喪屍",
				style = "{kci}/{o_kci}",
				width = 0.1,
			},
			{
				title = "血量狀態",
				style = "{state}",
				width = 0.1,

			},
			{
				title = "玩家",
				style = "[{rank}] {name}",
				width = 0.7,
			},
		],
		tankHurt = {
			title = "本次擊殺了共 {count} 只 Tank，傷害貢獻如下",
			style = "[{rank}] {hurt} <- {name}"
		},
		teamHurtInfo = 2, // 友傷即時提示 0:關閉 1:公開處刑 2:僅攻擊者和被攻擊者可見
		autoPrint = 0, // 每間隔多少s在聊天窗輸出一次數據統計，若為0則只在本局結束時輸出，若<0則永遠不輸出
		chatRank = 4, // 聊天窗輸出時除了最高友傷、最高被黑 剩下顯示最多多少人的數據
		chatStyle2 = "特:{ksi}({si}傷害) 尸:{kci} 黑:{atk} 被黑:{vct} <- {name}",
		discardLostRound = false, // 累計數據中是否不統計敗局的數據
		chatAtkMaxStyle = "隊友鯊手:{name}({hurt})", // 友傷最高與受到友傷最高
		chatVctMaxStyle = "都欺負我:{name}({hurt})",
		chatTeamHurtPraise = "大家真棒，沒有友傷的世界達成了~",
		HUDRankShowBot = false
	},
	textHeight2 = 0.026, // 一行文字通用高度
	position = {
		hostname_x = 0.4,
		hostname_y = 0.0,
		time_x = 0.75,
		time_y = 0.0,
		players_x = 0.0,
		players_y = 0.0,
		rank_x = 0.0,
		rank_y = 0.025
	}
};
::LinGe.Config.Add("HUD", ::LinGe.HUD.Config);
::LinGe.Cache.HUD_Config <- ::LinGe.HUD.Config;
local rankColumnAlign = clone ::LinGe.HUD.Config.hurt.rankColumnAlign; // 避免快取還原後影響陣列順序

::LinGe.HUD.playersIndex <- []; // 排行榜玩家實體索引列表 包括生還者（含BOT）與本局從生還者進入閑置或旁觀的玩家
::LinGe.HUD.hurtData <- []; // 傷害與擊殺數據
::LinGe.HUD.hurtData_bak <- {}; // 以UniqueID為key儲存數據，已經離開的玩家與過關時所有玩家的數據會在此儲存
::LinGe.Cache.hurtData_bak <- ::LinGe.HUD.hurtData_bak;
local hurtDataTemplate = { tank=0 };
local item_key = ["ksi", "hsi", "kci", "hci", "si", "atk", "vct"];
local ex_str = "";
local all_key = clone item_key;
foreach (key in item_key)
{
	all_key.append("o_" + key);
	all_key.append("t_" + key);
	hurtDataTemplate[key] <- 0;
	hurtDataTemplate["o_" + key] <- 0;
	hurtDataTemplate["t_" + key] <- 0;
	ex_str += format("|%s|t_%s|o_%s", key, key, key);
}
local exHurtItem = regexp("{(rank|name|state" + ex_str + ")((:%)([-\\w]+))?}");
// rank為排名，name為玩家名，state為玩家當前血量與狀態，若無異常狀態則只顯示血量
// ksi=擊殺的特感數量 hsi=爆頭擊殺特感的數量 kci=擊殺的喪屍數量 hci=爆頭擊殺喪屍的數量
// si=對特感傷害 atk=對別人的友傷 vct=自己受到的友傷 tank=對tank傷害
// 對特感傷害中不包含對Tank和Witch的傷害 對Tank傷害會單獨列出
// 以 t_ 開頭的代表整局遊戲的累計數據
// 以 o_ 開頭的數據總是在最開始的時候初始化為 t_ 的值，與 t_ 不同的是，它不會實時更新
// 可以指定格式化方式，設定方式參考 https://www.runoob.com/cprogramming/c-function-printf.html
// 需要注意數據型別相匹配，例如 {name:%4d} 會出錯，同時也不推薦對字串數據自定義格式化方式
// 最初是想用來設定數據對齊，不過效果太差，所以又做了分列數據的功能。自定義格式化方式的功能保留，但不推薦使用

// 預處理文字處理函式
::LinGe.HUD.Pre <- {};

local exPlayers = regexp("{([a-z\\,\\+\\-]*)}");
::LinGe.HUD.Pre.BuildFuncCode_Players <- function (result)
{
	local res = exPlayers.capture(result.format_str);

	if (res != null)
	{
		local des = split(result.format_str.slice(res[1].begin, res[1].end), ",");
		result.format_args += ",";
		local item = [];

		if (des.len() > 0)
		{
			local specialKey = 0, humanOrBot = 0, aliveOrDead = 0;
			local team = [];
			foreach (key in des)
			{
				switch (key)
				{
				case "ob":		specialKey = 1; break;
				case "idle":	specialKey = 2; break;
				case "vac":		specialKey = 3; break;
				case "max":		specialKey = 4;	break;
				case "sur":		team.append(2); break;
				case "spe":		team.append(3);	break;
				case "human":	humanOrBot = 1; break;
				case "bot":		humanOrBot = 2;	break;
				case "alive":	aliveOrDead = 1; break;
				case "dead":	aliveOrDead = 2; break;
				case "+": case "-":
					item.append({specialKey=specialKey, humanOrBot=humanOrBot, aliveOrDead=aliveOrDead, team=team, operator=key});
					specialKey = 0, humanOrBot = 0, aliveOrDead = 0;
					team = [];
					break;
				default:
				{
					local idx = all_key.find(key);
					if (idx != null)
						specialKey = key;
					else
						printl("[LinGe] HUD playersStyle 無效關鍵詞：" + key);
					break;
				}
				}
			}
			item.append({specialKey=specialKey, humanOrBot=humanOrBot, aliveOrDead=aliveOrDead, team=team, operator=""});
		}

		foreach (val in item)
		{
			local team = "";
			if (val.team.len() > 0)
			{
				foreach (i in val.team)
				{
					team = format("%d,%s", i, team);
				}
				team = format("[%s]", team);
			}
			else
				team = "null";

			if (typeof val.specialKey == "string")
				result.format_args += format("::LinGe.HUD.SumHurtData(\"%s\")", val.specialKey);
			else
			{
				switch (val.specialKey)
				{
				case 1:	result.format_args += "::pyinfo.ob"; break;
				case 2:	result.format_args += "::LinGe.GetIdlePlayerCount()"; break;
				case 3:	result.format_args += "::pyinfo.maxplayers - (::pyinfo.survivor+::pyinfo.ob+::pyinfo.special)";	break;
				case 4:	result.format_args += "::pyinfo.maxplayers"; break;
				default:
					result.format_args += format("::LinGe.GetPlayerCount(%s,%d,%d)", team, val.humanOrBot, val.aliveOrDead);
					break;
				}
			}
			result.format_args += val.operator;
		}

		result.format_str = result.format_str.slice(0, res[0].begin) + "%d" + result.format_str.slice(res[0].end);
		BuildFuncCode_Players(result);
	}
	else
	{
		result.funcCode = format("return format(\"%s\"%s);", result.format_str, result.format_args);
	}
}

::LinGe.HUD.Pre.BuildFuncCode_Rank <- function (result, wrap=@(str) str)
{
	local res = exHurtItem.capture(result.format_str); // index=0 帶{}的完整匹配 index=1 不帶{}的分組1

	if (res != null)
	{
		result.format_args += ",";
		local key = result.format_str.slice(res[1].begin, res[1].end);
		local format_str = null;
		if (res.len() >= 5 && res[3].begin>=0 && res[3].end > res[3].begin
		&& res[3].end <= result.format_str.len())
		{
			if (result.format_str.slice(res[3].begin, res[3].end).find(":%") == 0)
				format_str = "%" + result.format_str.slice(res[4].begin, res[4].end);
			else
				format_str = null;
		}

		if (key == "rank")
		{
			if (format_str == null)
				format_str = "%d";
			result.format_args += "vargv[0]";
		}
		else if (key == "name")
		{
			if (format_str == null)
				format_str = "%s";
			result.format_args += "vargv[1].GetPlayerName()";
		}
		else if (key == "state")
		{
			if (format_str == null)
				format_str = "%s";
			result.format_args += "::LinGe.HUD.GetPlayerState(vargv[1])";
		}
		else
		{
			if (format_str == null)
				format_str = "%d";
			result.format_args += "vargv[2]." + key;
			result.key.append(key);
		}
		result.format_str = result.format_str.slice(0, res[0].begin) + wrap(format_str) + result.format_str.slice(res[0].end);
		BuildFuncCode_Rank(result, wrap);
	}
	else
	{
		result.funcCode = format("return format(\"%s\"%s);", result.format_str, result.format_args);
	}
}

local exTeamHurt = regexp("{(name|hurt)((:%)([-\\w]+))?}");
::LinGe.HUD.Pre.BuildFuncCode_TeamHurt <- function (result, wrap=@(str) str)
{
	local res = exTeamHurt.capture(result.format_str);

	if (res != null)
	{
		result.format_args += ",";
		local key = result.format_str.slice(res[1].begin, res[1].end);
		local format_str = null;
		if (res.len() >= 5 && res[3].begin>=0 && res[3].end > res[3].begin
		&& res[3].end <= result.format_str.len())
		{
			if (result.format_str.slice(res[3].begin, res[3].end).find(":%") == 0)
				format_str = "%" + result.format_str.slice(res[4].begin, res[4].end);
			else
				format_str = null;
		}

		if (key == "name")
		{
			if (format_str == null)
				format_str = "%s";
			result.format_args += "vargv[0]";
		}
		else if (key == "hurt")
		{
			if (format_str == null)
				format_str = "%d";
			result.format_args += "vargv[1]";
		}
		result.format_str = result.format_str.slice(0, res[0].begin) + wrap(format_str) + result.format_str.slice(res[0].end);
		BuildFuncCode_TeamHurt(result, wrap);
	}
	else
	{
		result.funcCode = format("return format(\"%s\"%s);", result.format_str, result.format_args);
	}
}

local exTankTitle = regexp("{(count)((:%)([-\\w]+))?}");
::LinGe.HUD.Pre.BuildFuncCode_TankTitle <- function (result, wrap=@(str) str)
{
	local res = exTankTitle.capture(result.format_str);

	if (res != null)
	{
		result.format_args += ",";
		local key = result.format_str.slice(res[1].begin, res[1].end);
		local format_str = null;
		if (res.len() >= 5 && res[3].begin>=0 && res[3].end > res[3].begin
		&& res[3].end <= result.format_str.len())
		{
			if (result.format_str.slice(res[3].begin, res[3].end).find(":%") == 0)
				format_str = "%" + result.format_str.slice(res[4].begin, res[4].end);
			else
				format_str = null;
		}

		if (key == "count")
		{
			if (format_str == null)
				format_str = "%d";
			result.format_args += "vargv[0]";
		}
		result.format_str = result.format_str.slice(0, res[0].begin) + wrap(format_str) + result.format_str.slice(res[0].end);
		BuildFuncCode_TankTitle(result, wrap);
	}
	else
	{
		result.funcCode = format("return format(\"%s\"%s);", result.format_str, result.format_args);
	}
}

local exTankHurt = regexp("{(rank|name|hurt)((:%)([-\\w]+))?}");
::LinGe.HUD.Pre.BuildFuncCode_TankHurt <- function (result, wrap=@(str) str)
{
	local res = exTankHurt.capture(result.format_str);

	if (res != null)
	{
		result.format_args += ",";
		local key = result.format_str.slice(res[1].begin, res[1].end);
		local format_str = null;
		if (res.len() >= 5 && res[3].begin>=0 && res[3].end > res[3].begin
		&& res[3].end <= result.format_str.len())
		{
			if (result.format_str.slice(res[3].begin, res[3].end).find(":%") == 0)
				format_str = "%" + result.format_str.slice(res[4].begin, res[4].end);
			else
				format_str = null;
		}

		if (key == "rank")
		{
			if (format_str == null)
				format_str = "%d";
			result.format_args += "vargv[0]";
		}
		else if (key == "name")
		{
			if (format_str == null)
				format_str = "%s";
			result.format_args += "vargv[1].GetPlayerName()";
		}
		else if (key == "hurt")
		{
			if (format_str == null)
				format_str = "%d";
			result.format_args += "vargv[2]";
		}
		result.format_str = result.format_str.slice(0, res[0].begin) + wrap(format_str) + result.format_str.slice(res[0].end);
		BuildFuncCode_TankHurt(result, wrap);
	}
	else
	{
		result.funcCode = format("return format(\"%s\"%s);", result.format_str, result.format_args);
	}
}

::LinGe.HUD.Pre.CompileFunc <- function ()
{
	local empty_table = {key=[], format_str="", format_args="", funcCode=""};
	local result;

	// 戰役模式 玩家數量顯示預處理
	result = ::LinGe.DeepClone(empty_table);
	result.format_str = ::LinGe.HUD.Config.playersStyle.coop;
	BuildFuncCode_Players(result);
	::LinGe.HUD.Pre.PlayersCoop <- compilestring(result.funcCode);

	// 對抗模式 玩家數量顯示預處理
	result = ::LinGe.DeepClone(empty_table);
	result.format_str = ::LinGe.HUD.Config.playersStyle.versus;
	BuildFuncCode_Players(result);
	::LinGe.HUD.Pre.PlayersVersus <- compilestring(result.funcCode);

	// HUD排行榜緊湊模式預處理
	result = ::LinGe.DeepClone(empty_table);
	result.format_str = ::LinGe.HUD.Config.hurt.rankCompact.style;
	BuildFuncCode_Rank(result);
	::LinGe.HUD.Pre.HUDCompactKey <- result.key; // key列表需要儲存下來，用於排序
	::LinGe.HUD.Pre.HUDCompactFunc <- compilestring(result.funcCode);

	// HUD排行榜列對齊模式預處理
	::LinGe.HUD.Pre.HUDColumnKey <- [];
	::LinGe.HUD.Pre.HUDColumnFuncFull <- [];
	::LinGe.HUD.Pre.HUDColumnFunc <- [];
	::LinGe.HUD.Pre.HUDColumnNameIndex <- -1;
	foreach (val in rankColumnAlign)
	{
		result = ::LinGe.DeepClone(empty_table);
		result.format_str = val.style;
		BuildFuncCode_Rank(result);

		HUDColumnKey.extend(result.key);
		if (val.style.find("{name}") != null)
		{
			if (HUDColumnNameIndex != -1)
				printl("[LinGe] HUD 排行榜多列數據包含玩家名，不推薦這樣做。");
			HUDColumnNameIndex = HUDColumnFuncFull.len();
		}
		HUDColumnFuncFull.append(compilestring(result.funcCode));
	}

	// 聊天窗排行榜預處理
	result = ::LinGe.DeepClone(empty_table);
	result.format_str = ::LinGe.HUD.Config.hurt.chatStyle2;
	BuildFuncCode_Rank(result, @(str) "\x03" + str + "\x04");
	::LinGe.HUD.Pre.ChatKey <- result.key;
	::LinGe.HUD.Pre.ChatFunc <- compilestring(result.funcCode);

	// 最高友傷與受到最高友傷預處理
	if (::LinGe.HUD.Config.hurt.chatAtkMaxStyle)
	{
		result = ::LinGe.DeepClone(empty_table);
		result.format_str = ::LinGe.HUD.Config.hurt.chatAtkMaxStyle;
		BuildFuncCode_TeamHurt(result, @(str) "\x03"+str+"\x04");
		::LinGe.HUD.Pre.AtkMaxFunc <- compilestring(result.funcCode);
	}
	else
		::LinGe.HUD.Pre.AtkMaxFunc <- null;
	if (::LinGe.HUD.Config.hurt.chatVctMaxStyle)
	{
		result = ::LinGe.DeepClone(empty_table);
		result.format_str = ::LinGe.HUD.Config.hurt.chatVctMaxStyle;
		BuildFuncCode_TeamHurt(result, @(str) "\x03"+str+"\x04");
		::LinGe.HUD.Pre.VctMaxFunc <- compilestring(result.funcCode);
	}
	else
		::LinGe.HUD.Pre.VctMaxFunc <- null;

	// Tank 傷害預處理
	result = ::LinGe.DeepClone(empty_table);
	result.format_str = ::LinGe.HUD.Config.hurt.tankHurt.title;
	BuildFuncCode_TankTitle(result, @(str) "\x03" + str + "\x04");
	::LinGe.HUD.Pre.TankTitleFunc <- compilestring(result.funcCode);

	result = ::LinGe.DeepClone(empty_table);
	result.format_str = ::LinGe.HUD.Config.hurt.tankHurt.style;
	BuildFuncCode_TankHurt(result, @(str) "\x03" + str + "\x04");
	::LinGe.HUD.Pre.TankHurtFunc <- compilestring(result.funcCode);
}
::LinGe.HUD.Pre.CompileFunc();

const HUD_MAX_STRING_LENGTH = 127; // 一個HUD Slot最多隻能顯示127位元組字元
const HUD_SLOT_BEGIN = 0;
const HUD_SLOT_END = 14;
const HUD_SLOT_RANK_BEGIN	= 0; // 緊湊模式下 第一個SLOT顯示標題 後續顯示每個玩家的數據 分列模式則各自顯示不同的數據
local HUD_SLOT_RANK_END		= 0;
local HUD_RANK_COMPACT_PLAYERS	= 0; // 根據空閑slot數量，緊湊模式最多能顯示28個玩家數據
const HUD_RANK_COLUMN_PLAYERS_COMPAT = 8; // 分列模式相容模式最多能顯示8個玩家的數據，7列數據
const HUD_RANK_COLUMN_PLAYERS	= 16; // 分列模式不相容模式最多能顯示16個玩家的數據，5列數據
local HUD_RANK_COLUMN_MAX		= 0;
// 伺服器每1s內會多次根據HUD_table更新螢幕上的HUD
// 指令碼只需將HUD_table中的數據進行更新 而無需反覆執行HUDSetLayout和HUDPlace
local HUD_table_template = {
	hostname = { // 伺服器名
		slot = 0,
		dataval = Convars.GetStr("hostname"),
		flags = HUD_FLAG_NOBG | HUD_FLAG_ALIGN_LEFT
	},
	time = { // 顯示當地時間需 LinGe_VScripts 輔助外掛支援
		slot = 0,
		// 無邊框 左對齊
		flags = HUD_FLAG_NOBG | HUD_FLAG_ALIGN_LEFT
	},
	players = { // 目前玩家數
		slot = 0,
		dataval = "",
		// 無邊框 左對齊
		flags = HUD_FLAG_NOBG | HUD_FLAG_ALIGN_LEFT
	}
};
for (local i=HUD_SLOT_BEGIN; i<=HUD_SLOT_END; i++)
{
	HUD_table_template["rank" + i] <- {
		slot = 0,
		dataval = "",
		flags = HUD_FLAG_NOBG | HUD_FLAG_ALIGN_LEFT
	};
}
::LinGe.HUD.HUD_table <- {Fields = clone HUD_table_template};

local isExistTime = false;
// 按照Config配置更新HUD屬性資訊
::LinGe.HUD.ApplyConfigHUD <- function ()
{
	if (!Config.HUDShow.all)
	{
		::VSLib.Timers.RemoveTimerByName("Timer_HUD");
		if (Config.HUDShow.CompatVSLibHud)
			HUDSetLayout( ::VSLib.HUD._hud );
		else
			HUD_table.Fields = {};
		return;
	}
	local height = Config.textHeight2;

	HUD_table.Fields = clone HUD_table_template;
	HUD_SLOT_RANK_END = HUD_SLOT_END;
	if (Config.HUDShow.time)
	{
		HUD_table.Fields.time.slot = HUD_SLOT_RANK_END;
		HUDPlace(HUD_SLOT_RANK_END, Config.position.time_x, Config.position.time_y, 1.0, height); // 設定時間顯示位置
		HUD_SLOT_RANK_END--;
		if (isExistTime)
			HUD_table.Fields.time.dataval <- "";
		else
			HUD_table.Fields.time.special <- HUD_SPECIAL_ROUNDTIME;
	}
	else
	{
		HUD_table.Fields.rawdelete("time");
	}

	if (Config.HUDShow.players)
	{
		HUD_table.Fields.players.slot = HUD_SLOT_RANK_END;
		HUDPlace(HUD_SLOT_RANK_END, Config.position.players_x, Config.position.players_y, 1.0, height); // 設定玩家數量資訊顯示位置
		HUD_SLOT_RANK_END--;
	}
	else
	{
		HUD_table.Fields.rawdelete("players");
	}

	if (Config.HUDShow.hostname)
	{
		HUD_table.Fields.hostname.slot = HUD_SLOT_RANK_END;
		HUDPlace(HUD_SLOT_RANK_END, Config.position.hostname_x, Config.position.hostname_y, 1.0, height); // 設定伺服器名顯示位置
		HUD_SLOT_RANK_END--;
	}
	else
	{
		HUD_table.Fields.rawdelete("hostname");
	}

	HUD_RANK_COMPACT_PLAYERS = 2 * (HUD_SLOT_RANK_END - HUD_SLOT_RANK_BEGIN);

	// 編號與隱藏多餘的rank項
	local i = 0;
	for (i=HUD_SLOT_RANK_BEGIN; i<=HUD_SLOT_RANK_END; i++)
	{
		HUD_table.Fields["rank" + i].slot = i;
	}
	for (; i<=HUD_SLOT_END; i++)
	{
		HUD_table.Fields.rawdelete("rank" + i);
	}

	switch (Config.hurt.HUDRankMode)
	{
	case 0:
		// 緊湊模式
		local slot_end = HUD_SLOT_RANK_BEGIN;
		HUD_table.Fields["rank" + HUD_SLOT_RANK_BEGIN].dataval = Config.hurt.rankCompact.title;

		// 當一行只顯示一個玩家數據slot不夠用時，一行顯示兩個玩家的數據
		if (Config.hurt.HUDRank > HUD_RANK_COMPACT_PLAYERS / 2)
		{
			HUDPlace(HUD_SLOT_RANK_BEGIN, Config.position.rank_x, Config.position.rank_y, 1.0, height);
			for (i=HUD_SLOT_RANK_BEGIN+1; i<=HUD_SLOT_RANK_END; i++)
				HUDPlace(i, Config.position.rank_x, Config.position.rank_y + height*((i-HUD_SLOT_RANK_BEGIN)*2 - 1), 1.0, height*2);
			slot_end += (Config.hurt.HUDRank + 1) / 2;
		}
		else
		{
			for (i=HUD_SLOT_RANK_BEGIN; i<=HUD_SLOT_RANK_END; i++)
				HUDPlace(i, Config.position.rank_x, Config.position.rank_y + height*(i-HUD_SLOT_RANK_BEGIN), 1.0, height);
			slot_end += Config.hurt.HUDRank;
		}

		if (slot_end > HUD_SLOT_RANK_END)
			slot_end = HUD_SLOT_RANK_END;
		else if (slot_end <= HUD_SLOT_RANK_BEGIN)
			slot_end = -1;

		for (i=HUD_SLOT_RANK_BEGIN; i<=slot_end; i++) // 將需要顯示的 slot 取消隱藏
			HUD_table.Fields["rank"+i].flags = HUD_table.Fields["rank"+i].flags & (~HUD_FLAG_NOTVISIBLE);
		// 隱藏多餘的 slot
		while (i <= HUD_SLOT_RANK_END)
		{
			HUD_table.Fields["rank"+i].flags = HUD_table.Fields["rank"+i].flags | HUD_FLAG_NOTVISIBLE;
			i++;
		}
		break;
	case 1:
		// 分列模式 相容
		for (i=HUD_SLOT_RANK_BEGIN; i<=HUD_SLOT_RANK_END; i++)
		{
			HUD_table.Fields["rank"+i].dataval = "";
			HUD_table.Fields["rank"+i].flags = HUD_table.Fields["rank"+i].flags & (~HUD_FLAG_NOTVISIBLE);
		}

		// 將 slot 擺放至指定位置
		local pos_x = Config.position.rank_x;
		if (Config.hurt.HUDRank > HUD_RANK_COLUMN_PLAYERS_COMPAT / 2)
		{
			HUD_RANK_COLUMN_MAX = (HUD_SLOT_RANK_END - HUD_SLOT_RANK_BEGIN) / 2;
			if (Pre.HUDColumnFuncFull.len() > HUD_RANK_COLUMN_MAX)
				Pre.HUDColumnFunc = Pre.HUDColumnFuncFull.slice(0, HUD_RANK_COLUMN_MAX);
			else
				Pre.HUDColumnFunc = Pre.HUDColumnFuncFull;

			for (i=0; i<Pre.HUDColumnFunc.len(); i++)
			{
				local width = rankColumnAlign[i].width;
				if (i > 0)
					pos_x += rankColumnAlign[i-1].width;
				HUDPlace(HUD_SLOT_RANK_BEGIN + i, pos_x,
					Config.position.rank_y,	width, height * 5);
				HUDPlace(HUD_SLOT_RANK_BEGIN + HUD_RANK_COLUMN_MAX + i, pos_x,
					Config.position.rank_y + height * 5, width, height * 4);
			}
		}
		else
		{
			HUD_RANK_COLUMN_MAX = HUD_SLOT_RANK_END - HUD_SLOT_RANK_BEGIN;
			if (Pre.HUDColumnFuncFull.len() > HUD_RANK_COLUMN_MAX)
				Pre.HUDColumnFunc = Pre.HUDColumnFuncFull.slice(0, HUD_RANK_COLUMN_MAX);
			else
				Pre.HUDColumnFunc = Pre.HUDColumnFuncFull;
			for (i=0; i<Pre.HUDColumnFunc.len(); i++)
			{
				local width = rankColumnAlign[i].width;
				if (i > 0)
					pos_x += rankColumnAlign[i-1].width;
				HUDPlace(HUD_SLOT_RANK_BEGIN + i, pos_x,
					Config.position.rank_y,	width, height * 5);
			}
		}
		break;
	default:
		// 分列模式 非相容
		for (i=HUD_SLOT_RANK_BEGIN; i<=HUD_SLOT_RANK_END; i++)
		{
			HUD_table.Fields["rank"+i].dataval = "";
			HUD_table.Fields["rank"+i].flags = HUD_table.Fields["rank"+i].flags & (~HUD_FLAG_NOTVISIBLE);
		}

		// 將 slot 擺放至指定位置
		local pos_x = Config.position.rank_x;
		if (Config.hurt.HUDRank > HUD_RANK_COLUMN_PLAYERS/2)
		{
			HUD_RANK_COLUMN_MAX = (HUD_SLOT_RANK_END - HUD_SLOT_RANK_BEGIN - 1) / 2;
			if (Pre.HUDColumnFuncFull.len() > HUD_RANK_COLUMN_MAX)
				Pre.HUDColumnFunc = Pre.HUDColumnFuncFull.slice(0, HUD_RANK_COLUMN_MAX);
			else
				Pre.HUDColumnFunc = Pre.HUDColumnFuncFull;

			for (i=0; i<Pre.HUDColumnFunc.len(); i++)
			{
				local width = rankColumnAlign[i].width;
				if (i > 0)
					pos_x += rankColumnAlign[i-1].width;
				if (i == Pre.HUDColumnNameIndex)
				{
					HUDPlace(HUD_SLOT_RANK_BEGIN + i, pos_x,
						Config.position.rank_y,	width, height * 5);
					HUDPlace(HUD_SLOT_RANK_END, pos_x,
						Config.position.rank_y + height * 5, width, height * 4);
					HUDPlace(HUD_SLOT_RANK_BEGIN + HUD_RANK_COLUMN_MAX + i, pos_x,
						Config.position.rank_y + height * (5 + 4), width, height * 4);
					HUDPlace(HUD_SLOT_RANK_END - 1, pos_x,
						Config.position.rank_y + height * (5 + 4 + 4), width, height * 4);
				}
				else
				{
					HUDPlace(HUD_SLOT_RANK_BEGIN + i, pos_x,
						Config.position.rank_y,	width, height * 9);
					HUDPlace(HUD_SLOT_RANK_BEGIN + HUD_RANK_COLUMN_MAX + i, pos_x,
						Config.position.rank_y + height * 9, width, height * 8);
				}
			}
		}
		else
		{
			HUD_RANK_COLUMN_MAX = HUD_SLOT_RANK_END - HUD_SLOT_RANK_BEGIN;
			if (Pre.HUDColumnFuncFull.len() > HUD_RANK_COLUMN_MAX)
				Pre.HUDColumnFunc = Pre.HUDColumnFuncFull.slice(0, HUD_RANK_COLUMN_MAX);
			else
				Pre.HUDColumnFunc = Pre.HUDColumnFuncFull;
			for (i=0; i<Pre.HUDColumnFunc.len(); i++)
			{
				local width = rankColumnAlign[i].width;
				if (i > 0)
					pos_x += rankColumnAlign[i-1].width;
				if (i == Pre.HUDColumnNameIndex)
				{
					HUDPlace(HUD_SLOT_RANK_BEGIN + i, pos_x,
						Config.position.rank_y,	width, height * 5);
					HUDPlace(HUD_SLOT_RANK_END, pos_x,
						Config.position.rank_y + height * 5, width, height * 4);
				}
				else
				{
					HUDPlace(HUD_SLOT_RANK_BEGIN + i, pos_x,
						Config.position.rank_y,	width, height * 9);
				}
			}
		}
		break;
	}

	if (::LinGe.isVersus && Config.HUDShow.versusNoHUDRank)
	{
		for (i=HUD_SLOT_RANK_BEGIN; i<=HUD_SLOT_RANK_END; i++)
			HUD_table.Fields["rank"+i].flags = HUD_table.Fields["rank"+i].flags | HUD_FLAG_NOTVISIBLE;
	}

	HUDSetLayout(HUD_table);

	UpdateRankHUD();
	Timer_HUD();
	::VSLib.Timers.AddTimer(1.5, false, Timer_DelayHUD);
	::VSLib.Timers.AddTimerByName("Timer_HUD", 1.0, true, Timer_HUD);
}

::LinGe.HUD.Timer_DelayHUD <- function (params=null)
{
	if (Config.hurt.HUDRank > 0)
	{
		// 不在 Timer_HUD 里更新排行榜，避免同一Tick內處理太多數據導致遊戲卡頓
		UpdateRankHUD();
		::VSLib.Timers.AddTimerByName("Timer_UpdateRankHUD", 1.0, true, UpdateRankHUD);
	}
	else
	{
		::VSLib.Timers.RemoveTimerByName("Timer_UpdateRankHUD");
	}
	HUDSetLayout(HUD_table); // 延遲1.5s再次HUDSetLayout，避免與其它MOD衝突而失效
}.bindenv(::LinGe.HUD);

::LinGe.HUD.Timer_HUD <- function (params=null)
{
	if (isExistTime && HUD_table.Fields.rawin("time"))
		HUD_table.Fields.time.dataval = Convars.GetStr("linge_time");
	if (HUD_table.Fields.rawin("players"))
	{
		if (::LinGe.isVersus)
			HUD_table.Fields.players.dataval = Pre.PlayersVersus();
		else
			HUD_table.Fields.players.dataval = Pre.PlayersCoop();
	}
}.bindenv(::LinGe.HUD);

// 將玩家的傷害數據從 hurtData 備份到 hurtData_bak
::LinGe.HUD.BackupAllHurtData <- function ()
{
	for (local i=1; i<=32; i++)
	{
		local player = PlayerInstanceFromIndex(i);
		if (player && player.IsValid()
		&& player.GetNetworkIDString() != "BOT"
		&& 3 != ::LinGe.GetPlayerTeam(player))
		{
			local id = ::LinGe.SteamIDCastUniqueID(player.GetNetworkIDString());
			if (id != "S00")
				hurtData_bak.rawset(id, clone hurtData[i]);
		}
	}
}

::LinGe.HUD.GetPlayerBakHurtData <- function (player)
{
	if (typeof player != "instance")
		throw "player 型別非法";
	if (!player.IsValid())
		return null;
	if (player.GetNetworkIDString() == "BOT")
		return null;
	local id = ::LinGe.SteamIDCastUniqueID(player.GetNetworkIDString());
	if (!hurtData_bak.rawin(id))
		return null;
	return hurtData_bak[id];
}

::LinGe.HUD.On_cache_restore <- function (params)
{
	// 將HurtData_bak中的非累計數據置為0
	foreach (id, d in hurtData_bak)
	{
		if (!d.rawin("hsi")) // Cache 還原后，小寫h總是會被改寫為大寫H，大坑
			d.hsi <- 0;
		if (!d.rawin("hci"))
			d.hci <- 0;
		foreach (key in item_key)
			d[key] = 0;
		d.tank = 0;
	}

	// 初始化 hurtData
	for (local i=0; i<=32; i++)
	{
		local d = clone hurtDataTemplate;
		hurtData.append(d);

		local player = PlayerInstanceFromIndex(i);
		if (player && player.IsValid() && 3 != ::LinGe.GetPlayerTeam(player)
		&& params.isValidCache)
		{
			local last_data = GetPlayerBakHurtData(player);
			if (last_data)
			{
				foreach (key in item_key)
				{
					d["t_" + key] = last_data["t_" + key];
					d["o_" + key] = d["t_" + key];
				}
			}
		}
	}

	// 將 rankColumnAlign 還原為配置檔案內容
	// 因為儲存到 Cache 時，array會變成table，順序會被打亂
	// 所以需要將其直接還原為配置檔案內容，以避免在 !save 時儲存成亂序的排行榜配置
	Config.hurt.rankColumnAlign = clone rankColumnAlign;
}
::LinEventHook("cache_restore", ::LinGe.HUD.On_cache_restore, ::LinGe.HUD);

// 回合失敗
::LinGe.HUD.SaveHurt_RoundLost <- function (params)
{
	// 如果不統計回合失敗時的累計數據，則需將 t_ 數據還原為 o_
	BackupAllHurtData();
	if (Config.hurt.discardLostRound)
	{
		foreach (id, d in hurtData_bak)
		{
			foreach (key in item_key)
				d["t_" + key] = d["o_" + key];
		}
	}
}
::LinEventHook("OnGameEvent_round_end", ::LinGe.HUD.SaveHurt_RoundLost, ::LinGe.HUD);

// 成功過關
::LinGe.HUD.SaveHurt_RoundWin <- function (params)
{
	BackupAllHurtData();
}
::LinEventHook("OnGameEvent_map_transition", ::LinGe.HUD.SaveHurt_RoundWin, ::LinGe.HUD);

// 事件：回合開始
::LinGe.HUD.OnGameEvent_round_start <- function (params)
{
	// 如果linge_time變數不存在則顯示回合時間
	if (null == Convars.GetStr("linge_time"))
	{
		isExistTime = false;
	}
	else
	{
		isExistTime = true;
	}

	playersIndex = clone ::pyinfo.survivorIdx;

	ApplyAutoHurtPrint();
	ApplyConfigHUD();
}
::LinEventHook("OnGameEvent_round_start", ::LinGe.HUD.OnGameEvent_round_start, ::LinGe.HUD);

// 玩家隊伍更換事件
// team=0：玩家剛連線、和斷開連線時會被分配到此隊伍 不統計此隊伍的人數
// team=1：旁觀者 team=2：生還者 team=3：特感
::LinGe.HUD.OnGameEvent_player_team <- function (params)
{
	if (!params.rawin("userid"))
		return;

	local player = GetPlayerFromUserID(params.userid);
	local entityIndex = player.GetEntityIndex();
	local steamid = player.GetNetworkIDString();
	local isHuman = steamid != "BOT";
	local uniqueID = ::LinGe.SteamIDCastUniqueID(steamid);
	local idx = playersIndex.find(entityIndex);

	if (isHuman)
	{
		UpdateRankHUD();
	}

	if ( (params.disconnect || 3 == params.team) && null != idx )
	{
		playersIndex.remove(idx);
		if (isHuman && uniqueID != "S00")
		{
			hurtData_bak.rawset(uniqueID, clone hurtData[entityIndex]);
			hurtData[entityIndex] = clone hurtDataTemplate;
		}
	}
	else if (2 == params.team && null == idx)
	{
		playersIndex.append(entityIndex);
		if (isHuman && hurtData_bak.rawin(uniqueID))
		{
			hurtData[entityIndex] = clone hurtData_bak[uniqueID];
		}
	}
}
::LinEventHook("OnGameEvent_player_team", ::LinGe.HUD.OnGameEvent_player_team, ::LinGe.HUD);

// 事件：玩家受傷 友傷資訊提示、傷害數據統計
// 對witch傷害和對小殭屍傷害不會觸發這個事件
// witch傷害不記錄，tank傷害單獨記錄
::LinGe.HUD.tempTeamHurt <- {}; // 友傷臨時數據記錄
::LinGe.HUD.OnGameEvent_player_hurt <- function (params)
{
	if (!params.rawin("dmg_health"))
		return;
	if (params.dmg_health < 1)
		return;

	if (0 == params.type) // 傷害型別為0
		return;
	local attacker = GetPlayerFromUserID(params.attacker); // 獲得攻擊者實體
	if (null == attacker) // 攻擊者無效
		return;
	if (!attacker.IsSurvivor()) // 攻擊者不是生還者
		return;

	// 獲取被攻擊者實體
	local victim = GetPlayerFromUserID(params.userid);
	local vctHp = victim.GetHealth();
	local dmg = params.dmg_health;
	// 如果被攻擊者是生還者則統計友傷數據
	if (victim.IsSurvivor())
	{
		if (victim.IsDying() || victim.IsDead())
			return;
		else if (vctHp < 0) // 致死傷害事件發生時，victim.IsDead()還不會為真，但血量會<0
		{
			// 如果是本次傷害致其死亡，則 生命值 + 傷害值 > 0
			if (vctHp + dmg <= 0)
				return;
		}
		else if (victim.IsIncapacitated())
		{
			// 如果是本次傷害致其倒地，則其目前血量+傷害量=300
			// 如果不是，則說明攻擊時已經倒地，則不統計本次友傷
			if (vctHp + dmg != 300)
				return;
		}

		// 若不是對自己造成的傷害，則計入累計統計
		if (attacker != victim)
		{
			hurtData[attacker.GetEntityIndex()].atk += dmg;
			hurtData[attacker.GetEntityIndex()].t_atk += dmg;
			hurtData[victim.GetEntityIndex()].vct += dmg;
			hurtData[victim.GetEntityIndex()].t_vct += dmg;
		}

		// 若開啟了友傷提示，則計入臨時數據統計
		if (Config.hurt.teamHurtInfo >= 1 && Config.hurt.teamHurtInfo <= 2)
		{
			local key = params.attacker + "_" + params.userid;
			if (!tempTeamHurt.rawin(key))
			{
				tempTeamHurt[key] <- { dmg=0, attacker=attacker, atkName=attacker.GetPlayerName(),
					victim=victim, vctName=victim.GetPlayerName(), isDead=false, isIncap=false };
			}
			tempTeamHurt[key].dmg += dmg;
			// 友傷發生后，0.5秒內同一人若未再對同一人造成友傷，則輸出其造成的傷害
			VSLib.Timers.AddTimerByName(key, 0.5, false, Timer_PrintTeamHurt, key);
		}
	}
	else // 不是生還者團隊則統計對特感的傷害數據
	{
		// 如果是Tank 則將數據記錄到臨時Tank傷害數據記錄
		if (8 == victim.GetZombieType())
		{
			if (5000 == dmg) // 擊殺Tank時會產生5000傷害事件，不知道為什麼設計了這樣的機制
				return;
			hurtData[attacker.GetEntityIndex()].tank += dmg;
		}
		else // 不是生還者且不是Tank，則為普通特感(此事件下不可能為witch)
		{
			if (vctHp < 0)
				dmg += vctHp; // 修正溢出傷害
			hurtData[attacker.GetEntityIndex()].si += dmg;
			hurtData[attacker.GetEntityIndex()].t_si += dmg;
		}
	}
}
::LinEventHook("OnGameEvent_player_hurt", ::LinGe.HUD.OnGameEvent_player_hurt, ::LinGe.HUD);
/*	Tank的擊殺傷害與致隊友倒地時的傷害存在溢出
	沒能發現太好修正方法，因為當上述兩種情況發生時
	已經無法獲得其最後一刻的真實血量
	除非時刻記錄Tank和隊友的血量，然後以此為準編寫一套邏輯
	但這樣實在太浪費資源，且容易出現BUG
*/

// 提示一次友傷傷害並刪除累積數據
::LinGe.HUD.Timer_PrintTeamHurt <- function (key)
{
	local info = tempTeamHurt[key];
	local atkName = info.atkName;
	local vctName = info.vctName;
	local text = "";

	if (Config.hurt.teamHurtInfo == 1)
	{
		if (info.attacker == info.victim)
			vctName = "他自己";
		text = "\x03" + atkName
			+ "\x04 對 \x03" + vctName
			+ "\x04 造成了 \x03" + info.dmg + "\x04 點傷害";
		if (info.isDead)
		{
			if (info.attacker == info.victim)
				text += "，並且死亡";
			else
				text += "，並且殺死了對方";
		}
		else if (info.isIncap)
		{
			if (info.attacker == info.victim)
				text += "，並且倒地";
			else
				text += "，並且擊倒了對方";
		}
		ClientPrint(null, 3, text);
	}
	else if (Config.hurt.teamHurtInfo == 2)
	{
		if (info.attacker == info.victim)
		{
			if (info.attacker.IsValid())
			{
				text = "\x04你對 \x03自己\x04 造成了 \x03" + info.dmg + "\x04 點傷害";
				if (info.isDead)
					text += "，並且死亡";
				else if (info.isIncap)
					text += "，並且倒地";
				ClientPrint(info.attacker, 3, text);
			}
		}
		else
		{
			if (info.attacker.IsValid())
			{
				text = "\x04你對 \x03" + vctName
					+ "\x04 造成了 \x03" + info.dmg + "\x04 點傷害";
				if (info.isDead)
					text += "，並且殺死了他";
				else if (info.isIncap)
					text += "，並且擊倒了他";
				ClientPrint(info.attacker, 3, text);
			}

			if (info.victim.IsValid())
			{
				text = "\x03" + atkName
				+ "\x04 對你造成了 \x03" + info.dmg + "\x04 點傷害";
				if (info.isDead)
					text += "，並且殺死了你";
				else if (info.isIncap)
					text += "，並且打倒了你";
				ClientPrint(info.victim, 3, text);
			}
		}
	}
	tempTeamHurt.rawdelete(key);
}.bindenv(LinGe.HUD);

// 事件：玩家(特感/喪屍)死亡 統計擊殺數量
// 雖然是player_death 但小喪屍和witch死亡也會觸發該事件
::LinGe.HUD.OnGameEvent_player_death <- function (params)
{
	local dier = 0;	// 死者ID
	local dierEntity = null;	// 死者實體
	local attacker = 0; // 攻擊者ID
	local attackerEntity = null; // 攻擊者實體

	if (params.victimname == "Infected" || params.victimname == "Witch")
	{
		// witch 和 小喪屍 不屬於玩家可控制實體 無userid
		dier = params.entityid;
	}
	else
		dier = params.userid;
	if (dier == 0)
		return;

	attacker = params.attacker;
	dierEntity = GetPlayerFromUserID(dier);
	attackerEntity = GetPlayerFromUserID(attacker);

	if (dierEntity && dierEntity.IsSurvivor())
	{
		// 自殺時傷害型別為0
		if (params.type == 0)
			return;

		// 如果是友傷致其死亡
		if (attackerEntity && attackerEntity.IsSurvivor())
		{
			local key = params.attacker + "_" + dier;
			if (tempTeamHurt.rawin(key))
				tempTeamHurt[key].isDead = true;
		}
	}
	else
	{
		if (attackerEntity && attackerEntity.IsSurvivor())
		{
			if (params.victimname == "Infected")
			{
				hurtData[attackerEntity.GetEntityIndex()].kci++;
				hurtData[attackerEntity.GetEntityIndex()].t_kci++;
				if (params.headshot)
				{
					hurtData[attackerEntity.GetEntityIndex()].hci++;
					hurtData[attackerEntity.GetEntityIndex()].t_hci++;
				}
			}
			else
			{
				hurtData[attackerEntity.GetEntityIndex()].ksi++;
				hurtData[attackerEntity.GetEntityIndex()].t_ksi++;
				if (params.headshot)
				{
					hurtData[attackerEntity.GetEntityIndex()].hsi++;
					hurtData[attackerEntity.GetEntityIndex()].t_hsi++;
				}
			}
			// UpdateRankHUD();
		}
	}
}
::LinEventHook("OnGameEvent_player_death", ::LinGe.HUD.OnGameEvent_player_death, ::LinGe.HUD);

// 事件：玩家倒地
::LinGe.HUD.OnGameEvent_player_incapacitated <- function (params)
{
	if (!params.rawin("userid") || params.userid == 0)
		return;

	local player = GetPlayerFromUserID(params.userid);
	local attackerEntity = null;
	if (params.rawin("attacker")) // 如果是小喪屍或Witch等使玩家倒地，則無attacker
		attackerEntity = GetPlayerFromUserID(params.attacker);
	if (player.IsSurvivor())
	{
		// 如果是友傷致其倒地
		if (attackerEntity && attackerEntity.IsSurvivor())
		{
			local key = params.attacker + "_" + params.userid;
			if (tempTeamHurt.rawin(key))
				tempTeamHurt[key].isIncap = true;
		}
	}
}
::LinEventHook("OnGameEvent_player_incapacitated", ::LinGe.HUD.OnGameEvent_player_incapacitated, ::LinGe.HUD);

::LinGe.HUD.OnGameEvent_hostname_changed <- function (params)
{
	local hostname = Convars.GetStr("hostname");
	if (hostname && typeof hostname == "string")
	{
		if (HUD_table.Fields.rawin("hostname"))
			HUD_table.Fields.hostname.dataval = hostname;
		HUD_table_template.hostname.dataval = hostname;
	}
}
::LinEventHook("OnGameEvent_hostname_changed", ::LinGe.HUD.OnGameEvent_hostname_changed, ::LinGe.HUD);

::LinGe.HUD.Cmd_thi <- function (player, args)
{
	if (2 == args.len())
	{
		local style = LinGe.TryStringToInt(args[1], 0);
		Config.hurt.teamHurtInfo = style;
	}
	switch (Config.hurt.teamHurtInfo)
	{
	case 1:
		ClientPrint(null, 3, "\x04伺服器已開啟友傷提示 \x03公開處刑");
		break;
	case 2:
		ClientPrint(null, 3, "\x04伺服器已開啟友傷提示 \x03僅雙方可見");
		break;
	default:
		ClientPrint(null, 3, "\x04伺服器已關閉友傷提示");
		break;
	}
	ClientPrint(player, 3, "\x04!thi 0:關閉友傷提示 1:公開處刑 2:僅雙方可見");
}
::LinCmdAdd("thi", ::LinGe.HUD.Cmd_thi, ::LinGe.HUD, "0:關閉友傷提示 1:公開處刑 2:僅雙方可見");

::LinGe.HUD.Cmd_hurtdata <- function (player, args)
{
	local len = args.len();
	if (1 == len)
		PrintChatRank();
	else if (3 == len)
	{
		if (!::LinGe.Admin.IsAdmin(player))
		{
			ClientPrint(player, 3, "\x04許可權不足！");
		}
		else if ("auto" == args[1])
		{
			local time = ::LinGe.TryStringToFloat(args[2]);
			Config.hurt.autoPrint = time;
			ApplyAutoHurtPrint();
			if (time > 0)
				ClientPrint(player, 3, "\x04已設定每 \x03" + time + "\x04 秒播報一次聊天窗排行榜");
			else if (0 == time)
				ClientPrint(player, 3, "\x04已關閉定時聊天窗排行榜播報，回合結束時仍會播報");
			else
				ClientPrint(player, 3, "\x04已徹底關閉聊天窗排行榜播報");
		}
		else if ("player" == args[1])
		{
			local player = ::LinGe.TryStringToInt(args[2]);
			Config.hurt.chatRank = player;
			if (player > 0)
				ClientPrint(player, 3, "\x04聊天窗排行榜將顯示最多 \x03" + player + "\x04 人");
			else
				ClientPrint(player, 3, "\x04已徹底關閉聊天窗排行榜與TANK傷害統計播報");
		}
	}
}
::LinCmdAdd("hurtdata", ::LinGe.HUD.Cmd_hurtdata, ::LinGe.HUD, "", false);
::LinCmdAdd("hurt", ::LinGe.HUD.Cmd_hurtdata, ::LinGe.HUD, "", false);
::LinCmdAdd("hd", ::LinGe.HUD.Cmd_hurtdata, ::LinGe.HUD, "輸出一次聊天窗排行榜或者調整自動播報配置", false);

local reHudCmd = regexp("^(all|time|players|hostname)$");
::LinGe.HUD.Cmd_hud <- function (player, args)
{
	if (1 == args.len())
	{
		Config.HUDShow.all = !Config.HUDShow.all;
		ApplyConfigHUD();
		return;
	}
	else if (2 == args.len())
	{
		if (args[1] == "rank")
		{
			ClientPrint(player, 3, "\x04!hud rank n 設定排行榜最大顯示人數為n");
			return;
		}
		else if (reHudCmd.search(args[1]))
		{
			Config.HUDShow[args[1]] = !Config.HUDShow[args[1]];
			ApplyConfigHUD();
			return;
		}
	}
	else if (3 == args.len() && args[1] == "rank")
	{
		Config.hurt.HUDRank = ::LinGe.TryStringToInt(args[2]);
		ApplyConfigHUD();
		return;
	}
	ClientPrint(player, 3, "\x04!hud time/players/hostname/rank 控制HUD元素的顯示");
}
::LinCmdAdd("hud", ::LinGe.HUD.Cmd_hud, ::LinGe.HUD, "time/players/hostname/rank 控制HUD元素的顯示");

::LinGe.HUD.Cmd_rank <- function (player, args)
{
	if (2 == args.len())
	{
		Config.hurt.HUDRank = ::LinGe.TryStringToInt(args[1]);
		ApplyConfigHUD();
		return;
	}
	ClientPrint(player, 3, "\x04!rank n 設定排行榜最大顯示人數為n");
}
::LinCmdAdd("rank", ::LinGe.HUD.Cmd_rank, ::LinGe.HUD);

::LinGe.HUD.GetPlayerState <- function (player)
{
	if (::LinGe.GetPlayerTeam(player) == 1)
		return "摸魚";
	else if (!::LinGe.IsAlive(player))
		return "死亡";
	else
	{
		local hp = player.GetHealth() + player.GetHealthBuffer().tointeger();
		local text = format("%d", hp);
		if (player.GetSpecialInfectedDominatingMe())
			text += ",被控";
		else if (player.IsHangingFromLedge())
			text += ",掛邊";
		else if (player.IsIncapacitated())
			text += ",倒地";
		else if (::LinGe.GetReviveCount(player) >= 2)
			text += ",瀕死";
		return text;
	}
}

::LinGe.HUD.UpdateRankHUD <- function (params=null)
{
	if (Config.hurt.HUDRank < 1)
		return;
	if (::LinGe.isVersus && Config.HUDShow.versusNoHUDRank)
		return;

	local len = playersIndex.len();
	switch (Config.hurt.HUDRankMode)
	{
	case 0:
		local max_rank = Config.hurt.HUDRank > HUD_RANK_COMPACT_PLAYERS ? HUD_RANK_COMPACT_PLAYERS : Config.hurt.HUDRank;
		hurtDataSort(playersIndex, Pre.HUDCompactKey);
		local rank = 1;
		if (max_rank > HUD_RANK_COMPACT_PLAYERS/2)
		{
			for (local i=0; i < len && rank <= max_rank; i++)
			{
				local player = PlayerInstanceFromIndex(playersIndex[i]);
				if (!IsPlayerABot(player) || Config.hurt.HUDRankShowBot)
				{
					local text = Pre.HUDCompactFunc(rank, player, hurtData[playersIndex[i]]);
					if (rank % 2 == 1)
						HUD_table.Fields["rank" + (HUD_SLOT_RANK_BEGIN + (rank+1)/2)].dataval = text + "\n";
					else
						HUD_table.Fields["rank" + (HUD_SLOT_RANK_BEGIN + (rank+1)/2)].dataval += text;
					rank++;
				}
			}
			// 目前排行榜顯示的人數小於最大顯示人數時，清除可能存在的多餘的行
			if (rank % 2 == 0)
				rank++;
			while (rank <= max_rank)
			{
				HUD_table.Fields["rank" + (HUD_SLOT_RANK_BEGIN + (rank+1)/2)].dataval = "\n";
				rank+=2;
			}
		}
		else
		{
			for (local i=0; i < len && rank <= max_rank; i++)
			{
				local player = PlayerInstanceFromIndex(playersIndex[i]);
				if (!IsPlayerABot(player) || Config.hurt.HUDRankShowBot)
				{
					local text = Pre.HUDCompactFunc(rank, player, hurtData[playersIndex[i]]);
					HUD_table.Fields["rank" + (HUD_SLOT_RANK_BEGIN + rank)].dataval = text;
					rank++;
				}
			}
			// 目前排行榜顯示的人數小於最大顯示人數時，清除可能存在的多餘的行
			while (rank <= max_rank)
			{
				HUD_table.Fields["rank" + (HUD_SLOT_RANK_BEGIN + rank)].dataval = "";
				rank++;
			}
		}
		break;
	case 1:
		local max_rank = Config.hurt.HUDRank > HUD_RANK_COLUMN_PLAYERS_COMPAT ? HUD_RANK_COLUMN_PLAYERS_COMPAT : Config.hurt.HUDRank;
		hurtDataSort(playersIndex, Pre.HUDColumnKey);

		// 重新設定每列的內容
		if (max_rank > HUD_RANK_COLUMN_PLAYERS_COMPAT/2)
		{
			for (local i=0; i<Pre.HUDColumnFunc.len(); i++)
			{
				HUD_table.Fields["rank" + (HUD_SLOT_RANK_BEGIN + i)].dataval =
					rankColumnAlign[i].title;
				HUD_table.Fields["rank" + (HUD_SLOT_RANK_BEGIN + HUD_RANK_COLUMN_MAX + i)].dataval = "";
			}
		}
		else
		{
			for (local i=0; i<Pre.HUDColumnFunc.len(); i++)
			{
				HUD_table.Fields["rank" + (HUD_SLOT_RANK_BEGIN + i)].dataval =
					rankColumnAlign[i].title;
			}
		}

		local rank = 1;
		local begin = HUD_SLOT_RANK_BEGIN;
		local nl_normal = "\n";
		local player = null;
		for (local i=0; i<len && rank <= max_rank; i++)
		{
			player = PlayerInstanceFromIndex(playersIndex[i]);
			if (!IsPlayerABot(player) || Config.hurt.HUDRankShowBot)
			{
				nl_normal = "\n";
				if (rank == 5)
				{
					begin = HUD_SLOT_RANK_BEGIN + HUD_RANK_COLUMN_MAX;
					nl_normal = "";
				}
				foreach (index, func in Pre.HUDColumnFunc)
				{
					HUD_table.Fields["rank" + (begin + index)].dataval += nl_normal +
						func(rank, player, hurtData[playersIndex[i]]);
				}
				rank++;
			}
		}

		// 使用換行符填充剩餘的行，使文字行數對齊
		while (rank <= 4)
		{
			foreach (index, func in Pre.HUDColumnFunc)
			{
				HUD_table.Fields["rank" + (HUD_SLOT_RANK_BEGIN + index)].dataval += "\n";
			}
			rank++;
		}
		// 如果rank==5，則下半段的slot都是空白，無需處理
		if (rank > 5)
		{
			while (rank <= 8)
			{
				foreach (index, func in Pre.HUDColumnFunc)
				{
					HUD_table.Fields["rank" + (HUD_SLOT_RANK_BEGIN + HUD_RANK_COLUMN_MAX + index)].dataval += "\n";
				}
				rank++;
			}
		}
		break;
	default:
		local max_rank = Config.hurt.HUDRank > HUD_RANK_COLUMN_PLAYERS ? HUD_RANK_COLUMN_PLAYERS : Config.hurt.HUDRank;
		hurtDataSort(playersIndex, Pre.HUDColumnKey);

		if (max_rank > HUD_RANK_COLUMN_PLAYERS/2)
		{
			// 重新設定每列的內容
			HUD_table.Fields["rank" + HUD_SLOT_RANK_END].dataval = "";
			HUD_table.Fields["rank" + (HUD_SLOT_RANK_END - 1)].dataval = "";
			for (local i=0; i<Pre.HUDColumnFunc.len(); i++)
			{
				HUD_table.Fields["rank" + (HUD_SLOT_RANK_BEGIN + i)].dataval =
					rankColumnAlign[i].title;
				HUD_table.Fields["rank" + (HUD_SLOT_RANK_BEGIN + HUD_RANK_COLUMN_MAX + i)].dataval = "";
			}
		}
		else
		{
			HUD_table.Fields["rank"+HUD_SLOT_RANK_END].dataval = "";
			for (local i=0; i<Pre.HUDColumnFunc.len(); i++)
			{
				HUD_table.Fields["rank" + (HUD_SLOT_RANK_BEGIN + i)].dataval =
					rankColumnAlign[i].title;
			}
		}

		// 列模式下，排行榜1~4、5、6~8、9、10~12、13、14~16名次均需要進行不同的處理
		local rank = 1;
		local begin = HUD_SLOT_RANK_BEGIN;
		local name_slot2 = HUD_table.Fields["rank" + HUD_SLOT_RANK_END];
		local nl_normal = "\n", nl_name = "\n";
		local player = null;

		for (local i=0; i<len && rank <= max_rank; i++)
		{
			player = PlayerInstanceFromIndex(playersIndex[i]);
			if (!IsPlayerABot(player) || Config.hurt.HUDRankShowBot)
			{
				nl_normal = nl_name = "\n";
				switch (rank)
				{
				case 9:
					begin = HUD_SLOT_RANK_BEGIN + HUD_RANK_COLUMN_MAX;
					name_slot2 = HUD_table.Fields["rank" + (HUD_SLOT_RANK_END - 1)];
					nl_normal = "";
					nl_name = "";
				case 1: case 2: case 3: case 4:
				case 10:case 11:case 12:
					foreach (index, func in Pre.HUDColumnFunc)
					{
						HUD_table.Fields["rank" + (begin + index)].dataval += nl_normal +
							func(rank, player, hurtData[playersIndex[i]]);
					}
					break;
				case 5: case 13:
					nl_name = "";
				case 6: case 7: case 8:
				case 14:case 15:case 16:
					foreach (index, func in Pre.HUDColumnFunc)
					{
						if (index == Pre.HUDColumnNameIndex)
						{
							name_slot2.dataval += nl_name +
								func(rank, player, hurtData[playersIndex[i]]);
						}
						else
						{
							HUD_table.Fields["rank" + (begin + index)].dataval += nl_normal +
								func(rank, player, hurtData[playersIndex[i]]);
						}
					}
					break;
				}
				rank++;
			}
		}

		// 使用換行符填充剩餘的行，使文字行數對齊
		while (rank <= 8)
		{
			foreach (index, func in Pre.HUDColumnFunc)
			{
				if (index == Pre.HUDColumnNameIndex && rank > 4)
				{
					HUD_table.Fields["rank" + HUD_SLOT_RANK_END].dataval += "\n";
				}
				else
				{
					HUD_table.Fields["rank" + (HUD_SLOT_RANK_BEGIN + index)].dataval += "\n";
				}
			}
			rank++;
		}
		// 如果rank==9，則下半段的slot都是空白，無需處理
		if (rank > 9)
		{
			while (rank <= 16)
			{
				foreach (index, func in Pre.HUDColumnFunc)
				{
					if (index == Pre.HUDColumnNameIndex && rank > 12)
					{
						HUD_table.Fields["rank" + (HUD_SLOT_RANK_END - 1)].dataval += "\n";
					}
					else
					{
						HUD_table.Fields["rank" + (HUD_SLOT_RANK_BEGIN + HUD_RANK_COLUMN_MAX + index)].dataval += "\n";
					}
				}
				rank++;
			}
		}
		break;
	}
}.bindenv(::LinGe.HUD);

// Tank 事件控制
// 在Tank全部死亡時輸出並清空本次克局傷害統計
local nowTank = 0;
local killTank = 0;
::LinGe.HUD.OnGameEvent_tank_spawn <- function (params)
{
	nowTank++;
}
::LinGe.HUD.OnGameEvent_tank_killed <- function (params)
{
	nowTank--;
	killTank++;
	if (nowTank == 0)
	{
		PrintTankHurtData();
		killTank = 0;
		for (local i=1; i<=32; i++)
			hurtData[i].tank = 0;
	}
}
::LinEventHook("OnGameEvent_tank_spawn", ::LinGe.HUD.OnGameEvent_tank_spawn, ::LinGe.HUD);
::LinEventHook("OnGameEvent_tank_killed", ::LinGe.HUD.OnGameEvent_tank_killed, ::LinGe.HUD);

::LinGe.HUD.PrintTankHurtData <- function ()
{
	local maxRank = Config.hurt.chatRank;
	local idx = clone playersIndex;
	local len = idx.len();

	if (maxRank > 0 && len > 0)
	{
		hurtDataSort(idx, ["tank"]);
		// 如果第一位的傷害也為0，則本次未對該Tank造成傷害，則不輸出Tank傷害統計
		// 終局時無線刷Tank 經常會出現這種0傷害的情況
		if (hurtData[idx[0]].tank == 0)
			return;
		ClientPrint(null, 3, "\x04" + Pre.TankTitleFunc(killTank));
		for (local i=0; i<maxRank && i<len; i++)
		{
			local player = PlayerInstanceFromIndex(idx[i]);
			ClientPrint(null, 3, "\x04" + Pre.TankHurtFunc(i+1, player, hurtData[idx[i]].tank));
		}
	}
}

// 根據目前的 Config.hurt.autoPrint 設定定時輸出Timer
::LinGe.HUD.ApplyAutoHurtPrint <- function ()
{
	if (Config.hurt.autoPrint <= 0)
		::VSLib.Timers.RemoveTimerByName("Timer_AutoPrintHurt");
	else
		::VSLib.Timers.AddTimerByName("Timer_AutoPrintHurt", Config.hurt.autoPrint, true, PrintChatRank);

	::LinEventUnHook("OnGameEvent_round_end", ::LinGe.HUD.PrintChatRank);
	::LinEventUnHook("OnGameEvent_map_transition", ::LinGe.HUD.PrintChatRank);
	if (Config.hurt.autoPrint >= 0)
	{
		// 回合結束時輸出本局傷害統計
		::LinEventHook("OnGameEvent_round_end", ::LinGe.HUD.PrintChatRank);
		::LinEventHook("OnGameEvent_map_transition", ::LinGe.HUD.PrintChatRank);
	}
}

// 向聊天窗公佈目前的傷害數據統計
// params是預留參數位置 為方便關聯事件和定時器
::LinGe.HUD.PrintChatRank <- function (params=0)
{
	local maxRank = Config.hurt.chatRank;
	local survivorIdx = clone playersIndex;
	local name = "", len = survivorIdx.len();
	if (len > 0)
	{
		local atkMax = { name="", hurt=0 };
		local vctMax = clone atkMax;
		// 遍歷找出黑槍最多和被黑最多
		for (local i=0; i<len; i++)
		{
			local temp = hurtData[survivorIdx[i]];
			if (temp.atk > atkMax.hurt)
			{
				atkMax.hurt = temp.atk;
				atkMax.name = PlayerInstanceFromIndex(survivorIdx[i]).GetPlayerName();
			}
			if (temp.vct > vctMax.hurt)
			{
				vctMax.hurt = temp.vct;
				vctMax.name = PlayerInstanceFromIndex(survivorIdx[i]).GetPlayerName();
			}
		}
		if (maxRank > 0)
		{
			hurtDataSort(survivorIdx, Pre.ChatKey);
			for (local i=0; i<maxRank && i<len; i++)
			{
				local player = PlayerInstanceFromIndex(survivorIdx[i]);
				ClientPrint(null, 3, "\x04" +
					Pre.ChatFunc(i+1, player, hurtData[survivorIdx[i]]));
			}
		}

		// 顯示最高黑槍和最高被黑
		if (0 == atkMax.hurt && 0 == vctMax.hurt && Config.hurt.chatTeamHurtPraise)
		{
			ClientPrint(null, 3, "\x05" + Config.hurt.chatTeamHurtPraise);
		}
		else
		{
			local text = "\x04";
			if (atkMax.hurt > 0 && Pre.AtkMaxFunc)
				text += Pre.AtkMaxFunc(atkMax.name, atkMax.hurt) + " ";
			if (vctMax.hurt > 0 && Pre.VctMaxFunc)
				text += Pre.VctMaxFunc(vctMax.name, vctMax.hurt);
			if (text != "\x04")
				ClientPrint(null, 3, text);
		}
	}
}.bindenv(::LinGe.HUD);

::LinGe.HUD.SumHurtData <- function (key)
{
	local result = 0;
	foreach (playerIndex in playersIndex)
	{
		result += hurtData[playerIndex][key];
	}
	return result;
}

// 氣泡排序 預設降序排序
::LinGe.HUD.hurtDataSort <- function (survivorIdx, key, desc=true)
{
	local temp;
	local len = survivorIdx.len();
	local result = desc ? 1 : -1;
	for (local i=0; i<len-1; i++)
	{
		for (local j=0; j<len-1-i; j++)
		{
			if (hurtDataCompare(survivorIdx[j], survivorIdx[j+1], key, 0) == result)
			{
				temp = survivorIdx[j];
				survivorIdx[j] = survivorIdx[j+1];
				survivorIdx[j+1] = temp;
			}
		}
	}
}

::LinGe.HUD.hurtDataCompare <- function (idx1, idx2, key, keyIdx)
{
	if (hurtData[idx1][key[keyIdx]] > hurtData[idx2][key[keyIdx]])
		return -1;
	else if (hurtData[idx1][key[keyIdx]] == hurtData[idx2][key[keyIdx]])
	{
		if (keyIdx+1 < key.len()) // 如果還有可比較的值就繼續比較
			return hurtDataCompare(idx1, idx2, key, keyIdx+1);
		else
			return 0;
	}
	else
		return 1;
}
