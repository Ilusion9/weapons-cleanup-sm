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

ConVar g_Cvar_MaxWeapons;
ConVar g_Cvar_MaxC4;

float g_WeaponDropTime[2049];

public void OnPluginStart()
{
	g_Cvar_MaxWeapons = CreateConVar("sm_weapon_max_before_cleanup", "24", "Maintain the specified dropped weapons in the world.", FCVAR_NONE);
	g_Cvar_MaxC4 = CreateConVar("sm_c4_max_before_cleanup", "5", "Maintain the specified dropped c4s in the world.", FCVAR_NONE);

	AutoExecConfig(true, "weapons_cleanup");
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (strncmp(classname, "weapon_", 7, true) != 0)
	{
		return;
	}
	
	SDKHook(entity, SDKHook_SpawnPost, Event_WeaponSpawn);
}

public void Event_WeaponSpawn(int entity)
{
	g_WeaponDropTime[entity] = 0.0;
	RemoveWeaponsFromWorld(entity);
}

public Action CS_OnCSWeaponDrop(int client, int weaponIndex)
{
	if (weaponIndex != -1)
	{
		g_WeaponDropTime[weaponIndex] = GetGameTime();
		RemoveWeaponsFromWorld(weaponIndex);
	}
}

public void RemoveWeaponsFromWorld(int currentWeapon)
{
	if (g_Cvar_MaxWeapons.IntValue < 1)
	{
		return;
	}
	
	int ent = -1;
	ArrayList listWeapons = new ArrayList();
	
	while ((ent = FindEntityByClassname(ent, "weapon_c4")) != -1)
	{
		if (ent == currentWeapon || !CanBePickedUp(ent) || GetEntityOwner(ent) != -1)
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
	
	ent = -1;
	listWeapons.Clear();
	char classname[65];
	
	while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
	{
		if (ent == currentWeapon || !CanBePickedUp(ent) || GetEntityOwner(ent) != -1)
		{
			continue;
		}
		
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
	
	if (g_WeaponDropTime[weapon1] < g_WeaponDropTime[weapon2])
	{
		return 1;
	}
	
	if (g_WeaponDropTime[weapon1] > g_WeaponDropTime[weapon2])
	{
		return -1;
	}
	
	return 0;
}

bool CanBePickedUp(int entity)
{
	return view_as<bool>(GetEntProp(entity, Prop_Data, "m_bCanBePickedUp"));
}

int GetEntityOwner(int entity)
{
	return GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
}
