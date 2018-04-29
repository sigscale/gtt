%%% gtt.hrl
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
%%%

-include_lib("m3ua/include/m3ua.hrl").

-type ep_ref() :: term().
-type as_ref() :: term().

-record(gtt_ep,
		{name :: ep_ref(),
		sctp_role :: client | server | '_',
		m3ua_role :: sgp | asp | '_',
		callback :: atom() | #m3ua_fsm_cb{},
		local :: {Address :: inet:ip_address(),
				Port :: inet:port_number(), Options :: list()} | '_',
		remote :: undefined | {Address :: inet:ip_address(),
				Port :: inet:port_number(), Options :: list()} | '_',
		as = [] :: [AS :: as_ref()] | '_',
		node :: node(),
		ep :: pid() | undefined | '_'}). % to be removed

-record(gtt_as,
		{name :: as_ref(),
		role :: as | sg,
		na :: pos_integer(),
		keys :: [{DPC :: pos_integer(), [SI :: pos_integer()], [OPC :: pos_integer()]}],
		mode :: override | loadshare | broadcast,
		min_asp = 1 :: pos_integer(),
		max_asp :: pos_integer(),
		fsm = [] :: [{EP :: pid(), Assoc :: pos_integer()}]}). % to be removed 

-record(gtt_pc,
		{dpc :: pos_integer() | undefined,
		mask = 0 :: non_neg_integer() | '_',
		na :: pos_integer() | '_' | undefined,
		si = [] :: [byte()] | '_',
		opc = [] :: [pos_integer()] | '_',
		as :: routing_key() | '$1' | undefined}).

