/*
 * Copyright (C) 2022  Mikusch
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>
#include <dhooks>

ConVar tf_forced_holiday;

bool g_bIsMapRunning;
bool g_bNoForcedHoliday;

public Plugin myinfo =
{
	name = "[TF2] Halloween Cosmetic Enabler",
	author = "Mikusch",
	description = "Enables Halloween cosmetics and spells regardless of current holiday",
	version = "1.2.0",
	url = "https://github.com/Mikusch/HalloweenCosmeticEnabler"
}

public void OnPluginStart()
{
	tf_forced_holiday = FindConVar("tf_forced_holiday");
	tf_forced_holiday.AddChangeHook(ConVarChanged_ForcedHoliday);
	
	GameData gamedata = new GameData("hwn_cosmetic_enabler");
	if (gamedata)
	{
		DynamicDetour detour = DynamicDetour.FromConf(gamedata, "CLogicOnHoliday::InputFire");
		if (detour)
		{
			if (!detour.Enable(Hook_Pre, DHookCallback_InputFire_Pre))
				LogError("Failed to enable pre detour for CLogicOnHoliday::InputFire");
			
			if (!detour.Enable(Hook_Post, DHookCallback_InputFire_Post))
				LogError("Failed to enable post detour for CLogicOnHoliday::InputFire");
		}
		else
		{
			LogError("Failed to setup detour for CTFPlayer::InputFire");
		}
		
		delete gamedata;
	}
	
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
			OnClientPutInServer(client);
	}
}

public void OnMapStart()
{
	g_bIsMapRunning = true;
}

public void OnMapEnd()
{
	g_bIsMapRunning = false;
}

public Action TF2_OnIsHolidayActive(TFHoliday holiday, bool &result)
{
	// Force-enable Halloween at all times
	if (holiday == TFHoliday_HalloweenOrFullMoon && !g_bNoForcedHoliday)
	{
		result = true;
		return Plugin_Changed;
	}
	
	// Otherwise, let the game determine which holiday is active
	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client))
		ReplicateHolidayToClient(client, TFHoliday_HalloweenOrFullMoon);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (!g_bIsMapRunning)
		return;
	
	if (!strncmp(classname, "item_healthkit_", 15))
		SDKHook(entity, SDKHook_SpawnPost, SDKHookCB_HealthKit_SpawnPost);
}

public MRESReturn DHookCallback_InputFire_Pre(int entity, DHookParam param)
{
	// Prevent tf_logic_on_holiday from assuming it's always Halloween
	g_bNoForcedHoliday = true;
	
	return MRES_Ignored;
}

public MRESReturn DHookCallback_InputFire_Post(int entity, DHookParam param)
{
	g_bNoForcedHoliday = false;
	
	return MRES_Ignored;
}

public void SDKHookCB_HealthKit_SpawnPost(int entity)
{
	// Force non-holiday model index unless it's Halloween or Full Moon
	if (!TF2_IsHolidayActive(TFHoliday_HalloweenOrFullMoon))
		SetEntProp(entity, Prop_Send, "m_nModelIndexOverrides", 0, _, 2);
}

public void ConVarChanged_ForcedHoliday(ConVar convar, const char[] oldValue, const char[] newValue)
{
	// If tf_forced_holiday was changed, replicate the desired value back to each client
	if (view_as<TFHoliday>(convar.IntValue) != TFHoliday_HalloweenOrFullMoon)
	{
		// Delay by a frame to allow clients to react to the initial change first
		RequestFrame(RequestFrameCallback_ReplicateForcedHoliday);
	}
}

public void RequestFrameCallback_ReplicateForcedHoliday()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client))
			ReplicateHolidayToClient(client, TFHoliday_HalloweenOrFullMoon);
	}
}

void ReplicateHolidayToClient(int client, TFHoliday holiday)
{
	// Replicate the value of tf_forced_holiday to the client to allow spells to work
	char value[8];
	if (IntToString(view_as<int>(holiday), value, sizeof(value)))
		tf_forced_holiday.ReplicateToClient(client, value);
}
