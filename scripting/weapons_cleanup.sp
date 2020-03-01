#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#pragma newdecls required

public Plugin myinfo =
{
	name = "Weapons Cleanup",
	author = "Ilusion9",
	description = "Maintain the specified dropped weapons in the world.",
	version = "1.2",
	url = "https://github.com/Ilusion9/"
};

#define MAXENTITIES 2048
enum struct WeaponInfo
{
	bool mapPlaced;
	bool canBePicked;
	bool isBomb;
	float dropTime;
}

bool g_IsPluginLoadedLate;
ConVar g_Cvar_MaxWeapons;
ConVar g_Cvar_MaxBombs;
WeaponInfo g_WeaponsInfo[MAXENTITIES + 1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_IsPluginLoadedLate = late;
}

public void OnPluginStart()
{
	g_Cvar_MaxWeapons = CreateConVar("sm_weapon_max_before_cleanup", "24", "Maintain the specified dropped weapons in the world.", FCVAR_PROTECTED, true, 0.0);
	g_Cvar_MaxBombs = CreateConVar("sm_c4_max_before_cleanup", "5", "Maintain the specified dropped C4 bombs in the world.", FCVAR_PROTECTED, true, 0.0);
	
	AutoExecConfig(true, "weapons_cleanup");
	HookEvent("round_start", Event_RoundStart);
	
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
	if (strncmp(classname, "weapon_", 7, true) != 0)
	{
		return;
	}
	
	g_WeaponsInfo[entity].isBomb = StrEqual(classname[7], "c4", true);
	SDKHook(entity, SDKHook_SpawnPost, SDK_OnWeaponSpawn_Post);
}

public void SDK_OnWeaponSpawn_Post(int weapon)
{
	if (!IsValidEntity(weapon))
	{
		return;
	}
	
	g_WeaponsInfo[weapon].mapPlaced = false;
	g_WeaponsInfo[weapon].dropTime = GetGameTime();
	RequestFrame(Frame_OnWeaponSpawn_Post, EntIndexToEntRef(weapon));
}

public void Frame_OnWeaponSpawn_Post(any data)
{
	int weapon = EntRefToEntIndex(view_as<int>(data));
	if (weapon == INVALID_ENT_REFERENCE)
	{
		return;
	}
	
	g_WeaponsInfo[weapon].canBePicked = CanBePickedUp(weapon);
	if (IsEntityOwned(weapon))
	{
		return;
	}
	
	if (g_WeaponsInfo[weapon].isBomb)
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
	
	g_WeaponsInfo[weapon].mapPlaced = false;
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
	
	if (g_WeaponsInfo[weapon].isBomb)
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
	RequestFrame(Frame_Event_RoundStart);
}

public void Frame_Event_RoundStart(any data)
{
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
	{
		if (IsEntityOwned(ent))
		{
			continue;
		}
		
		g_WeaponsInfo[ent].mapPlaced = true;
	}
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
		if (IsEntityOwned(ent) || !g_WeaponsInfo[ent].canBePicked || g_WeaponsInfo[ent].mapPlaced)
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
		if (IsEntityOwned(ent) || !g_WeaponsInfo[ent].canBePicked || g_WeaponsInfo[ent].mapPlaced || g_WeaponsInfo[ent].isBomb)
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

bool IsEntityOwned(int entity)
{
	return GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity") != -1;
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
