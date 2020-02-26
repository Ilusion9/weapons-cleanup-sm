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
	char classname[128];
	bool mapPlaced;
	float dropTime;
	float spawnTime;
}

bool g_IsPluginLoadedLate;
bool g_HasRoundStarted;

ConVar g_Cvar_MaxWeapons;
ConVar g_Cvar_MaxC4;
WeaponInfo g_WeaponsInfo[MAXENTITIES + 1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_IsPluginLoadedLate = late;
}

public void OnPluginStart()
{
	g_Cvar_MaxWeapons = CreateConVar("sm_weapon_max_before_cleanup", "24", "Maintain the specified dropped weapons in the world. The C4 will be ignored.", FCVAR_PROTECTED, true, 0.0);
	g_Cvar_MaxWeapons.AddChangeHook(ConVarChange_MaxWeapons);
	
	g_Cvar_MaxC4 = CreateConVar("sm_c4_max_before_cleanup", "3", "Maintain the specified dropped C4 in the world.", FCVAR_PROTECTED, true, 0.0);
	g_Cvar_MaxC4.AddChangeHook(ConVarChange_MaxC4);

	AutoExecConfig(true, "weapons_cleanup");
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	
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

public void OnMapStart()
{
	g_HasRoundStarted = false;
}

public void ConVarChange_MaxWeapons(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!g_Cvar_MaxWeapons.IntValue)
	{
		return;
	}
	
	int value = StringToInt(oldValue);
	if (!value || g_Cvar_MaxWeapons.IntValue < value)
	{
		ManageDroppedWeapons(-1, false);
	}
}

public void ConVarChange_MaxC4(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!g_Cvar_MaxC4.IntValue)
	{
		return;
	}
	
	int value = StringToInt(oldValue);
	if (!value || g_Cvar_MaxC4.IntValue < value)
	{
		ManageDroppedWeapons(-1, true);
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (strncmp(classname, "weapon_", 7, true) == 0)
	{
		SDKHook(entity, SDKHook_SpawnPost, SDK_OnWeaponSpawn_Post);
	}
}

public void SDK_OnWeaponSpawn_Post(int weapon)
{
	if (!IsValidEntity(weapon))
	{
		return;
	}
	
	float gameTime = GetGameTime();
	if (gameTime - g_WeaponsInfo[weapon].spawnTime < 1.0) // SDKSpawn is called twice ...
	{
		return;
	}
	
	g_WeaponsInfo[weapon].mapPlaced = false;
	g_WeaponsInfo[weapon].dropTime = 0.0;
	g_WeaponsInfo[weapon].spawnTime = gameTime;
	Format(g_WeaponsInfo[weapon].classname, sizeof(WeaponInfo::classname), "");
	
	RequestFrame(Frame_WeaponSpawn, EntIndexToEntRef(weapon));
}

public void Frame_WeaponSpawn(any data)
{
	int weapon = EntRefToEntIndex(view_as<int>(data));
	if (weapon == INVALID_ENT_REFERENCE)
	{
		return;
	}
	
	GetEntityClassname(weapon, g_WeaponsInfo[weapon].classname, sizeof(WeaponInfo::classname));
	if (!g_HasRoundStarted)
	{
		return;
	}
	
	ManageDroppedWeapons(weapon, IsWeaponC4(weapon));
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
	
	RequestFrame(Frame_WeaponDrop, EntIndexToEntRef(weapon));
}

public void Frame_WeaponDrop(any data)
{
	int weapon = EntRefToEntIndex(view_as<int>(data));
	if (weapon == INVALID_ENT_REFERENCE)
	{
		return;
	}
	
	ManageDroppedWeapons(weapon, IsWeaponC4(weapon));
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) 
{
	if (IsWarmupPeriod())
	{
		return;
	}
	
	RequestFrame(Frame_RoundStart);
}

public void Frame_RoundStart(any data)
{
	g_HasRoundStarted = true;
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

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) 
{
	g_HasRoundStarted = false;
}

void ManageDroppedWeapons(int currentWeapon = -1, bool caseC4 = false)
{
	int maxWeapons = g_Cvar_MaxWeapons.IntValue;
	char classname[64] = "weapon_*";
	
	if (caseC4)
	{
		maxWeapons = g_Cvar_MaxC4.IntValue;
		strcopy(classname, sizeof(classname), g_WeaponsInfo[currentWeapon].classname);
	}
	
	int ent = -1;
	ArrayList listWeapons = new ArrayList();
	
	while ((ent = FindEntityByClassname(ent, classname)) != -1)
	{
		if (ent == currentWeapon || IsEntityOwned(ent) || !CanBePickedUp(ent) || g_WeaponsInfo[ent].mapPlaced)
		{
			continue;
		}
		
		if (!caseC4 && IsWeaponC4(ent))
		{
			continue;
		}
		
		listWeapons.Push(ent);
	}
	
	if (currentWeapon != -1 && !IsEntityOwned(currentWeapon))
	{
		maxWeapons--;
	}
	
	int diff = listWeapons.Length - maxWeapons;
	if (diff > 1)
	{
		listWeapons.SortCustom(sortWeapons);
		for (int i = maxWeapons; i < listWeapons.Length; i++)
		{
			AcceptEntityInput(listWeapons.Get(i), "Kill");
		}
	}
	else if (diff == 1)
	{
		int toRemove = listWeapons.Get(0);
		for (int i = 1; i < listWeapons.Length; i++)
		{
			ent = listWeapons.Get(i);
			if (g_WeaponsInfo[ent].dropTime < g_WeaponsInfo[toRemove].dropTime)
			{
				toRemove = ent;
			}
		}
		
		AcceptEntityInput(toRemove, "Kill");
	}
	
	delete listWeapons;
}

bool IsWarmupPeriod()
{
	return GameRules_GetProp("m_bWarmupPeriod") != 0;
}

bool IsWeaponC4(int weapon)
{
	return StrEqual(g_WeaponsInfo[weapon].classname[7], "c4", true);
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
