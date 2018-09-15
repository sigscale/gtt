%%% gtt_api_SUITE.erl
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
%%%  Test suite for the gtt app.
%%%
-module(gtt_api_SUITE).
-copyright('Copyright (c) 2015-2018 SigScale Global Inc.').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

-compile(export_all).

-include_lib("m3ua/include/m3ua.hrl").
-include_lib("common_test/include/ct.hrl").

%%---------------------------------------------------------------------
%%  Test server callback functions
%%---------------------------------------------------------------------

-spec suite() -> DefaultData :: [tuple()].
%% Require variables and set default values for the suite.
%%
suite() ->
	[{timetrap, {minutes, 1}}].

-spec init_per_suite(Config :: [tuple()]) -> Config :: [tuple()].
%% Initiation before the whole suite.
%%
init_per_suite(Config) ->
	PrivDir = ?config(priv_dir, Config),
	application:load(mnesia),
	ok = application:set_env(mnesia, dir, PrivDir),
	{ok, [m3ua_asp, m3ua_as]} = m3ua_app:install(),
	ok = application:start(m3ua),
	ok = application:start(gtt),
	Config.

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(_Config) ->
	ok = application:stop(gtt),
	ok = application:stop(m3ua).

-spec init_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> Config :: [tuple()].
%% Initiation before each test case.
%%
init_per_testcase(TC, Config) ->
	case is_alive() of
			true ->
				Config;
			false ->
				{skip, not_alive}
	end;
init_per_testcase(_TestCase, Config) ->
	Config.

-spec end_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> any().
%% Cleanup after each test case.
%%
end_per_testcase(_TestCase, _Config) ->
	ok.

-spec sequences() -> Sequences :: [{SeqName :: atom(), Testcases :: [atom()]}].
%% Group test cases into a test sequence.
%%
sequences() ->
	[].

-spec all() -> TestCases :: [Case :: atom()].
%% Returns a list of all test cases in this test suite.
%%
all() ->
	[].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

transfer_in() ->
	[{userdata, [{doc, "Transfer MTP3 payload to SG."}]}].

transfer_in(_Config) ->
	PC = 2305,
	{ok, SgNode} = slave(),
	{ok, _} = rpc:call(Sg1Node, m3ua_app, install, [[SgNode]]),
	ok = rpc:call(SgNode, application, start, [m3ua]),
	{ok, SgpEP} = rpc:call(SgNode, m3ua, start,
			[gtt_m3ua_cb, 0, [{role, sgp}]]),
	{_, server, sgp, {_, Port}} = m3ua:get_ep(SgpEP),
	Ref = make_ref(),
	{Ref, ClientEP} = m3ua:start(callback(Ref), Port, []),
	AspPid = wait(Ref),
	[Assoc] = m3ua:get_assoc(ClientEP),
	ok = m3ua:asp_up(ClientEP, Assoc),
	Keys = [{PC, [], []}],
	{ok, RC} =  m3ua:register(ClientEP, Assoc,
			undefined, undefined, Keys, loadshare),
	ok = m3ua:asp_active(ClientEP, Assoc),
	{Ref, RC, active} = wait(Ref),
	Stream = 1,
	NI = rand:uniform(4),
	SI = rand:uniform(10),
	SLS = rand:uniform(10),
	Data = crypto:strong_rand_bytes(100),
	DPC = rand:uniform(16777215),
	ok = m3ua:transfer(Asp, Stream, RC, PC, DPC, NI, SI, SLS, Data),
	ok = rpc:call(SgNode, m3ua, stop, [SgpEP]),
	ok = m3ua:stop(ClientEP),
	ok = slave:stop(AsNode).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

slave() ->
	Path1 = filename:dirname(code:which(m3ua)),
	Path2 = filename:dirname(code:which(?MODULE)),
	ErlFlags = "-pa " ++ Path1 ++ " -pa " ++ Path2,
	{ok, Host} = inet:gethostname(),
	Node = "as" ++ integer_to_list(erlang:unique_integer([positive])),
	slave:start_link(Host, Node, ErlFlags).

callback(Ref) ->
	Finit = fun(_Module, _Asp, _EP, _EpName, _Assoc, Pid) ->
				Pid ! {Ref, self()},
				{ok, once, []}
	end,
	Fnotify = fun(RC, Status, _AspID, State, Pid) ->
				Pid ! {Ref, RC, Status},
				{ok, State}
	end,
	#m3ua_fsm_cb{init = Finit, notify = Fnotify, extra = [self()]}.

wait(Ref) ->
	receive
		{Ref, Pid} ->
			Pid;
		{Ref, RC, Status} ->
			{RC, Status}
	end.

