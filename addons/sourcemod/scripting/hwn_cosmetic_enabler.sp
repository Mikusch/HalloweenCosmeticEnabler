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
#include <dhooks>
#include <tf2_stocks>

#define NULL	0

ConVar tf_forced_holiday;

int g_OffsetHolidayRestriction;

DynamicDetour g_DHookGetStaticData;
DynamicHook g_DHookModifyOrAppendCriteria;
Handle g_SDKCallFindCriterionIndex;
Handle g_SDKCallRemoveCriteria;

bool g_ForceHalloweenOrFullMoonActive;

public Plugin myinfo =
{
	name = "[TF2] Halloween Cosmetic Enabler",
	author = "Mikusch",
	description = "Enables Halloween cosmetics and spells regardless of current holiday",
	version = "1.0.0",
	url = "https://github.com/Mikusch/HalloweenCosmeticEnabler"
}

public void OnPluginStart()
{
	tf_forced_holiday = FindConVar("tf_forced_holiday");
	tf_forced_holiday.AddChangeHook(ConVarChanged_ForcedHoliday);
	
	GameData gamedata = new GameData("hwn_cosmetic_enabler");
	if (gamedata)
	{
		g_OffsetHolidayRestriction = gamedata.GetOffset("CEconItemDefinition::m_pszHolidayRestriction");
		if (!g_OffsetHolidayRestriction)
			LogError("Failed to find offset for CEconItemDefinition::m_pszHolidayRestriction");
		
		g_DHookGetStaticData = DynamicDetour.FromConf(gamedata, "CEconItemView::GetStaticData");
		if (g_DHookGetStaticData)
		{
			if (!g_DHookGetStaticData.Enable(Hook_Post, DHookCallback_GetStaticData_Post))
				LogError("Failed to enable post detour for CEconItemView::GetStaticData");
		}
		else
		{
			LogError("Failed to setup detour for CEconItemView::GetStaticData");
		}
		
		g_DHookModifyOrAppendCriteria = DynamicHook.FromConf(gamedata, "CBaseEntity::ModifyOrAppendCriteria");
		if (!g_DHookModifyOrAppendCriteria)
			LogError("Failed to find offset for CBaseEntity::ModifyOrAppendCriteria");
		
		StartPrepSDKCall(SDKCall_Raw);
		PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "AI_CriteriaSet::FindCriterionIndex");
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
		g_SDKCallFindCriterionIndex = EndPrepSDKCall();
		if (!g_SDKCallFindCriterionIndex)
			LogError("Failed to create SDKCall: AI_CriteriaSet::FindCriterionIndex");
		
		StartPrepSDKCall(SDKCall_Raw);
		PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "AI_CriteriaSet::RemoveCriteria");
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		g_SDKCallRemoveCriteria = EndPrepSDKCall();
		if (!g_SDKCallRemoveCriteria)
			LogError("Failed to create SDKCall: AI_CriteriaSet::RemoveCriteria");
		
		delete gamedata;
	}
	
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
			OnClientPutInServer(client);
	}
}

public Action TF2_OnIsHolidayActive(TFHoliday holiday, bool &result)
{
	// Force-enable Halloween or Full Moon if our code requests it
	if (g_ForceHalloweenOrFullMoonActive && holiday == TFHoliday_HalloweenOrFullMoon)
	{
		result = true;
		return Plugin_Changed;
	}
	
	// Otherwise, let the game determine which holiday is active
	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	if (g_DHookModifyOrAppendCriteria)
	{
		if (g_DHookModifyOrAppendCriteria.HookEntity(Hook_Pre, client, DHookCallback_ModifyOrAppendCriteria_Pre) == INVALID_HOOK_ID)
			LogError("Failed to hook entity %d for pre virtual hook CBaseEntity::ModifyOrAppendCriteria", client);
		
		if (g_DHookModifyOrAppendCriteria.HookEntity(Hook_Post, client, DHookCallback_ModifyOrAppendCriteria_Post) == INVALID_HOOK_ID)
			LogError("Failed to hook entity %d for post virtual hook CBaseEntity::ModifyOrAppendCriteria", client);
	}
	
	if (!IsFakeClient(client))
		ReplicateHalloweenOrFullMoonToClient(client);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	// Remove halloween health kit models, unless it's actually Halloween or Full Moon
	if (!strncmp(classname, "item_healthkit_", 15))
		SDKHook(entity, SDKHook_SpawnPost, SDKHookCB_HealthKit_SpawnPost);
}

public MRESReturn DHookCallback_GetStaticData_Post(DHookReturn ret)
{
	// CEconItemDefinition
	Address itemDef = view_as<Address>(ret.Value);
	
	// Set m_pszHolidayRestriction to NULL to remove any holiday restrictions on econ items
	StoreToAddress(itemDef + view_as<Address>(g_OffsetHolidayRestriction), NULL, NumberType_Int32);
	
	return MRES_Ignored;
}

public MRESReturn DHookCallback_ModifyOrAppendCriteria_Pre(int entity, DHookParam param)
{
	// Allow users of Halloween costume sets to use custom voice lines
	g_ForceHalloweenOrFullMoonActive = true;
	
	return MRES_Ignored;
}

public MRESReturn DHookCallback_ModifyOrAppendCriteria_Post(int entity, DHookParam param)
{
	g_ForceHalloweenOrFullMoonActive = false;
	
	// Suppress the Thriller taunt unless it's Halloween or the Thriller condition was added
	if (!TF2_IsHolidayActive(TFHoliday_Halloween) && !TF2_IsPlayerInCondition(entity, TFCond_HalloweenThriller))
	{
		// AI_CriteriaSet
		int criteriaSet = param.Get(1);
		
		if (FindCriterionIndex(criteriaSet, "IsHalloweenTaunt") != -1)
			RemoveCriteria(criteriaSet, "IsHalloweenTaunt");
	}
	
	return MRES_Ignored;
}

public void SDKHookCB_HealthKit_SpawnPost(int iEntity)
{
	// Force non-holiday model index unless it's Halloween or Full Moon
	if (!TF2_IsHolidayActive(TFHoliday_HalloweenOrFullMoon))
	{
		SetEntProp(iEntity, Prop_Send, "m_nModelIndexOverrides", 0, _, 2);
	}
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
			ReplicateHalloweenOrFullMoonToClient(client);
	}
}

void ReplicateHalloweenOrFullMoonToClient(int client)
{
	// Replicate the value of tf_forced_holiday to the client to allow spells to work
	char value[8];
	if (IntToString(view_as<int>(TFHoliday_HalloweenOrFullMoon), value, sizeof(value)))
		tf_forced_holiday.ReplicateToClient(client, value);
}

int FindCriterionIndex(int criteriaSet, const char[] criteria)
{
	if (g_SDKCallFindCriterionIndex)
		return SDKCall(g_SDKCallFindCriterionIndex, criteriaSet, criteria);
	
	return -1;
}

void RemoveCriteria(int criteriaSet, const char[] criteria)
{
	if (g_SDKCallRemoveCriteria)
		SDKCall(g_SDKCallRemoveCriteria, criteriaSet, criteria);
}
