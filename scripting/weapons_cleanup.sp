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
float g_WeaponDropTime[2049];

public void OnPluginStart()
{
	g_Cvar_MaxWeapons = CreateConVar("sm_weapon_max_before_cleanup", "24", "Maintain the specified dropped weapons in the world.", FCVAR_NONE);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (strncmp(classname, "weapon_", 7, true) != 0)
	{
		return;
	}
	
	SDKHook(entity, SDKHook_SpawnPost, Event_WeaponSpawn);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponDropPost, Event_WeaponDrop);
}

public void Event_WeaponSpawn(int weapon)
{
	g_WeaponDropTime[weapon] = 0.0;
	RemoveWeaponsFromWorld(weapon);
}

public void Event_WeaponDrop(int client, int weapon)
{
	g_WeaponDropTime[weapon] = GetGameTime();
	RemoveWeaponsFromWorld(weapon);
}

public void RemoveWeaponsFromWorld(int currentWeapon)
{
	if (g_Cvar_MaxWeapons.IntValue < 1)
	{
		return;
	}
	
	int ent = -1, c4 = -1;
	ArrayList listWeapons = new ArrayList();
	
	/* Keep at least one c4 dropped in the world if no player has one */
	while ((c4 = FindEntityByClassname(c4, "weapon_c4")) != -1)
	{
		if (GetEntityOwner(c4) != -1)
		{
			c4 = -1;
			break;
		}
	}
		
	while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
	{
		if (ent == currentWeapon || ent == c4)
		{
			continue;
		}
		
		if (!CanBePickedUp(ent))
		{
			continue;
		}
		
		if (GetEntityOwner(ent) != -1)
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
