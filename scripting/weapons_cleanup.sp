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
	bool mapPlaced;
	float dropTime;
}

ConVar g_Cvar_MaxWeapons;
ConVar g_Cvar_MaxBombs;
ConVar g_Cvar_MaxItems;
WeaponInfo g_WeaponsInfo[MAXENTITIES + 1];

public void OnPluginStart()
{
	g_Cvar_MaxWeapons = CreateConVar("sm_weapon_max_before_cleanup", "24", "Maintain the specified dropped weapons in the world.", FCVAR_PROTECTED, true, 0.0);
	g_Cvar_MaxWeapons.AddChangeHook(ConVarChange_MaxWeapons);
	
	g_Cvar_MaxItems = CreateConVar("sm_item_max_before_cleanup", "16", "Maintain the specified dropped items in the world.", FCVAR_PROTECTED, true, 0.0);
	g_Cvar_MaxItems.AddChangeHook(ConVarChange_MaxItems);
	
	g_Cvar_MaxBombs = CreateConVar("sm_c4_max_before_cleanup", "1", "Maintain the specified dropped C4 bombs in the world.", FCVAR_PROTECTED, true, 0.0);
	g_Cvar_MaxBombs.AddChangeHook(ConVarChange_MaxBombs);

	HookEvent("round_start", Event_RoundStart);
	AutoExecConfig(true, "weapons_cleanup");
	
	for (int i = 1; i <= MaxClients; i++) if (IsClientInGame(i)) OnClientPutInServer(i);
}

public void ConVarChange_MaxWeapons(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!g_Cvar_MaxWeapons.IntValue)
	{
		return;
	}
	
	int oldval = StringToInt(oldValue);
	if (oldval < g_Cvar_MaxWeapons.IntValue)
	{
		return;
	}
	
	ManageDroppedWeapons();
}

public void ConVarChange_MaxItems(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!g_Cvar_MaxItems.IntValue)
	{
		return;
	}
	
	int oldval = StringToInt(oldValue);
	if (oldval < g_Cvar_MaxItems.IntValue)
	{
		return;
	}
	
	ManageDroppedItems();
}

public void ConVarChange_MaxBombs(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!g_Cvar_MaxBombs.IntValue)
	{
		return;
	}
	
	int oldval = StringToInt(oldValue);
	if (oldval < g_Cvar_MaxBombs.IntValue)
	{
		return;
	}
	
	ManageDroppedC4();
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrNumEqual(classname, "weapon_", 7, true))
	{
		g_WeaponsInfo[entity].mapPlaced = false;
		g_WeaponsInfo[entity].isItem = false;
		g_WeaponsInfo[entity].isBomb = StrEqual(classname[7], "c4", true);
		g_WeaponsInfo[entity].canBePicked = false;
		
		SDKHook(entity, SDKHook_SpawnPost, SDK_OnWeaponSpawn_Post);
	}
	
	else if (StrNumEqual(classname, "item_", 5, true))
	{
		g_WeaponsInfo[entity].mapPlaced = false;
		g_WeaponsInfo[entity].isItem = true;
		g_WeaponsInfo[entity].isBomb = false;
		g_WeaponsInfo[entity].canBePicked = false;
		
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
	
	float gameTime = GetGameTime();
	g_WeaponsInfo[weapon].dropTime = gameTime;
	g_WeaponsInfo[weapon].canBePicked = g_WeaponsInfo[weapon].isItem ? true : CanBePickedUp(weapon);
	
	if (HasOwner(weapon))
	{
		// The number of dropped entities has not changed
		return;
	}
	
	if (g_WeaponsInfo[weapon].isItem)
	{
		ManageDroppedItems();
	}
	else if (g_WeaponsInfo[weapon].isBomb)
	{
		ManageDroppedC4();
	}
	else
	{
		ManageDroppedWeapons();
	}
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
	
	float gameTime = GetGameTime();
	g_WeaponsInfo[weapon].mapPlaced = false;
	g_WeaponsInfo[weapon].dropTime = gameTime;
	
	if (g_WeaponsInfo[weapon].isItem)
	{
		ManageDroppedItems();
	}
	else if (g_WeaponsInfo[weapon].isBomb)
	{
		ManageDroppedC4();
	}
	else
	{
		ManageDroppedWeapons();
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{	
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
	{
		if (HasOwner(ent))
		{
			continue;
		}
		
		g_WeaponsInfo[ent].mapPlaced = true;
	}
	
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "item_*")) != -1)
	{
		if (HasOwner(ent))
		{
			continue;
		}
		
		g_WeaponsInfo[ent].mapPlaced = true;
	}
}

void ManageDroppedItems()
{
	if (!g_Cvar_MaxItems.IntValue)
	{
		return;
	}
	
	int ent = -1;
	int numWeapons = 0;
	int listWeapons[512];
	
	while ((ent = FindEntityByClassname(ent, "item_*")) != -1)
	{
		if (HasOwner(ent))
		{
			continue;
		}
		
		listWeapons[numWeapons++] = ent;
	}
	
	RemoveOldestWeapons(listWeapons, numWeapons, g_Cvar_MaxItems.IntValue);
}

void ManageDroppedC4()
{
	if (!g_Cvar_MaxBombs.IntValue)
	{
		return;
	}
	
	int ent = -1;
	int numWeapons = 0;
	int listWeapons[512];
	
	while ((ent = FindEntityByClassname(ent, "weapon_c4")) != -1)
	{
		if (!g_WeaponsInfo[ent].canBePicked || g_WeaponsInfo[ent].mapPlaced || HasOwner(ent))
		{
			continue;
		}
		
		listWeapons[numWeapons++] = ent;
	}
	
	RemoveOldestWeapons(listWeapons, numWeapons, g_Cvar_MaxBombs.IntValue);
}

void ManageDroppedWeapons()
{
	if (!g_Cvar_MaxWeapons.IntValue)
	{
		return;
	}
	
	int ent = -1;
	int numWeapons = 0;
	int listWeapons[512];
	
	while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
	{
		if (!g_WeaponsInfo[ent].canBePicked || g_WeaponsInfo[ent].isBomb || g_WeaponsInfo[ent].mapPlaced || HasOwner(ent))
		{
			continue;
		}
		
		listWeapons[numWeapons++] = ent;
	}
	
	RemoveOldestWeapons(listWeapons, numWeapons, g_Cvar_MaxWeapons.IntValue);
}

void RemoveOldestWeapons(int[] listWeapons, int numWeapons, int maxWeapons)
{
	int diff = numWeapons - maxWeapons;
	if (diff == 1)
	{
		int toCompare;
		int toRemove = listWeapons[0];
		
		for (int i = 1; i < numWeapons; i++)
		{
			toCompare = listWeapons[i];
			if (g_WeaponsInfo[toCompare].dropTime < g_WeaponsInfo[toRemove].dropTime)
			{
				toRemove = toCompare;
			}
		}
		
		AcceptEntityInput(toRemove, "Kill");
	}
	else if (diff > 1)
	{
		SortCustom1D(listWeapons, numWeapons, sortWeapons);
		for (int i = maxWeapons; i < numWeapons; i++)
		{
			AcceptEntityInput(listWeapons[i], "Kill");
		}
	}
}

bool HasOwner(int entity)
{
	return GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity") != -1;
}

bool CanBePickedUp(int entity)
{
	return GetEntProp(entity, Prop_Data, "m_bCanBePickedUp") != 0;
}

public int sortWeapons(int weapon1, int weapon2, const int[] array, Handle hndl)
{
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

bool StrNumEqual(const char[] str1, const char[] str2, int num, bool caseSensitive = true)
{
	return strncmp(str1, str2, num, caseSensitive) == 0;
}
