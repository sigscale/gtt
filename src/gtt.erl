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

-export([add_endpoint/6, add_endpoint/7, find_endpoint/1,
		start_endpoint/1, stat_endpoint/1, stat_endpoint/2]).
-export([add_sg/6, add_sg/7, find_sg/1, start_sg/1]).
-export([add_as/7, add_as/8, get_as/0, find_as/1, start_as/1]).
-export([add_key/1, find_pc/1, find_pc/2, find_pc/3, find_pc/4]).

-include("gtt.hrl").

%%----------------------------------------------------------------------
%%  The gtt public API
%%----------------------------------------------------------------------

-spec add_endpoint(Name, Local, Remote,
		SCTPRole, M3UARole, Callback) -> Result
	when
		Name :: term(),
		Local :: {Address, Port, Options},
		Remote :: undefined | {Address, Port, Options},
		SCTPRole :: client | server,
		M3UARole :: sgp | asp,
		Callback :: atom() | #m3ua_fsm_cb{},
		Port :: inet:port_number(),
		Address :: inet:ip_address(),
		Options :: list(),
		Result :: {ok, EP} | {error, Reason},
		EP :: #gtt_endpoint{},
		Reason :: term().
%% @equiv add_endpoint(Name, Local, Remote, SCTPRole, M3UARole, Callback, node())
add_endpoint(Name, Local, Remote, SCTPRole, M3UARole, Callback) ->
	add_endpoint(Name, Local, Remote, SCTPRole, M3UARole, Callback, node()).

-spec add_endpoint(Name, Local, Remote,
		SCTPRole, M3UARole, Callback, Node) -> Result
	when
		Name :: term(),
		Local :: {Address, Port, Options},
		Remote :: undefined | {Address, Port, Options},
		SCTPRole :: client | server,
		M3UARole :: sgp | asp,
		Callback :: atom() | #m3ua_fsm_cb{},
		Node :: node(),
		Port :: inet:port_number(),
		Address :: inet:ip_address(),
		Options :: list(),
		Result :: {ok, EP} | {error, Reason},
		EP :: #gtt_endpoint{},
		Reason :: term().
%% @doc Create an endpoint.
add_endpoint(Name, {LocalAddr, LocalPort, _} = Local,
		Remote, SCTPRole, M3UARole, Callback, Node) when
		is_tuple(LocalAddr), is_integer(LocalPort),
		((is_tuple(Remote)) orelse (Remote == undefined)),
		((is_tuple(Callback)) orelse (is_atom(Callback))),
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

-spec add_as(Name, NA, Keys, Mode, MinAsp, MaxAsp, EPs) -> Result
	when
		Name :: term(),
		NA :: pos_integer(),
		Keys :: [Key],
		Mode :: override | loadshare | broadcast,
		MinAsp :: pos_integer(),
		MaxAsp :: pos_integer(),
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
%% @doc Create new Application Server entry.
add_as(Name, NA, Keys, Mode, MinAsp, MaxAsp, EPs) ->
	add_as(Name, NA, Keys, Mode, MinAsp, MaxAsp, node(), EPs).

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

-spec get_as() -> AsNames
	when
		AsNames :: [AsName],
		AsName :: term().
%% @doc Get names of all Application Servers.
get_as() ->
	F = fun() -> mnesia:all_keys(gtt_as) end,
	case mnesia:transaction(F) of
		{atomic, AsNames} ->
			AsNames;
		{aborted, Reason} ->
			exit(Reason)
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

-spec add_sg(Name, NA, Keys, Mode, MinAsp, MaxAsp) -> Result
	when
		Name :: term(),
		NA :: pos_integer(),
		Keys :: [Key],
		Mode :: override | loadshare | broadcast,
		MinAsp :: pos_integer(),
		MaxAsp :: pos_integer(),
		Result :: {ok, AS} | {error, Reason},
		Key :: {DPC, SIs, OPCs},
		DPC :: pos_integer(),
		SIs :: [SI],
		OPCs :: [OPC],
		SI :: pos_integer(),
		OPC :: pos_integer(),
		AS :: #gtt_sg{},
		Reason :: term().
%% @doc Create new Service Gateway entry.
add_sg(Name, NA, Keys, Mode, MinAsp, MaxAsp) ->
	add_sg(Name, NA, Keys, Mode, MinAsp, MaxAsp, node()).

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

-spec add_key(Key) -> Result
	when
		Key :: routing_key(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Add point codes to Point Code table.
add_key({NA, Keys, _} = Key) when is_list(Keys),
		(is_integer(NA) or (NA == undefined)) ->
	Fadd = fun(F, [{DPC, SI, OPC} | T]) when is_integer(DPC),
					is_list(SI), is_list(OPC) ->
				PC = #gtt_pc{dpc = DPC, na = NA, si = SI, opc = OPC, as = Key},
				ok = mnesia:write(PC),
				F(F, T);
			(_, []) ->
				ok
	end,
	case mnesia:transaction(Fadd, [Fadd, Keys]) of
		{atomic, ok} ->
			ok;
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec find_pc(DPC) -> Result
	when
		DPC :: pos_integer(),
		Result :: [ASref],
		ASref :: routing_key().
%% @equiv find_pc(undefined, DPC, undefined, undefined)
find_pc(DPC) ->
	find_pc(undefined, DPC, undefined, undefined).

-spec find_pc(DPC, SI) -> Result
	when
		DPC :: pos_integer(),
		SI :: pos_integer() | undefined,
		Result :: [ASref],
		ASref :: routing_key().
%% @equiv find_pc(undefined, DPC, SI, undefined)
find_pc(DPC, SI) ->
	find_pc(undefined, DPC, SI, undefined).

-spec find_pc(DPC, SI, OPC) -> Result
	when
		DPC :: pos_integer(),
		SI :: pos_integer() | undefined,
		OPC :: pos_integer() | undefined,
		Result :: [ASref],
		ASref :: routing_key().
%% @equiv find_pc(undefined, DPC, SI, OPC)
find_pc(DPC, SI, OPC) ->
	find_pc(undefined, DPC, SI, OPC).

-spec find_pc(NA, DPC, SI, OPC) -> Result
	when
		NA :: pos_integer() | undefined,
		DPC :: pos_integer(),
		SI :: pos_integer() | undefined,
		OPC :: pos_integer() | undefined,
		Result :: [ASref],
		ASref :: routing_key().
%% @doc Find Application Servers matching destination.
find_pc(NA, DPC, SI, OPC)
		when ((NA == undefined) or is_integer(NA)),
		((DPC == undefined) or is_integer(DPC)),
		((SI == undefined) or is_integer(SI)),
		((OPC == undefined) or is_integer(OPC)) ->
	find_pc1(NA, DPC, SI, OPC, #gtt_pc{}).
%% @hidden
find_pc1(undefined, DPC, SI, OPC, GTT) ->
	find_pc2(DPC, SI, OPC, GTT#gtt_pc{na = '_'});
find_pc1(NA, DPC, SI, OPC, GTT) when is_integer(NA) ->
	find_pc2(DPC, SI, OPC, GTT#gtt_pc{na = NA}).
%% @hidden
find_pc2(DPC, SI, undefined, GTT) ->
	find_pc3(DPC, SI, GTT#gtt_pc{opc = '_'});
find_pc2(DPC, SI, OPC, GTT) when is_integer(OPC) ->
	% @todo match in list of OPC
	find_pc3(DPC, SI, GTT#gtt_pc{opc = [OPC]}).
%% @hidden
find_pc3(DPC, undefined, GTT) ->
	find_pc4(DPC, GTT#gtt_pc{si = '_'});
find_pc3(DPC, SI, GTT) when is_integer(SI) ->
	% @todo match in list of SI
	find_pc4(DPC, GTT#gtt_pc{si = [SI]}).
%% @hidden
find_pc4(DPC, GTT) when is_integer(DPC) ->
	MatchHead = GTT#gtt_pc{dpc = DPC, mask = '_', as = '$1'},
	MatchConditions = [],
	MatchBody = ['$1'],
	MatchFunction = {MatchHead, MatchConditions, MatchBody},
	MatchExpression = [MatchFunction],
	mnesia:dirty_select(gtt_pc, MatchExpression).

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
					callback = Callback, local = {LocalAddr, LocalPort, Options},
					node = Node} = EP] ->
				NewOptions = [{sctp_role, SCTPRole}, {m3ua_role, M3UARole},
					{ip, LocalAddr}] ++ Options,
				case catch start_endpoint1(Node, LocalPort, NewOptions, Callback) of
					{ok, EndPoint} ->
						NewEP = EP#gtt_endpoint{ep = EndPoint},
						ok = mnesia:write(NewEP);
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
start_endpoint1(Node, Port, Options, Callback) when Node == node() ->
	m3ua:open(Port, Options, Callback);
start_endpoint1(Node, Port, Options, Callback) ->
	case rpc:call(Node, m3ua, open, [Port, Options, Callback]) of
		{ok, EP} ->
			{ok, EP};
		{error, Reason} ->
			{error, Reason};
		{badrpc, Reason} ->
			{error, Reason}
	end.


-spec start_sg(SgName) -> Result
	when
		SgName :: term(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Register remote Appication Server.
start_sg(SgName) ->
	F = fun() ->
		case mnesia:read(gtt_sg, SgName, read) of
			[#gtt_sg{na = NA, keys = Keys, mode = Mode,
					min_asp = Min, max_asp = Max, node = Node}] ->
				case start_sg1(Node, SgName, NA, Keys, Mode, Min, Max) of
					{ok, _} ->
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
start_sg1(Node, SgName, NA, Keys, Mode, Min, Max) when Node == node() ->
	m3ua:as_add(SgName, NA, Keys, Mode, Min, Max);
start_sg1(Node, SgName, NA, Keys, Mode, Min, Max) ->
	rpc:call(Node, m3ua, as_add, [SgName, NA, Keys, Mode, Min, Max]).

-spec start_as(AsName) -> Result
	when
		AsName :: term(),
		Result :: ok.
%% @doc Register local Appication Server.
start_as(AsName) ->
	F = fun() ->
		case mnesia:read(gtt_as, AsName, write) of
			[#gtt_as{eps = EpRefs} = As] ->
				start_as1(As, EpRefs);
			[] ->
				ok
		end
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			ok;
		{aborted, Reason} ->
			{error, Reason}
	end.
%% @hidden
start_as1(#gtt_as{max_asp = Max} = As, [EPRef | T]) ->
	case mnesia:read(gtt_endpoint, EPRef, read) of
		[#gtt_endpoint{remote = undefined}] ->
			start_as1(As, T);
		[#gtt_endpoint{ep = EP, node = Node,
				remote = {RAddr, RPort, Options},
				m3ua_role = M3UARole, sctp_role = SCTPRole}] ->
			NewAs = start_as2(Node, EP, RAddr, RPort,
					Options, SCTPRole, M3UARole, Max, As),
			start_as1(NewAs, T);
		[] ->
			error_logger:error_report(["Endpoint not found",
					{ep, EPRef}, {reason, epunavilable},
					{module, ?MODULE}]),
			start_as1(As, T)
	end;
start_as1(As, []) ->
	ok.
%% @hidden
start_as2(Node1, _, _, _, _, _, _, _, #gtt_as{node = Node2} = As)
		when Node1 /= Node2 ->
	As;
start_as2(_, _, _, _, _, _, _, 0 = _Max, As) ->
	As;
start_as2(Node, EP, Address, Port, Options, SCTPRole, M3UARole,
		Max, #gtt_as{name = AsName, keys = Keys, na = Na, mode = Mode,
		asp = Asps} = As) when Node == node() ->
	case m3ua:sctp_establish(EP, Address, Port, Options) of
		{ok, Assoc} ->
			case start_as3(Node, EP, Assoc, AsName, Na, Keys, Mode) of
				ok ->
					NewAsps = [{EP, Assoc} | Asps],
					start_as2(Node, EP, Address, Port, Options,
						SCTPRole, M3UARole, Max - 1, As#gtt_as{asp = NewAsps});
				{error, _Reason} ->
					start_as2(Node, EP, Address, Port, Options, SCTPRole, M3UARole, Max, As)
			end;
		{error, Reason} ->
			error_logger:error_report(["Faild to establish sctp connection",
					{ep, EP}, {address, Address}, {port, Port},
					{module, ?MODULE}, {reason, Reason}]),
			As
	end;
start_as2(Node, EP, Address, Port, Options, SCTPRole, M3UARole,
		Max, #gtt_as{name = AsName, keys = Keys, na = Na, mode = Mode,
		asp = Asps} = As) ->
	case rpc:call(Node, m3ua, sctp_establish, [EP, Address, Port, Options]) of
		{ok, Assoc} ->
			case start_as3(Node, EP, Assoc, AsName, Na, Keys, Mode) of
				ok ->
					NewAsps = [{EP, Assoc} | Asps],
					start_as2(Node, EP, Address, Port, Options,
							SCTPRole, M3UARole, Max - 1, As#gtt_as{asp = NewAsps});
				{error, _Reason} ->
					start_as2(Node, EP, Address, Port, Options, SCTPRole, M3UARole, Max, As)
			end;
		{_, Reason} ->
			error_logger:error_report(["Faild to establish sctp connection",
					{ep, EP}, {address, Address}, {port, Port},
					{module, ?MODULE}, {reason, Reason}]),
			As
	end.
%% @hidden
start_as3(Node, EP, Assoc, AsName, Na, Keys, Mode) when Node == node() ->
	case m3ua:asp_up(EP, Assoc) of
		ok ->
			start_as4(Node, EP, Assoc, AsName, Na, Keys, Mode);
		{error, Reason} ->
			{error, Reason}
	end;
start_as3(Node, EP, Assoc, AsName, Na, Keys, Mode) ->
	case rpc:call(Node, m3ua, asp_up, [EP, Assoc]) of
		ok ->
			start_as4(Node, EP, Assoc, AsName, Na, Keys, Mode);
		{error, Reason} ->
			{error, Reason};
		{badrpc, Reason} ->
			{error, Reason}
	end.
%% @hidden
start_as4(Node, EP, Assoc, AsName, NA, Keys, Mode) when Node == node() ->
	case m3ua:register(EP, Assoc, NA, Keys, Mode, AsName) of
		{ok, _} ->
			ok;
		{error, Reason} ->
			{error, Reason}
	end;
start_as4(Node, EP, Assoc, AsName, NA, Keys, Mode) ->
	case rpc:call(Node, m3ua, register,
			[EP, Assoc, NA, Keys, Mode, AsName]) of
		{ok, _} ->
			ok;
		{error, Reason} ->
			{error, Reason};
		{badrpc, Reason} ->
			{error, Reason}
	end.

-spec stat_endpoint(EPRef) -> Result
	when
		EPRef :: term(),
		Result :: {ok, OptionValues} | {error, inet:posix()},
		OptionValues :: [{inet:stat_option(), Count}],
		Count :: non_neg_integer().
%% @doc Get socket statistics for an endpoint.
%% @see //m3ua/m3ua:getstat_endpoint/1
stat_endpoint(EPRef) ->
	case find_endpoint(EPRef) of
		{ok, #gtt_endpoint{node = Node, ep = EP}}
				when Node == undefined orelse Node == node() ->
			m3ua:getstat_endpoint(EP);
		{ok, #gtt_endpoint{node = Node, ep = EP}} ->
			case rpc:call(Node, m3ua, getstat_endpoint, [EP]) of
				{ok, OptionValues} ->
					{ok, OptionValues};
				{error, Reason} ->
					{error, Reason};
				{badrpc, Reason} ->
					{error, Reason}
			end;
		{error, Reason} ->
			{error, Reason}
	end.

-spec stat_endpoint(EPRef, Options) -> Result
	when
		EPRef :: term(),
		Options :: [inet:stat_option()],
		Result :: {ok, OptionValues} | {error, inet:posix()},
		OptionValues :: [{inet:stat_option(), Count}],
		Count :: non_neg_integer().
%% @doc Get socket statistics for an endpoint.
%% @see //m3ua/m3ua:getstat_endpoint/2
stat_endpoint(EPRef, Options) when is_list(Options) ->
	case find_endpoint(EPRef) of
		{ok, #gtt_endpoint{node = Node, ep = EP}}
				when Node == undefined orelse Node == node() ->
			m3ua:getstat_endpoint(EP, Options);
		{ok, #gtt_endpoint{node = Node, ep = EP}} ->
			case rpc:call(Node, m3ua, getstat_endpoint, [EP, Options]) of
				{ok, OptionValues} ->
					{ok, OptionValues};
				{error, Reason} ->
					{error, Reason};
				{badrpc, Reason} ->
					{error, Reason}
			end;
		{error, Reason} ->
			{error, Reason}
	end.

%%----------------------------------------------------------------------
%%  The gtt private API
%%----------------------------------------------------------------------


%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

