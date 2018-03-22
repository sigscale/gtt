%%% gtt_app.erl
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
%%% @doc This {@link //stdlib/application. application} behaviour callback
%%% 	module starts and stops the
%%% 	{@link //gtt. gtt} application.
%%%
-module(gtt_app).
-copyright('Copyright (c) 2015-2018 SigScale Global Inc.').

-behaviour(application).

%% callbacks needed for application behaviour
-export([start/2, stop/1, config_change/3]).
%% optional callbacks for application behaviour
-export([prep_stop/1, start_phase/3]).
%% export the gtt private API for installation
-export([install/0, install/1]).

-record(state, {}).

-define(WAITFORSCHEMA, 10000).
-define(WAITFORTABLES, 10000).

-include("gtt.hrl").

%%----------------------------------------------------------------------
%%  The gtt_app aplication callbacks
%%----------------------------------------------------------------------

-type start_type() :: normal | {takeover, node()} | {failover, node()}.
-spec start(StartType :: start_type(), StartArgs :: term()) ->
	{'ok', pid()} | {'ok', pid(), State :: #state{}}
			| {'error', Reason :: term()}.
%% @doc Starts the application processes.
%% @see //kernel/application:start/1
%% @see //kernel/application:start/2
%%
start(normal = _StartType, _Args) ->
	Tables = [gtt_ep, gtt_as],
	case mnesia:wait_for_tables(Tables, 60000) of
		ok ->
			start1();
		{timeout, _} = Reason ->
			{error, Reason};
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
start1() ->
	case supervisor:start_link(gtt_sup, []) of
		{ok, TopSup} ->
			start2(TopSup);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
start2(TopSup) ->
	F = fun() -> mnesia:all_keys(gtt_as) end,
	case mnesia:transaction(F) of
		{atomic, ASs} ->
			Children = supervisor:which_children(TopSup),
			{_, AsFsmSup, _, _} = lists:keyfind(gtt_as_fsm_sup, 1, Children),
			{_, EpFsmSup, _, _} = lists:keyfind(gtt_ep_fsm_sup, 1, Children),
			start3(TopSup, EpFsmSup, AsFsmSup, ASs);
		{aborted, Reason} ->
			{error, Reason}
	end.
%% @hidden
start3(TopSup, EpFsmSup, AsFsmSup, [Name | T]) ->
	StartMod = gtt_as_fsm,
	StartArgs = [Name],
	StartOpts = [],
	case supervisor:start_child(AsFsmSup,
			[{global, Name}, StartMod, StartArgs, StartOpts]) of
		{ok, _Child} ->
			start3(TopSup, EpFsmSup, AsFsmSup, T);
		{error, Reason} ->
			error_logger:error_report(["Failed to start Application Server",
					{as, Name}, {reason, Reason}, {module, ?MODULE}]),
			start3(TopSup, EpFsmSup, AsFsmSup, T)
	end;
start3(TopSup, EpFsmSup, _, []) ->
	F = fun() -> mnesia:all_keys(gtt_ep) end,
	case mnesia:transaction(F) of
		{atomic, EndPoints} ->
			start4(TopSup, EpFsmSup, EndPoints);
		{aborted, Reason} ->
			{error, Reason}
	end.
%% @hidden
start4(TopSup, EpFsmSup, [Name | T]) ->
	StartMod = gtt_ep_fsm,
	StartArgs = [Name],
	StartOpts = [],
	case supervisor:start_child(EpFsmSup,
			[StartMod, StartArgs, StartOpts]) of
		{ok, _Child} ->
			start4(TopSup, EpFsmSup, T);
		{error, Reason} ->
			error_logger:error_report(["Failed to start SCTP endpoint",
					{endpoint, Name}, {reason, Reason}, {module, ?MODULE}]),
			start4(TopSup, EpFsmSup, T)
	end;
start4(TopSup, _, []) ->
	{ok, TopSup}.

-spec start_phase(Phase :: atom(), StartType :: start_type(),
		PhaseArgs :: term()) -> ok | {error, Reason :: term()}.
%% @doc Called for each start phase in the application and included
%% 	applications.
%% @see //kernel/app
%%
start_phase(_Phase, _StartType, _PhaseArgs) ->
	ok.

-spec prep_stop(State :: #state{}) -> #state{}.
%% @doc Called when the application is about to be shut down,
%% 	before any processes are terminated.
%% @see //kernel/application:stop/1
%%
prep_stop(State) ->
	State.

-spec stop(State :: #state{}) -> any().
%% @doc Called after the application has stopped to clean up.
%%
stop(_State) ->
	ok.

-spec config_change(Changed :: [{Par :: atom(), Val :: atom()}],
		New :: [{Par :: atom(), Val :: atom()}],
		Removed :: [Par :: atom()]) -> ok.
%% @doc Called after a code  replacement, if there are any
%% 	changes to the configuration  parameters.
%%
config_change(_Changed, _New, _Removed) ->
	ok.

-spec install() -> Result
	when
		Result :: {ok, Tables} | {error, Reason},
		Tables :: [atom()],
		Reason :: term().
%% @equiv install([node() | nodes()])
install() ->
	Nodes = [node() | nodes()],
	install(Nodes).

-spec install(Nodes) -> Result
	when
		Nodes :: [node()],
		Result :: {ok, Tables} | {error, Reason},
		Tables :: [atom()],
		Reason :: term().
%% @doc Initialize GTT tables.
%% 	`Nodes' is a list of the nodes where
%% 	{@link //gtt. gtt} tables will be replicated.
%%
%% 	If {@link //mnesia. mnesia} is not running an attempt
%% 	will be made to create a schema on all available nodes.
%% 	If a schema already exists on any node
%% 	{@link //mnesia. mnesia} will be started on all nodes
%% 	using the existing schema.
%%
%% @private
%%
install(Nodes) when is_list(Nodes) ->
	case mnesia:system_info(is_running) of
		no ->
			case mnesia:create_schema(Nodes) of
				ok ->
					error_logger:info_report("Created mnesia schema",
							[{nodes, Nodes}]),
					install1(Nodes);
				{error, Reason} ->
					error_logger:error_report(["Failed to create schema",
							mnesia:error_description(Reason),
							{nodes, Nodes}, {error, Reason}]),
					{error, Reason}
			end;
		_ ->
			install2(Nodes)
	end.
%% @hidden
install1([Node] = Nodes) when Node == node() ->
	case mnesia:start() of
		ok ->
			error_logger:info_msg("Started mnesia~n"),
			install2(Nodes);
		{error, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
					{error, Reason}]),
			{error, Reason}
	end;
install1(Nodes) ->
	case rpc:multicall(Nodes, mnesia, start, [], 60000) of
		{Results, []} ->
			F = fun(ok) ->
						false;
					(_) ->
						true
			end,
			case lists:filter(F, Results) of
				[] ->
					error_logger:info_report(["Started mnesia on all nodes",
							{nodes, Nodes}]),
					install2(Nodes);
				NotOKs ->
					error_logger:error_report(["Failed to start mnesia"
							" on all nodes", {nodes, Nodes}, {errors, NotOKs}]),
					{error, NotOKs}
			end;
		{Results, BadNodes} ->
			error_logger:error_report(["Failed to start mnesia"
					" on all nodes", {nodes, Nodes}, {results, Results},
					{badnodes, BadNodes}]),
			{error, {Results, BadNodes}}
	end.
%% @hidden
install2(Nodes) ->
	case mnesia:wait_for_tables([schema], ?WAITFORSCHEMA) of
		ok ->
			install3(Nodes, []);
		{error, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason};
		{timeout, Tables} ->
			error_logger:error_report(["Timeout waiting for tables",
					{tables, Tables}]),
			{error, timeout}
	end.
%% @hidden
install3(Nodes, Tables) ->
	case mnesia:create_table(gtt_ep, [{disc_copies, Nodes},
			{attributes, record_info(fields, gtt_ep)}]) of
		{atomic, ok} ->
			error_logger:info_msg("Created new endpoint table.~n"),
			install4(Nodes, [gtt_ep | Tables]);
		{aborted, {not_active, _, Node} = Reason} ->
			error_logger:error_report(["Mnesia not started on node",
					{node, Node}]),
			{error, Reason};
		{aborted, {already_exists, gtt_ep}} ->
			error_logger:info_msg("Found existing endpoint table.~n"),
			install4(Nodes, [gtt_ep | Tables]);
		{aborted, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
install4(Nodes, Tables) ->
	case mnesia:create_table(gtt_as, [{disc_copies, Nodes},
			{attributes, record_info(fields, gtt_as)}]) of
		{atomic, ok} ->
			error_logger:info_msg("Created new application server table.~n"),
			install5(Nodes, [gtt_as | Tables]);
		{aborted, {not_active, _, Node} = Reason} ->
			error_logger:error_report(["Mnesia not started on node",
					{node, Node}]),
			{error, Reason};
		{aborted, {already_exists, gtt_as}} ->
			error_logger:info_msg("Found existing application server table.~n"),
			install5(Nodes, [gtt_as | Tables]);
		{aborted, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
install5(Nodes, Tables) ->
	case mnesia:create_table(gtt_pc, [{disc_copies, Nodes},
			{attributes, record_info(fields, gtt_pc)},
			{type, bag}]) of
		{atomic, ok} ->
			error_logger:info_msg("Created new point code table.~n"),
			{ok, lists:reverse([gtt_pc | Tables])};
		{aborted, {not_active, _, Node} = Reason} ->
			error_logger:error_report(["Mnesia not started on node",
					{node, Node}]),
			{error, Reason};
		{aborted, {already_exists, gtt_pc}} ->
			error_logger:info_msg("Found existing point code table.~n"),
			{ok, lists:reverse([gtt_pc | Tables])};
		{aborted, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason}
	end.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

