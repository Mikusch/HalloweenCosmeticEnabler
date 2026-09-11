/**
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

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>
#include <dhooks>

#define PLUGIN_VERSION "1.5.0"

enum
{
	VISION_MODE_NONE = 0,
	VISION_MODE_PYRO,
	VISION_MODE_HALLOWEEN,
	VISION_MODE_ROME,

	MAX_VISION_MODES
};

ConVar tf_enable_halloween_cosmetics;
ConVar tf_forced_holiday;
DynamicDetour g_hDetourIsHolidayActive;

bool g_bIsEnabled;
bool g_bIsMapRunning;
bool g_bNoForcedHoliday;

enum struct HealthKitEntry
{
	int iRef;
	int iModelIndex;
}

ArrayList g_hHealthKits;

public Plugin myinfo =
{
	name = "[TF2] Halloween Cosmetic Enabler",
	author = "Mikusch",
	description = "Enables Halloween cosmetics and spells regardless of current holiday",
	version = PLUGIN_VERSION,
	url = "https://github.com/Mikusch/HalloweenCosmeticEnabler"
}

public void OnPluginStart()
{
	g_hHealthKits = new ArrayList(sizeof(HealthKitEntry));

	tf_enable_halloween_cosmetics = CreateConVar("tf_enable_halloween_cosmetics", "1", "Whether to enable cosmetics and effects with a Halloween / Full Moon restriction.");
	tf_enable_halloween_cosmetics.AddChangeHook(ConVarChanged_EnableHalloweenCosmetics);

	tf_forced_holiday = FindConVar("tf_forced_holiday");

	GameData hGameConf = new GameData("hwn_cosmetic_enabler");
	if (!hGameConf)
		SetFailState("Failed to find hwn_cosmetic_enabler gamedata");

	g_hDetourIsHolidayActive = DynamicDetour.FromConf(hGameConf, "TF_IsHolidayActive");
	if (!g_hDetourIsHolidayActive)
		SetFailState("Failed to setup detour for TF_IsHolidayActive");

	delete hGameConf;
}

public void OnPluginEnd()
{
	if (g_bIsEnabled)
		TogglePlugin(false);
}

public void OnMapStart()
{
	g_bIsMapRunning = true;

	if (g_bIsEnabled)
		UpdateAllHealthKitModelOverrides(true);
}

public void OnMapEnd()
{
	g_bIsMapRunning = false;

	g_hHealthKits.Clear();
}

public void OnConfigsExecuted()
{
	if (g_bIsEnabled != tf_enable_halloween_cosmetics.BoolValue)
		TogglePlugin(tf_enable_halloween_cosmetics.BoolValue);
}

public void OnClientPutInServer(int iClient)
{
	if (!g_bIsEnabled)
		return;

	if (!IsFakeClient(iClient))
		ReplicateHolidayToClient(iClient, TFHoliday_HalloweenOrFullMoon);
}

public void OnEntityCreated(int iEntity, const char[] szClassname)
{
	if (!strncmp(szClassname, "item_health", 11))
		SDKHook(iEntity, SDKHook_SpawnPost, SDKHookCB_HealthKit_SpawnPost);
}

public void OnEntityDestroyed(int iEntity)
{
	UntrackHealthKit(iEntity);
}

public void ConVarChanged_ForcedHoliday(ConVar hConVar, const char[] szOldValue, const char[] szNewValue)
{
	// If tf_forced_holiday was changed, replicate the desired value back to each client
	TFHoliday holiday = view_as<TFHoliday>(hConVar.IntValue);
	if (holiday != TFHoliday_HalloweenOrFullMoon)
	{
		// Allow clients to react to the initial change first
		RequestFrame(RequestFrameCallback_ReplicateForcedHoliday, TFHoliday_HalloweenOrFullMoon);
	}
}

public void ConVarChanged_EnableHalloweenCosmetics(ConVar hConVar, const char[] szOldValue, const char[] szNewValue)
{
	if (g_bIsEnabled != hConVar.BoolValue)
		TogglePlugin(hConVar.BoolValue);
}

public MRESReturn DHookCallback_IsHolidayActive_Post(DHookReturn hReturn, DHookParam hParam)
{
	if (g_bNoForcedHoliday)
		return MRES_Ignored;

	TFHoliday eHoliday = hParam.Get(1);

	// Force-enable Halloween at all times unless we specifically request not to
	if (eHoliday == TFHoliday_HalloweenOrFullMoon)
	{
		hReturn.Value = true;
		return MRES_Supercede;
	}

	// Otherwise, let the game determine which holiday is active
	return MRES_Ignored;
}

public void SDKHookCB_HealthKit_SpawnPost(int iEntity)
{
	int iModelIndex = TrackHealthKit(iEntity);
	if (!iModelIndex)
		return;

	if (g_bIsEnabled && g_bIsMapRunning)
		UpdateHealthKitModelOverride(iEntity, iModelIndex, true);
}

public void RequestFrameCallback_ReplicateForcedHoliday(TFHoliday eHoliday)
{
	if (!g_bIsEnabled)
		return;

	ReplicateHolidayToAllClients(eHoliday);
}

void TogglePlugin(bool bEnable)
{
	g_bIsEnabled = bEnable;

	if (bEnable)
	{
		tf_forced_holiday.AddChangeHook(ConVarChanged_ForcedHoliday);
		g_hDetourIsHolidayActive.Enable(Hook_Post, DHookCallback_IsHolidayActive_Post);
	}
	else
	{
		tf_forced_holiday.RemoveChangeHook(ConVarChanged_ForcedHoliday);
		g_hDetourIsHolidayActive.Disable(Hook_Post, DHookCallback_IsHolidayActive_Post);
	}

	TFHoliday eHoliday = bEnable ? TFHoliday_HalloweenOrFullMoon : view_as<TFHoliday>(tf_forced_holiday.IntValue);
	ReplicateHolidayToAllClients(eHoliday);

	if (!g_bIsMapRunning)
		return;

	if (bEnable)
		TrackExistingHealthKits();

	UpdateAllHealthKitModelOverrides(bEnable);
}

void TrackExistingHealthKits()
{
	g_hHealthKits.Clear();

	int iEntity = -1;
	while ((iEntity = FindEntityByClassname(iEntity, "item_health*")) != -1)
	{
		TrackHealthKit(iEntity);
	}
}

int TrackHealthKit(int iEntity)
{
	int iModelIndex = GetEntProp(iEntity, Prop_Send, "m_nModelIndexOverrides", _, VISION_MODE_HALLOWEEN);
	if (!iModelIndex)
		return 0;

	HealthKitEntry entry;
	entry.iRef = EntIndexToEntRef(iEntity);
	entry.iModelIndex = iModelIndex;

	g_hHealthKits.PushArray(entry);

	return iModelIndex;
}

void UntrackHealthKit(int iEntity)
{
	if (!g_hHealthKits.Length)
		return;

	iEntity = EntRefToEntIndex(iEntity);
	if (iEntity == -1)
		return;

	int iIndex = g_hHealthKits.FindValue(EntIndexToEntRef(iEntity), HealthKitEntry::iRef);
	if (iIndex != -1)
		g_hHealthKits.Erase(iIndex);
}

void UpdateAllHealthKitModelOverrides(bool bEnable)
{
	HealthKitEntry entry;
	for (int i = g_hHealthKits.Length - 1; i >= 0; i--)
	{
		g_hHealthKits.GetArray(i, entry);

		int iEntity = EntRefToEntIndex(entry.iRef);
		if (iEntity == -1)
		{
			g_hHealthKits.Erase(i);
			continue;
		}

		UpdateHealthKitModelOverride(iEntity, entry.iModelIndex, bEnable);
	}
}

void UpdateHealthKitModelOverride(int iEntity, int iModelIndex, bool bEnable)
{
	if (bEnable && !IsHolidayActiveIgnoringOverride(TFHoliday_HalloweenOrFullMoon))
	{
		SetEntProp(iEntity, Prop_Send, "m_nModelIndexOverrides", 0, _, VISION_MODE_HALLOWEEN);
		return;
	}

	if (!GetEntProp(iEntity, Prop_Send, "m_nModelIndexOverrides", _, VISION_MODE_NONE))
		return;

	SetEntProp(iEntity, Prop_Send, "m_nModelIndexOverrides", iModelIndex, _, VISION_MODE_HALLOWEEN);
}

bool IsHolidayActiveIgnoringOverride(TFHoliday eHoliday)
{
	// TF2_IsHolidayActive ends up in the function we detour, ask for the game's real answer
	g_bNoForcedHoliday = true;
	bool bIsActive = TF2_IsHolidayActive(eHoliday);
	g_bNoForcedHoliday = false;

	return bIsActive;
}

void ReplicateHolidayToAllClients(TFHoliday eHoliday)
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient))
			continue;

		if (IsFakeClient(iClient))
			continue;

		ReplicateHolidayToClient(iClient, eHoliday);
	}
}

void ReplicateHolidayToClient(int iClient, TFHoliday eHoliday)
{
	char szHoliday[12];
	IntToString(view_as<int>(eHoliday), szHoliday, sizeof(szHoliday));

	// Make client code think that it is a different holiday
	tf_forced_holiday.ReplicateToClient(iClient, szHoliday);
}
