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
	/* Check if this entity is a weapon */
	if (strncmp(classname, "weapon_", 7, true) != 0)
	{
		return;
	}
	
	/* Hook this entity spawn event */
	SDKHook(entity, SDKHook_SpawnPost, Event_WeaponSpawn);
}

public void OnClientPutInServer(int client)
{
	/* Hook the weapon drop event */
	SDKHook(client, SDKHook_WeaponDropPost, Event_WeaponDrop);
}

public void Event_WeaponSpawn(int weapon)
{
	g_WeaponDropTime[weapon] = 0.0;
	
	/* Maintain the specified dropped weapons in the world */
	RemoveWeaponsFromWorld(weapon);
}

public void Event_WeaponDrop(int client, int weapon)
{
	g_WeaponDropTime[weapon] = GetGameTime();
	
	/* Maintain the specified dropped weapons in the world */	
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
		/* Check if someone is equipped with a c4 */
		if (GetEntityOwner(c4) != -1)
		{
			c4 = -1; // someone is equipped with c4, count all dropped c4s for removal
			break;
		}
	}
		
	/* Get all dropped weapons */
	while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
	{
		/* Skip the current weapon spawned or dropped and skip that c4 dropped */
		if (ent == currentWeapon || ent == c4)
		{
			continue;
		}
		
		/* Check if this entity can be picked up */
		if (!CanBePickedUp(ent))
		{
			continue;
		}
		
		/* Check if this entity is dropped */
		if (GetEntityOwner(ent) != -1)
		{
			continue;
		}
		
		listWeapons.Push(ent);
	}
	
	/* Check of there are two many dropped weapons in the world */
	if (listWeapons.Length > g_Cvar_MaxWeapons.IntValue - 1)
	{
		/* Sort all found weapons by drop time */
		listWeapons.SortCustom(sortWeapons);
		
		/* Remove the oldest dropped weapons from the world */
		for (int i = g_Cvar_MaxWeapons.IntValue - 1; i < listWeapons.Length; i++)
		{
			AcceptEntityInput(listWeapons.Get(i), "Kill");
		}
	}
	
	delete listWeapons;
}

public int sortWeapons(int index1, int index2, Handle array, Handle hndl)
{
	/* Get the two comparable weapons from the list */
	int weapon1 = view_as<ArrayList>(array).Get(index1);
	int weapon2 = view_as<ArrayList>(array).Get(index2);
	
	/* Compare these weapons by drop time */
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
