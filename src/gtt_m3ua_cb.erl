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
-export([init/4, transfer/11, pause/7, resume/7, status/7,
		register/7, asp_up/4, asp_down/4, asp_active/4, asp_inactive/4]).

-include("gtt.hrl").
-include_lib("sccp/include/sccp.hrl").

%%----------------------------------------------------------------------
%%  The gtt_m3ua_cb public API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The m3ua_[asp|sgp]_fsm callabcks
%%----------------------------------------------------------------------

-spec init(Module, Fsm, EP, Assoc) -> Result
	when
		Module :: atom(),
		Fsm :: pid(),
		EP :: pid(),
		Assoc :: pos_integer(),
		Result :: {ok, State} | {error, Reason},
		State :: term(),
		Reason :: term().
%% @doc Initialize ASP/SGP callback handler
%%%  Called when ASP is started.
init(_Module, _Fsm, _EP, _Assoc) ->
erlang:display({?MODULE, ?LINE, init, _Module, _Fsm, _EP, _Assoc}),
	{ok, []}.

-spec transfer(Fsm, EP, Assoc, Stream, RC, OPC, DPC, SLS, SIO, Data, State) -> Result
	when
		Fsm :: pid(),
		EP :: pid(),
		Assoc :: pos_integer(),
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
transfer(Fsm, EP, Assoc, Stream, RC, OPC, DPC, SLS, SIO, UnitData, State)
		when DPC =:= 2057; DPC =:= 2065 ->
	log(Fsm, EP, Assoc, Stream, RC, OPC, DPC, SLS, SIO, UnitData),
	ASs = lists:flatten([gtt:find_pc(PC) || PC <- [6211, 2089, 6210, 2306]]),
	transfer1(6209, SLS, SIO, UnitData, State, ASs);
transfer(Fsm, EP, Assoc, Stream, RC, OPC, DPC, SLS, SIO, UnitData, State)
		when DPC == 6209 ->
	ASs = lists:flatten([gtt:find_pc(PC) || PC <- [2097, 2098]]),
	log(Fsm, EP, Assoc, Stream, RC, OPC, DPC, SLS, SIO, UnitData),
	transfer1(2057, SLS, SIO, UnitData, State, ASs).
%% @hidden
transfer1(OPC, SLS, SIO, UnitData, State, ASs) ->
erlang:display({?MODULE, ?LINE, OPC, SLS, SIO, UnitData}),
	MatchHead = #m3ua_as{routing_key = '$1', name = '_',
			min_asp = '_', max_asp = '_', state = active, asp = '$2'},
	% match specs require "double tuple parenthesis"
	F1 = fun({NA, Keys, Mode}) ->
				{'=:=', '$1', {{NA, [{Key} || Key <- Keys], Mode}}}
	end,
	MatchConditions = [list_to_tuple(['or' | lists:map(F1, ASs)])],
	MatchBody = [{{'$1', '$2'}}],
	MatchFunction = {MatchHead, MatchConditions, MatchBody},
	MatchExpression = [MatchFunction],
	ASPs = mnesia:dirty_select(m3ua_as, MatchExpression),
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
log(Fsm, EP, Assoc, Stream, RC, OPC, DPC, SLS, SIO, UnitData) ->
	#sccp_unitdata{called_party = #party_address{ri = CldRI,
			ssn = CldSSN, translation_type = CldTT, numbering_plan = CldNP,
			nai = CldNAI, gt = CldGT},
			calling_party = #party_address{ri = ClgRI, ssn = ClgSSN,
			translation_type = ClgTT, numbering_plan = ClgNP,
			nai = ClgNAI, gt = ClgGT},
			data = _Payload} = sccp_codec:sccp(UnitData),
	error_logger:info_report(["MTP-TRANSFER request",
			{fsm, Fsm}, {ep, EP}, {assoc, Assoc},
			{stream, Stream}, {rc, RC}, {opc, OPC},
			{dpc, DPC}, {sls, SLS}, {sio, SIO},
			{ri, {CldRI, ClgRI}}, {ssn, {CldSSN, ClgSSN}},
			{tt, {CldTT, ClgTT}}, {np, {CldNP, ClgNP}},
			{nai, {CldNAI, ClgNAI}}, {gt, {CldGT, ClgGT}}]).

-spec pause(Fsm, EP, Assoc, Stream, RC, DPCs, State) -> Result
	when
		Fsm :: pid(),
		EP :: pid(),
		Assoc :: pos_integer(),
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
pause(_Fsm, _EP, _Assoc, _Stream, _RC, _DPCs, State) ->
erlang:display({?MODULE, ?LINE, pause, _Fsm, _EP, _Assoc, _Stream, _RC, _DPCs, State}),
	{ok, State}.

-spec resume(Fsm, EP, Assoc, Stream, RC, DPCs, State) -> Result
	when
		Fsm :: pid(),
		EP :: pid(),
		Assoc :: pos_integer(),
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
resume(_Fsm, _EP, _Assoc, _Stream, _RC, _DPCs, State) ->
erlang:display({?MODULE, ?LINE, resume, _Fsm, _EP, _Assoc, _Stream, _RC, _DPCs, State}),
	{ok, State}.

-spec status(Fsm, EP, Assoc, Stream, RC, DPCs, State) -> Result
	when
		Fsm :: pid(),
		EP :: pid(),
		Assoc :: pos_integer(),
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
status(_Fsm, _EP, _Assoc, _Stream, _RC, _DPCs, State) ->
erlang:display({?MODULE, ?LINE, status, _Fsm, _EP, _Assoc, _Stream, _RC, _DPCs, State}),
	{ok, State}.

-spec register(Fsm, EP, Assoc, NA, Keys, TMT, State) -> Result
	when
		Fsm :: pid(),
		EP :: pid(),
		Assoc :: pos_integer(),
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
register(_Fsm, _EP, _Assoc, NA, Keys, TMT, State) ->
erlang:display({?MODULE, ?LINE, register, _Fsm, _EP, _Assoc, NA, Keys, TMT, State}),
	case gtt:add_key({NA, Keys, TMT}) of
		ok ->
			{ok, State};
		{error, Reason} ->
			{error, Reason}
	end.

-spec asp_up(Fsm, EP, Assoc, State) -> Result
	when
		Fsm :: pid(),
		EP :: pid(),
		Assoc :: pos_integer(),
		State :: term(),
		Result :: {ok, State}.
%% @doc Called when ASP reports that it has received an ASP UP Ack
%% 	message from its peer or M3UA reports that it has successfully
%%		processed an incoming ASP Up message from its peer.
asp_up(_Fsm, _EP, _Assoc, State) ->
erlang:display({?MODULE, ?LINE, asp_up, _Fsm, _EP, _Assoc, State}),
	{ok, State}.

-spec asp_down(Fsm, EP, Assoc, State) -> Result
	when
		Fsm :: pid(),
		EP :: pid(),
		Assoc :: pos_integer(),
		State :: term(),
		Result :: {ok, State}.
%% @doc Called when ASP reports that it has received an ASP Down Ack
%%		message from its peer or M3UA reports that it has successfully
%%		processed an incoming ASP Down message from its peer.
asp_down(_Fsm, _EP, _Assoc, State) ->
erlang:display({?MODULE, ?LINE, asp_down, _Fsm, _EP, _Assoc, State}),
	{ok, State}.

-spec asp_active(Fsm, EP, Assoc, State) -> Result
	when
		Fsm :: pid(),
		EP :: pid(),
		Assoc :: pos_integer(),
		State :: term(),
		Result :: {ok, State}.
%% @doc Called when ASP reports that it has received an ASP Active
%%		Ack message from its peer or M3UA reports that it has successfully
%%		processed an incoming ASP Active message from its peer.
asp_active(_Fsm, _EP, _Assoc, State) ->
erlang:display({?MODULE, ?LINE, asp_active, _Fsm, _EP, _Assoc, State}),
	{ok, State}.

-spec asp_inactive(Fsm, EP, Assoc, State) -> Result
	when
		Fsm :: pid(),
		EP :: pid(),
		Assoc :: pos_integer(),
		State :: term(),
		Result :: {ok, State}.
%% @doc Called when ASP reports that it has received an ASP Inactive
%%		Ack message from its peer or M3UA reports that it has successfully
%%		processed an incoming ASP Inactive message from its peer.
asp_inactive(_Fsm, _EP, _Assoc, State) ->
erlang:display({?MODULE, ?LINE, asp_inactive, _Fsm, _EP, _Assoc, State}),
	{ok, State}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

