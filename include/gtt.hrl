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
-record(gtt_endpoint,
		{name :: term(),
		sctp_role :: client | server,
		m3ua_role :: sgp | asp,
		callback :: {Module :: atom(), State :: term()},
		address :: inet:ip_address(),
		port :: inet:port_number(),
		options :: list(),
		node :: node(),
		ep :: pid()}).

-record(gtt_as,
		{name :: term(),
		na :: pos_integer(),
		keys :: [{DPC :: pos_integer(), [SI :: pos_integer()], [OPC :: pos_integer()]}],
		mode :: override | loadshare | broadcast,
		min_asp = 1 :: pos_integer(),
		max_asp :: pos_integer(),
		node :: node()}).

-record(gtt_sg,
		{name :: term(),
		na :: pos_integer(),
		keys :: [{DPC :: pos_integer(), [SI :: pos_integer()], [OPC :: pos_integer()]}],
		mode :: override | loadshare | broadcast,
		min_asp = 1 :: pos_integer(),
		max_asp :: pos_integer(),
		node :: node()}).


