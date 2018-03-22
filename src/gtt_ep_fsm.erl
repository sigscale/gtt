%%% gtt_ep_fsm.erl
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
%%% 	implements a state machine for an SCTP endpoint
%%% 	in the {@link //gtt. gtt} application.
%%%
-module(gtt_ep_fsm).
-copyright('Copyright (c) 2018 SigScale Global Inc.').

-behaviour(gen_fsm).

%% export the gtt_ep_fsm public API
-export([]).

%% export the gtt_ep_fsm state callbacks
-export([opening/2, listening/2, connecting/2, connected/2]).

%% export the call backs needed for gen_fsm behaviour
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
			terminate/3, code_change/4]).

-include("gtt.hrl").

-record(statedata,
		{name :: ep_ref(),
		sctp_role :: client | server,
		m3ua_role :: sgp | asp,
		callback :: atom() | #m3ua_fsm_cb{},
		local_port :: inet:port_number(),
		local_address :: inet:ip_address(),
		local_options = [] :: list(),
		remote_address :: inet:ip_address(),
		remote_port :: inet:port_number(),
		remote_options = [] :: list(),
		node :: atom(),
		ep :: pid(),
		assoc :: pos_integer()}).
-type statedata() :: #statedata{}.

-define(TIMEOUT, 300000).

%%----------------------------------------------------------------------
%%  The gtt_ep_fsm API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The gtt_ep_fsm gen_fsm call backs
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
	F = fun() -> mnesia:read(gtt_ep, Name, read) end,
	case mnesia:transaction(F) of
		{atomic, #gtt_ep{name = Name,
				sctp_role = SctpRole, m3ua_role = M3uaRole,
				callback = CallBack, node = Node,
				local = {LocalAddress, LocalPort, LocalOptions},
				remote = Remote}} ->
			{RemoteAddress, RemotePort, RemoteOptions} = case Remote of
				{RA, RP, RO} ->
					{RA, RP, RO};
				undefined ->
					{undefined, undefined, []}
			end,
			StateData = #statedata{name = Name,
					sctp_role = SctpRole, m3ua_role = M3uaRole,
					callback = CallBack, node = Node,
					local_address = LocalAddress, local_port = LocalPort,
					local_options = LocalOptions, remote_address = RemoteAddress,
					remote_port = RemotePort, remote_options = RemoteOptions},
			{ok, opening, StateData, 0};
		{aborted, Reason} ->
			{stop, Reason}
	end.

-spec opening(Event, StateData) -> Result
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
opening(timeout, #statedata{node = Node,
		local_address = Address, local_port = Port,
		local_options = Options1, callback = Callback,
		sctp_role = SctpRole, m3ua_role = M3uaRole} = StateData) ->
	Options2 = [{ip, Address}, {port, Port},
			{sctp_role, SctpRole}, {m3ua_role, M3uaRole} | Options1],
	opening1(open(Node, Port, Options2, Callback), StateData).
opening1({ok, EP}, #statedata{sctp_role = server} = StateData) ->
	{next_state, listening, StateData#statedata{ep = EP}};
opening1({ok, EP}, #statedata{sctp_role = client,
		node = Node, ep = EP, remote_address = Address,
		remote_port = Port, remote_options = Options} = StateData) ->
	connect(Node, EP, Address, Port, Options),
	{next_state, connecting, StateData, ?TIMEOUT};
opening1({error, Reason}, StateData) ->
	{stop, Reason, StateData}.

-spec listening(Event, StateData) -> Result
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
listening(_Event, StateData) ->
	{stop, unimplemented, StateData}.

-spec connecting(Event, StateData) -> Result
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
connecting(timeout, StateData) ->
	{stop, timeout, StateData}.

-spec connected(Event, StateData) -> Result
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
connected(_Event, StateData) ->
	{stop, unimplemented, StateData}.

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
handle_event(_Event, _StateName, StateData) ->
	{stop, unimplemented, StateData}.

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
handle_sync_event(_Event, _From, _StateName, StateData) ->
	{stop, unimplemented, StateData}.

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
handle_info({Ref, {ok, Assoc}}, connecting, StateData)
		when is_reference(Ref), is_integer(Assoc) ->
	{next_state, connected, StateData#statedata{assoc = Assoc}};
handle_info({Ref, {error, Reason}}, connecting, StateData)
		when is_reference(Ref) ->
	{stop, Reason, StateData}.

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
open(Node, Port, Options, Callback) when Node == node() ->
	m3ua:open(Port, Options, Callback);
open(Node, Port, Options, Callback) ->
	case rpc:call(Node, m3ua, open, [Port, Options, Callback]) of
		{ok, EP} ->
			{ok, EP};
		{badrpc, _} = Reason ->
			{error, Reason};
		{error, Reason} ->
			{error, Reason}
	end.

%% @hidden
connect(Node, EP, Address, Port, Options) when Node == node() ->
	Req = {'M-SCTP_ESTABLISH', request, EP, Address, Port, Options},
	catch gen_server:call(m3ua, Req, 0);
connect(Node, EP, Address, Port, Options) ->
	Req = {'M-SCTP_ESTABLISH', request, EP, Address, Port, Options},
	catch gen_server:call({m3ua, Node}, Req, 0).

