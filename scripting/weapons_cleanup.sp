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
float g_WeaponDropTime[2049]; // IntMaps are not available ...

public void OnPluginStart()
{
	g_Cvar_MaxWeapons = CreateConVar("sm_weapon_max_before_cleanup", "24", "Maintain the specified dropped weapons in the world.", FCVAR_NONE);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	/* Check if this entity is not a weapon */
	if (strncmp(classname, "weapon_", 7, true) != 0)
	{
		return;
	}
	
	/* Hook this weapon spawn event */
	SDKHook(entity, SDKHook_SpawnPost, Event_WeaponSpawn);
}

public void OnClientPutInServer(int client)
{
	/* Hook the drop weapon event */
	SDKHook(client, SDKHook_WeaponDropPost, Event_WeaponDrop);
}

public void Event_WeaponSpawn(int weapon)
{
	g_WeaponDropTime[weapon] = 0.0;
	
	/* Check if there are too many dropped weapons in the world */
	RemoveWeaponsFromWorld(weapon);
}

public void Event_WeaponDrop(int client, int weapon)
{
	/* Set the drop time for this weapon */
	g_WeaponDropTime[weapon] = GetGameTime();
	
	/* Check if there are too many dropped weapons in the world */
	RemoveWeaponsFromWorld(weapon);
}

public void RemoveWeaponsFromWorld(int currentWeapon)
{
	if (g_Cvar_MaxWeapons.IntValue < 1)
	{
		return;
	}
	
	int ent = -1, bomb = -1;
	ArrayList listWeapons = new ArrayList();
	
	/* Keep at least one c4 on the ground */
	while ((bomb = FindEntityByClassname(bomb, "weapon_c4")) != -1)
	{
		/* If someone is equipped with a c4, count all dropped c4s for removal */
		if (GetEntPropEnt(bomb, Prop_Data, "m_hOwnerEntity") != -1)
		{
			bomb = -1;
			break;
		}
	}
	
	while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
	{
		/* Skip the current weapon spawned or dropped */
		/* Skip a c4 dropped on the ground */ 
		if (ent == currentWeapon || ent == bomb)
		{
			continue;
		}
		
		/* Check if this weapon can be picked up */
		if (!GetEntProp(ent, Prop_Data, "m_bCanBePickedUp"))
		{
			continue;
		}
		
		/* Check if this weapon is dropped on the ground */
		if (GetEntPropEnt(ent, Prop_Data, "m_hOwnerEntity") != -1)
		{
			continue;
		}
		
		listWeapons.Push(ent);
	}
	
	/* Check if there are more dropped weapons than the specified limit */
	if (listWeapons.Length > g_Cvar_MaxWeapons.IntValue - 1)
	{
		/* Sort the dropped weapons by drop time */
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
