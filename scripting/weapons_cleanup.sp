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

StringMap g_Map_WeaponDropTime;
ConVar g_Cvar_MaxWeapons;

public void OnPluginStart()
{
	g_Map_WeaponDropTime = new StringMap();
	g_Cvar_MaxWeapons = CreateConVar("sm_weapon_max_before_cleanup", "32", "Maintain the specified dropped weapons in the world.", FCVAR_NONE);
}

public void OnMapStart()
{
	g_Map_WeaponDropTime.Clear();
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponDropPost, SDK_WeaponDropPost);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrContains(classname, "weapon_", false) != -1)
	{
		SDKHook(entity, SDKHook_SpawnPost, SDK_WeaponSpawnPost);
	}
}

public void OnEntityDestroyed(int entity)
{
	char entRef[64];
	IntToString(EntIndexToEntRef(entity), entRef, sizeof(entRef));
	g_Map_WeaponDropTime.Remove(entRef);
}

public void SDK_WeaponSpawnPost(int entity)
{
	RequestFrame(RemoveWeaponsFromWorld, EntIndexToEntRef(entity));
}

public void SDK_WeaponDropPost(int client, int weapon)
{
	int weaponRef = EntIndexToEntRef(weapon);
	
	char entRef[64];
	IntToString(weaponRef, entRef, sizeof(entRef));
	
	g_Map_WeaponDropTime.SetValue(entRef, GetGameTime());
	RequestFrame(RemoveWeaponsFromWorld, weaponRef);
}

public void RemoveWeaponsFromWorld(any data)
{
	if (g_Cvar_MaxWeapons.IntValue < 1)
	{
		return;
	}
	
	int ent = -1;
	int skipEntRef = view_as<int>(data);
	ArrayList listWeapons = new ArrayList();
	
	while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
	{
		int entRef = EntIndexToEntRef(ent);
		
		/* Skip the current weapon spawned or dropped */
		if (entRef == skipEntRef)
		{
			continue;
		}
		
		/* Check if weapon can be picked up */
		if (!GetEntProp(ent, Prop_Data, "m_bCanBePickedUp"))
		{
			continue;
		}
		
		/* Check if weapon it's dropped on the ground */
		if (GetEntPropEnt(ent, Prop_Data, "m_hOwnerEntity") != -1)
		{
			continue;
		}
		
		listWeapons.Push(entRef);
	}
	
	/* Sort weapons by drop time */
	listWeapons.SortCustom(sortWeapons);
	
	/* Remove the weapons */
	for (int i = g_Cvar_MaxWeapons.IntValue - 1; i < listWeapons.Length; i++)
	{
		AcceptEntityInput(EntRefToEntIndex(listWeapons.Get(i)), "Kill");
	}
	
	delete listWeapons;
}

public int sortWeapons(int index1, int index2, Handle array, Handle hndl)
{
	int weapon1 = view_as<ArrayList>(array).Get(index1);
	int weapon2 = view_as<ArrayList>(array).Get(index2);
	
	char entRef1[64], entRef2[64];
	IntToString(weapon1, entRef1, sizeof(entRef2));
	IntToString(weapon2, entRef1, sizeof(entRef2));
	
	float dropTime1, dropTime2;
	float currentTime = GetGameTime();
	
	g_Map_WeaponDropTime.GetValue(entRef1, dropTime1);
	g_Map_WeaponDropTime.GetValue(entRef2, dropTime2);
	
	if (currentTime - dropTime1 < currentTime - dropTime2)
	{
		return 1;
	}
	
	if (currentTime - dropTime1 > currentTime - dropTime2)
	{
		return -1;
	}
	
	return 0;
}
