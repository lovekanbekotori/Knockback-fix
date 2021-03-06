/*  CS:GO Knockback Fix
 *
 *  Copyright (C) 2017 Francisco 'Franc1sco' García
 * 
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option) 
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT 
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with 
 * this program. If not, see http://www.gnu.org/licenses/.
 */

#pragma semicolon 1
#include <sourcemod>
#include <dhooks>
#include <sdktools>

#define PLUGIN_VERSION "1.3.3"
#define CS_PLAYER_SPEED_RUN 260.0
#define MAX_SPEED 4096.0

new Handle:g_hGetSpeed;
new Handle:g_hTeleport;

new MaxVelocity[MAXPLAYERS+1]; 
new Float:g_fHighSpeed[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "CS:GO Knockback Fix",
	author = "Jannik \"Peace-Maker\" Hartung, Franc1sco franug, Mapeadores",
	description = "Enables knockback in CS:GO by allowing higher walking speeds when necassary",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/id/franug"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	if(GetEngineVersion() != Engine_CSGO)
	{
		Format(error, err_max, "This fix applies only on CS:GO.");
		return APLRes_Failure;
	}
	
	return APLRes_Success;
}

public OnPluginStart()
{
	//HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
	
	new Handle:hGameConf = LoadGameConfigFile("knockbackfix.games");
	if(hGameConf == INVALID_HANDLE)
		SetFailState("Gamedata file knockbackfix.games.txt is missing.");
	
	new iOffset = GameConfGetOffset(hGameConf, "GetPlayerMaxSpeed");
	//iOffset = 493;
	CloseHandle(hGameConf);
	
	if(iOffset == -1)
		SetFailState("Gamedata is missing the \"GetPlayerMaxSpeed\" offset.");
	
	g_hGetSpeed = DHookCreate(iOffset, HookType_Entity, ReturnType_Float, ThisPointer_CBaseEntity, Hook_GetPlayerMaxSpeedPost);
	if(g_hGetSpeed == INVALID_HANDLE)
		SetFailState("Failed to create hook on \"GetPlayerMaxSpeed\".");
	
	hGameConf = LoadGameConfigFile("sdktools.games");
	if(hGameConf == INVALID_HANDLE)
		SetFailState("Gamedata file sdktools.games.txt is missing.");
	iOffset = GameConfGetOffset(hGameConf, "Teleport");
	CloseHandle(hGameConf);
	if(iOffset == -1)
		SetFailState("Gamedata is missing the \"Teleport\" offset.");
	
	g_hTeleport = DHookCreate(iOffset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, Hook_OnTeleport);
	if(g_hTeleport == INVALID_HANDLE)
		return;
	DHookAddParam(g_hTeleport, HookParamType_VectorPtr);
	DHookAddParam(g_hTeleport, HookParamType_ObjectPtr);
	DHookAddParam(g_hTeleport, HookParamType_VectorPtr);
	DHookAddParam(g_hTeleport, HookParamType_Bool);
	
	// Account for late loading
	for(new i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
}

public OnClientPutInServer(client)
{
	DHookEntity(g_hGetSpeed, true, client);
	DHookEntity(g_hTeleport, false, client);
}

public OnClientDisconnect(client)
{
	g_fHighSpeed[client] = 0.0;
	
	MaxVelocity[client] = 0;
}

public MRESReturn:Hook_GetPlayerMaxSpeedPost(client, Handle:hReturn)
{
	//PrintToChat(client, "conseguido");
	if(g_fHighSpeed[client] <= 0.0)
	{
	
		if(!(GetEntityFlags(client) & FL_ONGROUND) && GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") != -1)
		{
			new flags = GetEntityFlags(client);
			SetEntityFlags(client, flags | FL_ONGROUND);
			//PrintToChat(client, "conseguido");
		}
		return MRES_Ignored;
		
	}
	
	if(!IsPlayerAlive(client))
	{
		g_fHighSpeed[client] = 0.0;
		return MRES_Ignored;
	}
	
	if(MaxVelocity[client]<=0 && (GetEntityFlags(client) & FL_INWATER || GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") != -1)) // prevent bunny hopping with the knockback
	{
		g_fHighSpeed[client] = 0.0;
		if(!(GetEntityFlags(client) & FL_ONGROUND))
		{
			new flags = GetEntityFlags(client);
			SetEntityFlags(client, flags | FL_ONGROUND);
			//PrintToChat(client, "conseguido");
		}
		return MRES_Ignored;
	}
	
	// Set new high limit temporarily.
	DHookSetReturn(hReturn, g_fHighSpeed[client]);
	
	
	return MRES_Override;
}

public MRESReturn:Hook_OnTeleport(client, Handle:hParams)
{
	//PrintToChat(client, "conseguido22");
	if(DHookIsNullParam(hParams, 3))
	{
		return MRES_Ignored;
	}
	
	// remove onground flag for a better knockback
	if(GetEntityFlags(client) & FL_ONGROUND)
	{
		new flags = GetEntityFlags(client);
		SetEntityFlags(client, flags&~FL_ONGROUND);
	}
	
	new Float:velocity[3];
	DHookGetParamVector(hParams, 3, velocity);
	
	
	// Something wants the player to get faster than he is usually allowed to walk.
	// Set the maxspeed to that value until he slowed down enough again
	new Float:fSpeed = GetVectorLength(velocity);
	
	//PrintToChatAll("Knockback value: %f",fSpeed); // debug msg
	
	if(fSpeed > CS_PLAYER_SPEED_RUN)
	{
        // Add to the counter representing how fast we're going a value divided by the minimum speed that goes out of CS:GO's limits
		MaxVelocity[client]+= 3+RoundToNearest(((fSpeed>MAX_SPEED)?MAX_SPEED:fSpeed)/CS_PLAYER_SPEED_RUN);
		RequestFrame(NextFrame, client);
		g_fHighSpeed[client] = fSpeed;

	}
	
	return MRES_Ignored;
}

public NextFrame(any:client)
{	
    if(MaxVelocity[client]>0)
    {
        RequestFrame(NextFrame, client);
        MaxVelocity[client] -= 1;
    }
}