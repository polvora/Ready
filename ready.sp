#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>


#define PLUGIN_URL ""
#define PLUGIN_VERSION "1.0"
#define PLUGIN_NAME "Ready!"
#define PLUGIN_AUTHOR "Statik"

#define SOUND_MATCHSTARTING "ui/vote_success.wav"

public Plugin:myinfo = 
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = "Individual ready up in pre-game.",
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
}

new bool:isTournament = false;
new bool:isPreGame = false;
new bool:isPreGameRestart = false;

new bool:playerReady[32];

new activePlayers[32], readyPlayers[32], notReadyPlayers[32];
new activePlayersCount, readyPlayersCount, notReadyPlayersCount;

new Handle:cvarEnableSounds;
new Handle:cvarTournament;
new Handle:hud;
new Handle:altHud;

public OnPluginStart()
{
	CreateConVar("ready_version", PLUGIN_VERSION, "Ready! Version", FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
	
	cvarEnableSounds = CreateConVar("rdy_enablesounds", "1", "Enables plugin sounds", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	cvarTournament = FindConVar("mp_tournament");
	HookConVarChange(cvarTournament, OnTournamentModeChanged);
	AddCommandListener(OnTournamentRestart, "mp_tournament_restart");
	
	AddCommandListener(cmdSay, "say");
	AddCommandListener(cmdSay, "say_team");
	
	HookEvent("tournament_stateupdate", OnTournamentStateUpdate, EventHookMode_Pre);
	HookEvent("player_team", OnPlayerChangeTeam);
	HookEvent("teamplay_round_restart_seconds", OnRoundRestartSeconds, EventHookMode_Pre);
	HookEvent("teamplay_restart_round", OnRoundRestart, EventHookMode_Pre);
	
	CreateTimer(1.0, mainTimer, _, TIMER_REPEAT);
	hud = CreateHudSynchronizer();
	altHud = CreateHudSynchronizer();
}

public OnConfigsExecuted()
{
	isTournament = GetConVarBool(cvarTournament);
	PrecacheSound(SOUND_MATCHSTARTING);
}

public OnTournamentModeChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (StrEqual(newValue, "0")) isTournament = false;
	else isTournament = true;
}

public Action:OnTournamentRestart(client, const String:command[], args)
{
	UnreadyAllPlayers();
}

public Action:OnTournamentStateUpdate(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (GetEventBool(event, "namechange")) return Plugin_Continue;
	
	if (isPreGame || isPreGameRestart)
	{
		GameRules_SetProp("m_bTeamReady", 0, _ , 2, true);
		GameRules_SetProp("m_bTeamReady", 0, _ , 3, true);
	}
	return Plugin_Changed;
}

public Action:OnPlayerChangeTeam(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!isPreGame) return Plugin_Continue;
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new oldTeam = GetEventInt(event, "oldteam");
	new newTeam = GetEventInt(event, "team");
	
	if (oldTeam == 2 || oldTeam == 3)
	{
		decl String:clientName[64];
		GetClientName(client, clientName, sizeof clientName);
		String_ToUpper(clientName, clientName, sizeof(clientName));
		
		new Handle:tempHud = CreateHudSynchronizer();
		SetHudTextParams(-1.0, 0.24, 4.0, 255, 0, 0, 255, _, 0.0, 0.0, 0.0);
		ShowSyncHudTextTeam(tempHud, oldTeam, "%s LEFT YOUR TEAM", clientName);
		CloseHandle(tempHud);
	}
	
	if (newTeam == 2 || newTeam == 3)
	{
		PrintToChat(client, "\x07FFF047Type \x01.ready \x07FFF047in chat to ready/unready.");
	}
	
	playerReady[client] = false;
	UpdatePlayersState();
	DisplayReadyTable();
	return Plugin_Continue;
}

public Action:OnRoundRestartSeconds(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (isPreGame)
	{
		isPreGameRestart = true;
	}
}

public Action:OnRoundRestart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (isPreGameRestart)
	{
		SetHudTextParams(-1.0, 0.2, 3.0, 255, 255, 255, 255, _, 0.0, 0.0, 0.0);
		ShowSyncHudTextAll(altHud, "MATCH HAS BEGUN");
		isPreGameRestart = false;
	}
}

public Action:cmdSay(client, const String:command[], args)
{
	if (!isPreGame) return Plugin_Continue;
	if (!IsActivePlayer(client)) return Plugin_Continue;
	
	new String:text[192];
	GetCmdArgString(text, sizeof(text));
	StripQuotes(text);
	
	if (StrEqual(text, ".ready", false))
	{
		CreateTimer(0.1, tmrReadyCommand, client);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action:tmrReadyCommand(Handle:timer, any:client) 
{ 
	if (!IsClientInGame(client)) return Plugin_Continue;
	
	playerReady[client] = !playerReady[client];
	
	new team = GetClientTeam(client);
	decl String:teamColor[16];
	if (team == 2) strcopy(teamColor, sizeof teamColor, "\x07FF4040");
	else if (team == 3) strcopy(teamColor, sizeof teamColor, "\x0799CCFF");
	
	if (playerReady[client]) PrintToChatAll("%s%N \x01is \x079EC34FReady", teamColor, client);
	else PrintToChatAll("%s%N \x01is \x079EC34FNot Ready", teamColor, client);
	
	UpdatePlayersState();
	DisplayReadyTable();
	
	return Plugin_Continue;
}

public OnGameFrame()
{
	if (isTournament)
		isPreGame = bool:GameRules_GetProp("m_bAwaitingReadyRestart");
}

public Action:mainTimer(Handle:hTimer, any:data)
{	
	if (!isPreGame) return Plugin_Continue;
	
	UpdatePlayersState();
	if (activePlayersCount == 0) return Plugin_Continue;
	
	static retractTime = -1;
	if (retractTime >= 0)
	{
		if (notReadyPlayersCount > 0)
		{
			retractTime = -1;
			DisplayReadyTable();
			return Plugin_Continue;
		}
		if (retractTime == 0)
		{
			ServerCommand("mp_restartround 5");
			//GameRules_SetProp("m_bTeamReady", 1, _ , 2, true);
			//GameRules_SetProp("m_bTeamReady", 1, _ , 3, true);
			retractTime = -1;
			RespawnActivePlayers();
			UnreadyAllPlayers();
			
			CreateTimer(0.1, tmrSetupStart);
			
			return Plugin_Continue;
		}
		if (retractTime == 5 && GetConVarBool(cvarEnableSounds))
		{
			EmitSoundToAll(SOUND_MATCHSTARTING);
		}
		SetHudTextParams(-1.0, 0.17, 1.4, 0, 255, 0, 255, _, 0.0, 0.0, 0.0);
		ShowSyncHudTextAll(hud, "RETRACT TIME: %i", retractTime);
		SetHudTextParams(-1.0, 0.2, 1.4, 255, 255, 255, 255, _, 0.0, 0.0, 0.0);
		ShowSyncHudTextAll(altHud, "ALL PLAYERS READY");
		retractTime--;
		return Plugin_Continue;
	}
	
	if (notReadyPlayersCount == 0) // All players ready
	{
		retractTime = 5;
	}
	
	DisplayReadyTable();
	return Plugin_Continue;
}

public Action:tmrSetupStart(Handle:hTimer, any:data)
{
	SetHudTextParams(-1.0, 0.17, 4.0, 0, 255, 0, 255, _, 0.0, 0.0, 0.0);
	ShowSyncHudTextAll(hud, "SETUP CLASSES");
	SetHudTextParams(-1.0, 0.2, 4.0, 255, 255, 255, 255, _, 0.0, 0.0, 0.0);
	ShowSyncHudTextAll(altHud, "MATCH IS STARTING SOON");
}

UnreadyAllPlayers()
{
	for (new i = 0; i < sizeof playerReady; i++)
	{
		playerReady[i] = false;
	}
}

UpdatePlayersState()
{
	activePlayersCount = GetActivePlayers(activePlayers, sizeof activePlayers);
	readyPlayersCount = 0;
	notReadyPlayersCount = 0;
	
	for (new i = 0; i < activePlayersCount; i++)
	{
		if (playerReady[activePlayers[i]] == true)
			readyPlayers[readyPlayersCount++] = activePlayers[i];
		else
			notReadyPlayers[notReadyPlayersCount++] = activePlayers[i];
	}
}

GetActivePlayers(players[], maxlength)
{
	new count = 0;
	for (new i = 1; i <= MaxClients; i++)
	{
		if (count >= maxlength) break;
		if (IsActivePlayer(i))
		{
			players[count++] = i;
		}
	}
	return count;
}

RespawnActivePlayers()
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsActivePlayer(i))
			TF2_RespawnPlayer(i);
	}
}

// Is player on a team
IsActivePlayer(client)
{
	if (IsValidClient(client))
	{
		new team = GetClientTeam(client);
		if (team == 2 || team == 3)
		{
			return true;
		}
	}
	return false;
}

DisplayReadyTable()
{
	decl String:text[1024] = "";
	
	if (readyPlayersCount > 0)
	{
		StrCat(text, sizeof text, "READY:\n");
		
		for (new i = 0 ; i < readyPlayersCount ; i++)
		{
			new String:name[64]; 
			GetClientName(readyPlayers[i], name, sizeof name);
			StrCat(name, sizeof name, "\n");
			
			StrCat(text, sizeof text, name);
		}
		StrCat(text, sizeof text, "\n");
	}
	if (notReadyPlayersCount > 0)
	{
		StrCat(text, sizeof text, "NOT READY:\n");
		
		for (new i = 0 ; i < notReadyPlayersCount ; i++)
		{
			new String:name[64];
			GetClientName(notReadyPlayers[i], name, sizeof name);
			StrCat(name, sizeof name, "\n");
			
			StrCat(text, sizeof text, name);
		}
	}	
	SetHudTextParams(0.7, 0.15, 1.4, 255, 255, 255, 255, _, 0.0, 0.0, 0.0);
	ShowSyncHudTextAll(hud, text);
}

ShowSyncHudTextAll(Handle:sync, const String:message[], any:...)
{
	decl String:text[2048];
	VFormat(text, sizeof(text), message, 3);
	
	for(new i = 1; i <= MaxClients; i++) if(IsValidClient(i))
		if(IsValidClient(i))
			ShowSyncHudText(i, sync, text);
}

ShowSyncHudTextTeam(Handle:sync, team, const String:message[], any:...)
{
	decl String:text[2048];
	VFormat(text, sizeof(text), message, 4);
	
	for(new i = 1; i <= MaxClients; i++) if(IsValidClient(i))
		if(IsValidClient(i) && GetClientTeam(i) == team)
			ShowSyncHudText(i, sync, text);
}

IsValidClient(client)
{
	//if(client <= 0 || client > MaxClients || !IsClientInGame(client)) // DEBUG PURPOSES
	if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return false;
	return true;
}

String_ToUpper(const String:input[], String:output[], size) // SMLib
{
	size--;
	new x=0;
	while (input[x] != '\0')
	{
			if (IsCharLower(input[x])) 
				output[x] = CharToUpper(input[x]);
			else 
				output[x] = input[x];
			x++;
	}
	output[x] = '\0';
}






