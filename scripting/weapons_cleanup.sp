#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma newdecls required

public Plugin myinfo =
{
	name = "Weapons Cleanup",
	author = "Ilusion9",
	description = "Maintain the specified dropped weapons in the world",
	version = "1.0",
	url = "https://github.com/Ilusion9/"
};

enum struct WeaponInfo
{
	bool mapPlaced;
	float dropTime;
}

WeaponInfo g_WeaponInfo[2049];

ConVar g_Cvar_MaxWeapons;
ConVar g_Cvar_MaxBombs;

public void OnPluginStart()
{
	g_Cvar_MaxWeapons = CreateConVar("sm_weapon_max_before_cleanup", "24", "Maintain the specified dropped weapons in the world. The c4 bombs will be ignored.", FCVAR_NONE);
	g_Cvar_MaxBombs = CreateConVar("sm_c4_max_before_cleanup", "3", "Maintain the specified dropped c4 bombs in the world.", FCVAR_NONE);
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
		RemoveBombsFromWorld(entity);
	}
	else
	{
		RemoveWeaponsFromWorld(entity);
	}
}

public Action CS_OnCSWeaponDrop(int client, int weaponIndex)
{
	if (weaponIndex != -1)
	{
		g_WeaponInfo[weaponIndex].mapPlaced = false;
		g_WeaponInfo[weaponIndex].dropTime = GetGameTime();
		
		char classname[128];
		GetEntityClassname(weaponIndex, classname, sizeof(classname));
		
		if (StrEqual(classname, "weapon_c4", true))
		{
			RemoveBombsFromWorld(weaponIndex);
		}
		else
		{
			RemoveWeaponsFromWorld(weaponIndex);
		}
	}
}

public void RemoveBombsFromWorld(int currentWeapon)
{
	if (g_Cvar_MaxBombs.IntValue == 0)
	{
		return;
	}
	
	int ent = -1;
	ArrayList listWeapons = new ArrayList();
	
	// Maintain the specified dropped c4s in the world
	while ((ent = FindEntityByClassname(ent, "weapon_c4")) != -1)
	{
		if (ent == currentWeapon || GetEntityOwner(ent) != -1 || g_WeaponInfo[ent].mapPlaced)
		{
			continue;
		}
		
		listWeapons.Push(ent);
	}
	
	if (listWeapons.Length > g_Cvar_MaxBombs.IntValue - 1)
	{
		listWeapons.SortCustom(sortWeapons);
		for (int i = g_Cvar_MaxBombs.IntValue - 1; i < listWeapons.Length; i++)
		{
			AcceptEntityInput(listWeapons.Get(i), "Kill");
		}
	}
	
	delete listWeapons;
}

public void RemoveWeaponsFromWorld(int currentWeapon)
{
	if (g_Cvar_MaxWeapons.IntValue == 0)
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
