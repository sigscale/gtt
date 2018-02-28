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
%%% @doc This {@link //m3ua/m3ua_asp_fsm. m3ua_asp_fsm} or
%%% 	{@link //m3ua/m3ua_sgp_fsm. m3ua_sgp_fsm} behaviour callback
%%%	module implements a handler for a User Service Access Point (USAP)
%%% 	of an M3UA stack SAP in the {@link //gtt. gtt} application.
%%%
-module(gtt_m3ua_cb).
-copyright('Copyright (c) 2018 SigScale Global Inc.').

%% m3ua_asp_fsm callbacks
-export([init/3, transfer/11, pause/7, resume/7, status/7,
		asp_up/4, asp_down/4, asp_active/4, asp_inactive/4]).

-include("gtt.hrl").

%%----------------------------------------------------------------------
%%  The gtt_m3ua_cb public API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The m3ua_[asp|sgp]_fsm callabcks
%%----------------------------------------------------------------------
-spec init(Fsm, EP, Assoc) -> Result
	when
		Fsm :: pid(),
		EP :: pid(),
		Assoc :: pos_integer(),
		Result :: {ok, State} | {error, Reason},
		State :: term(),
		Reason :: term().
%% @doc Initialize ASP/SGP callback handler
%%%  Called when ASP is started.
init(_Fsm, _EP, _Assoc) ->
	{ok, []}.

-spec transfer(Fsm, EP, Assoc, Stream, RK, OPC, DPC, SLS, SIO, Data, State) -> Result
	when
		Fsm :: pid(),
		EP :: pid(),
		Assoc :: pos_integer(),
		Stream :: pos_integer(),
		RK :: routing_key(),
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
transfer(_Fsm, _EP, _Assoc, _Stream, _RK, _OPC, _DPC, _SLS, _SIO, _Data, State) ->
	{ok, State}.

-spec pause(Fsm, EP, Assoc, Stream, RK, DPCs, State) -> Result
	when
		Fsm :: pid(),
		EP :: pid(),
		Assoc :: pos_integer(),
		Stream :: pos_integer(),
		DPCs :: [DPC],
		RK :: routing_key(),
		DPC :: pos_integer(),
		State :: term(),
		Result :: {ok, NewState} | {error, Reason},
		NewState :: term(),
		Reason :: term().
%% @doc MTP-PAUSE indication
%%%  Called when an SS7 destination is unreachable.
pause(_Fsm, _EP, _Assoc, _Stream, _RK, _DPCs, State) ->
	{ok, State}.

-spec resume(Fsm, EP, Assoc, Stream, RK, DPCs, State) -> Result
	when
		Fsm :: pid(),
		EP :: pid(),
		Assoc :: pos_integer(),
		Stream :: pos_integer(),
		DPCs :: [DPC],
		RK :: routing_key(),
		DPC :: pos_integer(),
		State :: term(),
		Result :: {ok, NewState} | {error, Reason},
		NewState :: term(),
		Reason :: term().
%% @doc MTP-RESUME indication.
%%%  Called when a previously unreachable SS7 destination
%%%  becomes reachable.
resume(_Fsm, _EP, _Assoc, _Stream, _RK, _DPCs, State) ->
	{ok, State}.

-spec status(Fsm, EP, Assoc, Stream, RK, DPCs, State) -> Result
	when
		Fsm :: pid(),
		EP :: pid(),
		Assoc :: pos_integer(),
		Stream :: pos_integer(),
		DPCs :: [DPC],
		RK :: routing_key(),
		DPC :: pos_integer(),
		State :: term(),
		Result :: {ok, NewState} | {error, Reason},
		NewState :: term(),
		Reason :: term().
%% @doc Called when congestion occurs for an SS7 destination
%%% 	or to indicate an unavailable remote user part.
status(_Fsm, _EP, _Assoc, _Stream, _RK, _DPCs, State) ->
	{ok, State}.

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
	{ok, State}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

