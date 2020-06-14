// ==============================================================================================================================
// >>> GLOBAL INCLUDES
// ==============================================================================================================================
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

// ==============================================================================================================================
// >>> PLUGIN INFORMATION
// ==============================================================================================================================
#define PLUGIN_VERSION "1.6.2f"
public Plugin:myinfo =
{
	name 			= "[Achievements] Core",
	author 			= "AlexTheRegent",
	description 	= "",
	version 		= PLUGIN_VERSION,
	url 			= ""
}

// ==============================================================================================================================
// >>> DEFINES
// ==============================================================================================================================
//#pragma newdecls required
#define MPS 		MAXPLAYERS+1
#define PMP 		PLATFORM_MAX_PATH
#define MTF 		MENU_TIME_FOREVER
#define CID(%0) 	GetClientOfUserId(%0)
#define UID(%0) 	GetClientUserId(%0)
#define SZF(%0) 	%0, sizeof(%0)
#define LC(%0) 		for (new %0 = 1; %0 <= MaxClients; ++%0) if ( IsClientInGame(%0) ) 

// debug stuff
#define DEBUG
#if defined DEBUG
stock DebugMessage(const String:message[], any:...)
{
	decl String:sMessage[256];
	VFormat(sMessage, sizeof(sMessage), message, 2);
	PrintToServer("[Debug] %s", sMessage);
}
#define DbgMsg(%0); DebugMessage(%0);
#else
#define DbgMsg(%0);
#endif

// ==============================================================================================================================
// >>> CONSOLE VARIABLES
// ==============================================================================================================================
// new Handle:		g_hConVar_iItemsPerPage;
// new Handle:		g_hConVar_iPlayersInTop;
// new Handle:		g_hConVar_bTopPlayers;
new Handle:		g_hConVar_iMinPlayers;
new Handle:		g_hConVar_iNotificationType;

// new bool:		g_bTopPlayers;
// new 			g_iItemsPerPage;
// new 			g_iPlayersInTop;
new 			g_iMinPlayers;
new 			g_iNotificationType;

// ==============================================================================================================================
// >>> GLOBAL VARIABLES
// ==============================================================================================================================
new Handle:		g_hArray_sAchievementNames;			// array with names
new Handle:		g_hTrie_AchievementData;			// name -> event, executor, condition, count, reward
new Handle:		g_hTrie_ClientProgress[MPS];		// name -> count
new Handle:		g_hTrie_EventAchievements;			// event -> array with achievement names

// forward handles
new Handle:		g_hForward_OnConfigSectionReaded;
new Handle:		g_hForward_OnGotAchievement;

// if loaded after doing some achievement
new bool:		g_bLateLoaded[MPS];

// panel stuff
new 			g_iExitBackButtonSlot;
new 			g_iExitButtonSlot;
// total achievements count
new 			g_iTotalAchievements;

// ==============================================================================================================================
// >>> LOCAL INCLUDES
// ==============================================================================================================================
#include "achievements/menus.sp"
// CreateProgressMenu(iClient)
// DisplayAchivementsMenu(iClient)
// DisplayAchivementsTypeMenu(iClient)
// DisplayInProgressMenu(iClient, iTarget, iItem=0)
// DisplayCompletedMenu(iClient, iTarget, iItem=0)
// DisplayAchivementDetailsMenu(iClient, iTarget, const String:sName[])
// DisplayPluginTopMenu(iClient, iStartItem, iItemsPerPage) 

#include "achievements/handlers.sp"
// menu handles 

#include "achievements/configuration.sp"
// LoadAchivements();

#include "achievements/sql.sp"
// CreateDatabase();
// LoadClient(iClient);
// LoadProgress(iClient);
// SaveProgress(iClient, const String:sName[]);

#include "achievements/events.sp"
// ProcessEvent(iClient, Handle:hEvent, const String:sEventName[])
// GetPlayingClients()

#include "achievements/modules.sp"
// ProcessModule(Handle:hTrie, const String:sEventName[]);

#include "achievements/reward.sp"
// GiveReward(iClient, const String:sName[]);

// ==============================================================================================================================
// >>> FORWARDS
// ==============================================================================================================================
public APLRes:AskPluginLoad2(Handle:hMySelf, bool:bLate, String:sError[], iErrorMax)
{
	// register natives
	CreateNative("Achievements_ProcessEvent", Native_ProcessEvent);
	return APLRes_Success;
}

public OnPluginStart() 
{
	// create forwards
	g_hForward_OnConfigSectionReaded = CreateGlobalForward("Achievements_OnConfigSectionReaded", ET_Ignore, Param_Cell, Param_String);
	g_hForward_OnGotAchievement = CreateGlobalForward("Achievements_OnGotAchievement", ET_Ignore, Param_Cell, Param_String);
	
	// load translations
	LoadTranslations("achievements_common.phrases.txt");
	LoadTranslations("achievements.phrases.txt");
	// establish database connection
	CreateDatabase();
	
	// dependency of panel keys from game engine
	// decl String:sGameName[32];
	// GetGameFolderName(SZF(sGameName));
	// if ( strcmp(sGameName, "csgo") == 0 ) {
	if ( GetEngineVersion() == Engine_CSGO ) {
		g_iExitBackButtonSlot = 7;
		g_iExitButtonSlot = 9;
	}
	else {
		g_iExitBackButtonSlot = 8;
		g_iExitButtonSlot = 10;
	}
	
	// register commands
	RegConsoleCmd("sm_achievements", 	Command_Achievements);
	RegConsoleCmd("sm_ach", 			Command_Achievements);
	
	// create convars
	CreateConVar("sm_achievements_version", PLUGIN_VERSION, "[Achievements] core plugin version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	// g_hConVar_iItemsPerPage = CreateConVar("sm_achievements_items_per_page", "5", "Top players per page", 0, true, 1.0, true, 7.0);
	// g_hConVar_iPlayersInTop = CreateConVar("sm_achievements_players_in_top", "15", "Players in top", 0, true, 0.0);
	// g_hConVar_bTopPlayers = CreateConVar("sm_achievements_top_players", "1", "Show (1) or not (0) top players item in menu", 0, true, 0.0, true, 1.0);
	g_hConVar_iMinPlayers 		= CreateConVar("sm_achievements_min_players", "4", "Min players for plugin to work", 0, true, 0.0);
	g_hConVar_iNotificationType = CreateConVar("sm_achievements_notification_type", "2", "When player got achievement write about it: 2 - in all chat, 1 - only to player, 0 - do not write", 0, true, 0.0);
	AutoExecConfig(true, "achievements_core");
}

public OnMapStart() 
{
	// do nothing
}

public OnConfigsExecuted() 
{
	// extract cvar values
	// g_iItemsPerPage = GetConVarInt(g_hConVar_iItemsPerPage);
	// g_iPlayersInTop = GetConVarInt(g_hConVar_iPlayersInTop);
	// g_bTopPlayers   = GetConVarBool(g_hConVar_bTopPlayers);
	g_iNotificationType = GetConVarInt(g_hConVar_iNotificationType);
	g_iMinPlayers = GetConVarInt(g_hConVar_iMinPlayers);
}

public OnAllPluginsLoaded()
{
	// bad but ok for first time. 
	// will be replaced with forward
	LoadAchivements();
}

public OnClientConnected(iClient)
{
	// allocate memory
	g_hTrie_ClientProgress[iClient] = CreateTrie();
	g_bLateLoaded[iClient] = false;
}

public OnClientPutInServer(iClient)
{
	// load client data
	LoadClient(iClient);
}

public OnClientDisconnect(iClient)
{
	// free memory
	CloseHandle(g_hTrie_ClientProgress[iClient]);
}

// ==============================================================================================================================
// >>> 
// ==============================================================================================================================
public Action:Command_Achievements(iClient, iArgc)
{
	DisplayAchivementsMenu(iClient);
	return Plugin_Handled;
}
