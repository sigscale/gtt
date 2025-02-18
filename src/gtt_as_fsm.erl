%%% gtt_as_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016-2025 SigScale Global Inc.
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
-copyright('Copyright (c) 2016-2025 SigScale Global Inc.').

-behaviour(gen_fsm).

%% export the gtt_as_fsm public API
-export([]).

%% export the gtt_as_fsm state callbacks
-export([down/2, inactive/2, active/2, pending/2]).

%% export the call backs needed for gen_fsm behaviour
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
			terminate/3, code_change/4]).

-record(statedata,
		{name :: gtt:as_ref(),
		role :: as | sg,
		rc :: undefined | 0..4294967295,
		na :: undefined | 0..4294967295,
		keys :: [{DPC :: 0..16777215,
				[SI :: byte()], [OPC :: 0..16777215]}],
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
init([Name] = _Args) ->
	F = fun() -> mnesia:read(gtt_as, Name, read) end,
	case mnesia:transaction(F) of
		{atomic, [#gtt_as{name = Name, role = Role,
				rc = RC, na = NA, keys = Keys,
				mode = Mode, min_asp = Min, max_asp = Max}]} ->
			StateData = #statedata{name = Name, role = Role,
					rc = RC, na = NA, keys = Keys, mode = Mode,
					min = Min, max = Max},
			{ok, down, StateData};
		{aborted, Reason} ->
			{stop, Reason}
	end.

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
%%		gen_fsm:send_event/2} in the <b>down</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
down({'M-ASP_DOWN', Node, EP, Assoc},
		#statedata{role = as} = StateData) when Node == node() ->
	case m3ua:asp_up(EP, Assoc) of
		ok ->
			{next_state, down, StateData};
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
down({'M-ASP_DOWN', Node, _EP, _Assoc},
		#statedata{role = sg} = StateData) when Node == node() ->
	{next_state, down, StateData};
down({'M-ASP_UP', Node, EP, Assoc}, #statedata{role = as,
		name = Name, rc = undefined, na = NA, keys = Keys,
		mode = Mode} = StateData) when Node == node() ->
	case m3ua:register(EP, Assoc, undefined, NA, Keys, Mode, Name) of
		{ok, RC} ->
			NewStateData = StateData#statedata{rc = RC},
			case m3ua:asp_active(EP, Assoc) of
				ok ->
					{next_state, inactive, NewStateData};
				{error, Reason} ->
					{stop, Reason, StateData}
			end;
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
down({'M-ASP_UP', Node, EP, Assoc}, #statedata{role = as,
		name = Name, rc = RC, na = NA, keys = Keys,
		mode = Mode} = StateData) when is_integer(RC), Node == node() ->
	case m3ua:register(EP, Assoc, RC, NA, Keys, Mode, Name) of
		{ok, RC} ->
			case m3ua:asp_active(EP, Assoc) of
				ok ->
					{next_state, inactive, StateData};
				{error, Reason} ->
					{stop, Reason, StateData}
			end;
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
down({'M-ASP_UP', Node, _EP, _Assoc},
		#statedata{role = sg} = StateData) when Node == node() ->
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
%%		gen_fsm:send_event/2} in the <b>inactive</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
inactive({'M-NOTIFY', Node, _EP, _Assoc, RC, AsState, _AspID},
		#statedata{role = as, rc = RC} = StateData)
		when Node == node(), is_integer(RC) ->
	update_state(as_state(AsState), StateData);
inactive({'M-NOTIFY', Node, _EP, _Assoc, undefined, AsState, _AspID},
		#statedata{role = as} = StateData) when Node == node() ->
	update_state(as_state(AsState), StateData);
inactive({'M-ASP_DOWN', Node, EP, Assoc},
		#statedata{role = as} = StateData) when Node == node() ->
	case m3ua:asp_up(EP, Assoc) of
		ok ->
			{next_state, inactive, StateData};
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
inactive({'M-ASP_DOWN', Node, _EP, _Assoc},
		#statedata{role = as} = StateData) when Node == node() ->
	{next_state, inactive, StateData};
inactive({'M-ASP_UP', Node, EP, Assoc}, #statedata{role = as,
		name = Name, rc = undefined, na = NA, keys = Keys,
		mode = Mode} = StateData) when Node == node() ->
	case m3ua:register(EP, Assoc, undefined, NA, Keys, Mode, Name) of
		{ok, RC} ->
			NewStateData = StateData#statedata{rc = RC},
			case m3ua:asp_active(EP, Assoc) of
				ok ->
					{next_state, inactive, NewStateData};
				{error, Reason} ->
					{stop, Reason, StateData}
			end;
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
inactive({'M-ASP_UP', Node, EP, Assoc}, #statedata{role = as,
		name = Name, rc = RC, na = NA, keys = Keys,
		mode = Mode} = StateData) when is_integer(RC), Node == node() ->
	case m3ua:register(EP, Assoc, RC, NA, Keys, Mode, Name) of
		{ok, RC} ->
			case m3ua:asp_active(EP, Assoc) of
				ok ->
					{next_state, inactive, StateData};
				{error, Reason} ->
					{stop, Reason, StateData}
			end;
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
inactive({'M-ASP_UP', Node, _EP, _Assoc},
		#statedata{role = sg} = StateData) when Node == node() ->
	{next_state, inactive, StateData};
inactive({'M-ASP_INACTIVE', Node, _EP, _Assoc}, StateData) when Node == node() ->
	{next_state, inactive, StateData};
inactive({'M-ASP_ACTIVE', Node, _EP, _Assoc}, StateData) when Node == node() ->
	update_state(active, StateData).

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
%%		gen_fsm:send_event/2} in the <b>active</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
active({'M-NOTIFY', Node, _EP, _Assoc, RC, AsState, _AspID},
		#statedata{role = as, rc = RC} = StateData)
		when Node == node(), is_integer(RC) ->
	% @todo should m3ua_asp_fsm accept asp_active/2 in active state?
	update_state(as_state(AsState), StateData);
active({'M-NOTIFY', Node, _EP, _Assoc, undefined, AsState, _AspID},
		#statedata{role = as} = StateData) when Node == node() ->
	update_state(as_state(AsState), StateData);
active({'M-ASP_DOWN', Node, EP, Assoc},
		#statedata{role = as} = StateData) when Node == node() ->
	case m3ua:asp_up(EP, Assoc) of
		ok ->
			{next_state, active, StateData};
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
active({'M-ASP_DOWN', Node, _EP, _Assoc},
		#statedata{role = sg} = StateData) when Node == node() ->
	{next_state, active, StateData};
active({'M-ASP_UP', Node, EP, Assoc}, #statedata{role = as,
		name = Name, rc = undefined, na = NA, keys = Keys,
		mode = Mode} = StateData) when Node == node() ->
	case m3ua:register(EP, Assoc, undefined, NA, Keys, Mode, Name) of
		{ok, RC} ->
			NewStateData = StateData#statedata{rc = RC},
			case m3ua:asp_active(EP, Assoc) of
				ok ->
					{next_state, active, NewStateData};
				{error, Reason} ->
					{stop, Reason, StateData}
			end;
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
active({'M-ASP_UP', Node, EP, Assoc}, #statedata{role = as,
		name = Name, rc = RC, na = NA, keys = Keys,
		mode = Mode} = StateData) when is_integer(RC), Node == node() ->
	case m3ua:register(EP, Assoc, RC, NA, Keys, Mode, Name) of
		{ok, RC} ->
			case m3ua:asp_active(EP, Assoc) of
				ok ->
					{next_state, active, StateData};
				{error, Reason} ->
					{stop, Reason, StateData}
			end;
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
active({'M-ASP_UP', Node, _EP, _Assoc},
		#statedata{role = sg} = StateData) when Node == node() ->
	{next_state, active, StateData};
active({'M-ASP_INACTIVE', Node, _EP, _Assoc}, StateData) when Node == node() ->
	{next_state, active, StateData};
active({'M-ASP_ACTIVE', Node, _EP, _Assoc}, StateData) when Node == node() ->
	update_state(active, StateData).

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
%%		gen_fsm:send_event/2} in the <b>pending</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
pending(timeout, #statedata{} = StateData) ->
	{next_state, down, StateData};
pending({'M-NOTIFY', Node, _EP, _Assoc, RC, AsState, _AspID},
		#statedata{role = as, rc = RC} = StateData)
		when Node == node(), is_integer(RC) ->
	update_state(as_state(AsState), StateData);
pending({'M-NOTIFY', Node, _EP, _Assoc, undefined, AsState, _AspID},
		#statedata{role = as} = StateData) when Node == node() ->
	update_state(as_state(AsState), StateData);
pending({'M-ASP_UP', Node, EP, Assoc}, #statedata{role = as,
		name = Name, rc = undefined, na = NA, keys = Keys,
		mode = Mode} = StateData) when Node == node() ->
	case m3ua:register(EP, Assoc, undefined, NA, Keys, Mode, Name) of
		{ok, RC} ->
			NewStateData = StateData#statedata{rc = RC},
			case m3ua:asp_active(EP, Assoc) of
				ok ->
					{next_state, inactive, NewStateData};
				{error, Reason} ->
					{stop, Reason, StateData}
			end;
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
pending({'M-ASP_UP', Node, EP, Assoc}, #statedata{role = as,
		name = Name, rc = RC, na = NA, keys = Keys,
		mode = Mode} = StateData) when is_integer(RC), Node == node() ->
	case m3ua:register(EP, Assoc, RC, NA, Keys, Mode, Name) of
		{ok, RC} ->
			case m3ua:asp_active(EP, Assoc) of
				ok ->
					{next_state, inactive, StateData};
				{error, Reason} ->
					{stop, Reason, StateData}
			end;
		{error, Reason} ->
			{stop, Reason, StateData}
	end;
pending({'M-ASP_UP', Node, _EP, _Assoc},
		#statedata{role = sg} = StateData) when Node == node() ->
	{next_state, inactive, StateData}.

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

%% @hidden
as_state(as_active) ->
	active;
as_state(as_inactive) ->
	inactive;
as_state(as_pending) ->
	pending.

%% @hidden
update_state(StateName, #statedata{rc = RC} = StateData) ->
	F = fun() ->
			[#m3ua_as{} = AS] = mnesia:read(m3ua_as, RC, write),
			mnesia:write(AS#m3ua_as{state = StateName})
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			{next_state, StateName, StateData};
		{aborted, Reason} ->
			{stop, Reason, StateData}
	end.

