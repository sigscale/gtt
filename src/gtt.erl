%%% gtt.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2015-2018 SigScale Global Inc.
%%% @end
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc This library module implements the public API for the
%%% 	{@link //gtt. gtt} application.
%%%
-module(gtt).
-copyright('Copyright (c) 2015-2018 SigScale Global Inc.').

-export([add_endpoint/7, find_endpoint/1, start_endpoint/1]).
-export([add_sg/7, find_sg/1, start_sg/1]).
-export([add_as/8, find_as/1]).

-include("gtt.hrl").

%%----------------------------------------------------------------------
%%  The gtt public API
%%----------------------------------------------------------------------

-spec add_endpoint(Name, Local, Remote,
		SCTPRole, M3UARole, Callback, Node) -> Result
	when
		Name :: term(),
		Local :: {Address, Port, Options},
		Remote :: {Address, Port, Options},
		SCTPRole :: client | server,
		M3UARole :: sgp | asp,
		Callback :: {Module, State},
		Node :: node(),
		Port :: inet:port_number(),
		Address :: inet:ip_address(),
		Options :: list(),
		Module :: atom(),
		State :: term(),
		Result :: {ok, EP} | {error, Reason},
		EP :: #gtt_endpoint{},
		Reason :: term().
%% @doc Create an endpoint
add_endpoint(Name, {LocalAddr, LocalPort, _} = Local,
		{RemoteAddr, RemotePort, _} = Remote, SCTPRole, M3UARole,
		Callback, Node) when is_tuple(LocalAddr), is_integer(LocalPort),
		is_tuple(RemoteAddr), is_integer(RemotePort), is_tuple(Callback),
		((SCTPRole == client) orelse (SCTPRole == server)),
		((M3UARole == sgp) orelse (M3UARole == asp))->
	F = fun() ->
			GttEP = #gtt_endpoint{name = Name, local = Local,
				remote = Remote, sctp_role = SCTPRole, m3ua_role = M3UARole,
				callback = Callback, node = Node},
			mnesia:write(gtt_endpoint, GttEP, write),
			GttEP
	end,
	case mnesia:transaction(F) of
		{atomic, EP} ->
			{ok, EP};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec find_endpoint(EndPointName) -> Result
	when
		EndPointName :: term(),
		Result :: {ok, EndPoint} | {error, Reason},
		EndPoint :: #gtt_endpoint{},
		Reason :: term().
%% @doc Search for an endpoint entry in gtt_endpoint table
find_endpoint(EndPointName) ->
	F = fun() -> mnesia:read(gtt_endpoint, EndPointName, read) end,
	case mnesia:transaction(F) of
		{atomic, []} ->
			{error, not_found};
		{atomic, [#gtt_endpoint{} = EndPoint]} ->
			{ok, EndPoint};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec add_as(Name, NA, Keys, Mode, MinAsp, MaxAsp, Node, EPs) -> Result
	when
		Name :: term(),
		NA :: pos_integer(),
		Keys :: [Key],
		Mode :: override | loadshare | broadcast,
		MinAsp :: pos_integer(),
		MaxAsp :: pos_integer(),
		Node :: node(),
		EPs :: [EPRef],
		Result :: {ok, AS} | {error, Reason},
		Key :: {DPC, SIs, OPCs},
		DPC :: pos_integer(),
		SIs :: [SI],
		OPCs :: [OPC],
		SI :: pos_integer(),
		OPC :: pos_integer(),
		EPRef :: term(),
		AS :: #gtt_as{},
		Reason :: term().
%% @doc Create new Application Server entry
add_as(Name, NA, Keys, Mode, MinAsp, MaxAsp, Node, EPs)
		when is_integer(NA), is_list(Keys), is_integer(MinAsp),
		is_integer(MaxAsp), ((Mode == override) orelse (Mode == loadshare)
		orelse (Mode == broadcast)) ->
	F = fun() ->
			GttAs = #gtt_as{name = Name, na = NA, keys = Keys,
					mode = Mode, min_asp = MinAsp, max_asp = MaxAsp,
					node = Node, eps = EPs},
			mnesia:write(gtt_as, GttAs, write),
			GttAs
	end,
	case mnesia:transaction(F) of
		{atomic, AS} ->
			{ok, AS};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec find_as(AsName) -> Result
	when
		AsName :: term(),
		Result :: {ok, AS} | {error, Reason},
		AS :: #gtt_as{},
		Reason :: term().
%% @doc Search for an endpoint entry in gtt_as table
find_as(AsName) ->
	F = fun() -> mnesia:read(gtt_as, AsName, read) end,
	case mnesia:transaction(F) of
		{atomic, []} ->
			{error, not_found};
		{atomic, [#gtt_as{} = AS]} ->
			{ok, AS};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec add_sg(Name, NA, Keys, Mode, MinAsp, MaxAsp, Node) -> Result
	when
		Name :: term(),
		NA :: pos_integer(),
		Keys :: [Key],
		Mode :: override | loadshare | broadcast,
		MinAsp :: pos_integer(),
		MaxAsp :: pos_integer(),
		Node :: node(),
		Result :: {ok, AS} | {error, Reason},
		Key :: {DPC, SIs, OPCs},
		DPC :: pos_integer(),
		SIs :: [SI],
		OPCs :: [OPC],
		SI :: pos_integer(),
		OPC :: pos_integer(),
		AS :: #gtt_sg{},
		Reason :: term().
%% @doc Create new Service Gateway entry
add_sg(Name, NA, Keys, Mode, MinAsp, MaxAsp, Node)
		when is_integer(NA), is_list(Keys), is_integer(MinAsp),
		is_integer(MaxAsp), ((Mode == override) orelse (Mode == loadshare)
		orelse (Mode == broadcast))->
	F = fun() ->
			GttSg = #gtt_sg{name = Name, na = NA, keys = Keys,
					mode = Mode, min_asp = MinAsp, max_asp = MaxAsp,
					node = Node},
			mnesia:write(gtt_sg, GttSg, write),
			GttSg
	end,
	case mnesia:transaction(F) of
		{atomic, SG} ->
			{ok, SG};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec find_sg(SgName) -> Result
	when
		SgName :: term(),
		Result :: {ok, SG} | {error, Reason},
		SG :: #gtt_sg{},
		Reason :: term().
%% @doc Search for an endpoint entry in gtt_sg table
find_sg(SgName) ->
	F = fun() -> mnesia:read(gtt_sg, SgName, read) end,
	case mnesia:transaction(F) of
		{atomic, []} ->
			{error, not_found};
		{atomic, [#gtt_sg{} = SG]} ->
			{ok, SG};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec start_endpoint(EndPointName) -> Result
	when
		EndPointName :: term(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Start new m3ua endpoint
start_endpoint(EndPointName) ->
	F = fun() ->
		case mnesia:read(gtt_endpoint, EndPointName, write) of
			[#gtt_endpoint{sctp_role = SCTPRole, m3ua_role = M3UARole,
					callback = Callback, local = Local, remote = Remote,
					node = Node} = EP] ->
				case catch start_endpoint1(Node, Local,
						Remote, SCTPRole, M3UARole, Callback) of
					{ok, EndPoint, Assoc} ->
						NewEP = EP#gtt_endpoint{ep = EndPoint, assoc = Assoc},
						ok = mnesia:write(NewEP),
						Association = #gtt_association{key = {EndPoint, Assoc}},
						ok = mnesia:write(gtt_association, Association, write);
					{error, Reason} ->
						throw(Reason);
					{'EXIT', Reason} ->
						throw(Reason)
				end;
			[] ->
				throw(not_found)
		end
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			ok;
		{aborted, {throw, Reason}} ->
			{error, Reason};
		{aborted, Reason} ->
			{error, Reason}
	end.
%% @hidden
start_endpoint1(Node, {LocalAddr, LocalPort, Options},
		Remote, SCTPRole, M3UARole, Callback) when Node == node() ->
	NewOptions = [{sctp_role, SCTPRole}, {m3ua_role = M3UARole},
			{callback, Callback, {ip, LocalAddr}}] ++ Options,
	case m3ua:open(LocalPort, NewOptions) of
		{ok, EP} ->
			start_endpoint2(Node, Remote, SCTPRole, EP);
		{error, Reason} ->
			{error, Reason}
	end;
start_endpoint1(Node, {LocalAddr, LocalPort, Options},
		Remote, SCTPRole, M3UARole, Callback) ->
	NewOptions = [{sctp_role, SCTPRole}, {m3ua_role = M3UARole},
			{callback, Callback}, {ip, LocalAddr}] ++ Options,
	case rpc:call(Node, m3ua, open, [LocalPort, NewOptions]) of
		{ok, EP} ->
			start_endpoint2(Node, Remote, SCTPRole, EP);
		{error, Reason} ->
			{error, Reason};
		{badrpc, Reason} ->
			{error, Reason}
	end.
%% @hidden
start_endpoint2(Node, {RemoteAddr, RemotePort, Options}, client, EP)
		when Node == node() ->
	case m3ua:sctp_establish(EP, RemoteAddr, RemotePort, Options) of
		{ok, Assoc} ->
			{ok, EP, Assoc};
		{error, Reason} ->
			{error, Reason}
	end;
start_endpoint2(Node, {RemoteAddr, RemotePort, Options}, client, EP) ->
	case rpc:call(Node, m3ua, sctp_establish,
			[EP, RemoteAddr, RemotePort, Options]) of
		{ok, Assoc} ->
			{ok, EP, Assoc};
		{error, Reason} ->
			{error, Reason};
		{badrpc, Reason} ->
			{error, Reason}
	end;
start_endpoint2(_Node, _Remote, server, EP) ->
	{ok, EP, undefined}.


-spec start_sg(AsName) -> Result
	when
		AsName :: term(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Register remote Appication Server.
start_sg(AsName) ->
	F = fun() ->
		case mnesia:read(gtt_sg, AsName, read) of
			[#gtt_sg{na = NA, keys = Keys, mode = Mode,
					min_asp = Min, max_asp = Max, node = Node}] ->
				case start_sg1(Node, AsName, NA, Keys, Mode, Min, Max) of
					ok ->
						ok;
					{badrpc, Reason} ->
						throw(Reason);
					{error, Reason} ->
						throw(Reason)
				end;
			[] ->
				throw(not_found)
		end
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			ok;
		{aborted, {throw, Reason}} ->
			{error, Reason};
		{aborted, Reason} ->
			{error, Reason}
	end.
%% @hidden
start_sg1(Node, AsName, NA, Keys, Mode, Min, Max) when Node == node() ->
	m3ua:as_add(AsName, NA, Keys, Mode, Min, Max);
start_sg1(Node, AsName, NA, Keys, Mode, Min, Max) ->
	rpc:call(Node, m3ua, as_add, [AsName, NA, Keys, Mode, Min, Max]).


%%----------------------------------------------------------------------
%%  The gtt private API
%%----------------------------------------------------------------------


%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

