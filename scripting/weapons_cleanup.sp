#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#pragma newdecls required

public Plugin myinfo =
{
	name = "Weapons Cleanup",
	author = "Ilusion9",
	description = "Maintain the specified dropped weapons in the world.",
	version = "1.3",
	url = "https://github.com/Ilusion9/"
};

#define MAXENTITIES 2048
enum struct WeaponInfo
{
	bool canBePicked;
	bool isBomb;
	bool isItem;
	float dropTime;
}

bool g_IsPluginLoadedLate;
ConVar g_Cvar_MaxWeapons;
ConVar g_Cvar_MaxBombs;
ConVar g_Cvar_MaxItems;
WeaponInfo g_WeaponsInfo[MAXENTITIES + 1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_IsPluginLoadedLate = late;
}

public void OnPluginStart()
{
	g_Cvar_MaxWeapons = CreateConVar("sm_weapon_max_before_cleanup", "24", "Maintain the specified dropped weapons in the world.", FCVAR_PROTECTED, true, 0.0);
	g_Cvar_MaxItems = CreateConVar("sm_item_max_before_cleanup", "16", "Maintain the specified dropped items in the world.", FCVAR_PROTECTED, true, 0.0);
	g_Cvar_MaxBombs = CreateConVar("sm_c4_max_before_cleanup", "1", "Maintain the specified dropped C4 bombs in the world.", FCVAR_PROTECTED, true, 0.0);
	AutoExecConfig(true, "weapons_cleanup");
	
	if (g_IsPluginLoadedLate)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrNumEqual(classname, "weapon_", 7, true))
	{
		g_WeaponsInfo[entity].isItem = false;
		g_WeaponsInfo[entity].isBomb = StrEqual(classname[7], "c4", true);
		
		SDKHook(entity, SDKHook_SpawnPost, SDK_OnWeaponSpawn_Post);
	}
	
	else if (StrNumEqual(classname, "item_", 5, true))
	{
		g_WeaponsInfo[entity].isItem = true;
		g_WeaponsInfo[entity].isBomb = false;
		
		SDKHook(entity, SDKHook_SpawnPost, SDK_OnWeaponSpawn_Post);
	}
}

public void SDK_OnWeaponSpawn_Post(int weapon)
{
	if (!IsValidEntity(weapon))
	{
		return;
	}
	
	RequestFrame(Frame_OnWeaponSpawn_Post, EntIndexToEntRef(weapon));
}

public void Frame_OnWeaponSpawn_Post(any data)
{
	int weapon = EntRefToEntIndex(view_as<int>(data));
	if (weapon == INVALID_ENT_REFERENCE)
	{
		return;
	}
	
	g_WeaponsInfo[weapon].dropTime = GetGameTime();
	g_WeaponsInfo[weapon].canBePicked = g_WeaponsInfo[weapon].isItem ? true : CanBePickedUp(weapon);
	
	if (HasOwner(weapon))
	{
		// The number of dropped entities has not changed
		return;
	}
	
	if (g_WeaponsInfo[weapon].isItem)
	{
		ManageDroppedItems();
		return;
	}
	
	if (g_WeaponsInfo[weapon].isBomb)
	{
		ManageDroppedC4();
		return;
	}

	ManageDroppedWeapons();
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponDropPost, SDK_OnWeaponDrop_Post);
}

public void SDK_OnWeaponDrop_Post(int client, int weapon)
{
	if (!IsValidEntity(weapon))
	{
		return;
	}
	
	g_WeaponsInfo[weapon].dropTime = GetGameTime();
	RequestFrame(Frame_OnWeaponDrop_Post, EntIndexToEntRef(weapon));
}

public void Frame_OnWeaponDrop_Post(any data)
{
	int weapon = EntRefToEntIndex(view_as<int>(data));
	if (weapon == INVALID_ENT_REFERENCE)
	{
		return;
	}
	
	if (g_WeaponsInfo[weapon].isItem)
	{
		ManageDroppedItems();
		return;
	}
	
	if (g_WeaponsInfo[weapon].isBomb)
	{
		ManageDroppedC4();
		return;
	}

	ManageDroppedWeapons();
}

void ManageDroppedItems()
{
	if (!g_Cvar_MaxItems.IntValue)
	{
		return;
	}
	
	int ent = -1;
	ArrayList listWeapons = new ArrayList();
	
	while ((ent = FindEntityByClassname(ent, "item_*")) != -1)
	{
		if (HasOwner(ent) || !HasPrevOwner(ent))
		{
			continue;
		}
		
		listWeapons.Push(ent);
	}
	
	RemoveOldestWeapons(listWeapons, g_Cvar_MaxItems.IntValue);
	delete listWeapons;
}

void ManageDroppedC4()
{
	if (!g_Cvar_MaxBombs.IntValue)
	{
		return;
	}
	
	int ent = -1;
	ArrayList listWeapons = new ArrayList();
	
	while ((ent = FindEntityByClassname(ent, "weapon_c4")) != -1)
	{
		if (!g_WeaponsInfo[ent].canBePicked || HasOwner(ent) || !HasPrevOwner(ent))
		{
			continue;
		}
		
		listWeapons.Push(ent);
	}
	
	RemoveOldestWeapons(listWeapons, g_Cvar_MaxBombs.IntValue);
	delete listWeapons;
}

void ManageDroppedWeapons()
{
	if (!g_Cvar_MaxWeapons.IntValue)
	{
		return;
	}
	
	int ent = -1;
	ArrayList listWeapons = new ArrayList();
	
	while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
	{
		if (!g_WeaponsInfo[ent].canBePicked || g_WeaponsInfo[ent].isBomb || HasOwner(ent) || !HasPrevOwner(ent))
		{
			continue;
		}
		
		listWeapons.Push(ent);
	}
	
	RemoveOldestWeapons(listWeapons, g_Cvar_MaxWeapons.IntValue);
	delete listWeapons;
}

void RemoveOldestWeapons(ArrayList listWeapons, int maxWeapons)
{
	int diff = listWeapons.Length - maxWeapons;
	if (diff == 1)
	{
		int toCompare;
		int toRemove = listWeapons.Get(0);
		
		for (int i = 1; i < listWeapons.Length; i++)
		{
			toCompare = listWeapons.Get(i);
			if (g_WeaponsInfo[toCompare].dropTime < g_WeaponsInfo[toRemove].dropTime)
			{
				toRemove = toCompare;
			}
		}
		
		AcceptEntityInput(toRemove, "Kill");
	}
	else if (diff > 1)
	{
		listWeapons.SortCustom(sortWeapons);
		for (int i = maxWeapons; i < listWeapons.Length; i++)
		{
			AcceptEntityInput(listWeapons.Get(i), "Kill");
		}
	}
}

bool HasOwner(int entity)
{
	return GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity") != -1;
}

bool HasPrevOwner(int entity)
{
	return GetEntPropEnt(entity, Prop_Send, "m_hPrevOwner") != -1;
}

bool CanBePickedUp(int entity)
{
	return GetEntProp(entity, Prop_Data, "m_bCanBePickedUp") != 0;
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

bool StrNumEqual(const char[] str1, const char[] str2, int num, bool caseSensitive)
{
	return strncmp(str1, str2, num, caseSensitive) == 0;
}
