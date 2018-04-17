%%% gtt_as_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2017 SigScale Global Inc.
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
%%% @doc This {@link //stdlib/gen_fsm. gen_fsm} behaviour module
%%% 	implements a state machine for an Application Server (AS)
%%% 	in the {@link //gtt. gtt} application.
%%%
-module(gtt_as_fsm).
-copyright('Copyright (c) 2018 SigScale Global Inc.').

-behaviour(gen_fsm).

%% export the gtt_as_fsm public API
-export([]).

%% export the gtt_as_fsm state callbacks
-export([down/2, inactive/2, active/2, pending/2]).

%% export the call backs needed for gen_fsm behaviour
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
			terminate/3, code_change/4]).

-record(statedata,
		{name :: as_ref(),
		role :: as | sg,
		na :: pos_integer(),
		keys :: [{DPC :: pos_integer(), [SI :: pos_integer()], [OPC :: pos_integer()]}],
		mode :: override | loadshare | broadcast,
		min :: pos_integer(),
		max :: pos_integer()}).
-type statedata() :: #statedata{}.

-include("gtt.hrl").

%% Timer T(r)
-define(Tr, 2000).

%%----------------------------------------------------------------------
%%  The gtt_as_fsm API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The gtt_as_fsm gen_fsm call backs
%%----------------------------------------------------------------------

-spec init(Args) -> Result
	when
		Args :: list(),
		Result :: {ok, StateName :: atom(), StateData :: statedata()}
		| {ok, StateName :: atom(), StateData :: statedata(),
			Timeout :: non_neg_integer() | infinity}
		| {ok, StateName :: atom(), StateData :: statedata(), hibernate}
		| {stop, Reason :: term()} | ignore.
%% @doc Initialize the {@module} finite state machine.
%% @see //stdlib/gen_fsm:init/1
%% @private
%%
init([Name, Role, NA, Keys, Mode, Min, Max]) ->
	{ok, down, #statedata{name = Name, role = Role,
			na = NA, keys = Keys, mode = Mode, min = Min, max = Max}}.

-spec down(Event, StateData) -> Result
	when
		Event :: timeout | term(),
		StateData :: statedata(),
		Result :: {next_state, NextStateName :: atom(), NewStateData :: statedata()}
		| {next_state, NextStateName :: atom(), NewStateData :: statedata(),
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: statedata(), hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: statedata()}.
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>request</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
down({'M-ASP_UP', Node, EP, Assoc},
		#statedata{name = Name, na = NA, keys = Keys, mode = Mode} = StateData) ->
	case rpc:call(Node, m3ua, register, [EP, Assoc, NA, Keys, Mode, Name]) of
		{ok, _RoutingContext} ->
			{next_state, inactive, StateData};
		{badrpc, _} = Reason->
			{stop, Reason, StateData};
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
down({'M-ASP_INACTIVE', _Node, _EP, _Assoc}, StateData) ->
	{next_state, inactive, StateData}.

-spec inactive(Event, StateData) -> Result
	when
		Event :: timeout | term(),
		StateData :: statedata(),
		Result :: {next_state, NextStateName :: atom(), NewStateData :: statedata()}
		| {next_state, NextStateName :: atom(), NewStateData :: statedata(),
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: statedata(), hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: statedata()}.
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>request</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
inactive({'M-NOTIFY', Node, EP, Assoc, _RC, as_inactive, _AspID}, StateData) ->
	case rpc:call(Node, m3ua, asp_active, [EP, Assoc]) of
		ok ->
			{next_state, inactive, StateData};
		{badrpc, _} = Reason->
			{stop, Reason, StateData};
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
inactive({'M-NOTIFY', Node, EP, Assoc, _RC, as_active, _AspID}, StateData) ->
	case rpc:call(Node, m3ua, asp_active, [EP, Assoc]) of
		ok ->
			{next_state, active, StateData};
		{badrpc, _} = Reason->
			{stop, Reason, StateData};
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
inactive({'M-ASP_UP', Node, EP, Assoc},
		#statedata{name = Name, na = NA, keys = Keys, mode = Mode} = StateData) ->
	case rpc:call(Node, m3ua, register, [EP, Assoc, NA, Keys, Mode, Name]) of
		{ok, _RoutingContext} ->
			{next_state, inactive, StateData};
		{badrpc, _} = Reason->
			{stop, Reason, StateData};
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
inactive({'M-ASP_ACTIVE', _Node, _EP, _Assoc}, StateData) ->
	{next_state, active, StateData};
inactive({'M-ASP_DOWN', _Node, _EP, _Assoc}, StateData) ->
	{next_state, down, StateData}.

-spec active(Event, StateData) -> Result
	when
		Event :: timeout | term(),
		StateData :: statedata(),
		Result :: {next_state, NextStateName :: atom(), NewStateData :: statedata()}
		| {next_state, NextStateName :: atom(), NewStateData :: statedata(),
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: statedata(), hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: statedata()}.
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>request</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
active({'M-NOTIFY', _Node, _EP, _Assoc, _RC, as_inactive, _AspID}, StateData) ->
	{next_state, inactive, StateData};
active({'M-NOTIFY', _Node, _EP, _Assoc, _RC, as_pending, _AspID}, StateData) ->
	{next_state, pending, StateData};
active({'M-ASP_UP', EP, Assoc},
		#statedata{name = Name, na = NA, keys = Keys, mode = Mode} = StateData) ->
	case m3ua:register(EP, Assoc, NA, Keys, Mode, Name) of
		{ok, _RoutingContext} ->
			{next_state, active, StateData};
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
active({'M-ASP_ACTIVE', _Node, _EP, _Assoc}, StateData) ->
	{next_state, pending, StateData, ?Tr};
active({'M-ASP_DOWN', _Node, _EP, _Assoc}, StateData) ->
	{next_state, pending, StateData, ?Tr}.

-spec pending(Event, StateData) -> Result
	when
		Event :: timeout | term(),
		StateData :: statedata(),
		Result :: {next_state, NextStateName :: atom(), NewStateData :: statedata()}
		| {next_state, NextStateName :: atom(), NewStateData :: statedata(),
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: statedata(), hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: statedata()}.
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>request</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
pending(timeout, #statedata{} = StateData) ->
	{next_state, down, StateData};
pending({'M-NOTIFY', _Node, _EP, _Assoc, _RC, as_inactive, _AspID}, StateData) ->
	{next_state, inactive, StateData};
pending({'M-NOTIFY', _Node, _EP, _Assoc, _RC, as_active, _AspID}, StateData) ->
	{next_state, active, StateData}.

-spec handle_event(Event, StateName, StateData) -> Result
	when
		Event :: term(),
		StateName :: atom(),
		StateData :: statedata(),
		Result :: {next_state, NextStateName :: atom(), NewStateData :: statedata()}
		| {next_state, NextStateName :: atom(), NewStateData :: statedata(),
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: statedata(), hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: statedata()}.
%% @doc Handle an event sent with
%% 	{@link //stdlib/gen_fsm:send_all_state_event/2.
%% 	gen_fsm:send_all_state_event/2}.
%% @see //stdlib/gen_fsm:handle_event/3
%% @private
%%
handle_event(_Event, StateName, StateData) ->
	{next_state, StateName, StateData}.

-spec handle_sync_event(Event, From, StateName, StateData) -> Result
	when
		Event :: term(),
		From :: {Pid :: pid(), Tag :: term()},
		StateName :: atom(),
		StateData :: statedata(),
		Result :: {reply, Reply :: term(), NextStateName :: atom(), NewStateData :: statedata()}
		| {reply, Reply :: term(), NextStateName :: atom(), NewStateData :: statedata(),
		Timeout :: non_neg_integer() | infinity}
		| {reply, Reply :: term(), NextStateName :: atom(), NewStateData :: statedata(), hibernate}
		| {next_state, NextStateName :: atom(), NewStateData :: statedata()}
		| {next_state, NextStateName :: atom(), NewStateData :: statedata(),
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: statedata(), hibernate}
		| {stop, Reason :: normal | term(), Reply :: term(), NewStateData :: statedata()}
		| {stop, Reason :: normal | term(), NewStateData :: statedata()}.
%% @doc Handle an event sent with
%% 	{@link //stdlib/gen_fsm:sync_send_all_state_event/2.
%% 	gen_fsm:sync_send_all_state_event/2,3}.
%% @see //stdlib/gen_fsm:handle_sync_event/4
%% @private
%%
handle_sync_event(_Event, _From, StateName, StateData) ->
	{next_state, StateName, StateData}.

-spec handle_info(Info, StateName, StateData) -> Result
	when
		Info :: term(),
		StateName :: atom(),
		StateData :: statedata(),
		Result :: {next_state, NextStateName :: atom(), NewStateData :: statedata()}
		| {next_state, NextStateName :: atom(), NewStateData :: statedata(),
		Timeout :: non_neg_integer() | infinity}
		| {next_state, NextStateName :: atom(), NewStateData :: statedata(), hibernate}
		| {stop, Reason :: normal | term(), NewStateData :: statedata()}.
%% @doc Handle a received message.
%% @see //stdlib/gen_fsm:handle_info/3
%% @private
%%
handle_info(_, StateName, StateData) ->
	{next_state, StateName, StateData}.

-spec terminate(Reason, StateName, StateData) -> any()
	when
		Reason :: normal | shutdown | term(),
		StateName :: atom(),
		StateData :: statedata().
%% @doc Cleanup and exit.
%% @see //stdlib/gen_fsm:terminate/3
%% @private
%%
terminate(_Reason, _StateName, _StateData) ->
	ok.

-spec code_change(OldVsn, StateName, StateData, Extra) -> Result
	when
		OldVsn :: (Vsn :: term() | {down, Vsn :: term()}),
		StateName :: atom(),
		StateData :: statedata(),
		Extra :: term(),
		Result :: {ok, NextStateName :: atom(), NewStateData :: statedata()}.
%% @doc Update internal state data during a release upgrade&#047;downgrade.
%% @see //stdlib/gen_fsm:code_change/4
%% @private
%%
code_change(_OldVsn, StateName, StateData, _Extra) ->
	{ok, StateName, StateData}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

