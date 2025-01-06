%%% gtt_m3ua_cb.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2018-2024 SigScale Global Inc.
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
%%% 	This module implements a Signalling Connection Control Part (SCCP)
%%% 	layer as an MTP3-User. A Signaling Gateway Process (SGP) started
%%% 	with this callback module shall perform an SCCP Routing Control (SCRC)
%%% 	function as well as SCCP Management (SCMG).
%%%
-module(gtt_m3ua_cb).
-copyright('Copyright (c) 2018-2024 SigScale Global Inc.').

%% m3ua_asp_fsm callbacks
-export([init/6, recv/9, send/11, pause/4, resume/4, status/4,
		register/5, asp_up/1, asp_down/1, asp_active/1,
		asp_inactive/1, notify/4, info/2, terminate/2]).

-dialyzer(no_undefined_callbacks).
-behaviour(m3ua_sgp_fsm).

-include("gtt.hrl").
-include_lib("sccp/include/sccp.hrl").
-include_lib("sccp/include/sccp_primitive.hrl").

-record(state,
		{module :: atom(),
		fsm :: pid(),
		ep :: pid(),
		ep_name :: term(),
		assoc :: pos_integer(),
		rk = [] :: [m3ua:routing_key()],
		ssn = #{} :: #{SSN :: 0..255 => USAP :: pid()}}).
-type state() :: #state{}.

-export_types([options/0]).

-type options() :: [option()].
-type option() :: {ssn, #{SSN :: 0..255 => USAP :: pid()}}.

-define(SSN_SCMG, 1).
-define(SCMG_SSA, 1).
-define(SCMG_SSP, 2).
-define(SCMG_SST, 3).
-define(SCMG_SOR, 4).
-define(SCMG_SOG, 5).
-define(SCMG_SSC, 6).

-define(sequenceControl(Class), (1 == (Class band 1))).
-define(returnOption(Class), (128 == (Class band 128))).

%%----------------------------------------------------------------------
%%  The gtt_m3ua_cb public API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The m3ua_[asp|sgp]_fsm callbacks
%%----------------------------------------------------------------------

-spec init(Module, Fsm, EP, EpName, Assoc, Options) -> Result
	when
		Module :: atom(),
		Fsm :: pid(),
		EP :: pid(),
		EpName :: term(),
		Assoc :: pos_integer(),
		Options :: options(),
		Result :: {ok, Active, State} | {ok, Active, State, ASs} | {error, Reason},
		Active :: true | false | once | pos_integer(),
		State :: state(),
		Active :: true | false | once | pos_integer(),
		State :: state(),
		ASs :: [{RC, RK, AsName}],
		RC :: 0..4294967295,
		RK :: {NA, Keys, TMT},
		NA :: 0..4294967295 | undefined,
		Keys :: [m3ua:key()],
		TMT :: m3ua:tmt(),
		AsName :: term(),
		Reason :: term().
%% @doc Initialize ASP/SGP callback handler.
%%
%%  Called when ASP/SGP is started.
%%
init(m3ua_sgp_fsm, Fsm, EP, EpName, Assoc, Options) ->
	SSNs = proplists:get_value(ssn, Options, #{}),
	State = #state{module = m3ua_sgp_fsm, fsm = Fsm,
			ep = EP, ep_name = EpName, assoc = Assoc, ssn = SSNs},
	[#gtt_ep{as = ASs}] = mnesia:dirty_read(gtt_ep, EpName),
	init1(ASs, State, []);
init(Module, Fsm, EP, EpName, Assoc, Options) ->
	SSNs = proplists:get_value(ssn, Options, #{}),
	State = #state{module = Module, fsm = Fsm,
			ep = EP, ep_name = EpName, assoc = Assoc, ssn = SSNs},
	{ok, once, State}.
%% @hidden
init1([AS | T], State, Acc) ->
	[#gtt_as{rc = RC, na = NA, keys = Keys, name = Name,
			mode = Mode}] = mnesia:dirty_read(gtt_as, AS),
	init1(T, State, [{RC, {NA, Keys, Mode}, Name} | Acc]);
init1([], State, Acc) ->
	{ok, once, State, lists:reverse(Acc)}.

-spec recv(Stream, RC, OPC, DPC, NI, SI, SLS, Data, State) -> Result
	when
		Stream :: pos_integer(),
		RC :: 0..4294967295 | undefined,
		OPC :: 0..16777215,
		DPC :: 0..16777215,
		NI :: byte(),
		SI :: byte(),
		SLS :: byte(),
		Data :: binary(),
		State :: state(),
		Result :: {ok, Active, NewState} | {error, Reason},
		Active :: true | false | once | pos_integer(),
		NewState :: state(),
		Reason :: term().
%% @doc MTP-TRANSFER indication
%%%  Called when data has arrived for the MTP user.
recv(Stream, RC, OPC, DPC, NI, SI, SLS, UnitData1,
		#state{fsm = Fsm, ssn = SSNs} = State) ->
	Fscmg = fun({ok, UD}) ->
				m3ua:cast(Fsm, Stream, RC, DPC, OPC, NI, SI, SLS, UD),
				{ok, once, State};
			(none) ->
				{ok, once, State}
	end,
	case catch sccp_codec:sccp(UnitData1) of
		#sccp_unitdata{called_party = #party_address{ri = route_on_ssn,
				ssn = ?SSN_SCMG}} = UnitData2 ->
			Fscmg(sccp_management(DPC, UnitData2));
		#sccp_extended_unitdata{called_party = #party_address{ri = route_on_ssn,
				ssn = ?SSN_SCMG}} = UnitData2 ->
			Fscmg(sccp_management(DPC, UnitData2));
		#sccp_long_unitdata{called_party = #party_address{ri = route_on_ssn,
				ssn = ?SSN_SCMG}} = UnitData2 ->
			Fscmg(sccp_management(DPC, UnitData2));
		#sccp_unitdata{data = Data, class = Class,
				called_party = #party_address{ri = route_on_ssn, ssn = SSN} = CalledParty,
				calling_party = CallingParty}
				when is_integer(SSN) andalso is_map_key(SSN, SSNs) ->
			CalledParty1 = CalledParty#party_address{pc = DPC, mtp_sap = Fsm},
			CallingParty1 = CallingParty#party_address{pc = OPC, mtp_sap = Fsm},
			UnitData2 = #'N-UNITDATA'{userData = Data,
					sequenceControl = ?sequenceControl(Class),
					returnOption = ?returnOption(Class),
					callingAddress = CallingParty1,
					calledAddress = CalledParty1},
			USAP = map_get(SSN, SSNs),
			gen_server:cast(USAP, {'N', 'UNITDATA', indication, UnitData2}),
			{ok, once, State};
		#sccp_unitdata{data = Data, class = Class,
				called_party = #party_address{ri = route_on_gt, ssn = SSN} = CalledParty,
				calling_party = CallingParty}
				when is_integer(SSN) andalso is_map_key(SSN, SSNs) ->
			CalledParty1 = CalledParty#party_address{pc = DPC, mtp_sap = Fsm},
			CallingParty1 = CallingParty#party_address{pc = OPC, mtp_sap = Fsm},
			UnitData2 = #'N-UNITDATA'{userData = Data,
					sequenceControl = ?sequenceControl(Class),
					returnOption = ?returnOption(Class),
					callingAddress = CallingParty1,
					calledAddress = CalledParty1},
			USAP = map_get(SSN, SSNs),
			gen_server:cast(USAP, {'N', 'UNITDATA', indication, UnitData2}),
			{ok, once, State};
		#sccp_extended_unitdata{data = Data, class = Class,
				called_party = #party_address{ri = route_on_ssn, ssn = SSN} = CalledParty,
				calling_party = CallingParty}
				when is_integer(SSN) andalso is_map_key(SSN, SSNs) ->
			CalledParty1 = CalledParty#party_address{pc = DPC, mtp_sap = Fsm},
			CallingParty1 = CallingParty#party_address{pc = OPC, mtp_sap = Fsm},
			UnitData2 = #'N-UNITDATA'{userData = Data,
					sequenceControl = ?sequenceControl(Class),
					returnOption = ?returnOption(Class),
					callingAddress = CallingParty1,
					calledAddress = CalledParty1},
			USAP = map_get(SSN, SSNs),
			gen_server:cast(USAP, {'N', 'UNITDATA', indication, UnitData2}),
			{ok, once, State};
		#sccp_extended_unitdata{data = Data, class = Class,
				called_party = #party_address{ri = route_on_gt, ssn = SSN} = CalledParty,
				calling_party = CallingParty}
				when is_integer(SSN) andalso is_map_key(SSN, SSNs) ->
			CalledParty1 = CalledParty#party_address{pc = DPC, mtp_sap = Fsm},
			CallingParty1 = CallingParty#party_address{pc = OPC, mtp_sap = Fsm},
			UnitData2 = #'N-UNITDATA'{userData = Data,
					sequenceControl = ?sequenceControl(Class),
					returnOption = ?returnOption(Class),
					callingAddress = CallingParty1,
					calledAddress = CalledParty1},
			USAP = map_get(SSN, SSNs),
			gen_server:cast(USAP, {'N', 'UNITDATA', indication, UnitData2}),
			{ok, once, State};
		#sccp_long_unitdata{data = Data, class = Class,
				called_party = #party_address{ri = route_on_ssn, ssn = SSN} = CalledParty,
				calling_party = CallingParty}
				when is_integer(SSN) andalso is_map_key(SSN, SSNs) ->
			CalledParty1 = CalledParty#party_address{pc = DPC, mtp_sap = Fsm},
			CallingParty1 = CallingParty#party_address{pc = OPC, mtp_sap = Fsm},
			UnitData2 = #'N-UNITDATA'{userData = Data,
					sequenceControl = ?sequenceControl(Class),
					returnOption = ?returnOption(Class),
					callingAddress = CallingParty1,
					calledAddress = CalledParty1},
			USAP = map_get(SSN, SSNs),
			gen_server:cast(USAP, {'N', 'UNITDATA', indication, UnitData2}),
			{ok, once, State};
		#sccp_long_unitdata{data = Data, class = Class,
				called_party = #party_address{ri = route_on_gt, ssn = SSN} = CalledParty,
				calling_party = CallingParty}
				when is_integer(SSN) andalso is_map_key(SSN, SSNs) ->
			CalledParty1 = CalledParty#party_address{pc = DPC, mtp_sap = Fsm},
			CallingParty1 = CallingParty#party_address{pc = OPC, mtp_sap = Fsm},
			UnitData2 = #'N-UNITDATA'{userData = Data,
					sequenceControl = ?sequenceControl(Class),
					returnOption = ?returnOption(Class),
					callingAddress = CallingParty1,
					calledAddress = CalledParty1},
			USAP = map_get(SSN, SSNs),
			gen_server:cast(USAP, {'N', 'UNITDATA', indication, UnitData2}),
			{ok, once, State};
		UnitData2 ->
			error_logger:info_report(["Other SCCP Message",
					{opc, OPC}, {dpc, DPC},
					{ni, NI}, {si, SI}, {sls, SLS},
					{data, UnitData2}]),
			{ok, once, State}
	end.

-spec send(From, Ref, Stream, RC, OPC, DPC, NI, SI, SLS, Data, State) -> Result
	when
		From :: pid(),
		Ref :: reference(),
		Stream :: pos_integer(),
		RC :: 0..4294967295 | undefined,
		OPC :: 0..16777215,
		DPC :: 0..16777215,
		NI :: byte(),
		SI :: byte(),
		SLS :: byte(),
		Data :: binary(),
		State :: state(),
		Result :: {ok, Active, NewState} | {error, Reason},
		Active :: true | false | once | pos_integer(),
		NewState :: state(),
		Reason :: term().
%% @doc MTP-TRANSFER request
%%%  Called when data has been sent for the MTP user.
send(_From, _Ref, _Stream, _RC, _OPC, _DPC, _NI, _SI, _SLS, _UnitData, State) ->
	{ok, once, State}.

-spec pause(Stream, RC, DPCs, State) -> Result
	when
		Stream :: pos_integer(),
		DPCs :: [DPC],
		RC :: 0..4294967295 | undefined,
		DPC :: 0..16777215,
		State :: state(),
		Result :: {ok, NewState} | {error, Reason},
		NewState :: state(),
		Reason :: term().
%% @doc MTP-PAUSE indication
%%%  Called when an SS7 destination is unreachable.
pause(_Stream, _RC, _DPCs, State) ->
	{ok, State}.

-spec resume(Stream, RC, DPCs, State) -> Result
	when
		Stream :: pos_integer(),
		RC :: 0..4294967295 | undefined,
		DPCs :: [DPC],
		DPC :: 0..16777215,
		State :: state(),
		Result :: {ok, NewState} | {error, Reason},
		NewState :: state(),
		Reason :: term().
%% @doc MTP-RESUME indication.
%%%  Called when a previously unreachable SS7 destination
%%%  becomes reachable.
resume(_Stream, _RC, _DPCs, State) ->
	{ok, State}.

-spec status(Stream, RC, DPCs, State) -> Result
	when
		Stream :: pos_integer(),
		RC :: 0..4294967295 | undefined,
		DPCs :: [DPC],
		DPC :: 0..16777215,
		State :: state(),
		Result :: {ok, NewState} | {error, Reason},
		NewState :: state(),
		Reason :: term().
%% @doc Called when congestion occurs for an SS7 destination
%%% 	or to indicate an unavailable remote user part.
status(_Stream, _RC, _DPCs, State) ->
	{ok, State}.

-spec register(RC, NA, Keys, TMT, State) -> Result
	when
		RC :: 0..4294967295 | undefined,
		NA :: 0..4294967295 | undefined,
		Keys :: [m3ua:key()],
		TMT :: m3ua:tmt(),
		State :: state(),
		Result :: {ok, NewState} | {error, Reason},
		NewState :: state(),
		Reason :: term().
%%  @doc Called when Registration Response message with a
%%		registration status of successful from its peer or
%%		successfully processed an incoming Registration Request message.
register(RC, NA, Keys, TMT, #state{rk = RKs} = State) ->
	RoutingKey = {NA, Keys, TMT},
	case gtt:add_key(RoutingKey) of
		ok ->
			{ok, State#state{rk = [RoutingKey | RKs]}};
		{error, Reason} ->
			{error, Reason}
	end.

-spec asp_up(State) -> Result
	when
		State :: state(),
		Result :: {ok, State}.
%% @doc Called when ASP reports that it has received an ASP UP Ack
%% 	message from its peer or M3UA reports that it has successfully
%%		processed an incoming ASP Up message from its peer.
asp_up(#state{ep_name = EpName, ep = EP, assoc = Assoc} = State) ->
	[#gtt_ep{as = ASs}] = mnesia:dirty_read(gtt_ep, EpName),
	F = fun(AS) ->
				catch gen_fsm:send_event(AS, {'M-ASP_UP', node(), EP, Assoc})
	end,
	lists:foreach(F, ASs),
	{ok, State}.

-spec asp_down(State) -> Result
	when
		State :: state(),
		Result :: {ok, State}.
%% @doc Called when ASP reports that it has received an ASP Down Ack
%%		message from its peer or M3UA reports that it has successfully
%%		processed an incoming ASP Down message from its peer.
asp_down(#state{ep_name = EpName, ep = EP, assoc = Assoc} = State) ->
	[#gtt_ep{as = ASs}] = mnesia:dirty_read(gtt_ep, EpName),
	F = fun(AS) ->
				catch gen_fsm:send_event(AS, {'M-ASP_DOWN', node(), EP, Assoc})
	end,
	lists:foreach(F, ASs),
	{ok, State}.

-spec asp_active(State) -> Result
	when
		State :: state(),
		Result :: {ok, State}.
%% @doc Called when ASP reports that it has received an ASP Active
%%		Ack message from its peer or M3UA reports that it has successfully
%%		processed an incoming ASP Active message from its peer.
asp_active(#state{ep_name = EpName, ep = EP, assoc = Assoc} = State) ->
	[#gtt_ep{as = ASs}] = mnesia:dirty_read(gtt_ep, EpName),
	F = fun(AS) ->
				catch gen_fsm:send_event(AS, {'M-ASP_ACTIVE', node(), EP, Assoc})
	end,
	lists:foreach(F, ASs),
	{ok, State}.

-spec asp_inactive(State) -> Result
	when
		State :: state(),
		Result :: {ok, State}.
%% @doc Called when ASP reports that it has received an ASP Inactive
%%		Ack message from its peer or M3UA reports that it has successfully
%%		processed an incoming ASP Inactive message from its peer.
asp_inactive(#state{ep_name = EpName, ep = EP, assoc = Assoc} = State) ->
	[#gtt_ep{as = ASs}] = mnesia:dirty_read(gtt_ep, EpName),
	F = fun(AS) ->
				catch gen_fsm:send_event(AS, {'M-ASP_INACTIVE', node(), EP, Assoc})
	end,
	lists:foreach(F, ASs),
	{ok, State}.

-spec notify(RCs, Status, AspID, State) -> Result
	when
		RCs :: [RC] | undefined,
		RC :: 0..4294967295,
		Status :: as_inactive | as_active | as_pending
				| insufficient_asp_active | alternate_asp_active
				| asp_failure,
		AspID :: undefined | pos_integer(),
		State :: state(),
		Result :: {ok, State}.
%% @doc Called when SGP reports Application Server (AS) state changes.
notify(_RCs, _Status, _AspID, #state{module = m3ua_sgp_fsm} = State) ->
	{ok, State};
notify(RCs, Status, AspID, #state{module = m3ua_asp_fsm,
		ep_name = EpName, ep = EP, assoc = Assoc} = State) ->
	[#gtt_ep{as = ASs}] = mnesia:dirty_read(gtt_ep, EpName),
	F = fun(AS) ->
				catch gen_fsm:send_event(AS, {'M-NOTIFY', node(), EP, Assoc, RCs, Status, AspID})
	end,
	lists:foreach(F, ASs),
	{ok, State}.

-spec info(Info, State) -> Result
	when
		Info :: term(),
		State :: state(),
		Result :: {ok, Active, NewState} | {error, Reason},
		Active :: true | false | once | pos_integer(),
		NewState :: state(),
		Reason :: term().
%% @doc Called when ASP/SGP receives other `Info' messages.
info({'MTP-TRANSFER', confirm, _Ref} = _Info, State) ->
	{ok, once, State}.

-spec terminate(Reason, State) -> Result
	when
		Reason :: term(),
		State :: state(),
		Result :: any().
%% @doc Called when ASP terminates.
terminate(_Reason, _State) ->
	ok.

-spec sccp_management(DPC, UnitData) -> Result
	when
		DPC :: 0..16383,
		UnitData :: #sccp_unitdata{} | #sccp_extended_unitdata{}
				| #sccp_long_unitdata{},
		Result :: {ok, UnitData} | none.
%% @doc Handle SCCP Management Procedures
sccp_management(DPC, #sccp_unitdata{called_party = CalledParty,
		calling_party = CallingParty, data = Data} = _UnitData) ->
	sccp_management1(DPC, CalledParty, CallingParty, Data);
sccp_management(DPC, #sccp_extended_unitdata{called_party = CalledParty,
		calling_party = CallingParty, data = Data}) ->
	sccp_management1(DPC, CalledParty, CallingParty, Data);
sccp_management(DPC, #sccp_long_unitdata{called_party = CalledParty,
		calling_party = CallingParty, data = Data}) ->
	sccp_management1(DPC, CalledParty, CallingParty, Data).
%% @hidden
sccp_management1(_DPC, CalledParty, CallingParty,
		<<?SCMG_SSA, SSN, PC:2/binary, _SMI, _Rest/binary>>) ->
	error_logger:info_report(["SCCP Management: "
			"Subsystem Allowed",
			{called, CalledParty},
			{calling, CallingParty},
			{ssn, SSN}, {pc, sccp:point_code(sccp_codec:point_code(PC))}]),
	none;
sccp_management1(_DPC, CalledParty, CallingParty,
		<<?SCMG_SSP, SSN, PC:2/binary, _SMI, _Rest/binary>>) ->
	error_logger:info_report(["SCCP Management: "
			"Subsystem Prohibited",
			{called, CalledParty},
			{calling, CallingParty},
			{ssn, SSN}, {pc, sccp:point_code(sccp_codec:point_code(PC))}]),
	none;
sccp_management1(DPC, CalledParty, CallingParty,
		<<?SCMG_SST, SSN, PC:2/binary, _SMI, _Rest/binary>>) ->
	error_logger:info_report(["SCCP Management: "
			"Subsystem Status Test",
			{called, CalledParty},
			{calling, CallingParty},
			{ssn, SSN}, {pc, sccp:point_code(sccp_codec:point_code(PC))}]),
	LocalPC = sccp_codec:point_code(DPC),
	SSA = <<?SCMG_SSA, SSN, LocalPC/binary, 0>>,
	SCMGParty = #party_address{ri = route_on_ssn, ssn = ?SSN_SCMG},
	UnitData = #sccp_unitdata{class = 0,
			called_party = SCMGParty,
			calling_party = SCMGParty,
			data = SSA},
	{ok, sccp_codec:sccp(UnitData)};
sccp_management1(_DPC, CalledParty, CallingParty,
		<<?SCMG_SOR, SSN, PC:2/binary, _SMI, _Rest/binary>>) ->
	error_logger:info_report(["SCCP Management: "
			"Subsystem Out-of-Service Request",
			{called, CalledParty},
			{calling, CallingParty},
			{ssn, SSN}, {pc, sccp:point_code(sccp_codec:point_code(PC))}]),
	none;
sccp_management1(_DPC, CalledParty, CallingParty,
		<<?SCMG_SOG, SSN, PC:2/binary, _SMI, _Rest/binary>>) ->
	error_logger:info_report(["SCCP Management: "
			"Subsystem Out-of-Service Grant",
			{called, CalledParty},
			{calling, CallingParty},
			{ssn, SSN}, {pc, sccp:point_code(sccp_codec:point_code(PC))}]),
	none;
sccp_management1(_DPC, CalledParty, CallingParty,
		<<?SCMG_SSC, SSN, PC:2/binary, _SMI, _:4, Level:4, _Rest/binary>>) ->
	error_logger:info_report(["SCCP Management: "
			"SCCP/Subsystem Congested",
			{called, CalledParty},
			{calling, CallingParty},
			{ssn, SSN}, {pc, sccp:point_code(sccp_codec:point_code(PC))},
			{level, Level}]),
	none;
sccp_management1(DPC, CalledParty, CallingParty, Other) ->
	error_logger:info_report(["SCCP Management: Other",
			{called, CalledParty},
			{calling, CallingParty},
			{dpc, DPC}, {data, Other}]),
	none.

%%----------------------------------------------------------------------
%%  private API functions
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

