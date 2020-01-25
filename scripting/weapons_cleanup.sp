#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma newdecls required

public Plugin myinfo =
{
	name = "Weapons Cleanup",
	author = "Ilusion9",
	description = "Maintain the specified dropped weapons in the world",
	version = "1.1",
	url = "https://github.com/Ilusion9/"
};

enum struct WeaponInfo
{
	bool hasOwner;
	bool canBePicked;
	bool mapPlaced;
	float dropTime;
}

ConVar g_Cvar_MaxWeapons;
ConVar g_Cvar_MaxC4;
WeaponInfo g_WeaponsInfo[2049];

public void OnPluginStart()
{
	g_Cvar_MaxWeapons = CreateConVar("sm_weapon_max_before_cleanup", "24", "Maintain the specified dropped weapons in the world. The C4 will be ignored.", FCVAR_NONE, true, 0.0);
	g_Cvar_MaxC4 = CreateConVar("sm_c4_max_before_cleanup", "3", "Maintain the specified dropped C4 in the world.", FCVAR_NONE, true, 0.0);
	
	AutoExecConfig(true, "weapons_cleanup");
	HookEvent("round_start", Event_RoundStart);
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
	g_WeaponsInfo[weapon].hasOwner = false;
	g_WeaponsInfo[weapon].canBePicked = view_as<bool>(GetEntProp(weapon, Prop_Data, "m_bCanBePickedUp"));
	g_WeaponsInfo[weapon].mapPlaced = false;
	g_WeaponsInfo[weapon].dropTime = 0.0;

	char classname[128];
	if (GetEntityClassname(weapon, classname, sizeof(classname)))
	{
		if (StrEqual(classname, "weapon_c4", true))
		{
			CleanC4WeaponsFromWorld(weapon);
			return;
		}
	}
	
	CleanWeaponsFromWorld(weapon);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponEquipPost, SDK_OnWeaponEquip_Post);
	SDKHook(client, SDKHook_WeaponDropPost, SDK_OnWeaponDrop_Post);
}

public void SDK_OnWeaponEquip_Post(int client, int weapon)
{
	g_WeaponsInfo[weapon].hasOwner = true;
}

public void SDK_OnWeaponDrop_Post(int client, int weapon)
{
	g_WeaponsInfo[weapon].hasOwner = false;
	g_WeaponsInfo[weapon].mapPlaced = false;
	g_WeaponsInfo[weapon].dropTime = GetGameTime();
	
	char classname[128];
	if (GetEntityClassname(weapon, classname, sizeof(classname)))
	{
		if (StrEqual(classname, "weapon_c4", true))
		{
			CleanC4WeaponsFromWorld(weapon);
			return;
		}
	}
	
	CleanWeaponsFromWorld(weapon);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) 
{
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
	{
		if (!g_WeaponsInfo[ent].hasOwner)
		{
			g_WeaponsInfo[ent].mapPlaced = true;
		}
	}
}

public void CleanC4WeaponsFromWorld(int currentWeapon)
{
	if (!g_Cvar_MaxC4.IntValue)
	{
		return;
	}
	
	int ent = -1;
	ArrayList listWeapons = new ArrayList();
	
	// Maintain the specified dropped C4 in the world
	while ((ent = FindEntityByClassname(ent, "weapon_c4")) != -1)
	{
		if (ent == currentWeapon || g_WeaponsInfo[ent].hasOwner || !g_WeaponsInfo[ent].canBePicked || g_WeaponsInfo[ent].mapPlaced)
		{
			continue;
		}
		
		listWeapons.Push(ent);
	}
	
	int maxC4 = g_WeaponsInfo[currentWeapon].hasOwner ? g_Cvar_MaxC4.IntValue : g_Cvar_MaxC4.IntValue - 1;
	if (listWeapons.Length > maxC4)
	{
		listWeapons.SortCustom(sortWeapons);
		for (int i = maxC4; i < listWeapons.Length; i++)
		{
			AcceptEntityInput(listWeapons.Get(i), "Kill");
		}
	}
	
	delete listWeapons;
}

public void CleanWeaponsFromWorld(int currentWeapon)
{
	if (!g_Cvar_MaxWeapons.IntValue)
	{
		return;
	}
	
	int ent = -1;
	char classname[128];
	ArrayList listWeapons = new ArrayList();
	
	// Maintain the specified dropped weapons in the world
	while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
	{
		if (ent == currentWeapon || g_WeaponsInfo[ent].hasOwner || !g_WeaponsInfo[ent].canBePicked || g_WeaponsInfo[ent].mapPlaced)
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
	
	int maxWeapons = g_WeaponsInfo[currentWeapon].hasOwner ? g_Cvar_MaxWeapons.IntValue : g_Cvar_MaxWeapons.IntValue - 1;
	if (listWeapons.Length > maxWeapons)
	{
		listWeapons.SortCustom(sortWeapons);
		for (int i = maxWeapons; i < listWeapons.Length; i++)
		{
			AcceptEntityInput(listWeapons.Get(i), "Kill");
		}
	}
	
	delete listWeapons;
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
