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
	Config.

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(_Config) ->
	ok = application:stop(m3ua).

-spec init_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> Config :: [tuple()].
%% Initiation before each test case.
%%
init_per_testcase(_TC, Config) ->
	case is_alive() of
			true ->
				Config;
			false ->
				{skip, not_alive}
	end.

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
	[transfer_in].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

transfer_in() ->
	[{userdata, [{doc, "Transfer MTP3 payload to SG."}]}].

transfer_in(_Config) ->
	Address = {127,0,0,1},
	PC = 2305,
	Keys = [{PC, [], []}],
	{ok, SgNode} = slave(),
	{ok, _} = rpc:call(SgNode, m3ua_app, install, [[SgNode]]),
	{ok, _} = rpc:call(SgNode, gtt_app, install, [[SgNode]]),
	{ok, _} = rpc:call(SgNode, gtt, add_ep, [ep1, {Address, 0, []},
			undefined, server, sgp, gtt_m3ua_cb, []]),
	ok = rpc:call(SgNode, application, start, [m3ua]),
	ok = rpc:call(SgNode, application, start, [sccp]),
	ok = rpc:call(SgNode, application, start, [gtt]),
	[SgpEP] = rpc:call(SgNode, m3ua, get_ep, []),
	{_, server, sgp, {_, Port}} = m3ua:get_ep(SgpEP),
	Ref = make_ref(),
	{ok, ClientEP} = m3ua:start(callback(Ref), 0,
			[{role, asp}, {connect, Address, Port, []}]),
	AspPid = wait(Ref),
	[ClientAssoc] = m3ua:get_assoc(ClientEP),
	ok = m3ua:asp_up(ClientEP, ClientAssoc),
	{ok, RC} =  m3ua:register(ClientEP, ClientAssoc,
			undefined, 0, Keys, loadshare),
	{[RC], as_inactive} = wait(Ref),
	ok = m3ua:asp_active(ClientEP, ClientAssoc),
	{_, as_active} = wait(Ref), % @todo include RC in notify
	[SgpAssoc] = rpc:call(SgNode, m3ua, get_assoc, [SgpEP]),
	Count = 10,
	Ftransfer = fun F(0) ->
				ok;
			F(N) ->
				Stream = 1,
				DPC = 2058,
				NI = rand:uniform(4),
				SI = rand:uniform(10),
				SLS = rand:uniform(10),
				Data = crypto:strong_rand_bytes(100),
				ok = m3ua:transfer(AspPid,
						Stream, RC, PC, DPC, NI, SI, SLS, Data),
				F(N - 1)
	end,
	ok = Ftransfer(Count),
	receive after 1000 -> ok end,
	{ok, #{transfer_in := Count}} = rpc:call(SgNode,
			m3ua, getcount, [SgpEP, SgpAssoc]),
erlang:display({?MODULE, ?LINE, Count}),
	ok = m3ua:stop(ClientEP),
erlang:display({?MODULE, ?LINE, ok}),
	ok = rpc:call(SgNode, m3ua, stop, [SgpEP]),
erlang:display({?MODULE, ?LINE, ok}),
	ok = slave:stop(SgNode).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

slave() ->
	Path1 = filename:dirname(code:which(m3ua)),
	Path2 = filename:dirname(code:which(gtt)),
	ErlFlags = "-pa " ++ Path1 ++ " -pa " ++ Path2,
	{ok, Host} = inet:gethostname(),
	Node = "as" ++ integer_to_list(erlang:unique_integer([positive])),
	slave:start_link(Host, Node, ErlFlags).

callback(Ref) ->
	Finit = fun(_Module, _Asp, _EP, _EpName, _Assoc, Pid) ->
				Pid ! {Ref, self()},
				{ok, once, []}
	end,
	Fnotify = fun(RCs, Status, _AspID, State, Pid) ->
				Pid ! {Ref, RCs, Status},
				{ok, State}
	end,
	#m3ua_fsm_cb{init = Finit, notify = Fnotify, extra = [self()]}.

wait(Ref) ->
	receive
		{Ref, Pid} ->
			Pid;
		{Ref, RCs, Status} ->
			{RCs, Status}
	end.

