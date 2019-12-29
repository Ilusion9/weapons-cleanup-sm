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
	bool mapPlaced;
	float dropTime;
}

WeaponInfo g_WeaponInfo[2049];

ConVar g_Cvar_MaxWeapons;
ConVar g_Cvar_MaxC4;

public void OnPluginStart()
{
	g_Cvar_MaxWeapons = CreateConVar("sm_weapon_max_before_cleanup", "24", "Maintain the specified dropped weapons in the world. The C4 will be ignored.", FCVAR_NONE, true, 0.0);
	g_Cvar_MaxC4 = CreateConVar("sm_c4_max_before_cleanup", "3", "Maintain the specified dropped C4 in the world.", FCVAR_NONE, true, 0.0);
	AutoExecConfig(true, "weapons_cleanup");
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (strncmp(classname, "weapon_", 7, true) != 0)
	{
		return;
	}
	
	SDKHook(entity, SDKHook_SpawnPost, SDK_OnEntitySpawn_Post);
}

public void SDK_OnEntitySpawn_Post(int entity)
{
	g_WeaponInfo[entity].mapPlaced = true;
	g_WeaponInfo[entity].dropTime = 0.0;
	
	char classname[128];
	GetEntityClassname(entity, classname, sizeof(classname));
	
	if (StrEqual(classname, "weapon_c4", true))
	{
		CleanC4FromWorld(entity);
	}
	else
	{
		CleanWeaponsFromWorld(entity);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponDropPost, SDK_OnWeaponDrop_Post);
}

public void SDK_OnWeaponDrop_Post(int client, int weapon)
{
	g_WeaponInfo[weapon].mapPlaced = false;
	g_WeaponInfo[weapon].dropTime = GetGameTime();
	
	char classname[128];
	GetEntityClassname(weapon, classname, sizeof(classname));
	
	if (StrEqual(classname, "weapon_c4", true))
	{
		CleanC4FromWorld(weapon);
	}
	else
	{
		CleanWeaponsFromWorld(weapon);
	}
}

public void CleanC4FromWorld(int currentWeapon)
{
	if (g_Cvar_MaxC4.IntValue < 1)
	{
		return;
	}
	
	int ent = -1;
	ArrayList listWeapons = new ArrayList();
	
	// Maintain the specified dropped C4 in the world
	while ((ent = FindEntityByClassname(ent, "weapon_c4")) != -1)
	{
		if (ent == currentWeapon || GetEntityOwner(ent) != -1 || g_WeaponInfo[ent].mapPlaced)
		{
			continue;
		}
		
		listWeapons.Push(ent);
	}
	
	if (listWeapons.Length > g_Cvar_MaxC4.IntValue - 1)
	{
		listWeapons.SortCustom(sortWeapons);
		for (int i = g_Cvar_MaxC4.IntValue - 1; i < listWeapons.Length; i++)
		{
			AcceptEntityInput(listWeapons.Get(i), "Kill");
		}
	}
	
	delete listWeapons;
}

public void CleanWeaponsFromWorld(int currentWeapon)
{
	if (g_Cvar_MaxWeapons.IntValue < 1)
	{
		return;
	}
	
	int ent = -1;
	ArrayList listWeapons = new ArrayList();

	// Maintain the specified dropped weapons in the world
	while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
	{
		if (ent == currentWeapon || GetEntityOwner(ent) != -1 || g_WeaponInfo[ent].mapPlaced)
		{
			continue;
		}
		
		char classname[128];
		GetEntityClassname(ent, classname, sizeof(classname));
		
		if (StrEqual(classname, "weapon_c4", true))
		{
			continue;
		}
		
		listWeapons.Push(ent);
	}
	
	if (listWeapons.Length > g_Cvar_MaxWeapons.IntValue - 1)
	{
		listWeapons.SortCustom(sortWeapons);
		for (int i = g_Cvar_MaxWeapons.IntValue - 1; i < listWeapons.Length; i++)
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
	
	if (g_WeaponInfo[weapon1].dropTime < g_WeaponInfo[weapon2].dropTime)
	{
		return 1;
	}
	
	if (g_WeaponInfo[weapon1].dropTime > g_WeaponInfo[weapon2].dropTime)
	{
		return -1;
	}
	
	return 0;
}

int GetEntityOwner(int entity)
{
	return GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
}
