// By LinGe https://github.com/Lin515/L4D2_LinGe_VScripts
// 本系列指令碼編寫主要參考以下文件
// L4D2指令碼函式清單：https://developer.valvesoftware.com/wiki/L4D2%E8%84%9A%E6%9C%AC%E5%87%BD%E6%95%B0%E6%B8%85%E5%8D%95
// L4D2 EMS/Appendix：HUD：https://developer.valvesoftware.com/wiki/L4D2_EMS/Appendix:_HUD
// L4D2 Events：https://wiki.alliedmods.net/Left_4_Dead_2_Events
// 以及VSLib與admin_system的指令碼原始碼
printl("[LinGe] Base 正在載入");
::LinGe <- {};
::LinGe.Debug <- false;

::LinGe.hostport <- Convars.GetFloat("hostport").tointeger();
printl("[LinGe] 目前伺服器埠 " + ::LinGe.hostport);

// ---------------------------全域性函式START-------------------------------------------
// 主要用於除錯
::LinGe.DebugPrintl <- function (str)
{
	if (::LinGe.Debug)
		printl(str);
}

::LinGe.DebugPrintlTable <- function (table)
{
	if (!::LinGe.Debug)
		return;
	if (typeof table != "table" && typeof table != "array")
		return;
	foreach (key, val in table)
		print(key + "=" + val + " ; ");
	print("\n");
}

// 遞迴深度克隆（只會對table或array的子項進行克隆）
::LinGe.DeepClone <- function (obj)
{
	if (typeof obj == "table")
	{
		local table = clone obj;
		foreach (key, val in table)
			table[key] = DeepClone(val);
		return table;
	}
	if (typeof obj == "array")
	{
		local array = clone obj;
		foreach (index, val in array)
			array[index] = DeepClone(val);
		return array;
	}
	return obj;
}

// 嘗試將一個字串轉換為int型別 eValue為出現異常時返回的值
::LinGe.TryStringToInt <- function (value, eValue=0)
{
	local ret = eValue;
	try
	{
		ret = value.tointeger();
	}
	catch (e)
	{
		ret = eValue;
	}
	return ret;
}
// 嘗試將一個字串轉換為float型別 eValue為出現異常時返回的值
::LinGe.TryStringToFloat <- function (value, eValue=0.0)
{
	local ret = eValue;
	try
	{
		ret = value.tofloat();
	}
	catch (e)
	{
		ret = eValue;
	}
	return ret;
}

// 查詢並移除找到的第一個元素 返回其索引，若未找到則返回null
::LinGe.RemoveInArray <- function (value, array)
{
	local idx = array.find(value);
	if (null != idx)
		array.remove(idx);
	return idx;
}

// 目前模式是否是對抗模式
::LinGe.CheckVersus <- function ()
{
	if (Director.GetGameMode() == "mutation15") // 生還者對抗
		return true;
	if ("versus" == g_BaseMode)
		return true;
	if ("scavenge" == g_BaseMode)
		return true;
	return false;
}
::LinGe.isVersus <- ::LinGe.CheckVersus();

// 設定某類下所有已產生實體的KeyValue
::LinGe.SetKeyValueByClassname <- function (className, key, value)
{
	local entity = null;
	local func = null;

	switch (typeof value)
	{
	case "integer":
		func = @(entity, key, value) entity.__KeyValueFromInt(key, value);
		break;
	case "float":
		func = @(entity, key, value) entity.__KeyValueFromFloat(key, value);
		break;
	case "string":
		func = @(entity, key, value) entity.__KeyValueFromString(key, value);
		break;
	case "Vector":
		func = @(entity, key, value) entity.__KeyValueFromVector(key, value);
		break;
	default:
		throw "參數型別非法";
	}

	local count = 0;
	while ( (entity = Entities.FindByClassname(entity, className)) != null)
	{
		func(entity, key, value);
		count++;
	}
	return count;
}

::LinGe.SteamIDCastUniqueID <- function (steamid)
{
	local uniqueID = ::VSLib.Utils.StringReplace(steamid, "STEAM_1:", "S");
	uniqueID = ::VSLib.Utils.StringReplace(uniqueID, "STEAM_0:", "S");
	uniqueID = ::VSLib.Utils.StringReplace(uniqueID, ":", "");
	return uniqueID;
}

// 獲取 targetname，並確保它在本指令碼系統中獨一無二
::LinGe.GetEntityTargetname <- function (entity)
{
	local targetname = entity.GetName();
	if (targetname.find("LinGe_") != 0)
	{
		targetname = "LinGe_" + UniqueString();
		entity.__KeyValueFromString("targetname", targetname);
	}
	return targetname;
}

// 通過userid獲得玩家實體索引
::LinGe.GetEntityIndexFromUserID <- function (userid)
{
	local entity = GetPlayerFromUserID(userid);
	if (null == entity)
		return null;
	else
		return entity.GetEntityIndex();
}

// 通過userid獲得steamid
::LinGe.GetSteamIDFromUserID <- function (userid)
{
	local entity = GetPlayerFromUserID(userid);
	if (null == entity)
		return null;
	else
		return entity.GetNetworkIDString();
}

// 該userid是否為BOT所有
::LinGe.IsBotUserID <- function (userid)
{
	local entity = GetPlayerFromUserID(userid);
	if (null == entity)
		return true;
	else
		return "BOT"==entity.GetNetworkIDString();
}

::LinGe.GetReviveCount <- function (player)
{
	return NetProps.GetPropInt(player, "m_currentReviveCount");
}

// 從網路屬性判斷一個實體是否存活
::LinGe.IsAlive <- function (ent)
{
	return NetProps.GetPropInt(ent, "m_lifeState") == 0;
}

// 從bot生還者中獲取其就位的生還者玩家實體
// 須自己先檢查是否是有效生還者bot 否則可能出錯
::LinGe.GetHumanPlayer <- function (bot)
{
	if (::LinGe.IsAlive(bot))
	{
		local human = GetPlayerFromUserID(NetProps.GetPropInt(bot, "m_humanSpectatorUserID"));
		if (null != human)
		{
			if (human.IsValid())
			{
				if ( "BOT" != human.GetNetworkIDString()
				&& 1 == ::LinGe.GetPlayerTeam(human) )
					return human;
			}
		}
	}
	return null;
}

// 判斷玩家是否處於閑置 參數可以是玩家實體也可以是實體索引
::LinGe.IsPlayerIdle <- function (player)
{
	local entityIndex = 0;
	local _player = null;
	// 通過類名查詢玩家
	if ("integer" == typeof player)
	{
		entityIndex = player;
		_player = PlayerInstanceFromIndex(entityIndex);
	}
	else if ("instance" == typeof player)
	{
		entityIndex = player.GetEntityIndex();
		_player = player;
	}
	else
		throw "參數型別非法";
	if (!_player.IsValid())
		return false;
	if (1 != ::LinGe.GetPlayerTeam(_player))
		return false;

	local bot = null;
	while ( bot = Entities.FindByClassname(bot, "player") )
	{
		// 判斷搜索到的實體有效性
		if ( bot.IsValid() )
		{
			// 判斷陣營
			if ( bot.IsSurvivor()
			&& "BOT" == bot.GetNetworkIDString()
			&& ::LinGe.IsAlive(bot) )
			{
				local human = ::LinGe.GetHumanPlayer(bot);
				if (human != null)
				{
					if (human.GetEntityIndex() == entityIndex)
						return true;
				}
			}
		}
	}
	return false;
}

// 獲取所有處於閑置的玩家
::LinGe.GetIdlePlayers <- function ()
{
	local bot = null;
	local players = [];
	while ( bot = Entities.FindByClassname(bot, "player") )
	{
		if ( bot.IsValid() )
		{
			if ( bot.IsSurvivor()
			&& "BOT" == bot.GetNetworkIDString()
			&& ::LinGe.IsAlive(bot) )
			{
				local human = ::LinGe.GetHumanPlayer(bot);
				if (human != null)
				{
					players.push(human);
				}
			}
		}
	}
	return players;
}

::LinGe.GetIdlePlayerCount <- function ()
{
	local bot = null;
	local count = 0;
	while ( bot = Entities.FindByClassname(bot, "player") )
	{
		if ( bot.IsValid() )
		{
			if ( bot.IsSurvivor()
			&& "BOT" == bot.GetNetworkIDString()
			&& ::LinGe.IsAlive(bot) )
			{
				local human = ::LinGe.GetHumanPlayer(bot);
				if (human != null)
				{
					count++;
				}
			}
		}
	}
	return count;
}

::LinGe.GetMaxHealth <- function (entity)
{
	return NetProps.GetPropInt(victim, "m_iMaxHealth");
}

::LinGe.GetPlayerTeam <- function (player)
{
	return NetProps.GetPropInt(player, "m_iTeamNum");
}

// 將 Vector 轉換為 QAngle
// hl2sdk-l4d2/mathlib/mathlib_base.cpp > line:506
::LinGe.QAngleFromVector <- function (forward)
{
	local tmp, yaw, pitch;

	if (forward.y == 0 && forward.x == 0)
	{
		yaw = 0;
		if (forward.z > 0)
			pitch = 270;
		else
			pitch = 90;
	}
	else
	{
		yaw = (atan2(forward.y, forward.x) * 180 / PI);
		if (yaw < 0)
			yaw += 360;

		tmp = sqrt(forward.x*forward.x + forward.y*forward.y);
		pitch = (atan2(-forward.z, tmp) * 180 / PI);
		if (pitch < 0)
			pitch += 360;
	}
	return QAngle(pitch, yaw, 0.0);
}

// 玩家是否看著實體的位置或指定位置
// VSLib/player.nut > line:1381 function VSLib::Player::CanSeeLocation
::LinGe.IsPlayerSeeHere <- function (player, location, tolerance = 50)
{
	local _location = null;
	if (typeof location == "instance")
		_location = location.GetOrigin();
	else if (typeof location == "Vector")
		_location = location;
	else
		throw "location 參數型別非法";

	local clientPos = player.EyePosition();
	local clientToTargetVec = _location - clientPos;
	local clientAimVector = player.EyeAngles().Forward();

	local angToFind = acos(
			::VSLib.Utils.VectorDotProduct(clientAimVector, clientToTargetVec)
			/ (clientAimVector.Length() * clientToTargetVec.Length())
		) * 360 / 2 / 3.14159265;

	if (angToFind < tolerance)
		return true;
	else
		return false;
}

::LinGe.TraceToLocation <- function (origin, location, mask=MASK_SHOT_HULL & (~CONTENTS_WINDOW), ignore=null)
{
	// 獲取出發點
	local start = null;
	if (typeof origin == "instance")
	{
		if ("EyePosition" in origin)
			start = origin.EyePosition(); // 如果對象是有眼睛的則獲取眼睛位置
		else
			start = origin.GetOrigin();
	}
	else if (typeof origin == "Vector")
		start = origin;
	else
		throw "origin 參數型別非法";

	// 獲取終點
	local end = null;
	if (typeof location == "instance")
	{
		if ("EyePosition" in location)
			end = location.EyePosition();
		else
			end = location.GetOrigin();
	}
	else if (typeof location == "Vector")
		end = location;
	else
		throw "location 參數型別非法";

	local tr = {
		start = start,
		end =  end,
		ignore = (ignore ? ignore : (typeof origin == "instance" ? origin : null) ),
		mask = mask,
	};
	TraceLine(tr);
	return tr;
}

// player 是否注意著 entity
::LinGe.IsPlayerNoticeEntity <- function (player, entity, tolerance = 50, mask=MASK_SHOT_HULL & (~CONTENTS_WINDOW), radius=0.0)
{
	if (!IsPlayerSeeHere(player, entity, tolerance))
		return false;
	local tr = TraceToLocation(player, entity, mask);
	if (tr.rawin("enthit") && tr.enthit == entity)
		return true;
	if (radius <= 0.0)
		return false;
	// 如果不能看到指定實體，但指定了半徑範圍，則進行搜索
	local _entity = null, className = entity.GetClassname();
	while ( _entity = Entities.FindByClassnameWithin(_entity, className, tr.pos, radius) )
	{
		if (_entity == entity)
			return true;
	}
	return false;
}

// 鏈式射線追蹤，當命中到型別為 ignoreClass 中的實體時，從其位置往前繼續射線追蹤
// ignoreClass 中可以有 entity 的型別，判斷時總會先判斷定位到的是否是 entity
// 如果最終能命中 entity，則返回 true
::LinGe.ChainTraceToEntity <- function (origin, entity, mask, ignoreClass, limit=4)
{
	local tr = {
		start = null,
		end = null,
		ignore = null,
		mask = mask,
	};

	// 獲取起始點
	if (typeof origin == "instance")
	{
		if ("EyePosition" in origin)
			tr.start = origin.EyePosition();
		else
			tr.start = origin.GetOrigin();
		tr.ignore = origin;
	}
	else if (typeof origin == "Vector")
		tr.start = origin;
	else
		throw "origin 參數型別非法";

	if ("EyePosition" in entity)
		tr.end = entity.EyePosition();
	else
		tr.end = entity.GetOrigin();
	if (limit < 1)
		limit = 4; // 不允許無限制的鏈式探測
	local start = tr.start; // 保留最初的起點

	local count = 0;
	while (true)
	{
		count++;
		TraceLine(tr);
		if (!tr.rawin("enthit"))
			break;
		if (tr.enthit == entity)
			return true;
		if (count >= limit)
			break;
		// 如果命中位置已經比目標位置要更遠離起始點，則終止
		if ((tr.pos-start).Length() > (tr.end-start).Length())
			break;
		if (ignoreClass.find(tr.enthit.GetClassname()) == null)
			break;
		tr.start = tr.pos;
		tr.ignore = tr.enthit;
	}
	return false;
}

// 獲取玩家實體陣列
// team 指定要獲取的隊伍 可以是陣列或數字 若為null則忽略隊伍
// humanOrBot 機器人 0:忽略是否是機器人 1:只獲取玩家 2:只獲取BOT
// aliveOrDead 存活 0:忽略是否存貨 1:只獲取存活的 2:只獲取死亡的
::LinGe.GetPlayers <- function (team=null, humanOrBot=0, aliveOrDead=0)
{
	local arr = [];
	// 通過類名查詢玩家
	local player = null;
	while ( player = Entities.FindByClassname(player, "player") )
	{
		// 判斷搜索到的實體有效性
		if ( player.IsValid() )
		{
			// 判斷陣營
			if (typeof team == "array")
			{
				if (team.find(::LinGe.GetPlayerTeam(player))==null)
					continue;
			}
			else if (typeof team == "integer" && team != ::LinGe.GetPlayerTeam(player))
				continue;
			if (humanOrBot == 1)
			{
				if ("BOT" == player.GetNetworkIDString())
					continue;
			}
			else if (humanOrBot == 2 && "BOT" != player.GetNetworkIDString())
				continue;
			if (aliveOrDead == 1)
			{
				if (!::LinGe.IsAlive(player))
					continue;
			}
			else if (aliveOrDead == 2 && ::LinGe.IsAlive(player))
				continue;
			arr.append(player);
		}
	}
	return arr;
}
::LinGe.GetPlayerCount <- function (team=null, humanOrBot=0, aliveOrDead=0)
{
	local count = 0;
	// 通過類名查詢玩家
	local player = null;
	while ( player = Entities.FindByClassname(player, "player") )
	{
		// 判斷搜索到的實體有效性
		if ( player.IsValid() )
		{
			// 判斷陣營
			if (typeof team == "array")
			{
				if (team.find(::LinGe.GetPlayerTeam(player))==null)
					continue;
			}
			else if (typeof team == "integer" && team != ::LinGe.GetPlayerTeam(player))
				continue;
			if (humanOrBot == 1)
			{
				if ("BOT" == player.GetNetworkIDString())
					continue;
			}
			else if (humanOrBot == 2 && "BOT" != player.GetNetworkIDString())
				continue;
			if (aliveOrDead == 1)
			{
				if (!::LinGe.IsAlive(player))
					continue;
			}
			else if (aliveOrDead == 2 && ::LinGe.IsAlive(player))
				continue;
			count++;
		}
	}
	return count;
}

// 如果source中某個key在dest中也存在，則將其賦值給dest中的key
// 如果 reserveKey 為 true，則dest中沒用該key也會被賦值
// key無視大小寫
::LinGe.Merge <- function (dest, source, typeMatch=true, reserveKey=false)
{
	if ("table" == typeof dest && "table" == typeof source)
	{
		foreach (key, val in source)
		{
			local keyIsExist = true;
			if (!dest.rawin(key))
			{
				// 為什麼有些儲存到 Cache 會產生大小寫轉換？？
				// HUD.Config.hurt 儲存到 Cache 恢復后，hurt 居然變成了 Hurt
				foreach (_key, _val in dest)
				{
					if (_key.tolower() == key.tolower())
					{
						source[_key] <- source[key];
						key = _key;
						break;
					}
				}
				if (!dest.rawin(key))
					keyIsExist = false;
			}
			if (!keyIsExist)
			{
				if (reserveKey)
					dest.rawset(key, val);
				continue;
			}
			local type_dest = typeof dest[key];
			local type_src = typeof val;
			// 如果指定key也是table，則進行遞迴
			if ("table" == type_dest && "table" == type_src)
				::LinGe.Merge(dest[key], val, typeMatch, reserveKey);
			else if (type_dest != type_src)
			{
				if (!typeMatch)
					dest[key] = val;
				else if (type_dest == "bool" && type_src == "integer") // 爭對某些情況下 bool 被轉換成了 integer
					dest[key] = (val!=0);
				else if (type_dest == "array" && type_src == "table") // 爭對某些情況下 array 被轉換成了 table 原陣列的順序可能會錯亂
				{
					dest[key].clear();
					foreach (_val in val)
						dest[key].append(_val);
				}
			}
			else
				dest[key] = val;
		}
	}
}
// ---------------------------全域性函式END-------------------------------------------

// -------------------------------VSLib 改寫-------------------------------------------------
// 判斷玩家是否為BOT時通過steamid進行判斷
function VSLib::Entity::IsBot()
{
	if (!IsEntityValid())
	{
		printl("VSLib Warning: Entity " + _idx + " is invalid.");
		return false;
	}
	if (IsPlayer())
		return "BOT" == GetSteamID();
	else
		return IsPlayerABot(_ent);
}

// 改良原函式，使其輸出的檔案帶有縮排
function VSLib::FileIO::SerializeTable(object, predicateStart = "{\n", predicateEnd = "}\n", indice = true, indent=1)
{
	local indstr = "";
	for (local i=0; i<indent; i++)
		indstr += "\t";

	local baseString = predicateStart;

	foreach (idx, val in object)
	{
		local idxType = typeof idx;

		if (idxType == "instance" || idxType == "class" || idxType == "function")
			continue;

		// Check for invalid characters
		local idxStr = idx.tostring();
		local reg = regexp("^[a-zA-Z0-9_]*$");

		if (!reg.match(idxStr))
		{
			printf("VSLib Warning: Index '%s' is invalid (invalid characters found), skipping...", idxStr);
			continue;
		}

		// Check for numeric fields and prefix them so system can compile
		reg = regexp("^[0-9]+$");
		if (reg.match(idxStr))
			idxStr = "_vslInt_" + idxStr;


		local preCompileString = indstr + ((indice) ? (idxStr + " = ") : "");

		switch (typeof val)
		{
			case "table":
				baseString += preCompileString + ::VSLib.FileIO.SerializeTable(val, "{\n", "}\n", true, indent+1);
				break;

			case "string":
				baseString += preCompileString + "\"" + ::VSLib.Utils.StringReplace(::VSLib.Utils.StringReplace(val, "\"", "{VSQUOTE}"), @"\\", "{VSSLASH}") + "\"\n"; // "
				break;

			case "integer":
				baseString += preCompileString + val + "\n";
				break;

			case "float":
				baseString += preCompileString + val + "\n";
				break;

			case "array":
				baseString += preCompileString + ::VSLib.FileIO.SerializeTable(val, "[\n", "]\n", false, indent+1);
				break;

			case "bool":
				baseString += preCompileString + ((val) ? "true" : "false") + "\n";
				break;
		}
	}

	// 末尾括號的縮排與上一級同級
	indstr = "";
	for (local i=0; i<indent-1; i++)
		indstr += "\t";

	baseString += indstr + predicateEnd;

	return baseString;
}

// -------------------------------VSLib-------------------------------------------------

// ---------------------------CONFIG-配置管理---------------------------------------
class ::LinGe.ConfigManager
{
	filePath = null;
	table = null;

	constructor(_filePath)
	{
		filePath = _filePath;
		table = {};
	}
	// 新增表到配置管理 若表名重複則會覆蓋
	function Add(tableName, _table, reserveKey=false)
	{
		table.rawset(tableName, _table.weakref());
		Load(tableName, reserveKey);
	}

	// 從配置管理中刪除表
	function Delete(tableName)
	{
		table.rawdelete(tableName);
	}
	// 載入指定表的配置
	// reserveKey為false時，配置載入只會載入已建立的key，配置檔案中有但指令碼程式碼未建立的key不會被載入
	// 反之則配置檔案中的key會被保留
	function Load(tableName, reserveKey=false)
	{
		if (!table.rawin(tableName))
			throw "未找到表";
		local fromFile = null;
		try {
			fromFile = ::VSLib.FileIO.LoadTable(filePath);
		} catch (e)	{
			printl("[LinGe] 伺服器配置檔案損壞，將自動還原為預設設定");
			fromFile = null;
		}
		if (null != fromFile && fromFile.rawin(tableName))
		{
			::LinGe.Merge(table[tableName], fromFile[tableName], true, reserveKey);
		}
		Save(tableName); // 保持檔案配置和已載入配置的一致性
	}
	// 儲存指定表的配置
	function Save(tableName)
	{
		if (table.rawin(tableName))
		{
			local fromFile = null;
			try {
				fromFile = ::VSLib.FileIO.LoadTable(filePath);
			} catch (e) {
				fromFile = null;
			}
			if (null == fromFile)
				fromFile = {};
			fromFile.rawset(tableName, table[tableName]);
			::VSLib.FileIO.SaveTable(filePath, fromFile);
		}
		else
			throw "未找到表";
	}

	// 載入所有表
	function LoadAll(reserveKey=false)
	{
		local fromFile = ::VSLib.FileIO.LoadTable(filePath);
		if (null != fromFile)
			::LinGe.Merge(table, fromFile, true, reserveKey);
		SaveAll();
	}
	// 儲存所有表
	function SaveAll()
	{
		local fromFile = ::VSLib.FileIO.LoadTable(filePath);
		foreach (k, v in table)
			fromFile.rawset(k, v);
		::VSLib.FileIO.SaveTable(filePath, fromFile);
	}
};

local FILE_CONFIG = "LinGe/Config_" + ::LinGe.hostport;
::LinGe.Config <- ::LinGe.ConfigManager(FILE_CONFIG);
// ---------------------------CONFIG-配置管理END-----------------------------------------

// -----------------------事件回撥函式註冊START--------------------------------------
//	集合管理事件函式，可以讓多個指令碼中同事件的函式呼叫順序變得可控

::LinGe.Events <- {};
::LinGe.Events.trigger <- {}; // 觸發表
::ACTION_CONTINUE <- 0;
::ACTION_RESETPARAMS <- 1;
::ACTION_STOP <- 2;

::LinGe.Events.TriggerFunc <- function (params)
{
	local action = ACTION_CONTINUE;
	local _params = null==params ? null : clone params;
	local len = callback.len();
	local val = null;
	::LinGe.DebugPrintlTable(params);
	for (local i=0; i<len; i++)
	{
		val = callback[i];
		if (null == val.func)
			continue;
		else
		{
			if (val.callOf != null)
				action = val.func.call(val.callOf, _params);
			else
				action = val.func(_params);
			switch (action)
			{
			case null: // 若沒有使用return返回數值 則為null
				break;
			case ACTION_CONTINUE:
				break;
			case ACTION_RESETPARAMS:
				_params = null==params ? null : clone params;
				break;
			case ACTION_STOP:
				return;
			default:
				throw "事件函式返回了非法的ACTION";
			}
		}
	}
}
// 繫結函式到事件 允許同一事件重複繫結同一函式
// event 為事件名 若以 OnGameEvent_ 開頭則視為遊戲事件
// callOf為函式執行時所在表，為null則不指定表
// last為真即插入到回撥函式列表的最後，為否則插入到最前，越靠前的函式呼叫得越早
// 成功繫結則返回該事件目前繫結的函式數量
// func若為null則表明本次EventHook只是註冊一下事件
::LinGe.Events.EventHook <- function (event, func=null, callOf=null, last=true)
{
	// 若該事件未註冊則進行註冊
	if (event == "callback")
		throw "事件名不能為 callback";

	if (!trigger.rawin(event))
	{
		trigger.rawset(event, { callback=[] });
		trigger[event][event] <- TriggerFunc.bindenv(trigger[event]);
		// trigger觸發表中每個元素的key=事件名（用於查詢），而每個元素的值都是一個table
		// 這個table中有一個事件函式，以事件名命名（用於註冊與呼叫），以及一個key為callback的回撥函式陣列
		// 事件函式的所完成的就是依次呼叫同table下callback中所有函式
		// 沒有把所有事件函式放在同一table下是爲了讓每個事件函式能快速找到自己的callback

		// 自動註冊OnGameEvent_開頭的遊戲事件
		if (event.find("OnGameEvent_") == 0)
			__CollectEventCallbacks(trigger[event], "OnGameEvent_", "GameEventCallbacks", RegisterScriptGameEventListener);
	}

	local callback = trigger[event].callback;
	if (null != func)
	{
		local _callOf = (callOf==null) ? null : callOf.weakref();
		if (last)
			callback.append( { func=func.weakref(), callOf=_callOf } );
		else
			callback.insert(0, { func=func.weakref(), callOf=_callOf } );
	}
	return callback.len();
}.bindenv(::LinGe.Events);
// 根據給定函式進行解綁 預設為逆向解綁，即解綁匹配項中最靠後的
// 事件未註冊返回-1 未找到函式返回-2 成功解綁則返回其索引值
::LinGe.Events.EventUnHook <- function (event, func, callOf=null, reverse=true)
{
	local idx = EventIndex(event, func, callOf, reverse);
	if (idx >= 0)
		trigger[event].callback.remove(idx);
	return idx;
}.bindenv(::LinGe.Events);

// 查詢函式在指定事件的函式表的索引
// 事件未註冊返回-1 未找到函式返回-2
::LinGe.Events.EventIndex <- function (event, func, callOf=null, reverse=true)
{
	if (trigger.rawin(event))
	{
		local callback = trigger[event].callback;
		local len = callback.len();
		local i = 0;
		if (reverse)
		{
			for (i=len-1; i>-1; i--)
			{
				if (func == callback[i].func
				&& callOf == callback[i].callOf )
					break;
			}
		}
		else
		{
			for (i=0; i<len; i++)
			{
				if (func == callback[i].func
				&& callOf == callback[i].callOf )
					break;
			}
		}
		if (-1 == i || i == len)
			return -2;
		else
			return i;
	}
	else
		return -1;
}.bindenv(::LinGe.Events);

::LinGe.Events.EventTrigger <- function (event, params=null, delay=0.0)
{
	if (trigger.rawin(event))
	{
		if (delay > 0.0)
			::VSLib.Timers.AddTimer(delay, false,
				@(params) ::LinGe.Events.trigger[event][event](params), params);
		else
			trigger[event][event](params);
	}
}.bindenv(::LinGe.Events);

::LinEventHook <- ::LinGe.Events.EventHook.weakref();
::LinEventUnHook <- ::LinGe.Events.EventUnHook.weakref();
::LinEventIndex <- ::LinGe.Events.EventIndex.weakref();
::LinEventTrigger <- ::LinGe.Events.EventTrigger.weakref();

// 只有具有FCVAR_NOTIFY flags的變數才會觸發該事件
//::LinGe.Events.OnGameEvent_server_cvar <- function (params)
//{
//	EventTrigger("cvar_" + params.cvarname, params);
//}
//::LinEventHook("OnGameEvent_server_cvar", ::LinGe.Events.OnGameEvent_server_cvar, ::LinGe.Events);
// --------------------------事件回撥函式註冊END----------------------------------------

// ------------------------------Admin---START--------------------------------------
::LinGe.Admin <- {};
::LinGe.Admin.Config <- {
	enabled = false,
	takeOverAdminSystem = false, // 是否接管adminsystem的許可權判斷
	adminsFile = "linge/admins_simple.ini"
};
::LinGe.Config.Add("Admin", ::LinGe.Admin.Config);

::LinGe.Admin.cmdTable <- {}; // 指令表
// 讀取管理員列表，若檔案不存在則建立
::LinGe.Admin.adminslist <- FileToString(::LinGe.Admin.Config.adminsFile);
if (null == ::LinGe.Admin.adminslist)
{
	::LinGe.Admin.adminslist = "STEAM_1:0:64877973 // Homura Chan";
	StringToFile(::LinGe.Admin.Config.adminsFile, ::LinGe.Admin.adminslist);
	::LinGe.Admin.adminslist = FileToString(::LinGe.Admin.Config.adminsFile);
	if (null == ::LinGe.Admin.adminslist)
		printl("[LinGe] " + adminsFile + " 檔案讀取失敗，無法獲取管理員列表");
}

/*	新增指令 若同名指令會覆蓋舊指令
	string	指令名
	func	指令回撥函式
	callOf	回撥函式執行所在的表
	isAdminCmd 是否是管理員指令
*/
::LinGe.Admin.CmdAdd <- function (command, func, callOf=null, remarks="", isAdminCmd=true, ignoreCase=true)
{
	local _callOf = (callOf==null) ? null : callOf.weakref();
	local table = { func=func.weakref(), callOf=_callOf, remarks=remarks, isAdminCmd=isAdminCmd, ignoreCase=ignoreCase };
	cmdTable.rawset(command.tolower(), table);
}.bindenv(::LinGe.Admin);

// 刪除指令 成功刪除返回其值 否則返回null
::LinGe.Admin.CmdDelete <- function (command)
{
	return cmdTable.rawdelete(command.tolower());
}.bindenv(::LinGe.Admin);
::LinCmdAdd <- ::LinGe.Admin.CmdAdd.weakref();
::LinCmdDelete <- ::LinGe.Admin.CmdDelete.weakref();

// 訊息指令觸發 通過 player_say
::LinGe.Admin.OnGameEvent_player_say <- function (params)
{
	local args = split(params.text, " ");
	local cmd = args[0];
	if (cmd.len() < 2)
		return;
	local player = GetPlayerFromUserID(params.userid);
	if (null == player || !player.IsValid())
		return;
	local firstChar = cmd.slice(0, 1); // 取第一個字元
	// 判斷字首有效性
	if (firstChar != "!"
	&& firstChar != "/"
	&& firstChar != "." )
		return;

	local text = params.text.slice(1);
	args = split(text, " ");
	cmd = args[0].tolower(); // 設定 args 第一個元素為指令名
	if (cmdTable.rawin(cmd))
	{
		if (cmdTable[cmd].ignoreCase)
			CmdExec(cmd, player, split(text.tolower(), " "));
		else
			CmdExec(cmd, player, args);
	}
}
::LinEventHook("OnGameEvent_player_say", ::LinGe.Admin.OnGameEvent_player_say, ::LinGe.Admin);

// scripted_user_func 指令觸發
::LinGe.Admin.OnUserCommand <- function (vplayer, args, text)
{
	local _args = split(text, ",");
	local cmdstr = _args[0].tolower();
	local cmdTable = ::LinGe.Admin.cmdTable;
	if (cmdTable.rawin(cmdstr))
	{
		if (cmdTable[cmdstr].ignoreCase)
			::LinGe.Admin.CmdExec(cmdstr, vplayer._ent, split(text.tolower(), ","));
		else
			::LinGe.Admin.CmdExec(cmdstr, vplayer._ent, _args);
	}
}
::EasyLogic.OnUserCommand.LinGeCommands <- ::LinGe.Admin.OnUserCommand.weakref();

// 指令呼叫執行
::LinGe.Admin.CmdExec <- function (command, player, args)
{
	local cmd = cmdTable[command];
	if (cmd.isAdminCmd && !IsAdmin(player))
	{	// 如果是管理員指令而使用者身份不是管理員，則發送許可權不足提示
		ClientPrint(player, 3, "\x04此條指令僅管理員可用！");
		return;
	}

	if (cmd.callOf != null)
		cmd.func.call(cmd.callOf, player, args);
	else
		cmd.func(player, args);
}

// 判斷該玩家是否是管理員
::LinGe.Admin.IsAdmin <- function (player)
{
	// 未啟用許可權管理則所有人視作管理員
	if (!Config.enabled)
		return true;
	// 如果是單人遊戲則直接返回true
	if (Director.IsSinglePlayerGame())
		return true;
	// 獲取steam id
	local steamID = null;
	local vplayer = player;
	if (typeof vplayer != "VSLIB_PLAYER")
		vplayer = ::VSLib.Player(player);
	if ( vplayer.IsServerHost() )
		return true;
	steamID = vplayer.GetSteamID();
	if (null == steamID)
		return false;

	// 通過steamID判斷是否是管理員
	if (null != adminslist)
	{
		if (null == adminslist.find(steamID))
			return false;
		else
			return true;
	}
	else
		return false;
}.bindenv(::LinGe.Admin);

// 事件：回合開始 如果啟用了AdminSystem則覆蓋其管理員判斷指令
::LinGe.Admin.OnGameEvent_round_start <- function (params)
{
	if ("AdminSystem" in getroottable() && Config.takeOverAdminSystem)
	{
		::AdminSystem.IsAdmin = ::LinGe.Admin.IsAdmin;
		::AdminSystem.IsPrivileged = ::LinGe.Admin.IsAdmin;
	}
}
::LinEventHook("OnGameEvent_round_start", ::LinGe.Admin.OnGameEvent_round_start, ::LinGe.Admin);

::LinGe.Admin.Cmd_setvalue <- function (player, args)
{
	if (args.len() == 3)
		Convars.SetValue(args[1], args[2]);
}
::LinCmdAdd("setvalue", ::LinGe.Admin.Cmd_setvalue, ::LinGe.Admin);

::LinGe.Admin.Cmd_getvalue <- function (player, args)
{
	if (args.len() == 2)
		ClientPrint(player, 3, Convars.GetStr(args[1]));
}
::LinCmdAdd("getvalue", ::LinGe.Admin.Cmd_getvalue, ::LinGe.Admin);

::LinGe.Admin.Cmd_saveconfig <- function (player, args)
{
	if (args.len() == 1)
	{
		::LinGe.Config.SaveAll();
		ClientPrint(player, 3, "\x04已儲存目前功能設定為預設設定\n");
		ClientPrint(player, 3, "\x04配置檔案: \x05 left4dead2/ems/" + FILE_CONFIG + ".tbl");
	}
	else if (args.len() == 2)
	{
		foreach (name, tbl in ::LinGe.Config.table)
		{
			if (name.tolower() == args[1])
			{
				::LinGe.Config.Save(name);
				ClientPrint(player, 3, "\x04已儲存目前功能設定為預設設定: \x05" + name);
				ClientPrint(player, 3, "\x04配置檔案: \x05 left4dead2/ems/" + FILE_CONFIG + ".tbl");
				return;
			}
		}
		ClientPrint(player, 3, "\x04未找到 \x05" + args[1]);
	}
}
::LinCmdAdd("saveconfig", ::LinGe.Admin.Cmd_saveconfig, ::LinGe.Admin);
::LinCmdAdd("save", ::LinGe.Admin.Cmd_saveconfig, ::LinGe.Admin, "儲存配置到配置檔案");

::LinGe.Admin.Cmd_lshelp <- function (player, args)
{
	foreach (key, val in cmdTable)
	{
		if (val.remarks != "")
			ClientPrint(player, 3, format("\x05!%s \x03%s", key, val.remarks));
	}
}
::LinCmdAdd("lshelp", ::LinGe.Admin.Cmd_lshelp, ::LinGe.Admin, "", false);

::LinGe.Admin.Cmd_config <- function (player, args)
{
	if (args.len() == 2)
	{
		local func = compilestring("return ::LinGe.Config.table." + args[1]);
		try {
			ClientPrint(player, 3, "\x04" + args[1] + " = \x05" + func());
		} catch (e) {
			ClientPrint(player, 3, "\x04讀取配置失敗： \x05" + args[1]);
		}
	}
	else if (args.len() >= 3)
	{
		try {
			local type = compilestring("return typeof ::LinGe.Config.table." + args[1])();
			switch (type)
			{
			case "bool":
			case "integer":
			case "float":
				compilestring("::LinGe.Config.table." + args[1] + " = " + args[2])();
				break;
			case "string":
			{
				local str = "";
				for (local i=2; i<args.len(); i++)
				{
					if (i != 2)
						str += " ";
					str += args[i];
				}
				compilestring("::LinGe.Config.table." + args[1] + " = \"" + str + "\"")();
				break;
			}
			default:
				ClientPrint(player, 3, "\x04不支援設定該類數據： \x05" + type);
				return;
			}
		} catch (e) {
			ClientPrint(player, 3, "\x04設定配置失敗： \x05" + args[1]);
			return;
		}
		ClientPrint(player, 3, "\x04配置修改成功");
	}
	else
	{
		ClientPrint(player, 3, "\x05!config [配置專案] [修改值]");
		ClientPrint(player, 3, "\x05例：!config HUD.textHeight2 0.03 不過針對不同的配置專案，修改後可能不能立即產生效果");
	}
}
::LinCmdAdd("config", ::LinGe.Admin.Cmd_config, ::LinGe.Admin, "", true, false);

// 開啟Debug模式
::LinGe.Admin.Cmd_lsdebug <- function (player, args)
{
	if (args.len() == 2)
	{
		if (args[1] == "on")
		{
			::LinGe.Debug = true;
			Convars.SetValue("display_game_events", 1);
			Convars.SetValue("ent_messages_draw", 1);
		}
		else if (args[1] == "off")
		{
			::LinGe.Debug = false;
			Convars.SetValue("display_game_events", 0);
			Convars.SetValue("ent_messages_draw", 0);
		}
	}
}
::LinCmdAdd("lsdebug", ::LinGe.Admin.Cmd_lsdebug, ::LinGe.Admin);
//----------------------------Admin-----END---------------------------------

//------------------------------LinGe.Cache---------------------------------------
::LinGe.Cache <- { isValidCache=false }; // isValidCache指定是否是有效Cache 數據無效時不恢復

::LinGe.OnGameEvent_round_start_post_nav <- function (params)
{
	CacheRestore();
	// 以下事件應插入到最後
	::LinEventHook("OnGameEvent_round_end", ::LinGe.OnGameEvent_round_end, ::LinGe);
	::LinEventHook("OnGameEvent_map_transition", ::LinGe.OnGameEvent_round_end, ::LinGe);
}
// 如果後續插入了排序在本事件之前的回撥，那麼該回調中不應訪問cache
::LinEventHook("OnGameEvent_round_start_post_nav", ::LinGe.OnGameEvent_round_start_post_nav, ::LinGe, false);

::LinGe.OnGameEvent_round_end <- function (params)
{
	CacheSave();
}

::LinGe.CacheRestore <- function ()
{
	local temp = {};
	local _params = { isValidCache=false };
	RestoreTable("LinGe_Cache", temp);
	if (temp.rawin("isValidCache"))
	{
		if (temp.isValidCache)
		{
			::LinGe.Merge(Cache, temp, true, true);
			Cache.rawset("isValidCache", false); // 開局時儲存一個Cache 並且設定為無效
			SaveTable("LinGe_Cache", Cache);
			_params.isValidCache = true;
		}
	}
	Cache.rawset("isValidCache", _params.isValidCache);
	::LinEventTrigger("cache_restore", _params);
}

::LinGe.CacheSave <- function ()
{
	Cache.rawset("isValidCache", true);
	SaveTable("LinGe_Cache", Cache);
	::LinEventTrigger("cache_save");
}


//----------------------------Base-----START--------------------------------
::LinGe.Base <- {};
::LinGe.Base.Config <- {
	isShowTeamChange = false,
	recordPlayerInfo = false
};
::LinGe.Config.Add("Base", ::LinGe.Base.Config);
::LinGe.Cache.Base_Config <- ::LinGe.Base.Config;

// 已知玩家列表 儲存加入過伺服器玩家的SteamID與名字
const FILE_KNOWNPLAYERS = "LinGe/playerslist";
::LinGe.Base.known <- { };
::LinGe.Base.knownManager <- ::LinGe.ConfigManager(FILE_KNOWNPLAYERS);
::LinGe.Base.knownManager.Add("playerslist", ::LinGe.Base.known, true);

// 玩家資訊
::LinGe.Base.info <- {
	maxplayers = 0, // 最大玩家數量
	survivor = 0, // 生還者玩家數量
	special = 0, // 特感玩家數量
	ob = 0, // 旁觀者玩家數量
	survivorIdx = [] // 生還者實體索引
};
::pyinfo <- ::LinGe.Base.info.weakref();

::LinGe.Base.GetHumans <- function ()
{
	return ::pyinfo.ob + ::pyinfo.survivor + ::pyinfo.special;
}

local isExistMaxplayers = true;
// 事件：回合開始
::LinGe.Base.OnGameEvent_round_start <- function (params)
{
	// 目前關卡重開的話，指令碼會被重新載入，玩家數據會被清空
	// 而重開情況下玩家的隊伍不會發生改變，不會觸發事件
	// 所以需要開局時搜索玩家
	InitPyinfo();

	if (Convars.GetFloat("sv_maxplayers") != null)
		::VSLib.Timers.AddTimer(1.0, true, ::LinGe.Base.UpdateMaxplayers);
	else
		isExistMaxplayers = false;
}
::LinEventHook("OnGameEvent_round_start", ::LinGe.Base.OnGameEvent_round_start, ::LinGe.Base);

// 玩家連線事件 參數列表：
// xuid			如果是BOT就為0，是玩家會是一串數字
// address		地址，如果是BOT則為none，是本地房主則為loopback
// networkid	steamID，如果是BOT則為 "BOT"
// index		不明
// userid		userid
// name			玩家名（Linux上是Name，Windows上是name，十分奇怪）
// bot			是否為BOT
// splitscreenplayer 不明
::LinGe.Base.OnGameEvent_player_connect <- function (params)
{
	if (!params.rawin("networkid"))
		return;
	if ("BOT" == params.networkid)
		return;
	local playerName = null;
	if (params.rawin("Name")) // Win平臺和Linux平臺的name參數似乎首字母大小寫有差異
		playerName = params.Name;
	else if (params.rawin("name"))
		playerName = params.name;
	else
		return;

	if (Config.isShowTeamChange)
		ClientPrint(null, 3, "\x03"+ playerName + "\x04 正在連線");

	if (Config.recordPlayerInfo)
	{
		local uniqueID = ::LinGe.SteamIDCastUniqueID(params.networkid);
		if (uniqueID != "S00")
		{
			known.rawset(uniqueID, { SteamID=params.networkid, Name=playerName });
			knownManager.Save("playerslist");
		}
	}
}
::LinEventHook("OnGameEvent_player_connect", ::LinGe.Base.OnGameEvent_player_connect, ::LinGe.Base);

// 玩家隊伍更換事件
// team=0：玩家剛連線、和斷開連線時會被分配到此隊伍 不統計此隊伍的人數
// team=1：旁觀者 team=2：生還者 team=3：特感
::LinGe.Base.OnGameEvent_player_team <- function (_params)
{
	if (!_params.rawin("userid"))
		return;

	local params = clone _params;
	params.player <- GetPlayerFromUserID(params.userid);
	params.steamid <- params.player.GetNetworkIDString();
	// 使用外掛等方式改變陣營的時候，可能導致 params.name 為空
	// 通過GetPlayerName重新獲取會比較穩定
	params.name <- params.player.GetPlayerName();
	params.entityIndex <- params.player.GetEntityIndex();

	local idx = ::pyinfo.survivorIdx.find(params.entityIndex);
	if ( 2 == params.oldteam && null != idx )
		::pyinfo.survivorIdx.remove(idx);
	else if (2 == params.team && null == idx)
		::pyinfo.survivorIdx.append(params.entityIndex);

	// 當不是BOT時，對當前玩家人數進行更新
	// 使用外掛等方式加入bot時，params.isbot不準確 應獲取其SteamID進行判斷
	if ("BOT" != params.steamid)
	{
		// 更新玩家最大人數
		UpdateMaxplayers();
		// 更新玩家數據資訊
		switch (params.oldteam)
		{
		case 0:
			break;
		case 1:
			::pyinfo.ob--;
			break;
		case 2:
			::pyinfo.survivor--;
			break;
		case 3:
			::pyinfo.special--;
			break;
		default:
			throw "未知情況發生";
		}
		switch (params.team)
		{
		case 0:
			break;
		case 1:
			::pyinfo.ob++;
			break;
		case 2:
			::pyinfo.survivor++;
			break;
		case 3:
			::pyinfo.special++;
			break;
		default:
			throw "未知情況發生";
		}
		// 觸發真實玩家變更事件
		::LinEventTrigger("human_team_nodelay", params);
		::LinEventTrigger("human_team", params, 0.1); // 延時0.1s觸發
	}
}
::LinEventHook("OnGameEvent_player_team", ::LinGe.Base.OnGameEvent_player_team, ::LinGe.Base);

// 玩家隊伍變更提示
::LinGe.Base.human_team <- function (params)
{
	if (!Config.isShowTeamChange)
		return;

	local text = "\x03" + params.name + "\x04 ";
	switch (params.team)
	{
	case 0:
		text += "已離開";
		break;
	case 1:
		if (params.oldteam == 2 && ::LinGe.IsPlayerIdle(params.entityIndex))
			text += "已閑置";
		else
			text += "進入旁觀";
		break;
	case 2:
		text += "加入了生還者";
		break;
	case 3:
		text += "加入了感染者";
		break;
	}
	ClientPrint(null, 3, text);
}
::LinEventHook("human_team", LinGe.Base.human_team, LinGe.Base);

::LinGe.Base.Cmd_teaminfo <- function (player, args)
{
	if (1 == args.len())
	{
		Config.isShowTeamChange = !Config.isShowTeamChange;
		local text = Config.isShowTeamChange ? "開啟" : "關閉";
		ClientPrint(player, 3, "\x04伺服器已" + text + "隊伍更換提示");
	}
}
::LinCmdAdd("teaminfo", ::LinGe.Base.Cmd_teaminfo, ::LinGe.Base, "開啟或關閉玩家隊伍更換提示");

// 搜索玩家
::LinGe.Base.InitPyinfo <- function ()
{
	UpdateMaxplayers();

	local player = null; // 玩家實例
	local table = ::pyinfo;
	// 通過類名查詢玩家
	while ( player = Entities.FindByClassname(player, "player") )
	{
		// 判斷搜索到的實體有效性
		if ( player.IsValid() )
		{
			local team = ::LinGe.GetPlayerTeam(player);
			if (2 == team)
				table.survivorIdx.append(player.GetEntityIndex());
			if ("BOT" != player.GetNetworkIDString())
			{
				// 如果不是BOT，則還需對玩家人數進行修正
				switch (team)
				{
				case 1:
					table.ob++;
					break;
				case 2:
					table.survivor++;
					break;
				case 3:
					table.special++;
					break;
				}
			}
		}
	}
}

::LinGe.Base.UpdateMaxplayers <- function (params=null)
{
	local old = ::pyinfo.maxplayers;
	local new = null;
	if (isExistMaxplayers)
	{
		new = Convars.GetFloat("sv_maxplayers");
	}

	if (new == null || new < 0)
	{
		if (::LinGe.isVersus)
			::pyinfo.maxplayers = 8;
		else
			::pyinfo.maxplayers = 4;
	}
	else
		::pyinfo.maxplayers = new.tointeger();
	if (old != ::pyinfo.maxplayers)
	{
		::LinEventTrigger("maxplayers_changed");
	}
}
//----------------------------Base-----END---------------------------------
