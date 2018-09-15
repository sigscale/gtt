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

-include("m3ua.hrl").
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

start() ->
	[{userdata, [{doc, "."}]}].

start(_Config) ->
	ok.

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

