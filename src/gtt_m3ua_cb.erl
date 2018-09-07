%%% gtt_m3ua_cb.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2018 SigScale Global Inc.
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
%%% @doc This {@link //m3ua/m3ua_asp_fsm. m3ua_asp_fsm}/{@link
%%% 	//m3ua/m3ua_sgp_fsm. m3ua_sgp_fsm} behaviour callback
%%%	module implements a handler for a User Service Access Point (USAP)
%%% 	of an M3UA stack SAP in the {@link //gtt. gtt} application.
%%%
-module(gtt_m3ua_cb).
-copyright('Copyright (c) 2018 SigScale Global Inc.').

%% m3ua_asp_fsm callbacks
-export([init/5, recv/9, send/11, pause/4, resume/4, status/4,
		register/5, asp_up/1, asp_down/1, asp_active/1,
		asp_inactive/1, notify/4, info/2, terminate/2]).

%% gtt_m3ua_cb private API
-export([select_asp/2]).

-include("gtt.hrl").
-include_lib("sccp/include/sccp.hrl").

-record(state,
		{module :: atom(),
		fsm :: pid(),
		ep :: pid(),
		ep_name :: term(),
		assoc :: pos_integer(),
		rk = [] :: [routing_key()],
		weights = [] :: [{Fsm :: pid(),
				Weight :: non_neg_integer(),
				Timestamp :: integer()}]}).

-define(TRANSFERWAIT, 1000).
-define(BLOCKTIME, 100).
-define(RECOVERYWAIT, 10000).

%%----------------------------------------------------------------------
%%  The gtt_m3ua_cb public API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The m3ua_[asp|sgp]_fsm callabcks
%%----------------------------------------------------------------------

-spec init(Module, Fsm, EP, EpName, Assoc) -> Result
	when
		Module :: atom(),
		Fsm :: pid(),
		EP :: pid(),
		EpName :: term(),
		Assoc :: pos_integer(),
		Result :: {ok, Active, State} | {error, Reason},
		Active :: true | false | once | pos_integer(),
		State :: term(),
		Reason :: term().
%% @doc Initialize ASP/SGP callback handler
%%%  Called when ASP is started.
init(m3ua_sgp_fsm, Fsm, EP, EpName, Assoc) ->
erlang:display({?MODULE, ?LINE, init, m3ua_sgp_fsm, Fsm, EP, EpName, Assoc}),
	State = #state{module = m3ua_sgp_fsm, fsm = Fsm,
			ep = EP, ep_name = EpName, assoc = Assoc},
	[#gtt_ep{as = ASs}] = mnesia:dirty_read(gtt_ep, EpName),
	init1(ASs, State, []);
init(Module, Fsm, EP, EpName, Assoc) ->
erlang:display({?MODULE, ?LINE, init, Module, Fsm, EP, EpName, Assoc}),
	{ok, once, #state{module = Module, fsm = Fsm,
			ep = EP, ep_name = EpName, assoc = Assoc}}.
%% @hidden
init1([AS | T], State, Acc) ->
	[#gtt_as{rc = RC, na = NA, keys = Keys, name = Name,
			mode = Mode}] = mnesia:dirty_read(gtt_as, AS),
	init1(T, State, [{RC, {NA, Keys, Mode}, Name} | Acc]);
init1([], State, Acc) ->
	{ok, State, lists:reverse(Acc)}.

-spec recv(Stream, RC, OPC, DPC, NI, SI, SLS, Data, State) -> Result
	when
		Stream :: pos_integer(),
		RC :: 0..4294967295 | undefined,
		OPC :: 0..16777215,
		DPC :: 0..16777215,
		NI :: byte(),
		SI :: byte(),
		SLS :: byte(),
		Data :: binary(),
		State :: term(),
		Result :: {ok, Active, NewState} | {error, Reason},
		Active :: true | false | once | pos_integer(),
		NewState :: term(),
		Reason :: term().
%% @doc MTP-TRANSFER indication
%%%  Called when data has arrived for the MTP user.
recv(Stream, RC, OPC, DPC, NI, SI, SLS, UnitData,
		#state{fsm = Fsm, ep = EP, ep_name = EpName, assoc = Assoc} = State)
%		when DPC =:= 2057; DPC =:= 2065 ->
		when DPC =:= 2073; DPC =:= 2081 ->
	log(Fsm, EP, EpName, Assoc, Stream, RC, OPC, DPC, NI, SI, SLS, UnitData),
%	ASs = lists:flatten([gtt:find_pc(PC) || PC <- [6211, 2089, 6210, 2306]]),
%	recv1(RC, 6209, 2, SI, SLS, UnitData, State, ASs);
	ASs = lists:flatten([gtt:find_pc(PC) || PC <- [2305]]),
	recv1(RC, 2058, 2, SI, SLS, UnitData, State, ASs);
recv(Stream, RC, OPC, DPC, NI, SI, SLS, UnitData,
		#state{fsm = Fsm, ep = EP, ep_name = EpName, assoc = Assoc} = State)
%		when DPC == 6209 ->
		when DPC == 2058 ->
	ASs = lists:flatten([gtt:find_pc(PC) || PC <- [2097, 2098]]),
	log(Fsm, EP, EpName, Assoc, Stream, RC, OPC, DPC, NI, SI, SLS, UnitData),
%	recv1(RC, 2057, 0, SI, SLS, UnitData, State, ASs).
%	recv1(RC, 2065, 0, SI, SLS, UnitData, State, ASs).
%	recv1(RC, 2073, 0, SI, SLS, UnitData, State, ASs).
	recv1(RC, 2081, 0, SI, SLS, UnitData, State, ASs).
%% @hidden
recv1(_RC, _OPC, _NI, _SI, _SLS, _UnitData, State, []) ->
	{ok, once, State};
recv1(RC, OPC, NI, SI, SLS, UnitData, #state{weights = Weights} = State, ASs) ->
erlang:display({?MODULE, ?LINE, RC, OPC, NI, SI, SLS, UnitData}),
	MatchHead = match_head(),
	F1 = fun({NA, Keys, Mode}) ->
				{'=:=', '$1', {{NA, [{Key} || Key <- Keys], Mode}}}
	end,
	MatchConditions = [list_to_tuple(['or' | lists:map(F1, ASs)])],
	MatchBody = [{{'$1', '$2'}}],
	MatchFunction = {MatchHead, MatchConditions, MatchBody},
	MatchExpression = [MatchFunction],
	ASPs = select(MatchExpression),
	F2 = fun F([{{_, [{PC, _, _} | _], _}, L1} | T], Acc) ->
				L2 = [A#m3ua_as_asp.fsm || A <- L1, A#m3ua_as_asp.state == active],
				F(T, [[{PC, A} || A <- L2] | Acc]);
			F([], Acc) ->
				lists:reverse(lists:flatten(Acc))
	end,
	case F2(ASPs, []) of
		[] ->
			{ok, once, State#state{weights = []}};
		ActiveAsps ->
			{DPC, Fsm, Delay, ActiveWeights} = ?MODULE:select_asp(ActiveAsps, Weights),
			Tstart = erlang:monotonic_time(),
			Ref = m3ua:cast(Fsm, 1, undefined,
					OPC, DPC, NI, SI, SLS, UnitData, ?TRANSFERWAIT),
			Weight = {Fsm, Ref, Delay, Tstart},
			NewWeights = lists:keyreplace(Fsm, 1, ActiveWeights, Weight),
			{ok, false, State#state{weights = NewWeights}}
	end.

-spec send(From, Ref, Stream, RC, OPC, DPC, NI, SI, SLS, Data, State) -> Result
	when
		From :: pid(),
		Ref :: reference(),
		Stream :: pos_integer(),
		RC :: 0..4294967295 | undefined,
		OPC :: 0..16777215,
		DPC :: 0..16777215,
		NI :: byte(),
		SI :: byte(),
		SLS :: byte(),
		Data :: binary(),
		State :: term(),
		Result :: {ok, Active, NewState} | {error, Reason},
		Active :: true | false | once | pos_integer(),
		NewState :: term(),
		Reason :: term().
%% @doc MTP-TRANSFER request
%%%  Called when data has been sent for the MTP user.
send(From, Ref, _Stream, _RC, _OPC, _DPC, _NI, _SI, _SLS, _UnitData, State) ->
erlang:display({?MODULE, ?LINE, From, Ref, _Stream, _RC, _OPC, _NI, _SI, _SLS, _UnitData}),
	From ! {'MTP-TRANSFER', confirm, Ref},
	{ok, once, State}.

%% @hidden
log(Fsm, EP, EpName, Assoc, Stream, RC, OPC, DPC, NI, SI, SLS, UnitData) ->
	case sccp_codec:sccp(UnitData) of
		#sccp_unitdata{called_party = #party_address{ri = CldRI,
				ssn = CldSSN, translation_type = CldTT, numbering_plan = CldNP,
				nai = CldNAI, gt = CldGT},
				calling_party = #party_address{ri = ClgRI, ssn = ClgSSN,
				translation_type = ClgTT, numbering_plan = ClgNP,
				nai = ClgNAI, gt = ClgGT}, data = _Payload} ->
			error_logger:info_report(["MTP-TRANSFER request",
					{fsm, Fsm}, {ep, EP}, {name, EpName}, {assoc, Assoc},
					{stream, Stream}, {rc, RC}, {opc, OPC},
					{dpc, DPC}, {ni, NI}, {si, SI}, {sls, SLS},
					{ri, {CldRI, ClgRI}}, {ssn, {CldSSN, ClgSSN}},
					{tt, {CldTT, ClgTT}}, {np, {CldNP, ClgNP}},
					{nai, {CldNAI, ClgNAI}}, {gt, {CldGT, ClgGT}}]);
		#sccp_unitdata_service{type = Type,
            return_cause = ReturnCause,
				called_party = #party_address{ri = CldRI,
				ssn = CldSSN, translation_type = CldTT, numbering_plan = CldNP,
				nai = CldNAI, gt = CldGT},
				calling_party = #party_address{ri = ClgRI, ssn = ClgSSN,
				translation_type = ClgTT, numbering_plan = ClgNP,
				nai = ClgNAI, gt = ClgGT}, data = _Payload} ->
			error_logger:info_report(["MTP-TRANSFER request",
					{fsm, Fsm}, {ep, EP}, {name, EpName}, {assoc, Assoc},
					{stream, Stream}, {rc, RC}, {opc, OPC},
					{dpc, DPC}, {ni, NI}, {si, SI}, {sls, SLS},
					{type, Type}, {return_cause, ReturnCause},
					{ri, {CldRI, ClgRI}}, {ssn, {CldSSN, ClgSSN}},
					{tt, {CldTT, ClgTT}}, {np, {CldNP, ClgNP}},
					{nai, {CldNAI, ClgNAI}}, {gt, {CldGT, ClgGT}}]);
		Other ->
erlang:display({?MODULE, ?LINE, Other})
	end.

-spec pause(Stream, RC, DPCs, State) -> Result
	when
		Stream :: pos_integer(),
		DPCs :: [DPC],
		RC :: 0..4294967295 | undefined,
		DPC :: 0..16777215,
		State :: term(),
		Result :: {ok, NewState} | {error, Reason},
		NewState :: term(),
		Reason :: term().
%% @doc MTP-PAUSE indication
%%%  Called when an SS7 destination is unreachable.
pause(_Stream, _RC, _DPCs, State) ->
erlang:display({?MODULE, ?LINE, pause, _Stream, _RC, _DPCs, State}),
	{ok, State}.

-spec resume(Stream, RC, DPCs, State) -> Result
	when
		Stream :: pos_integer(),
		RC :: 0..4294967295 | undefined,
		DPCs :: [DPC],
		DPC :: 0..16777215,
		State :: term(),
		Result :: {ok, NewState} | {error, Reason},
		NewState :: term(),
		Reason :: term().
%% @doc MTP-RESUME indication.
%%%  Called when a previously unreachable SS7 destination
%%%  becomes reachable.
resume(_Stream, _RC, _DPCs, State) ->
erlang:display({?MODULE, ?LINE, resume, _Stream, _RC, _DPCs, State}),
	{ok, State}.

-spec status(Stream, RC, DPCs, State) -> Result
	when
		Stream :: pos_integer(),
		RC :: 0..4294967295 | undefined,
		DPCs :: [DPC],
		DPC :: 0..16777215,
		State :: term(),
		Result :: {ok, NewState} | {error, Reason},
		NewState :: term(),
		Reason :: term().
%% @doc Called when congestion occurs for an SS7 destination
%%% 	or to indicate an unavailable remote user part.
status(_Stream, _RC, _DPCs, State) ->
erlang:display({?MODULE, ?LINE, status, _Stream, _RC, _DPCs, State}),
	{ok, State}.

-spec register(RC, NA, Keys, TMT, State) -> Result
	when
		RC :: 0..4294967295 | undefined,
		NA :: 0..4294967295 | undefined,
		Keys :: [key()],
		TMT :: tmt(),
		State :: term(),
		Result :: {ok, NewState} | {error, Reason},
		NewState :: term(),
		Reason :: term().
%%  @doc Called when Registration Response message with a
%%		registration status of successful from its peer or
%%		successfully processed an incoming Registration Request message.
register(RC, NA, Keys, TMT, #state{rk = RKs} = State) ->
erlang:display({?MODULE, ?LINE, register, RC, NA, Keys, TMT, State}),
	RoutingKey = {NA, Keys, TMT},
	case gtt:add_key(RoutingKey) of
		ok ->
			{ok, State#state{rk = [RoutingKey | RKs]}};
		{error, Reason} ->
			{error, Reason}
	end.

-spec asp_up(State) -> Result
	when
		State :: term(),
		Result :: {ok, State}.
%% @doc Called when ASP reports that it has received an ASP UP Ack
%% 	message from its peer or M3UA reports that it has successfully
%%		processed an incoming ASP Up message from its peer.
asp_up(#state{ep_name = EpName, ep = EP, assoc = Assoc} = State) ->
erlang:display({?MODULE, ?LINE, asp_up, State}),
	[#gtt_ep{as = ASs}] = mnesia:dirty_read(gtt_ep, EpName),
	F = fun(AS) ->
				catch gen_fsm:send_event(AS, {'M-ASP_UP', node(), EP, Assoc})
	end,
	lists:foreach(F, ASs),
	{ok, State}.

-spec asp_down(State) -> Result
	when
		State :: term(),
		Result :: {ok, State}.
%% @doc Called when ASP reports that it has received an ASP Down Ack
%%		message from its peer or M3UA reports that it has successfully
%%		processed an incoming ASP Down message from its peer.
asp_down(#state{ep_name = EpName, ep = EP, assoc = Assoc} = State) ->
erlang:display({?MODULE, ?LINE, asp_down, State}),
	[#gtt_ep{as = ASs}] = mnesia:dirty_read(gtt_ep, EpName),
	F = fun(AS) ->
				catch gen_fsm:send_event(AS, {'M-ASP_DOWN', node(), EP, Assoc})
	end,
	lists:foreach(F, ASs),
	{ok, State}.

-spec asp_active(State) -> Result
	when
		State :: term(),
		Result :: {ok, State}.
%% @doc Called when ASP reports that it has received an ASP Active
%%		Ack message from its peer or M3UA reports that it has successfully
%%		processed an incoming ASP Active message from its peer.
asp_active(#state{ep_name = EpName, ep = EP, assoc = Assoc} = State) ->
erlang:display({?MODULE, ?LINE, asp_active, State}),
	[#gtt_ep{as = ASs}] = mnesia:dirty_read(gtt_ep, EpName),
	F = fun(AS) ->
				catch gen_fsm:send_event(AS, {'M-ASP_ACTIVE', node(), EP, Assoc})
	end,
	lists:foreach(F, ASs),
	{ok, State}.

-spec asp_inactive(State) -> Result
	when
		State :: term(),
		Result :: {ok, State}.
%% @doc Called when ASP reports that it has received an ASP Inactive
%%		Ack message from its peer or M3UA reports that it has successfully
%%		processed an incoming ASP Inactive message from its peer.
asp_inactive(#state{ep_name = EpName, ep = EP, assoc = Assoc} = State) ->
erlang:display({?MODULE, ?LINE, asp_inactive, State}),
	[#gtt_ep{as = ASs}] = mnesia:dirty_read(gtt_ep, EpName),
	F = fun(AS) ->
				catch gen_fsm:send_event(AS, {'M-ASP_INACTIVE', node(), EP, Assoc})
	end,
	lists:foreach(F, ASs),
	{ok, State}.

-spec notify(RC, Status, AspID, State) -> Result
	when
		RC :: 0..4294967295 | undefined,
		Status :: as_inactive | as_active | as_pending
				| insufficient_asp_active | alternate_asp_active
				| asp_failure,
		AspID :: undefined | pos_integer(),
		State :: term(),
		Result :: {ok, State}.
%% @doc Called when SGP reports Application Server (AS) state changes.
notify(RC, Status, AspID, #state{module = m3ua_sgp_fsm} = State) ->
erlang:display({?MODULE, ?LINE, notify, RC, Status, AspID, State}),
	{ok, State};
notify(RC, Status, AspID, #state{module = m3ua_asp_fsm,
		ep_name = EpName, ep = EP, assoc = Assoc} = State) ->
erlang:display({?MODULE, ?LINE, notify, RC, Status, AspID, State}),
	[#gtt_ep{as = ASs}] = mnesia:dirty_read(gtt_ep, EpName),
	F = fun(AS) ->
				catch gen_fsm:send_event(AS, {'M-NOTIFY', node(), EP, Assoc, RC, Status, AspID})
	end,
	lists:foreach(F, ASs),
	{ok, State}.

-spec info(Info, State) -> Result
	when
		Info :: term(),
		State :: term(),
		Result :: {ok, Active, NewState} | {error, Reason},
		Active :: true | false | once | pos_integer(),
		NewState :: term(),
		Reason :: term().
%% @doc Called when ASP/SGP receives other `Info' messages.
info({'MTP-TRANSFER', confirm, Ref} = _Info, #state{weights = Weights} = State) ->
erlang:display({?MODULE, ?LINE, info, _Info, State}),
	case lists:keytake(Ref, 2, Weights) of
		{value, {Fsm, Ref, _Delay, StartTime}, Weights1} ->
			Now = erlang:monotonic_time(),
			NewDelay = Now - StartTime,
			Weights2 = [{Fsm, undefined, NewDelay, Now} | Weights1],
			{ok, once, State#state{weights = Weights2}};
		false ->
			{ok, once, State}
	end.

-spec terminate(Reason, State) -> Result
	when
		Reason :: term(),
		State :: term(),
		Result :: any().
%% @doc Called when ASP terminates.
terminate(_Reason, State) ->
erlang:display({?MODULE, ?LINE, terminate, _Reason, State}),
	ok.

%%----------------------------------------------------------------------
%%  private API functions
%%----------------------------------------------------------------------

-spec select_asp(ActiveAsps, Weights) -> Result
	when
		ActiveAsps :: [{DPC, Fsm}],
		DPC :: 0..4294967295,
		Fsm :: pid(),
		Weights :: [{Fsm, Weight, Timestamp}],
		Weight :: non_neg_integer(),
		Timestamp :: integer(),
		ActiveWeights :: [{Fsm, Weight, Timestamp}],
		Result :: {DPC, Fsm, Delay, ActiveWeights},
		Delay :: pos_integer().
%% @doc Select destination ASP with lowest weight.
select_asp(ActiveAsps, Weights) ->
	Now = erlang:monotonic_time(),
	ActiveWeights = select_asp1(Weights, ActiveAsps, Now, []),
	Fblock = fun({_, _, N, _}) when N < ?BLOCKTIME ->
				true;
			(_) ->
				false
	end,
	{Fsm, Delay} = case lists:takewhile(Fblock, ActiveWeights) of
		[{Pid, _, Delay1, _}] ->
			{Pid, Delay1};
		[] ->
			Ftimeout = fun({_, _, N, _}) when N < ?TRANSFERWAIT->
						true;
					(_) ->
						false
			end,
			case lists:takewhile(Ftimeout, ActiveWeights) of
				[] ->
					Len = length(ActiveWeights),
					{Pid, _, Delay1, _} = lists:nth(rand:uniform(Len), ActiveWeights),
					{Pid, Delay1};
				Responding ->
					Len = length(Responding),
					{Pid, _, Delay1, _} = lists:nth(rand:uniform(Len), Responding),
					{Pid, Delay1}
			end;
		NonBlocking ->
			Len = length(NonBlocking),
			{Pid, _, Delay1, _} = lists:nth(rand:uniform(Len), NonBlocking),
			{Pid, Delay1}
	end,
	{DPC, Fsm} = lists:keyfind(Fsm, 2, ActiveAsps),
	{DPC, Fsm, Delay, ActiveWeights}.
%% @hidden
select_asp1([{Fsm, _, _, Timestamp} = H | T] = _Weights, ActiveAsps, Now, Acc) ->
	case lists:keymember(Fsm, 2, ActiveAsps) of
		true when (Now - Timestamp) > ?RECOVERYWAIT ->
			select_asp1(T, ActiveAsps, Now, [{Fsm, undefined, 1, Now} | Acc]);
		true ->
			select_asp1(T, ActiveAsps, Now, [H | Acc]);
		false ->
			select_asp1(T, ActiveAsps, Now, Acc)
	end;
select_asp1([] = _Weights, ActiveAsps, Now, Acc) ->
	select_asp2(ActiveAsps, Now, lists:reverse(Acc)).
%% @hidden
select_asp2([{_, Fsm} | T] = _ActiveAsps, Now, Weights) ->
	case lists:keymember(Fsm, 1, Weights) of
		true ->
			select_asp2(T, Now, Weights);
		false ->
			select_asp2(T, Now, [{Fsm, undefined, 0, Now} | Weights])
	end;
select_asp2([] = _ActiveAsps, _Now, Weights) ->
	lists:keysort(2, Weights).

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-dialyzer([{nowarn_function, [match_head/0]}, no_contracts]).
match_head() ->
	#m3ua_as{rk = '$1', asp = '$2', state = active, _ = '_'}.

-dialyzer([{nowarn_function, [select/1]}, no_return]).
select(MatchExpression) ->
	mnesia:dirty_select(m3ua_as, MatchExpression).

