/* Headers */
#include <sourcemod>
#include <sdktools>
#include <basecomm>
#include <dhooks>
#include <lastrequest>
#include <cstrike>
#include "sd/sd.inc"

/* Compiler options */
#pragma newdecls required // Use the new syntax
#pragma semicolon 1 // Let me know if I miss a semicolon

/* Preprocessor directives */
#define PLUGIN_VERSION "0.1.0"
#define MAX_WEAPONS 48
#define MAX_EDICTS 2048

/* Global variables */
enum SD_Structure
{
	SD_PluginHandle,
	SD_DataPack
}

// Plugin info containers
ArrayList g_hPlugins;
Handle g_hOnReadyFwd;

// Core menu structures
Menu g_hHomeMenu;
Menu g_hStartMenu;
Menu g_hStatsMenu;

// Game logic & limits
bool g_bIsRunning;
Handle g_hRunningPlugin;
int g_iDaysPlayed;
int g_iMaxDaysPerMap;
ConVar g_cvMaxDaysPerMap;

// Offsets
int m_hActiveWeapon;
int m_iClip1;
int m_iClip2;
int m_iAmmo;
int m_iPrimaryAmmoType;
int m_iState;
int m_hMyWeapons;
int m_hOwner;
int m_vecOrigin;

// Weapons
Menu g_hPriWeaponMenu;
Menu g_hSecWeaponMenu;

// Block healing
Handle g_hTakeHealth;
bool g_bBlockHealing;

// Anti-gamedelay
int g_iGameIdleTimeMax;
int g_iGameIdleTimePassed;
Handle g_hOnGameIdleFwd;
Handle g_hGameIdleTimer;

// Miscellaneous
int g_iBeamSprite;
int g_iHaloSprite;
char g_sBlipSound[] = "buttons/blip1.wav";
char g_sHurtSounds[][] = 
{
	"player/damage1.wav", 
	"player/damage2.wav", 
	"player/damage3.wav"
};

/**
 * Plugin public information.
 */
public Plugin myinfo =
{
	name = "Special Days",
	author = "ici",
	description = "API for developing minigames for Jailbreak/Hosties",
	version = PLUGIN_VERSION,
	url = "https://hellclan.co.uk/"
};

/**
 * Called before OnPluginStart, in case the plugin wants to check for load failure.
 * This is called even if the plugin type is "private."  Any natives from modules are 
 * not available at this point.  Thus, this forward should only be used for explicit 
 * pre-emptive things, such as adding dynamic natives, setting certain types of load 
 * filters (such as not loading the plugin for certain games).
 * 
 * @note It is not safe to call externally resolved natives until OnPluginStart().
 * @note Any sort of RTE in this function will cause the plugin to fail loading.
 * @note If you do not return anything, it is treated like returning success. 
 * @note If a plugin has an AskPluginLoad2(), AskPluginLoad() will not be called.
 *
 *
 * @param myself	Handle to the plugin.
 * @param late		Whether or not the plugin was loaded "late" (after map load).
 * @param error		Error message buffer in case load failed.
 * @param err_max	Maximum number of characters for error message buffer.
 * @return			APLRes_Success for load success, APLRes_Failure or APLRes_SilentFailure otherwise
 */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	InitAPI();
	RegPluginLibrary("sd");
	return APLRes_Success;
}

/**
 * Called when the plugin is fully initialized and all known external references 
 * are resolved. This is only called once in the lifetime of the plugin, and is 
 * paired with OnPluginEnd().
 *
 * If any run-time error is thrown during this callback, the plugin will be marked 
 * as failed.
 */
public void OnPluginStart()
{
	GetOffsets();
	
	// Register the version as a public cvar
	CreateConVar("sm_sd_version", PLUGIN_VERSION, "Special Days Version", 
		FCVAR_NOTIFY|FCVAR_REPLICATED);
	
	// Command to open the special days menu
	RegAdminCmd("sm_sd", SM_SpecialDays, ADMFLAG_CUSTOM2, 
		"Command to open the special days menu", "", 0);
	
	// Create the special days menu
	g_hHomeMenu = new Menu(HomeMenu_Handler, MenuAction_Select|MenuAction_Cancel);
	g_hHomeMenu.SetTitle("Special Days");
	g_hHomeMenu.AddItem("startsd", "Start One", ITEMDRAW_DEFAULT);
	g_hHomeMenu.AddItem("viewstats", "View Stats", ITEMDRAW_DEFAULT);
	g_hHomeMenu.ExitButton = true;
	
	// Create the menu of available special days to start
	g_hStartMenu = new Menu(StartMenu_Handler, MenuAction_Select|MenuAction_Cancel);
	g_hStartMenu.SetTitle("Available Special Days");
	g_hStartMenu.ExitButton = true;
	g_hStartMenu.ExitBackButton = true;
	
	// For those special days which support stats
	g_hStatsMenu = new Menu(StatsMenu_Handler, MenuAction_Select|MenuAction_Cancel);
	g_hStatsMenu.SetTitle("Viewing Stats");
	g_hStatsMenu.ExitButton = true;
	g_hStatsMenu.ExitBackButton = true;
	
	// Create an arraylist to store special day plugins info
	g_hPlugins = new ArrayList(view_as<int>(SD_Structure));
	
	// Announce when special day plugins can link with this 'core' plugin
	g_hOnReadyFwd = CreateGlobalForward("SD_OnReady", ET_Ignore);
	
	// Cvar to limit the number of special days that can be played per map
	g_cvMaxDaysPerMap = CreateConVar("sm_sd_limit", "3", 
		"Max number of special days that can be played per map");
	
	g_cvMaxDaysPerMap.AddChangeHook(OnConVarChange);
	g_iMaxDaysPerMap = g_cvMaxDaysPerMap.IntValue;
	
	// For games which require weapons
	InitWeapons();
	
	// Wait for cfg/sourcemod/sd.cfg to load
	AutoExecConfig(true, "sd");
}

/**
 * Called when a client is entering the game.
 *
 * Whether a client has a steamid is undefined until OnClientAuthorized
 * is called, which may occur either before or after OnClientPutInServer.
 * Similarly, use OnClientPostAdminCheck() if you need to verify whether 
 * connecting players are admins.
 *
 * GetClientCount() will include clients as they are passed through this 
 * function, as clients are already in game at this point.
 *
 * @param client		Client index.
 */
public void OnClientPutInServer(int client)
{
	DHookEntity(g_hTakeHealth, false, client); // Auto-removed on entity destroyed
}

/**
 * Called when the map is loaded.
 *
 * @note This used to be OnServerLoad(), which is now deprecated.
 * Plugins still using the old forward will work.
 */
public void OnMapStart()
{
	// Precache resources
	g_iBeamSprite = PrecacheModel("materials/sprites/laser.vmt");
	g_iHaloSprite = PrecacheModel("materials/sprites/halo01.vmt");
	
	PrecacheSound( g_sBlipSound );
	
	// Precache hurt sounds
	for (int i = 0; i < sizeof(g_sHurtSounds); ++i)
	{
		PrecacheSound( g_sHurtSounds[i] );
	}
}

/**
 * Called when the map has loaded, servercfgfile (server.cfg) has been 
 * executed, and all plugin configs are done executing.  This is the best
 * place to initialize plugin functions which are based on cvar data.  
 *
 * @note This will always be called once and only once per map.  It will be 
 * called after OnMapStart().
 */
public void OnConfigsExecuted()
{
	g_iDaysPlayed = 0;
	g_iMaxDaysPerMap = g_cvMaxDaysPerMap.IntValue;
}

/**
 * Called after all plugins have been loaded.  This is called once for 
 * every plugin.  If a plugin late loads, it will be called immediately 
 * after OnPluginStart().
 */
public void OnAllPluginsLoaded()
{
	// Child plugins can link their menu function pointers at this point
	Call_StartForward(g_hOnReadyFwd);
	Call_Finish();
}

/** Called when a console variable's value is changed.
 * 
 * @param convar		Handle to the convar that was changed.
 * @param oldValue		String containing the value of the convar before it was changed.
 * @param newValue		String containing the new value of the convar.
 */
public void OnConVarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	//if (convar == g_cvMaxDaysPerMap)
	//{
		g_iMaxDaysPerMap = StringToInt(newValue);
	//}
}

/**
 * Called when the special days command is invoked.
 *
 * @param client		Index of the client, or 0 from the server.
 * @param args			Number of arguments that were in the argument string.
 * @return				An Action value.  Not handling the command
 *						means that Source will report it as "not found."
 */
public Action SM_SpecialDays(int client, int args)
{
	if (!client) // server console/RCON?
	{
		ReplyToCommand(client, "You cannot invoke this command from the server console.");
		return Plugin_Handled;
	}
	
	// Display the special days menu
	g_hHomeMenu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

/**
 * Called when a menu action is completed.
 *
 * @param menu				The menu being acted upon.
 * @param action			The action of the menu.
 * @param param1			First action parameter (usually the client).
 * @param param2			Second action parameter (usually the item).
 */
public int HomeMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		// Grab the info string
		char info[32];
		if ( !menu.GetItem(param2, info, sizeof(info)) )
		{
			return 0; // param2 was invalid
		}
		
		if (!strcmp(info, "startsd"))
		{
			// Open a list of available special days to start
			g_hStartMenu.Display(param1, MENU_TIME_FOREVER);
		}
		else if (!strcmp(info, "viewstats"))
		{
			// Show global / per-special day stats
			g_hStatsMenu.Display(param1, MENU_TIME_FOREVER);
		}
	}
	return 0;
}

/**
 * Called when a menu action is completed.
 *
 * @param menu				The menu being acted upon.
 * @param action			The action of the menu.
 * @param param1			First action parameter (usually the client).
 * @param param2			Second action parameter (usually the item).
 */
public int StartMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			// Player selected a special day to start
			char info[32];
			if ( !menu.GetItem(param2, info, sizeof(info)) )
			{
				return 0; // param2 was invalid
			}
			
			// Get the plugin's handle
			Handle plugin = view_as<Handle>(StringToInt(info));
			
			// Find where it's located in the array
			int index = g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle));
			
			// Does it exist?
			if (index == -1)
			{
				return 0; // It appears to be gone, can't do anything further.
			}
			
			// Get the test menu function pointer associated with the plugin
			DataPack datapack = g_hPlugins.Get(index, view_as<int>(SD_DataPack));
			if (datapack != null)
			{
				datapack.Reset();
				Function func = datapack.ReadFunction();
				
				// Start the function call
				Call_StartFunction(plugin, func);
				Call_PushCell(param1); // client index
				Call_Finish();
			}
			else
			{
				LogError("Uh oh, something went wrong!"
					... " The datapack is null.");
			}
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				// Player pressed the back button, go back
				g_hHomeMenu.Display(param1, MENU_TIME_FOREVER);
			}
		}
	}
	return 0;
}

/**
 * Called when a menu action is completed.
 *
 * @param menu				The menu being acted upon.
 * @param action			The action of the menu.
 * @param param1			First action parameter (usually the client).
 * @param param2			Second action parameter (usually the item).
 */
public int StatsMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				// Player pressed the back button, go back
				g_hHomeMenu.Display(param1, MENU_TIME_FOREVER);
			}
		}
	}
}

/**
 * Used by games which require weapons.
 */
void InitWeapons()
{
	// Primary weapons
	g_hPriWeaponMenu = new Menu(WeaponMenu_Handler, MenuAction_Select|MenuAction_Cancel);
	g_hPriWeaponMenu.SetTitle("Primary Weapon Selection Menu");
	g_hPriWeaponMenu.AddItem("m4a1", "M4A1");
	g_hPriWeaponMenu.AddItem("ak47", "AK47");
	g_hPriWeaponMenu.AddItem("awp", "AWP");
	g_hPriWeaponMenu.AddItem("p90", "P90");
	g_hPriWeaponMenu.AddItem("m249", "M249");
	g_hPriWeaponMenu.AddItem("mac10", "Mac10");
	g_hPriWeaponMenu.AddItem("m3", "M3");
	g_hPriWeaponMenu.AddItem("xm1014", "XM1014");
	g_hPriWeaponMenu.AddItem("scout", "Scout");
	g_hPriWeaponMenu.AddItem("galil", "Galil");
	g_hPriWeaponMenu.AddItem("famas", "Famas");
	g_hPriWeaponMenu.AddItem("tmp", "TMP");
	g_hPriWeaponMenu.AddItem("mp5navy", "MP5");
	g_hPriWeaponMenu.AddItem("ump45", "UMP45");
	
	// Secondary weapons
	g_hSecWeaponMenu = new Menu(WeaponMenu_Handler, MenuAction_Select|MenuAction_Cancel);
	g_hSecWeaponMenu.SetTitle("Secondary Weapon Selection Menu");
	g_hSecWeaponMenu.AddItem("glock", "Glock");
	g_hSecWeaponMenu.AddItem("usp", "USP");
	g_hSecWeaponMenu.AddItem("p228", "P228");
	g_hSecWeaponMenu.AddItem("deagle", "Deagle");
	g_hSecWeaponMenu.AddItem("elite", "Elite");
	g_hSecWeaponMenu.AddItem("fiveseven", "Fiveseven");
}

/**
 * Called when a menu action is completed.
 *
 * @param menu				The menu being acted upon.
 * @param action			The action of the menu.
 * @param param1			First action parameter (usually the client).
 * @param param2			Second action parameter (usually the item).
 */
public int WeaponMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		if ( !g_bIsRunning )
		{
			// Can't give weapons to players if no sd is running
			return 0;
		}
		
		if ( !IsPlayerAlive(param1) )
		{
			// Can't give weapons to dead players
			return 0;
		}
		
		char info[32];
		char weapon[32];
		
		if ( !menu.GetItem(param2, info, sizeof(info)) )
		{
			return 0; // param2 was invalid
		}
		
		FormatEx(weapon, sizeof(weapon), "weapon_%s", info);
		GivePlayerItem(param1, weapon);
		
		if (menu == g_hSecWeaponMenu)
		{
			// Let them choose a primary weapon afterwards
			g_hPriWeaponMenu.Display(param1, MENU_TIME_FOREVER);
		}
	}
	return 0;
}

/**
 * Creates the natives to be used by child plugins
 */
void InitAPI()
{
	// Linking & menu calls
	CreateNative("SD_AddToStartMenu", Native_SD_AddToStartMenu);
	CreateNative("SD_RemoveFromStartMenu", Native_SD_RemoveFromStartMenu);
	CreateNative("SD_DisplayHomeMenu", Native_SD_DisplayHomeMenu);
	CreateNative("SD_DisplayStartMenu", Native_SD_DisplayStartMenu);
	CreateNative("SD_DisplayStatsMenu", Native_SD_DisplayStatsMenu);
	
	// Game logic & limits
	CreateNative("SD_CanStart", Native_SD_CanStart);
	CreateNative("SD_IsRunning", Native_SD_IsRunning);
	CreateNative("SD_SetRunning", Native_SD_SetRunning);
	CreateNative("SD_GetDaysPlayed", Native_SD_GetDaysPlayed);
	CreateNative("SD_IncrementDaysPlayed", Native_SD_IncrementDaysPlayed);
	CreateNative("SD_GetMaxDaysPerMap", Native_SD_GetMaxDaysPerMap);
	CreateNative("SD_IsLastRequestRunning", Native_SD_IsLastRequestRunning);
	
	// Miscellaneous
	CreateNative("SD_DisplayGunMenu", Native_SD_DisplayGunMenu);
	CreateNative("SD_GivePlayerAmmo", Native_SD_GivePlayerAmmo);
	CreateNative("SD_StripPlayerWeapons", Native_SD_StripPlayerWeapons);
	CreateNative("SD_RemoveWorldWeapons", Native_SD_RemoveWorldWeapons);
	CreateNative("SD_OpenCells", Native_SD_OpenCells);
	CreateNative("SD_UnmutePlayer", Native_SD_UnmutePlayer);
	CreateNative("SD_MutePlayer", Native_SD_MutePlayer);
	CreateNative("SD_BlockHealing", Native_SD_BlockHealing);
	CreateNative("SD_BeaconPlayer", Native_SD_BeaconPlayer);
	CreateNative("SD_HurtPlayer", Native_SD_HurtPlayer);
	CreateNative("SD_SuppressFFMessages", Native_SD_SuppressFFMessages);
	CreateNative("SD_SuppressJoinTeamMessages", Native_SD_SuppressJoinTeamMessages);
	CreateNative("SD_GetRandomPlayer", Native_SD_GetRandomPlayer);
	CreateNative("SD_GetAlivePlayerCount", Native_SD_GetAlivePlayerCount);
	
	// Anti-gamedelay
	CreateNative("SD_HookOnGameIdle", Native_SD_HookOnGameIdle);
	CreateNative("SD_UnhookOnGameIdle", Native_SD_UnhookOnGameIdle);
	CreateNative("SD_SetGameIdleTimeMax", Native_SD_SetGameIdleTimeMax);
	CreateNative("SD_GameProgressed", Native_SD_GameProgressed);
}

/**
 * Defines a native function that adds your sd to the list of available sd's to start.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_AddToStartMenu(Handle plugin, int numParams)
{
	int index = g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle));
	if (index != -1)
	{
		// This plugin is trying to register twice, perform a clean-up
		DataPack datapack = g_hPlugins.Get(index, view_as<int>(SD_DataPack));
		if (datapack != null)
		{
			delete datapack;
		}
		g_hPlugins.Erase(index);
	}
	// Push the plugin handle
	index = g_hPlugins.Push(plugin);
	
	// Push the custom menu function pointer
	DataPack datapack = new DataPack();
	datapack.WriteFunction( GetNativeFunction(2) );
	g_hPlugins.Set(index, datapack, view_as<int>(SD_DataPack));
	
	// Append the new special day to the list
	char info[32];
	char display[32];
	
	IntToString(view_as<int>(plugin), info, sizeof(info));
	GetNativeString(1, display, sizeof(display));
	
	return view_as<int>( g_hStartMenu.AddItem(info, display, ITEMDRAW_DEFAULT) );
}

/**
 * Defines a native function that removes your sd from the list of available sd's to start.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_RemoveFromStartMenu(Handle plugin, int numParams)
{
	// Try to find the location of the plugin in the array
	int index = g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle));
	
	// If there's no menu item associated with this plugin, do nothing.
	if (index == -1)
	{
		return view_as<int>(false);
	}
	
	// Else - remove it from the list
	DataPack datapack = g_hPlugins.Get(index, view_as<int>(SD_DataPack));
	if (datapack != null)
	{
		delete datapack;
	}
	g_hPlugins.Erase(index);
	
	return view_as<int>( g_hStartMenu.RemoveItem(index) );
}

/**
 * Defines a native function that returns whether a SD can be started.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_CanStart(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	int client = GetNativeCell(1);
	if ( !SD_IsValidClientIndex(client) )
	{
		return ThrowNativeError(SP_ERROR_NOT_FOUND, "Client index %i is invalid.", client);
	}
	
	if ( g_hRunningPlugin != null && g_hRunningPlugin != plugin )
	{
		// Another special day is already running.
		PrintToChat(client, "\x04Another special day is already running.");
		return view_as<int>( false );
	}
	
	if (IsLastRequestRunning())
	{
		// There's an active LR, don't start.
		PrintToChat(client, "\x04Can't start because there's an active LR.");
		return view_as<int>( false );
	}
	
	// Method 1 - old way of limiting x number of special days per map
	if (g_iDaysPlayed >= g_iMaxDaysPerMap)
	{
		// Can't start the game. Reached the max num of SDs allowed per map.
		PrintToChat(client, "\x04You have reached the limit of %d special days per map.", g_iMaxDaysPerMap);
		return view_as<int>( false );
	}
	
	return view_as<int>( true );
}

/**
 * Defines a native function that returns if a special day is running.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_IsRunning(Handle plugin, int numParams)
{
	return view_as<int>( g_bIsRunning );
}

/**
 * Defines a native function that sets if a special day is running or not.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_SetRunning(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		// You might see this often.
		// It guards against performing calls from plugins
		// which are not special day plugins. 
		return view_as<int>(false); // No, it doesn't.
	}
	
	g_bIsRunning = view_as<bool>( GetNativeCell(1) );
	g_hRunningPlugin = (g_bIsRunning) ? plugin : null;
	
	return view_as<int>(true);
}

/**
 * Defines a native function that returns the number of special days that 
 * have been played this map.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_GetDaysPlayed(Handle plugin, int numParams)
{
	// As you can see, we don't need to perform that check here because
	// the outcome of executing this function would have no effect on the state.
	// It's just a "getter" function which returns the number of SDs played.
	return g_iDaysPlayed;
}

/**
 * Defines a native function that increments the total day count by one.
 * Usually called when a special day ends.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_IncrementDaysPlayed(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		// There you go. Since this changes the state, we have to be careful
		// which plugins we allow it to be called from!
		return view_as<int>(false); // No, it doesn't.
	}
	
	++g_iDaysPlayed;
	return view_as<int>(true);
}

/**
 * Defines a native function that returns the max number of special days that 
 * can be played per map.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_GetMaxDaysPerMap(Handle plugin, int numParams)
{
	return g_iMaxDaysPerMap;
}

/**
 * Defines a native function that returns whether an LR is running.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_IsLastRequestRunning(Handle plugin, int numParams)
{
	return view_as<int>( IsLastRequestRunning() );
}

/*
 * Returns whether there's an active LR running.
 *
 * @return 	True if there's an active LR, false otherwise.
 */
bool IsLastRequestRunning()
{
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}
		if (IsClientInLastRequest(i))
		{
			return true;
		}
	}
	return false;
}

/**
 * Defines a native function that displays the special days menu.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_DisplayHomeMenu(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	int client = GetNativeCell(1);
	if ( !SD_IsValidClientIndex(client) )
	{
		return ThrowNativeError(SP_ERROR_NOT_FOUND, "Client index %i is invalid.", client);
	}
	
	return view_as<int>( g_hHomeMenu.Display(client, MENU_TIME_FOREVER) );
}

/**
 * Defines a native function that displays the menu of available special days to start
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_DisplayStartMenu(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	int client = GetNativeCell(1);
	if ( !SD_IsValidClientIndex(client) )
	{
		return ThrowNativeError(SP_ERROR_NOT_FOUND, "Client index %i is invalid.", client);
	}
	
	return view_as<int>( g_hStartMenu.Display(client, MENU_TIME_FOREVER) );
}

/**
 * Defines a native function that displays the stats menu
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_DisplayStatsMenu(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	int client = GetNativeCell(1);
	if ( !SD_IsValidClientIndex(client) )
	{
		return ThrowNativeError(SP_ERROR_NOT_FOUND, "Client index %i is invalid.", client);
	}
	
	return view_as<int>( g_hStatsMenu.Display(client, MENU_TIME_FOREVER) );
}

/**
 * Defines a native function that displays the gun menu to a player.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_DisplayGunMenu(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	int client = GetNativeCell(1);
	if ( !SD_IsValidClientIndex(client) )
	{
		return ThrowNativeError(SP_ERROR_NOT_FOUND, "Client index %i is invalid.", client);
	}
	
	return view_as<int>( g_hSecWeaponMenu.Display(client, MENU_TIME_FOREVER) );
}

/**
 * Defines a native function that gives player ammo.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_GivePlayerAmmo(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	int client = GetNativeCell(1);
	if ( !SD_IsValidClientIndex(client) )
	{
		return ThrowNativeError(SP_ERROR_NOT_FOUND, "Client index %i is invalid.", client);
	}
	
	return GiveAmmo( client, GetNativeCell(2) );
}

/**
 * Gives ammo to a player.
 *
 * @param client 	The client index
 * @param amount	Amount of ammo to give. Is capped at ammotype's limit.
 *
 * @return Amount of ammo actually given.
 */
int GiveAmmo(int client, int amount)
{
	// Get player's active weapon
	int weaponIndex = GetEntDataEnt2(client, m_hActiveWeapon);
	if (weaponIndex == -1)
	{
		return 0; // couldn't find player's active weapon
	}
	
	return GivePlayerAmmo(client, amount, GetEntData(weaponIndex, m_iPrimaryAmmoType));
}

/**
 * Defines a native function that strips player's weapons
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_StripPlayerWeapons(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	int client = GetNativeCell(1);
	if ( !SD_IsValidClientIndex(client) )
	{
		return ThrowNativeError(SP_ERROR_NOT_FOUND, "Client index %i is invalid.", client);
	}
	
	return StripPlayerWeapons( client );
}

/**
 * Strips player's weapons
 *
 * @param client	The client index
 * @return 			Number of weapons removed
 */
int StripPlayerWeapons(int client)
{
	int numOfWeaponsRemoved = 0;
	
	// Go through every possible weapon /offset math/
	for (int i = 0; i < MAX_WEAPONS; ++i)
	{
		int weaponIndex = GetEntDataEnt2(client, m_hMyWeapons + i*4);
		if (weaponIndex == -1)
		{
			continue; // no entity at this location
		}
		
		if ( !IsValidEdict(weaponIndex) )
		{
			continue; // this weapon must have been destroyed or unnetworked?
		}
		
		if ( RemovePlayerItem(client, weaponIndex) )
		{
			// Managed to remove this weapon from the player
			// Time to completely delete it now
			AcceptEntityInput(weaponIndex, "Kill");
			++numOfWeaponsRemoved;
		}
	}
	return numOfWeaponsRemoved;
}

/**
 * Defines a native function that removes all weapons from the world.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_RemoveWorldWeapons(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	return RemoveWorldWeapons();
}

/**
 * Removes all weapons lying somewhere in the world / map
 *
 * @return 		Number of weapons removed
 */
int RemoveWorldWeapons()
{
	int numOfWeaponsRemoved = 0;
	
	// Go through all weapon edicts on the server
	int lastEdictInUse = GetEntityCount();
	char sBuffer[7];
	for (int edict = MaxClients+1; edict <= lastEdictInUse; ++edict)
	{
		if ( !IsValidEdict(edict) )
		{
			continue; // either destroyed or an unnetworked entity
		}
		
		// Is this edict a weapon?
		GetEdictClassname(edict, sBuffer, sizeof(sBuffer));
		if (strcmp(sBuffer, "weapon") != 0)
		{
			continue; // not a weapon
		}
		
		int owner = GetEntDataEnt2(edict, m_hOwner);
		if ( SD_IsValidClientIndex(owner) && IsClientInGame(owner) && IsPlayerAlive(owner) )
		{
			continue; // a player is holding this weapon, don't remove it
		}
		
		AcceptEntityInput(edict, "Kill");
		++numOfWeaponsRemoved;
	}
	return numOfWeaponsRemoved;
}

/**
 * Defines a native function that opens cells (door entities) on the map.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_OpenCells(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	OpenCells( view_as<bool>(GetNativeCell(1)) );
	return 0;
}

/**
 * Opens door entities.
 * 
 * @param breakCells	Set to true if you also want to break func_breakables
 */
void OpenCells(bool breakCells)
{
	int ent;
	char sTypesOfDoors[][] = {"func_door", "func_movelinear", "func_door_rotating"};
	
	// Go through each type of door and 'Open' it
	for (int i = 0; i < sizeof(sTypesOfDoors); ++i)
	{
		while ( (ent = FindEntityByClassname(ent, sTypesOfDoors[i])) != -1 )
		{
			AcceptEntityInput(ent, "Open");
		}
	}
	
	// Some maps use breakable cells such as jb_minecraft
	if (breakCells)
	{
		while ( (ent = FindEntityByClassname(ent, "func_breakable")) != -1 )
		{
			AcceptEntityInput(ent, "Break");
		}
	}
}

/**
 * Defines a native function that unmutes a player.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_UnmutePlayer(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	int client = GetNativeCell(1);
	if ( !SD_IsValidClientIndex(client) )
	{
		return ThrowNativeError(SP_ERROR_NOT_FOUND, "Client index %i is invalid.", client);
	}
	
	return view_as<int>( UnmutePlayer( client ) );
}

/**
 * Defines a native function that mutes a player.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_MutePlayer(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	int client = GetNativeCell(1);
	if ( !SD_IsValidClientIndex(client) )
	{
		return ThrowNativeError(SP_ERROR_NOT_FOUND, "Client index %i is invalid.", client);
	}
	
	return view_as<int>( MutePlayer( client ) );
}

/**
 * Unmutes a player.
 *
 * @param 		The client index
 * @return 		True on success, false if player is banned from speaking
 */
bool UnmutePlayer(int client)
{
	// Banned from speaking?
	if ( BaseComm_IsClientMuted(client) )
	{
		return false;
	}
	SetClientListeningFlags(client, VOICE_NORMAL);
	return true;
}

/**
 * Mutes a player.
 *
 * @param 		The client index
 * @return 		True on success, false if player is banned from speaking
 */
bool MutePlayer(int client)
{
	// Banned from speaking?
	if ( BaseComm_IsClientMuted(client) )
	{
		return false;
	}
	SetClientListeningFlags(client, VOICE_MUTED);
	return true;
}

/**
 * Defines a native function that turns on/off healing prevention.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_BlockHealing(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	g_bBlockHealing = view_as<bool>(GetNativeCell(1));
	return 0;
}

// Returns the amount of health actually taken.
// int CBaseEntity::TakeHealth( float flHealth, int bitsDamageType )
public MRESReturn Hook_TakeHealth_Pre(int pThis, Handle hReturn, Handle hParams)
{
	// Prevent players from healing
	if ( g_bIsRunning && g_bBlockHealing )
	{
		DHookSetReturn(hReturn, 0);
		return MRES_Supercede;
	}
	return MRES_Ignored;
}

/**
 * Defines a native function that hooks a function to call when 
 * the game remains idle for a period of time.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_HookOnGameIdle(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	// Disclaimer: I know I'm using forwards to call a function from just ONE plugin.
	// It automates logic in some cases which I am too lazy to handle myself.
	if (g_hOnGameIdleFwd == null)
	{
		g_hOnGameIdleFwd = CreateForward(ET_Ignore);
	}
	else
	{
		if (GetForwardFunctionCount(g_hOnGameIdleFwd) != 0)
		{
			LogError("Another SD is still using this feature! Wait for it to unhook.");
			return view_as<int>(false);
		}
	}
	return view_as<int>( AddToForward(g_hOnGameIdleFwd, plugin, GetNativeFunction(1)) );
}

/**
 * Defines a native function that unhooks a function to call 
 * when the game remains idle for a period of time.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_UnhookOnGameIdle(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	if (g_hOnGameIdleFwd == null)
	{
		// Can't proceed because no plugin has hooked.
		return view_as<int>(false);
	}
	
	if (RemoveFromForward(g_hOnGameIdleFwd, plugin, GetNativeFunction(1)))
	{
		// Managed to remove the forward at this point.
		
		// It's not like two SDs could be running at the same time but still.
		if (GetForwardFunctionCount(g_hOnGameIdleFwd) == 0)
		{
			// Perform a clean-up of resources.
			delete g_hOnGameIdleFwd;
			g_hOnGameIdleFwd = null;
		}
		
		// Destroy the timer in case it's running
		if ( g_hGameIdleTimer != null )
		{
			delete g_hGameIdleTimer;
			g_hGameIdleTimer = null;
		}
		return view_as<int>( true ); // Everything was ok.
	}
	return view_as<int>( false );
}

/**
 * Defines a native function that sets the game idle time maximum.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_SetGameIdleTimeMax(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	if (g_hOnGameIdleFwd == null)
	{
		// Can't proceed because no plugin has hooked.
		return view_as<int>(false);
	}
	
	// Set the new limit
	g_iGameIdleTimeMax = SD_IntAbs( GetNativeCell(1) );
	
	// Reset time passed
	g_iGameIdleTimePassed = 0;
	
	return view_as<int>( true );
}

/**
 * Defines a native function that progresses the game.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_GameProgressed(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	if (g_hOnGameIdleFwd == null)
	{
		// Can't proceed because no plugin has hooked.
		return view_as<int>(false);
	}
	
	// Reset time passed
	g_iGameIdleTimePassed = 0;
	
	/* It's at this point where we can safely start the game idle timer for the first time */
	if ( g_hGameIdleTimer == null )
	{
		g_hGameIdleTimer = CreateTimer(1.0, Timer_GameIdle, plugin, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	return view_as<int>( true );
}

/**
 * Called when the timer interval has elapsed.
 * 
 * @param timer			Handle to the timer object.
 * @param data			Data passed to CreateTimer() when timer was created.
 * @return				Plugin_Stop to stop a repeating timer, any other value for
 *						default behavior.
 */
public Action Timer_GameIdle(Handle timer, any plugin)
{
	if ( g_iGameIdleTimePassed >= g_iGameIdleTimeMax )
	{
		// Game remained idle for a bit. Notify the plugin.
		Call_StartForward( g_hOnGameIdleFwd );
		Call_Finish();
		return Plugin_Continue;
	}
	
	++g_iGameIdleTimePassed;
	return Plugin_Continue;
}

/**
 * Defines a native function that beacons a player. (only a single blip)
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_BeaconPlayer(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	int client = GetNativeCell(1);
	if ( !SD_IsValidClientIndex(client) )
	{
		return ThrowNativeError(SP_ERROR_NOT_FOUND, "Client index %i is invalid.", client);
	}
	
	int colour[4];
	GetNativeArray(2, colour, sizeof(colour));
	
	BeaconPlayer( client, colour );
	return 0;
}

/**
 * Beacons a player. (only a single blip)
 *
 * @param client 	The client index
 * @param colour 	Red, green, blue, alpha
 */
void BeaconPlayer(int client, const int colour[4])
{
	static const int greyColor[4] = {128, 128, 128, 255};
	
	float origin[3];
	GetEntDataVector(client, m_vecOrigin, origin);
	origin[2] += 10.0;
	
	TE_SetupBeamRingPoint(origin, 10.0, 375.0, g_iBeamSprite, g_iHaloSprite, 0, 15, 0.5, 5.0, 0.0, greyColor, 10, 0);
	TE_SendToAll();
	
	TE_SetupBeamRingPoint(origin, 10.0, 375.0, g_iBeamSprite, g_iHaloSprite, 0, 10, 0.6, 10.0, 0.5, colour, 10, 0);
	TE_SendToAll();
	
	EmitAmbientSound(g_sBlipSound, origin, client, SNDLEVEL_RAIDSIREN);
}

/**
 * Defines a native function that takes away health from a player.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_HurtPlayer(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	int client = GetNativeCell(1);
	if ( !SD_IsValidClientIndex(client) )
	{
		return ThrowNativeError(SP_ERROR_NOT_FOUND, "Client index %i is invalid.", client);
	}
	
	HurtPlayer( client, GetNativeCell(2), view_as<bool>(GetNativeCell(3)) );
	return 0;
}

/**
 * Takes away health from a player.
 *
 * @param client 	The client index
 * @param health	Amount of health to lose
 * @param hurtSound	Set to false if you don't want to play a hurt sound
 */
void HurtPlayer(int client, int health, bool hurtSound)
{
	if ( hurtSound )
	{
		PlayHurtSound( client );
	}
	
	int newHealth = GetClientHealth(client) - health;
	if (newHealth <= 0)
	{
		// Player must die
		ForcePlayerSuicide( client );
		return;
	}
	SetEntityHealth(client, newHealth);
}

/**
 * Plays a random hurt sound.
 *
 * @param client 	The client index
 */
void PlayHurtSound(int client)
{
	EmitSoundToAll(g_sHurtSounds[ GetRandomInt(0, sizeof(g_sHurtSounds)-1) ], 
		client, SNDCHAN_AUTO, SNDLEVEL_NORMAL);
}

/**
 * Defines a native function that suppresses teamkill messages.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_SuppressFFMessages(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	SuppressFFMessages( view_as<bool>(GetNativeCell(1)) );
	return 0;
}

/*
 * Suppresses teamkill, teamattack, mp_friendlyfire messages
 *
 * @param suppress		To block or not to block.
 */
void SuppressFFMessages(bool suppress)
{
	static bool lastPerformed = false;
	
	// Make sure we don't do the same thing twice
	if (lastPerformed == suppress)
		return;
	
	if (suppress)
	{
		HookUserMessage(GetUserMessageId("TextMsg"), Hook_TextMsg, true);
		HookUserMessage(GetUserMessageId("HintText"), Hook_HintText, true);
		HookEvent("server_cvar", Event_ServerCvar_Pre, EventHookMode_Pre);
	}
	else
	{
		UnhookUserMessage(GetUserMessageId("TextMsg"), Hook_TextMsg, true);
		UnhookUserMessage(GetUserMessageId("HintText"), Hook_HintText, true);
		UnhookEvent("server_cvar", Event_ServerCvar_Pre, EventHookMode_Pre);
	}
	lastPerformed = suppress;
}

/**
 * Called when a bit buffer based usermessage is hooked
 *
 * @param msg_id		Message index.
 * @param msg			Handle to the input bit buffer.
 * @param players		Array containing player indexes.
 * @param playersNum	Number of players in the array.
 * @param reliable		True if message is reliable, false otherwise.
 * @param init			True if message is an initmsg, false otherwise.
 * @return				Ignored for normal hooks.  For intercept hooks, Plugin_Handled 
 *						blocks the message from being sent, and Plugin_Continue 
 *						resumes normal functionality.
 */
public Action Hook_TextMsg(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	/* Block team-attack messages from being shown to players. */ 
	char message[256];
	BfReadString(msg, message, sizeof(message));

	if (StrContains(message, "teammate_attack") != -1)
		return Plugin_Handled;
		
	if (StrContains(message, "Killed_Teammate") != -1)
		return Plugin_Handled;
		
	return Plugin_Continue;
}

/**
 * Called when a bit buffer based usermessage is hooked
 *
 * @param msg_id		Message index.
 * @param msg			Handle to the input bit buffer.
 * @param players		Array containing player indexes.
 * @param playersNum	Number of players in the array.
 * @param reliable		True if message is reliable, false otherwise.
 * @param init			True if message is an initmsg, false otherwise.
 * @return				Ignored for normal hooks.  For intercept hooks, Plugin_Handled 
 *						blocks the message from being sent, and Plugin_Continue 
 *						resumes normal functionality.
 */
public Action Hook_HintText(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	/* Block team-attack tutorial messages from being shown to players. */ 
	char message[256];
	BfReadString(msg, message, sizeof(message));
	
	if (StrContains(message, "spotted_a_friend") != -1)
		return Plugin_Handled;
		
	if (StrContains(message, "careful_around_teammates") != -1)
		return Plugin_Handled;
		
	if (StrContains(message, "try_not_to_injure_teammates") != -1)
		return Plugin_Handled;
		
	return Plugin_Continue;
}

/**
 * Called when a game event is fired.
 *
 * @param event			Handle to event. This could be INVALID_HANDLE if every plugin hooking 
 *						this event has set the hook mode EventHookMode_PostNoCopy.
 * @param name			String containing the name of the event.
 * @param dontBroadcast	True if event was not broadcast to clients, false otherwise.
 * @return				Ignored for post hooks. Plugin_Handled will block event if hooked as pre.
 */
public Action Event_ServerCvar_Pre(Event event, const char[] name, bool dontBroadcast)
{
	/* Block server cvar changed notification in chat */
	char sConVarName[64];
	event.GetString("cvarname", sConVarName, sizeof(sConVarName));
	
	if ( !strcmp(sConVarName, "mp_friendlyfire") ||
		 !strcmp(sConVarName, "sv_tags") )
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

/**
 * Defines a native function that suppresses jointeam messages.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_SuppressJoinTeamMessages(Handle plugin, int numParams)
{
	// Does this plugin exist in the list?
	if (g_hPlugins.FindValue(plugin, view_as<int>(SD_PluginHandle)) == -1)
	{
		return view_as<int>(false); // No, it doesn't.
	}
	
	SuppressJoinTeamMessages( view_as<bool>(GetNativeCell(1)) );
	return 0;
}

/**
 * Suppress jointeam messages (spectators are ignored)
 * Use this when you need to perform heavy player swaps.
 * The point of this is to keep the chat tidy.
 *
 * @param suppress		True to block, false not to block
 */
void SuppressJoinTeamMessages(bool suppress)
{
	static bool lastPerformed = false;
	
	// Make sure we don't do the same thing twice
	if (lastPerformed == suppress)
		return;
	
	if (suppress)
	{
		HookEvent("player_team", Event_PlayerTeam_Pre, EventHookMode_Pre);
	}
	else
	{
		UnhookEvent("player_team", Event_PlayerTeam_Pre, EventHookMode_Pre);
	}
	lastPerformed = suppress;
}

/**
 * Called when a game event is fired.
 *
 * @param event			Handle to event. This could be INVALID_HANDLE if every plugin hooking 
 *						this event has set the hook mode EventHookMode_PostNoCopy.
 * @param name			String containing the name of the event.
 * @param dontBroadcast	True if event was not broadcast to clients, false otherwise.
 * @return				Ignored for post hooks. Plugin_Handled will block event if hooked as pre.
 */
public Action Event_PlayerTeam_Pre(Event event, const char[] name, bool dontBroadcast)
{
	if ( !dontBroadcast && !event.GetBool("silent") )
	{
		if ( event.GetInt("team", CS_TEAM_SPECTATOR) != CS_TEAM_SPECTATOR )
		{
			event.BroadcastDisabled = true;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

/**
 * Defines a native function that returns a random alive player.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_GetRandomPlayer(Handle plugin, int numParams)
{
	return GetRandomPlayer();
}

/*
 * Returns a random alive player (client index).
 */
int GetRandomPlayer()
{
	int[] clients = new int[MaxClients + 1];
	int clientCount;
	
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) <= CS_TEAM_SPECTATOR)
		{
			continue;
		}
		clients[ clientCount++ ] = i;
	}
	return clientCount ? clients[ GetRandomInt(0, clientCount-1) ] : -1;
}

/**
 * Defines a native function that returns the number of alive players in a team.
 *
 * It is not necessary to validate the parameter count 
 *
 * @param plugin			Handle of the calling plugin.
 * @param numParams			Number of parameters passed to the native.
 * @return 					Value for the native call to return.
 */
public int Native_SD_GetAlivePlayerCount(Handle plugin, int numParams)
{
	return GetAlivePlayerCount( GetNativeCell(1) );
}

/*
 * Returns the number of alive players in a team.
 *
 * @param 	int 	The team /CS_TEAM_T, CS_TEAM_CT/
 */
int GetAlivePlayerCount(int team)
{
	int count;
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != team)
		{
			continue;
		}
		++count;
	}
	return count;
}

/**
 * Retrieves and caches offsets for future use.
 */
void GetOffsets()
{
	m_hActiveWeapon = FindSendPropInfo("CBaseCombatCharacter", "m_hActiveWeapon");
	
	if (m_hActiveWeapon == -1)
	{
		SetFailState("Couldn't find CBaseCombatCharacter::m_hActiveWeapon");
	}
	if (m_hActiveWeapon == 0)
	{
		SetFailState("No offset available for CBaseCombatCharacter::m_hActiveWeapon");
	}
	
	m_iClip1 = FindSendPropInfo("CBaseCombatWeapon", "m_iClip1");
	
	if (m_iClip1 == -1)
	{
		SetFailState("Couldn't find CBaseCombatWeapon::m_iClip1");
	}
	if (m_iClip1 == 0)
	{
		SetFailState("No offset available for CBaseCombatWeapon::m_iClip1");
	}
	
	m_iClip2 = FindSendPropInfo("CBaseCombatWeapon", "m_iClip2");
	
	if (m_iClip2 == -1)
	{
		SetFailState("Couldn't find CBaseCombatWeapon::m_iClip2");
	}
	if (m_iClip2 == 0)
	{
		SetFailState("No offset available for CBaseCombatWeapon::m_iClip2");
	}
	
	m_iAmmo = FindSendPropInfo("CBasePlayer", "m_iAmmo");
	
	if (m_iAmmo == -1)
	{
		SetFailState("Couldn't find CBasePlayer::m_iAmmo");
	}
	if (m_iAmmo == 0)
	{
		SetFailState("No offset available for CBasePlayer::m_iAmmo");
	}
	
	m_iPrimaryAmmoType = FindSendPropInfo("CBaseCombatWeapon", "m_iPrimaryAmmoType");
	
	if (m_iPrimaryAmmoType == -1)
	{
		SetFailState("Couldn't find CBaseCombatWeapon::m_iPrimaryAmmoType");
	}
	if (m_iPrimaryAmmoType == 0)
	{
		SetFailState("No offset available for CBaseCombatWeapon::m_iPrimaryAmmoType");
	}
	
	m_iState = FindSendPropInfo("CBaseCombatWeapon", "m_iState");
	
	if (m_iState == -1)
	{
		SetFailState("Couldn't find CBaseCombatWeapon::m_iState");
	}
	if (m_iState == 0)
	{
		SetFailState("No offset available for CBaseCombatWeapon::m_iState");
	}
	
	m_hMyWeapons = FindSendPropInfo("CBaseCombatCharacter", "m_hMyWeapons");
	
	if (m_hMyWeapons == -1)
	{
		SetFailState("Couldn't find CBaseCombatCharacter::m_hMyWeapons");
	}
	if (m_hMyWeapons == 0)
	{
		SetFailState("No offset available for CBaseCombatCharacter::m_hMyWeapons");
	}
	
	m_hOwner = FindSendPropInfo("CBaseCombatWeapon", "m_hOwner");
	
	if (m_hOwner == -1)
	{
		SetFailState("Couldn't find CBaseCombatWeapon::m_hOwner");
	}
	if (m_hOwner == 0)
	{
		SetFailState("No offset available for CBaseCombatWeapon::m_hOwner");
	}
	
	m_vecOrigin = FindSendPropInfo("CBaseEntity", "m_vecOrigin");
	
	if (m_vecOrigin == -1)
	{
		SetFailState("Couldn't find CBaseEntity::m_vecOrigin");
	}
	if (m_vecOrigin == 0)
	{
		SetFailState("No offset available for CBaseEntity::m_vecOrigin");
	}
	
	Handle gameconf = LoadGameConfigFile("sd.games");
	if (gameconf == null)
	{
		SetFailState("Why you no has gamedata?");
	}
	
	int offset = GameConfGetOffset(gameconf, "TakeHealth");
	if (offset == -1)
	{
		delete gameconf;
		SetFailState("Couldn't find offset for TakeHealth");
	}
	
	g_hTakeHealth = DHookCreate(offset, HookType_Entity, ReturnType_Int, ThisPointer_CBaseEntity, Hook_TakeHealth_Pre);
	if (g_hTakeHealth == null)
	{
		delete gameconf;
		SetFailState("Couldn't setup DHooks handle for TakeHealth");
	}
	
	DHookAddParam(g_hTakeHealth, HookParamType_Float); // float flHealth
	DHookAddParam(g_hTakeHealth, HookParamType_Int); // int bitsDamageType
	delete gameconf;
}
