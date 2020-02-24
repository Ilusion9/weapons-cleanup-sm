#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#pragma newdecls required

public Plugin myinfo =
{
	name = "Weapons Cleanup",
	author = "Ilusion9",
	description = "Maintain the specified dropped weapons in the world.",
	version = "1.2",
	url = "https://github.com/Ilusion9/"
};

#define MAXENTITIES 2048
enum EventType
{
	WeaponSpawn,
	WeaponDrop
}

enum struct WeaponInfo
{
	bool mapPlaced;
	float dropTime;
}

ConVar g_Cvar_MaxWeapons;
ConVar g_Cvar_MaxC4;
WeaponInfo g_WeaponsInfo[MAXENTITIES + 1];

public void OnPluginStart()
{
	g_Cvar_MaxWeapons = CreateConVar("sm_weapon_max_before_cleanup", "24", "Maintain the specified dropped weapons in the world. The C4 will be ignored.", FCVAR_PROTECTED, true, 0.0);
	g_Cvar_MaxWeapons.AddChangeHook(ConVarChange_MaxWeapons);
	
	g_Cvar_MaxC4 = CreateConVar("sm_c4_max_before_cleanup", "3", "Maintain the specified dropped C4 in the world.", FCVAR_PROTECTED, true, 0.0);
	g_Cvar_MaxC4.AddChangeHook(ConVarChange_MaxC4);

	AutoExecConfig(true, "weapons_cleanup");
	HookEvent("round_start", Event_RoundStart);
}

public void ConVarChange_MaxWeapons(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!g_Cvar_MaxWeapons.IntValue)
	{
		return;
	}
	
	int value = StringToInt(oldValue);
	if (!value || g_Cvar_MaxWeapons.IntValue < value)
	{
		KeepMaxDroppedWeapons_ConVarChange(false);
	}
}

public void ConVarChange_MaxC4(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!g_Cvar_MaxC4.IntValue)
	{
		return;
	}
	
	int value = StringToInt(oldValue);
	if (!value || g_Cvar_MaxC4.IntValue < value)
	{
		KeepMaxDroppedWeapons_ConVarChange(true);
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (strncmp(classname, "weapon_", 7, true) == 0)
	{
		SDKHook(entity, SDKHook_SpawnPost, SDK_OnWeaponSpawn_Post);
	}
}

public void SDK_OnWeaponSpawn_Post(int weapon)
{
	g_WeaponsInfo[weapon].mapPlaced = false;
	g_WeaponsInfo[weapon].dropTime = 0.0;
	
	char classname[65];
	bool caseC4 = GetEntityClassname(weapon, classname, sizeof(classname)) && StrEqual(classname, "weapon_c4", true);
	KeepMaxDroppedWeapons(weapon, WeaponSpawn, caseC4);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponDropPost, SDK_OnWeaponDrop_Post);
}

public void SDK_OnWeaponDrop_Post(int client, int weapon)
{
	g_WeaponsInfo[weapon].mapPlaced = false;
	g_WeaponsInfo[weapon].dropTime = GetGameTime();
	
	char classname[65];
	bool caseC4 = GetEntityClassname(weapon, classname, sizeof(classname)) && StrEqual(classname, "weapon_c4", true);
	KeepMaxDroppedWeapons(weapon, WeaponDrop, caseC4);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) 
{
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
	{
		if (GetEntityOwner(ent) != -1)
		{
			continue;
		}
		
		g_WeaponsInfo[ent].mapPlaced = true;
	}
}

void KeepMaxDroppedWeapons(int currentWeapon, EventType eventType, bool caseC4)
{
	if (caseC4)
	{
		if (!g_Cvar_MaxC4.IntValue)
		{
			return;
		}
		
		int ent = -1, toRemove = -1, droppedWeapons = 0;
		while ((ent = FindEntityByClassname(ent, "weapon_c4")) != -1)
		{
			if (ent == currentWeapon || GetEntityOwner(ent) != -1 || !CanBePickedUp(ent) || g_WeaponsInfo[ent].mapPlaced)
			{
				continue;
			}
			
			droppedWeapons++;
			if (toRemove != -1)
			{
				if (g_WeaponsInfo[ent].dropTime < g_WeaponsInfo[toRemove].dropTime)
				{
					toRemove = ent;
				}
			}
			else
			{
				toRemove = ent;
			}
		}
		
		int maxC4 = eventType != WeaponDrop ? g_Cvar_MaxC4.IntValue : g_Cvar_MaxC4.IntValue - 1;
		if (droppedWeapons > maxC4)
		{
			AcceptEntityInput(toRemove, "Kill");
		}
	}
	else
	{
		if (!g_Cvar_MaxWeapons.IntValue)
		{
			return;
		}
		
		char classname[64];
		int ent = -1, toRemove = -1, droppedWeapons = 0;

		while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
		{
			if (ent == currentWeapon || GetEntityOwner(ent) != -1 || !CanBePickedUp(ent) || g_WeaponsInfo[ent].mapPlaced)
			{
				continue;
			}
			
			if (GetEntityClassname(ent, classname, sizeof(classname)))
			{
				if (StrEqual(classname, "weapon_c4", true))
				{
					continue;
				}
			}
			
			droppedWeapons++;
			if (toRemove != -1)
			{
				if (g_WeaponsInfo[ent].dropTime < g_WeaponsInfo[toRemove].dropTime)
				{
					toRemove = ent;
				}
			}
			else
			{
				toRemove = ent;
			}
		}
		
		int maxWeapons = eventType != WeaponDrop ? g_Cvar_MaxWeapons.IntValue : g_Cvar_MaxWeapons.IntValue - 1;
		if (droppedWeapons > maxWeapons)
		{
			AcceptEntityInput(toRemove, "Kill");
		}
	}
}

void KeepMaxDroppedWeapons_ConVarChange(bool caseC4)
{
	ArrayList listWeapons = new ArrayList();
	
	if (caseC4)
	{
		int ent = -1;
		while ((ent = FindEntityByClassname(ent, "weapon_c4")) != -1)
		{
			if (GetEntityOwner(ent) != -1 || !CanBePickedUp(ent) || g_WeaponsInfo[ent].mapPlaced)
			{
				continue;
			}
			
			listWeapons.Push(ent);
		}
		
		if (listWeapons.Length > g_Cvar_MaxC4.IntValue)
		{
			listWeapons.SortCustom(sortWeapons);
			for (int i = g_Cvar_MaxC4.IntValue; i < listWeapons.Length; i++)
			{
				AcceptEntityInput(listWeapons.Get(i), "Kill");
			}
		}
	}
	else
	{
		int ent = -1;
		char classname[64];
		
		while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
		{
			if (GetEntityOwner(ent) != -1 || !CanBePickedUp(ent) || g_WeaponsInfo[ent].mapPlaced)
			{
				continue;
			}
			
			if (GetEntityClassname(ent, classname, sizeof(classname)))
			{
				if (StrEqual(classname, "weapon_c4", true))
				{
					continue;
				}
			}
			
			listWeapons.Push(ent);
		}
		
		if (listWeapons.Length > g_Cvar_MaxWeapons.IntValue)
		{
			listWeapons.SortCustom(sortWeapons);
			for (int i = g_Cvar_MaxWeapons.IntValue; i < listWeapons.Length; i++)
			{
				AcceptEntityInput(listWeapons.Get(i), "Kill");
			}
		}
	}
	
	delete listWeapons;
}

int GetEntityOwner(int entity)
{
	return GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
}

bool CanBePickedUp(int entity)
{
	return view_as<bool>(GetEntProp(entity, Prop_Data, "m_bCanBePickedUp"));
}

public int sortWeapons(int index1, int index2, Handle array, Handle hndl)
{
	int weapon1 = view_as<ArrayList>(array).Get(index1);
	int weapon2 = view_as<ArrayList>(array).Get(index2);
	
	if (g_WeaponsInfo[weapon1].dropTime < g_WeaponsInfo[weapon2].dropTime)
	{
		return 1;
	}
	
	if (g_WeaponsInfo[weapon1].dropTime > g_WeaponsInfo[weapon2].dropTime)
	{
		return -1;
	}
	
	return 0;
}
