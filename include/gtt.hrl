%%% gtt.hrl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2015-2021 SigScale Global Inc.
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
%%%

-include_lib("m3ua/include/m3ua.hrl").

-record(gtt_ep,
		{name :: gtt:ep_ref(),
		sctp_role :: client | server | '_',
		m3ua_role :: sgp | asp | '_',
		callback :: atom() | #m3ua_fsm_cb{},
		cb_opts :: term() | undefined,
		local :: {Address :: inet:ip_address(),
				Port :: inet:port_number(), Options :: list()} | '_',
		remote :: undefined | {Address :: inet:ip_address(),
				Port :: inet:port_number(), Options :: list()} | '_',
		as = [] :: [AS :: gtt:as_ref()] | '_',
		node :: node(),
		ep :: pid() | undefined | '_'}). % to be removed

-record(gtt_as,
		{name :: gtt:as_ref(),
		role :: as | sg,
		rc :: undefined | 0..4294967295,
		na :: undefined | 0..4294967295,
		keys :: [{DPC :: 0..16777215,
				[SI :: byte()], [OPC :: 0..16777215]}],
		mode :: override | loadshare | broadcast,
		min_asp = 1 :: pos_integer(),
		max_asp :: pos_integer(),
		fsm = [] :: [{EP :: pid(), Assoc :: pos_integer()}]}). % to be removed 

-record(gtt_pc,
		{dpc :: 0..16777215 | undefined,
		mask = 0 :: non_neg_integer() | '_',
		na :: 0..4294967295 | '_' | undefined,
		si = [] :: [byte()] | '_',
		opc = [] :: [0..16777215] | '_',
		as :: m3ua:routing_key() | '$1' | undefined}).

