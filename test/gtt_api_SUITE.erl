%%% gtt_api_SUITE.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2015-2024 SigScale Global Inc.
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
-copyright('Copyright (c) 2015-2024 SigScale Global Inc.').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% export test cases
-export([new_gtt/0, new_gtt/1,
		insert_gtt/0, insert_gtt/1,
		lookup_first/0, lookup_first/1,
		lookup_last/0, lookup_last/1,
		get_first/0, get_first/1,
		get_last/0, get_last/1,
		delete_gtt/0, delete_gtt/1,
		list_tables/0, list_tables/1,
		list_table/0, list_table/1,
		clear_table/0, clear_table/1,
		delete_table/0, delete_table/1,
		add_tt/0, add_tt/1,
		add_translation/0, add_translation/1,
		translation/0, translation/1,
		translation_fun/0, translation_fun/1,
		transfer_in_1/0, transfer_in_1/1,
		transfer_in_10/0, transfer_in_10/1,
		transfer_in_100/0, transfer_in_100/1,
		transfer_in_1000/0, transfer_in_1000/1]).

-include_lib("m3ua/include/m3ua.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("sccp/include/sccp.hrl").

-define(SSN_CAP,   146).
-define(SSN_INAP,  241).

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
	{ok, [gtt_ep, gtt_as, gtt_pc, gtt_tt]} = gtt_app:install(),
	ok = application:start(inets),
	ok = application:start(snmp),
	ok = application:start(sigscale_mibs),
	ok = application:start(m3ua),
	Config.

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(_Config) ->
	ok = application:stop(m3ua),
	ok = application:stop(sigscale_mibs),
	ok = application:stop(snmp),
	ok = application:stop(inets),
	ok = application:stop(mnesia).

-spec init_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> Config :: [tuple()].
%% Initiation before each test case.
%%
init_per_testcase(_TC, Config) ->
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
	[new_gtt, insert_gtt, lookup_first, lookup_last,
			get_first, get_last, delete_gtt,
			list_tables, list_table, clear_table, delete_table,
			add_tt, add_translation, translation, translation_fun,
			transfer_in_1, transfer_in_10, transfer_in_100,
			transfer_in_1000].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

new_gtt() ->
	[{userdata, [{doc, "Create a new global title table."}]}].

new_gtt(_Config) ->
	Table = ?FUNCTION_NAME,
	ok = gtt_title:new(Table, [{disc_copies, [node() | nodes()]}]),
	mnesia:table_info(Table, attributes).

insert_gtt() ->
	[{userdata, [{doc, "Add an AS to a global title table."}]}].

insert_gtt(_Config) ->
	Table = ?FUNCTION_NAME,
	ok = gtt_title:new(Table, [{disc_copies, [node() | nodes()]}]),
	Address = address(),
	NA = rand:uniform(4294967296) - 1,
	DPC = rand:uniform(16777216) - 1,
	Keys = [{DPC, [], []}],
	TMF = loadshare,
	AS = {routing_key, {NA, Keys, TMF}},
	true = gtt_title:insert(Table, Address, AS).

lookup_first() ->
	[{userdata, [{doc, "Find the first matching address."}]}].

lookup_first(_Config) ->
	Table = ?FUNCTION_NAME,
	ok = gtt_title:new(Table, [{disc_copies, [node() | nodes()]}]),
	fill(Table),
	Address = address(12),
	NA = rand:uniform(4294967296) - 1,
	DPC = rand:uniform(16777216) - 1,
	Keys = [{DPC, [], []}],
	TMF = loadshare,
	AS = {routing_key, {NA, Keys, TMF}},
	gtt_title:insert(Table, Address, AS),
	{ok, _} = gtt_title:lookup_first(Table, Address).

lookup_last() ->
	[{userdata, [{doc, "Find the longest matching prefix."}]}].

lookup_last(_Config) ->
	Table = ?FUNCTION_NAME,
	ok = gtt_title:new(Table, [{disc_copies, [node() | nodes()]}]),
	fill(Table),
	Address = address(12),
	NA = rand:uniform(4294967296) - 1,
	DPC = rand:uniform(16777216) - 1,
	Keys = [{DPC, [], []}],
	TMF = loadshare,
	AS = {routing_key, {NA, Keys, TMF}},
	gtt_title:insert(Table, Address, AS),
	{ok, AS} = gtt_title:lookup_last(Table, Address).

get_first() ->
	[{userdata, [{doc, "get the first matching address."}]}].

get_first(_Config) ->
	Table = ?FUNCTION_NAME,
	ok = gtt_title:new(Table, [{disc_copies, [node() | nodes()]}]),
	fill(Table),
	Address = address(12),
	NA = rand:uniform(4294967296) - 1,
	DPC = rand:uniform(16777216) - 1,
	Keys = [{DPC, [], []}],
	TMF = loadshare,
	AS = {routing_key, {NA, Keys, TMF}},
	gtt_title:insert(Table, Address, AS),
	_ = gtt_title:get_first(Table, Address).

get_last() ->
	[{userdata, [{doc, "Get the longest matching prefix."}]}].

get_last(_Config) ->
	Table = ?FUNCTION_NAME,
	ok = gtt_title:new(Table, [{disc_copies, [node() | nodes()]}]),
	fill(Table),
	Address = address(20),
	NA = rand:uniform(4294967296) - 1,
	DPC = rand:uniform(16777216) - 1,
	Keys = [{DPC, [], []}],
	TMF = loadshare,
	AS = {routing_key, {NA, Keys, TMF}},
	gtt_title:insert(Table, Address, AS),
	AS = gtt_title:get_last(Table, Address).

delete_gtt() ->
	[{userdata, [{doc, "Delete one entry from the table."}]}].

delete_gtt(_Config) ->
	Table = ?FUNCTION_NAME,
	ok = gtt_title:new(Table, [{disc_copies, [node() | nodes()]}]),
	fill(Table),
	Address = address(12),
	NA = rand:uniform(4294967296) - 1,
	DPC = rand:uniform(16777216) - 1,
	Keys = [{DPC, [], []}],
	TMF = loadshare,
	AS = {routing_key, {NA, Keys, TMF}},
	gtt_title:insert(Table, Address, AS),
	true = gtt_title:delete(Table, Address).

list_tables() ->
	[{userdata, [{doc, "List all global title tables."}]}].

list_tables(_Config) ->
	ok = gtt_title:new(one, [{disc_copies, [node() | nodes()]}]),
	ok = gtt_title:new(two, [{disc_copies, [node() | nodes()]}]),
	ok = gtt_title:new(three, [{disc_copies, [node() | nodes()]}]),
	Tables = gtt_title:list(),
	true = lists:member(one, Tables),
	true = lists:member(two, Tables),
	true = lists:member(three, Tables).

list_table() ->
	[{userdata, [{doc, "List all entries in a global title table."}]}].

list_table(_Config) ->
	Table = ?FUNCTION_NAME,
	ok = gtt_title:new(Table, [{disc_copies, [node() | nodes()]}]),
	N = rand:uniform(500) + 100,
	fill(Table, N),
	F = fun F({eof, L}, Acc) ->
				lists:flatten([L | Acc]);
			F({Cont, L}, Acc) ->
				F(gtt_title:list(Cont, Table), [L | Acc])
	end,
	F(gtt_title:list(start, Table), []).

clear_table() ->
	[{userdata, [{doc, "Clear all entries in a global title table."}]}].

clear_table(_Config) ->
	Table = ?FUNCTION_NAME,
	ok = gtt_title:new(Table, [{disc_copies, [node() | nodes()]}]),
	fill(Table),
	ok = gtt_title:clear(Table).

delete_table() ->
	[{userdata, [{doc, "Delete a global title table."}]}].

delete_table(_Config) ->
	Table = ?FUNCTION_NAME,
	ok = gtt_title:new(Table, [{disc_copies, [node() | nodes()]}]),
	fill(Table),
	ok = gtt_title:delete(Table).

add_tt() ->
	[{userdata, [{doc, "Add a global title translation type."}]}].

add_tt(_Config) ->
	Table = ?FUNCTION_NAME,
	TT = 1,
	NP = isdn_tele,
	NAI = national,
	ok = gtt:add_tt(TT, NP, NAI, Table).

add_translation() ->
	[{userdata, [{doc, "Add a global title translation."}]}].

add_translation(_Config) ->
	Table = ?FUNCTION_NAME,
	ok = gtt_title:new(Table, [{disc_copies, [node() | nodes()]}]),
	TT = 1,
	NP = isdn_tele,
	NAI = national,
	ok = gtt:add_tt(TT, NP, NAI, Table),
	Prefix = address(5),
	Replace = address(5),
	USAP = {local, cse_tsl},
	ok = gtt:add_translation(Table,
			sccp_codec:global_title(Prefix),
			sccp_codec:global_title(Replace), usap, USAP).

translation() ->
	[{userdata, [{doc, "Perform global title translation with table"}]}].

translation(_Config) ->
	Table = ?FUNCTION_NAME,
	ok = gtt_title:new(Table, [{disc_copies, [node() | nodes()]}]),
	fill(Table),
	TT = 1,
	NP = isdn_tele,
	NAI = national,
	ok = gtt:add_tt(TT, NP, NAI, Table),
	Prefix = address(10),
	Replace = address(10),
	Rest = address(2),
	USAP = {local, cse_tsl},
	ok = gtt:add_translation(Table,
			sccp_codec:global_title(Prefix),
			sccp_codec:global_title(Replace), usap, USAP),
	GT1 = Prefix ++ Rest,
	GT2 = Replace ++ Rest,
	Address1 = #party_address{ri = route_on_gt,
			translation_type = TT,
			numbering_plan = NP,
			nai = NAI,
			gt = GT1},
	Address2 = Address1#party_address{gt = GT2},
	{ok, {usap, USAP, Address2}} = gtt:translate(Address1).

translation_fun() ->
	[{userdata, [{doc, "Perform global title translation with function"}]}].

translation_fun(_Config) ->
	TT = 1,
	NP = isdn_tele,
	NAI = international,
	CC = [1],
	NSN = [4, 1, 6, 5, 5, 5, 1, 2, 3, 4],
	USAP = {local, cse_tsl},
	MFA = {gtt, international_to_national, [CC, usap, USAP]},
	ok = gtt:add_tt(TT, NP, NAI, MFA),
	Address1 = #party_address{ri = route_on_gt,
			translation_type = TT,
			numbering_plan = NP,
			nai = NAI,
			gt = CC ++ NSN},
	Address2 = Address1#party_address{nai = national, gt = NSN},
	{ok, {usap, USAP, Address2}} = gtt:translate(Address1).

transfer_in_1() ->
	[{userdata, [{doc, "Transfer MTP3 payload to SG (once)."}]}].

transfer_in_1(_Config) ->
	transfer_in(1).

transfer_in_10() ->
	[{userdata, [{doc, "Transfer MTP3 payload to SG (ten)."}]}].

transfer_in_10(_Config) ->
	transfer_in(10).

transfer_in_100() ->
	[{userdata, [{doc, "Transfer MTP3 payload to SG (hundred)."}]}].

transfer_in_100(_Config) ->
	transfer_in(100).

transfer_in_1000() ->
	[{userdata, [{doc, "Transfer MTP3 payload to SG (thousand)."}]}].

transfer_in_1000(_Config) ->
	transfer_in(1000).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

address() ->
	address(rand:uniform(10)).
address(N) ->
	address(N, []).
address(0, Acc) ->
	Acc;
address(N, Acc) ->
	Digit = rand:uniform(10) - 1,
	address(N - 1, [Digit | Acc]).

fill(Table) ->
	fill(Table, 50).
fill(_Table, 0) ->
	ok;
fill(Table, N) ->
	Address = address(10),
	NA = rand:uniform(4294967296) - 1,
	DPC = rand:uniform(16777216) - 1,
	Keys = [{DPC, [], []}],
	TMF = loadshare,
	AS = {routing_key, {NA, Keys, TMF}},
	gtt_title:insert(Table, Address, AS),
	fill(Table, N - 1).

slave() ->
	Path1 = filename:dirname(code:which(m3ua)),
	Path2 = filename:dirname(code:which(gtt)),
	ErlFlags = "-pa " ++ Path1 ++ " -pa " ++ Path2,
	{ok, Host} = inet:gethostname(),
	Node = "as" ++ integer_to_list(erlang:unique_integer([positive])),
	slave:start_link(Host, Node, ErlFlags).

callback(Ref) ->
	Finit = fun(_Module, _Asp, _EP, _EpName, _Assoc, _Options, Pid) ->
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

transfer_in(Count) ->
	Address = {127,0,0,1},
	PC = 2305,
	Keys = [{PC, [], []}],
	{ok, SgNode} = slave(),
	{ok, _} = rpc:call(SgNode, m3ua_app, install, [[SgNode]]),
	{ok, _} = rpc:call(SgNode, gtt_app, install, [[SgNode]]),
	{ok, _} = rpc:call(SgNode, gtt, add_ep, [ep1, {Address, 0, []},
			undefined, server, sgp, gtt_m3ua_cb,
			[{ssn, #{?SSN_CAP => undefined}}], []]),
	ok = rpc:call(SgNode, application, start, [snmp]),
	ok = rpc:call(SgNode, application, start, [sigscale_mibs]),
	ok = rpc:call(SgNode, application, start, [inets]),
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
	Fcount = fun F() ->
			case rpc:call(SgNode, m3ua, getcount, [SgpEP, SgpAssoc]) of
				{ok, #{transfer_in := Count}} ->
					ok;
				{ok, #{transfer_in := N}} when N < Count ->
					receive after 500 -> ok end,
					F()
			end
	end,
	ok = Fcount(),
	ok = m3ua:stop(ClientEP),
	ok = rpc:call(SgNode, m3ua, stop, [SgpEP]),
	ok = slave:stop(SgNode).

