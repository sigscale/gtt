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

-export([add_ep/7, add_ep/8, get_ep/0, find_ep/1,
		start_ep/1, stat_ep/1, stat_ep/2]).
-export([add_as/7, get_as/0, find_as/1]).
-export([add_key/1, find_pc/1, find_pc/2, find_pc/3, find_pc/4]).

-include("gtt.hrl").

%%----------------------------------------------------------------------
%%  The gtt public API
%%----------------------------------------------------------------------

-export_type([ep_ref/0, as_ref/0]).

-spec add_ep(Name, Local, Remote,
		SctpRole, M3uaRole, Callback, ApplicationServers) -> Result
	when
		Name :: ep_ref(),
		Local :: {Address, Port, Options},
		Remote :: undefined | {Address, Port, Options},
		SctpRole :: client | server,
		M3uaRole :: sgp | asp,
		Callback :: atom() | #m3ua_fsm_cb{},
		ApplicationServers :: [as_ref()],
		Port :: inet:port_number(),
		Address :: inet:ip_address(),
		Options :: [m3ua:option()],
		Result :: {ok, EP} | {error, Reason},
		EP :: #gtt_ep{},
		Reason :: term().
%% @equiv add_ep(Name, Local, Remote, SctpRole, M3uaRole, Callback, node())
add_ep(Name, Local, Remote, SctpRole, M3uaRole,
		Callback, ApplicationServers) ->
	add_ep(Name, Local, Remote, SctpRole, M3uaRole,
			Callback, ApplicationServers, node()).

-spec add_ep(Name, Local, Remote,
		SctpRole, M3uaRole, Callback, ApplicationServers, Node) -> Result
	when
		Name :: ep_ref(),
		Local :: {Address, Port, Options},
		Remote :: undefined | {Address, Port, Options},
		SctpRole :: client | server,
		M3uaRole :: sgp | asp,
		Callback :: atom() | #m3ua_fsm_cb{},
		ApplicationServers :: [as_ref()],
		Node :: node(),
		Port :: inet:port_number(),
		Address :: inet:ip_address(),
		Options :: [m3ua:option()],
		Result :: {ok, EP} | {error, Reason},
		EP :: #gtt_ep{},
		Reason :: term().
%% @doc Create an SCTP endpoint specification.
add_ep(Name, {LocalAddr, LocalPort, _} = Local, Remote,
		SctpRole, M3uaRole, Callback, ApplicationServers, Node) when
		is_tuple(LocalAddr), is_integer(LocalPort),
		((is_tuple(Remote)) orelse (Remote == undefined)),
		((is_tuple(Callback)) orelse (is_atom(Callback))),
		((SctpRole == client) orelse (SctpRole == server)),
		((M3uaRole == sgp) orelse (M3uaRole == asp)),
		is_list(ApplicationServers) ->
	F = fun() ->
			GttEP = #gtt_ep{name = Name, local = Local,
				remote = Remote, sctp_role = SctpRole, m3ua_role = M3uaRole,
				callback = Callback, as = ApplicationServers, node = Node},
			mnesia:write(gtt_ep, GttEP, write),
			GttEP
	end,
	case mnesia:transaction(F) of
		{atomic, EP} ->
			{ok, EP};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec get_ep() -> EpNames
	when
		EpNames :: [EpName],
		EpName :: ep_ref().
%% @doc Get names of all SCTP endpoint specifications.
get_ep() ->
	F = fun() -> mnesia:all_keys(gtt_ep) end,
	case mnesia:transaction(F) of
		{atomic, EpNames} ->
			EpNames;
		{aborted, Reason} ->
			exit(Reason)
	end.

-spec find_ep(EpName) -> Result
	when
		EpName :: ep_ref(),
		Result :: {ok, EP} | {error, Reason},
		EP :: #gtt_ep{},
		Reason :: term().
%% @doc Search for an SCTP endpoint specification by name.
find_ep(EpName) ->
	F = fun() -> mnesia:read(gtt_ep, EpName, read) end,
	case mnesia:transaction(F) of
		{atomic, []} ->
			{error, not_found};
		{atomic, [#gtt_ep{} = EP]} ->
			{ok, EP};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec add_as(Name, Role, NA, Keys, Mode, MinAsp, MaxAsp) -> Result
	when
		Name :: as_ref(),
		Role :: as | sg,
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
		AS :: #gtt_as{},
		Reason :: term().
%% @doc Create new Application Server specification.
add_as(Name, Role, NA, Keys, Mode, MinAsp, MaxAsp)
		when is_integer(NA), is_list(Keys), is_integer(MinAsp),
		is_integer(MaxAsp), ((Mode == override) orelse (Mode == loadshare)
		orelse (Mode == broadcast)), ((Role == as) orelse (Role == sg)) ->
	F = fun() ->
			GttAs = #gtt_as{name = Name, role = Role,
					na = NA, keys = Keys, mode = Mode,
					min_asp = MinAsp, max_asp = MaxAsp},
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
		AsName :: as_ref().
%% @doc Get names of all Application Server specifications.
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
		AsName :: as_ref(),
		Result :: {ok, AS} | {error, Reason},
		AS :: #gtt_as{},
		Reason :: term().
%% @doc Search for an SCTP endpoint specification.
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

-spec add_key(Key) -> Result
	when
		Key :: m3ua:routing_key(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Add MTP3 point codes to Point Code route table.
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
		Result :: [as_ref()].
%% @equiv find_pc(undefined, DPC, undefined, undefined)
find_pc(DPC) ->
	find_pc(undefined, DPC, undefined, undefined).

-spec find_pc(DPC, SI) -> Result
	when
		DPC :: pos_integer(),
		SI :: pos_integer() | undefined,
		Result :: [m3ua:routing_key()].
%% @equiv find_pc(undefined, DPC, SI, undefined)
find_pc(DPC, SI) ->
	find_pc(undefined, DPC, SI, undefined).

-spec find_pc(DPC, SI, OPC) -> Result
	when
		DPC :: pos_integer(),
		SI :: pos_integer() | undefined,
		OPC :: pos_integer() | undefined,
		Result :: [m3ua:routing_key()].
%% @equiv find_pc(undefined, DPC, SI, OPC)
find_pc(DPC, SI, OPC) ->
	find_pc(undefined, DPC, SI, OPC).

-spec find_pc(NA, DPC, SI, OPC) -> Result
	when
		NA :: pos_integer() | undefined,
		DPC :: pos_integer(),
		SI :: pos_integer() | undefined,
		OPC :: pos_integer() | undefined,
		Result :: [m3ua:routing_key()].
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

-spec start_ep(EpName) -> Result
	when
		EpName :: term(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Start SCTP endpoint.
start_ep(EpName) ->
	F = fun() -> mnesia:read(gtt_ep, EpName, read) end,
	case mnesia:transaction(F) of
		{atomic, [EP]} ->
			start_ep1(EP);
		{aborted, Reason} ->
			{error, Reason}
	end.
%% @hidden
start_ep1(#gtt_ep{name = Name, sctp_role = SctpRole,
		m3ua_role = M3uaRole, callback = Callback,
		local = {LocalAddr, LocalPort, Options}, node = Node} = EP) ->
	NewOptions = [{name, Name}, {sctp_role, SctpRole},
			{m3ua_role, M3uaRole}, {ip, LocalAddr}] ++ Options,
	case catch start_ep2(Node, LocalPort, NewOptions, Callback) of
		{ok, Pid} ->
			F = fun() -> mnesia:write(EP#gtt_ep{ep = Pid}) end,
			case mnesia:transaction(F) of
				{atomic, ok} ->
					ok;
				{aborted, Reason} ->
					{error, Reason}
			end;
		{error, Reason} ->
			{error, Reason};
		{'EXIT', Reason} ->
			{error, Reason}
	end.
%% @hidden
start_ep2(Node, Port, Options, Callback) when Node == node() ->
	m3ua:open(Port, Options, Callback);
start_ep2(Node, Port, Options, Callback) ->
	case rpc:call(Node, m3ua, open, [Port, Options, Callback]) of
		{ok, EP} ->
			{ok, EP};
		{error, Reason} ->
			{error, Reason};
		{badrpc, Reason} ->
			{error, Reason}
	end.

-spec stat_ep(EpRef) -> Result
	when
		EpRef :: ep_ref(),
		Result :: {ok, OptionValues} | {error, inet:posix()},
		OptionValues :: [{inet:stat_option(), Count}],
		Count :: non_neg_integer().
%% @doc Get socket statistics for an SCTP endpoint.
%% @see //m3ua/m3ua:getstat_endpoint/1
stat_ep(EpRef) ->
	case find_ep(EpRef) of
		{ok, #gtt_ep{node = Node, ep = EP}}
				when Node == undefined orelse Node == node() ->
			m3ua:getstat_endpoint(EP);
		{ok, #gtt_ep{node = Node, ep = EP}} ->
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

-spec stat_ep(EpRef, Options) -> Result
	when
		EpRef :: ep_ref(),
		Options :: [inet:stat_option()],
		Result :: {ok, OptionValues} | {error, inet:posix()},
		OptionValues :: [{inet:stat_option(), Count}],
		Count :: non_neg_integer().
%% @doc Get socket statistics for an SCTP endpoint.
%% @see //m3ua/m3ua:getstat_endpoint/2
stat_ep(EpRef, Options) when is_list(Options) ->
	case find_ep(EpRef) of
		{ok, #gtt_ep{node = Node, ep = EP}}
				when Node == undefined orelse Node == node() ->
			m3ua:getstat_endpoint(EP, Options);
		{ok, #gtt_ep{node = Node, ep = EP}} ->
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

