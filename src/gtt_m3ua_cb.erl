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
-export([init/5, transfer/8, pause/4, resume/4, status/4,
		register/4, asp_up/1, asp_down/1, asp_active/1,
		asp_inactive/1, notify/4, terminate/2]).

-include("gtt.hrl").
-include_lib("sccp/include/sccp.hrl").

-record(state,
		{module :: atom(),
		fsm :: pid(),
		ep :: pid(),
		ep_name :: term(),
		assoc :: pos_integer()}).

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
		Result :: {ok, State} | {error, Reason},
		State :: term(),
		Reason :: term().
%% @doc Initialize ASP/SGP callback handler
%%%  Called when ASP is started.
init(Module, Fsm, EP, EpName, Assoc) ->
erlang:display({?MODULE, ?LINE, init, Module, Fsm, EP, EpName, Assoc}),
	{ok, #state{module = Module, fsm = Fsm,
			ep = EP, ep_name = EpName, assoc = Assoc}}.

-spec transfer(Stream, RC, OPC, DPC, SLS, SIO, Data, State) -> Result
	when
		Stream :: pos_integer(),
		RC :: pos_integer() | undefined,
		OPC :: pos_integer(),
		DPC :: pos_integer(),
		SLS :: non_neg_integer(),
		SIO :: non_neg_integer(),
		Data :: binary(),
		State :: term(),
		Result :: {ok, NewState} | {error, Reason},
		NewState :: term(),
		Reason :: term().
%% @doc MTP-TRANSFER indication
%%%  Called when data has arrived for the MTP user.
transfer(Stream, RC, OPC, DPC, SLS, SIO, UnitData,
		#state{fsm = Fsm, ep = EP, ep_name = EpName, assoc = Assoc} = State)
		when DPC =:= 2057; DPC =:= 2065 ->
	log(Fsm, EP, EpName, Assoc, Stream, RC, OPC, DPC, SLS, SIO, UnitData),
	ASs = lists:flatten([gtt:find_pc(PC) || PC <- [6211, 2089, 6210, 2306]]),
	transfer1(6209, SLS, SIO, UnitData, State, ASs);
transfer(Stream, RC, OPC, DPC, SLS, SIO, UnitData,
		#state{fsm = Fsm, ep = EP, ep_name = EpName, assoc = Assoc} = State)
		when DPC == 6209 ->
	ASs = lists:flatten([gtt:find_pc(PC) || PC <- [2097, 2098]]),
	log(Fsm, EP, EpName, Assoc, Stream, RC, OPC, DPC, SLS, SIO, UnitData),
	transfer1(2057, SLS, SIO, UnitData, State, ASs).
%% @hidden
transfer1(OPC, SLS, SIO, UnitData, State, ASs) ->
erlang:display({?MODULE, ?LINE, OPC, SLS, SIO, UnitData}),
	MatchHead = match_head(),
	F1 = fun({NA, Keys, Mode}) ->
				{'=:=', '$1', {{NA, [{Key} || Key <- Keys], Mode}}}
	end,
	MatchConditions = [list_to_tuple(['or' | lists:map(F1, ASs)])],
	MatchBody = [{{'$1', '$2'}}],
	MatchFunction = {MatchHead, MatchConditions, MatchBody},
	MatchExpression = [MatchFunction],
	ASPs = select(MatchExpression),
	F2 = fun(F, [{{_, [{PC, _, _} | _], _}, L1} | T], Acc) ->
				L2 = [A#m3ua_as_asp.fsm || A <- L1, A#m3ua_as_asp.state == active],
				F(F, T, [[{PC, A} || A <- L2] | Acc]);
			(_, [], Acc) ->
				lists:reverse(lists:flatten(Acc))
	end,
	case F2(F2, ASPs, []) of
		[] ->
			ok;
		Active ->
			{DPC, Fsm} = lists:nth(rand:uniform(length(Active)), Active),
			case catch m3ua:transfer(Fsm, 1, OPC, DPC, SLS, SIO, UnitData) of
				{Error, Reason} when Error == error; Error == 'EXIT' ->
					error_logger:error_report(["MTP-TRANSFER error",
							{error, Reason}]);
				ok ->
					ok
			end
	end,
	{ok, State}.

%% @hidden
log(Fsm, EP, EpName, Assoc, Stream, RC, OPC, DPC, SLS, SIO, UnitData) ->
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
					{dpc, DPC}, {sls, SLS}, {sio, SIO},
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
					{dpc, DPC}, {sls, SLS}, {sio, SIO},
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
		RC :: pos_integer() | undefined,
		DPC :: pos_integer(),
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
		DPCs :: [DPC],
		RC :: pos_integer() | undefined,
		DPC :: pos_integer(),
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
		DPCs :: [DPC],
		RC :: pos_integer() | undefined,
		DPC :: pos_integer(),
		State :: term(),
		Result :: {ok, NewState} | {error, Reason},
		NewState :: term(),
		Reason :: term().
%% @doc Called when congestion occurs for an SS7 destination
%%% 	or to indicate an unavailable remote user part.
status(_Stream, _RC, _DPCs, State) ->
erlang:display({?MODULE, ?LINE, status, _Stream, _RC, _DPCs, State}),
	{ok, State}.

-spec register(NA, Keys, TMT, State) -> Result
	when
		NA :: pos_integer(),
		Keys :: [key()],
		TMT :: tmt(),
		State :: term(),
		Result :: {ok, NewState} | {error, Reason},
		NewState :: term(),
		Reason :: term().
%%  @doc Called when Registration Response message with a
%%		registration status of successful from its peer or
%%		successfully processed an incoming Registration Request message.
register(NA, Keys, TMT, State) ->
erlang:display({?MODULE, ?LINE, register, NA, Keys, TMT, State}),
	case gtt:add_key({NA, Keys, TMT}) of
		ok ->
			{ok, State};
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
				gen_fsm:send_event({global, AS}, {'M-ASP_UP', node(), EP, Assoc})
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
asp_down(State) ->
erlang:display({?MODULE, ?LINE, asp_down, State}),
	{ok, State}.

-spec asp_active(State) -> Result
	when
		State :: term(),
		Result :: {ok, State}.
%% @doc Called when ASP reports that it has received an ASP Active
%%		Ack message from its peer or M3UA reports that it has successfully
%%		processed an incoming ASP Active message from its peer.
asp_active(State) ->
erlang:display({?MODULE, ?LINE, asp_active, State}),
	{ok, State}.

-spec asp_inactive(State) -> Result
	when
		State :: term(),
		Result :: {ok, State}.
%% @doc Called when ASP reports that it has received an ASP Inactive
%%		Ack message from its peer or M3UA reports that it has successfully
%%		processed an incoming ASP Inactive message from its peer.
asp_inactive(State) ->
erlang:display({?MODULE, ?LINE, asp_inactive, State}),
	{ok, State}.

-spec notify(RC, Status, AspID, State) -> Result
	when
		RC :: undefined | pos_integer(),
		Status :: as_inactive | as_active | as_pending
				| insufficient_asp_active | alternate_asp_active
				| asp_failure,
		AspID :: undefined | pos_integer(),
		State :: term(),
		Result :: {ok, State}.
%% @doc Called when SGP reports Application Server (AS) state changes.
notify(_RC, _Status, _AspID, State) ->
erlang:display({?MODULE, ?LINE, notify, _RC, _Status, _AspID, State}),
	{ok, State}.

-spec terminate(Reason, State) -> Result
	when
		Reason :: term(),
		State :: term(),
		Result :: any().
%% @doc Called when ASP terminates.
terminate(_Reason, _State) ->
erlang:display({?MODULE, ?LINE, terminate, _Reason, _State}),
	ok.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-dialyzer([{nowarn_function, [match_head/0]}, no_contracts]).
match_head() ->
	#m3ua_as{routing_key = '$1', name = '_',
			min_asp = '_', max_asp = '_', state = active, asp = '$2'}.

-dialyzer([{nowarn_function, [select/1]}, no_return]).
select(MatchExpression) ->
	mnesia:dirty_select(m3ua_as, MatchExpression).

