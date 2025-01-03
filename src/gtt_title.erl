%%% gtt_title.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2024-2025 SigScale Global Inc.
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
%%% @doc This library module implements global title translation tables
%%% 	in the {@link //gtt. gtt} application.
%%%
%%% @todo Implement garbage collection.
%%% @end
%%%
-module(gtt_title).
-copyright('Copyright (c) 2024-2025 SigScale Global Inc.').

%% export API
-export([new/2, insert/2, insert/3, delete/2,
		get_first/2, get_last/2, lookup_first/2, lookup_last/2,
		list/0, list/2, backup/2, restore/2, clear/1, delete/1]).

-include("gtt.hrl").

-define(WAIT, 10000).
-define(CHUNKSIZE, 100).

%%----------------------------------------------------------------------
%%  The gtt_title API
%%----------------------------------------------------------------------

-spec new(Table, Options) -> Result
	when
		Table :: atom(),
		Options :: [{Copies, Nodes}],
		Copies :: disc_copies | disc_only_copies | ram_copies,
		Nodes :: [atom()],
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Create a new global title table.
%%
%%  	The `Options' define table definitions used in {@link //mnesia}.
%%
%% @see //mnesia/mnesia:create_table/2
%%
new(Table, []) ->
	Nodes = [node() | nodes()],
	new(Table, [{disc_copies, Nodes}]);
new(Table, Options)
		when is_atom(Table), is_list(Options) ->
	case mnesia:create_table(Table, Options ++
			[{user_properties, [{gtt, true}]},
			{attributes, record_info(fields, gtt_title)},
			{record_name, gtt_title}]) of
		{atomic, ok} ->
			new1(mnesia:wait_for_tables([Table], ?WAIT));
		{aborted, Reason} ->
			{error, Reason}
	end.
%% @hidden
new1(ok) ->
	ok;
new1({timeout, [Table]}) ->
	{error, timeout};
new1({error, Reason}) ->
	{error, Reason}.

-spec insert(Table, Address, Value) -> true
	when
		Table :: atom(),
		Address :: string() | binary(),
		Value :: term().
%% @doc Insert a global title table entry.
%%
insert(Table, Address, Value) when is_binary(Address) ->
	insert(Table, binary_to_list(Address), Value);
insert(Table, Address, Value)
		when is_atom(Table), is_list(Address) ->
	F = fun() ->
			insert(Table, Address, Value, [])
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			true;
		{aborted, Reason} ->
			exit(Reason)
	end.

-spec insert(Table, Items) -> true
	when
		Table :: atom(),
		Items :: [{Address, Value}],
		Address :: string() | binary(),
		Value :: term().
%% @doc Insert a list of global title table entries.
%%
%% 	The entries are inserted as a transaction, either all entries
%% 	are added to the table or, if an entry insertion fails, none at
%% 	all.
%%
insert(Table, Items) when is_atom(Table), is_list(Items)  ->
	InsFun = fun F({Address, Value}) when is_binary(Address) ->
				F({binary_to_list(Address), Value});
			F({Address, Value}) when is_list(Address) ->
				insert(Table, Address, Value, [])
	end,
	TransFun = fun() ->
			lists:foreach(InsFun, Items)
	end,
	case mnesia:transaction(TransFun) of
		{atomic, ok} ->
			true;
		{aborted, Reason} ->
			exit(Reason)
	end.

-spec delete(Table, Address) -> true
	when
		Table :: atom(),
		Address :: string() | binary().
%% @doc Delete a global title table entry.
%%
delete(Table, Address) when is_atom(Table), is_list(Address) ->
	Fun = fun() ->
			mnesia:delete(Table, Address, write)
	end,
	case mnesia:transaction(Fun) of
		{atomic, ok} ->
			true;
		{aborted, Reason} ->
			exit(Reason)
	end.

-spec get_first(Table, Address) -> Value
	when
		Table :: atom(),
		Address :: string() | binary(),
		Value :: term().
%% @doc Get the value of the first matching address prefix.
%%
get_first(Table, [Digit | Rest]) when is_atom(Table) ->
	F1 = fun F([H | T], [#gtt_title{gtai = Prefix, value = undefined}]) ->
				F(T, mnesia:read(Table, Prefix ++ [H], read));
			F(_, [#gtt_title{value = Value}]) ->
				Value
	end,
	F2 = fun() ->
			F1(Rest, mnesia:read(Table, [Digit], read))
	end,
	mnesia:async_dirty(F2).

-spec get_last(Table, Address) -> Value
	when
		Table :: atom(),
		Address :: string() | binary(),
		Value :: term().
%% @doc Get the value with the longest matching address prefix.
%%
get_last(Table, Address) when is_atom(Table), is_list(Address) ->
	F1 = fun F([_ | T], []) ->
				F(T, mnesia:read(Table, lists:reverse(T), read));
			F([_ | T], [#gtt_title{value = undefined}]) ->
				F(T, mnesia:read(Table, lists:reverse(T), read));
			F(_, [#gtt_title{value = Value}]) ->
				Value
	end,
	F2 = fun() ->
				F1(lists:reverse(Address), mnesia:read(Table, Address, read))
	end,
	mnesia:async_dirty(F2).

-spec lookup_first(Table, Address) -> Result
	when
		Table :: atom(),
		Address :: string() | binary(),
		Result :: {ok, Value} | {error, Reason},
		Value :: term(),
		Reason :: not_found.
%% @doc Lookup the value with the first matching address prefix.
%%
lookup_first(Table, [Digit | Rest]) when is_atom(Table) ->
	F1 = fun F([H | T], [#gtt_title{gtai = Prefix, value = undefined}]) ->
				F(T, mnesia:read(Table, Prefix ++ [H], read));
			F(_, [#gtt_title{value = Value}]) ->
				{ok, Value};
			F(_, _) ->
				{error, not_found}
	end,
	F2 = fun() ->
			F1(Rest, mnesia:read(Table, [Digit], read))
	end,
	mnesia:async_dirty(F2).

-spec lookup_last(Table, Address) -> Result
	when
		Table :: atom(),
		Address :: string() | binary(),
		Result :: {ok, Value} | {error, Reason},
		Value :: term(),
		Reason :: not_found.
%% @doc Lookup the value with the longest matching address prefix.
%%
lookup_last(Table, Address) when is_atom(Table), is_list(Address) ->
	F1 = fun F([_ | T], []) ->
				F(T, mnesia:read(Table, lists:reverse(T), read));
			F([_ | T], [#gtt_title{value = undefined}]) ->
				F(T, mnesia:read(Table, lists:reverse(T), read));
			F(_, [#gtt_title{value = Value}]) ->
				{ok, Value};
			F(_, _) ->
				{error, not_found}
	end,
	F2 = fun() ->
				F1(lists:reverse(Address), mnesia:read(Table, Address, read))
	end,
	mnesia:async_dirty(F2).

-spec backup(Tables, File) -> Result
	when
		Tables :: Table | [Table],
		Table :: atom(),
		File :: string(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Create a backup of the named global title table(s) in `File.BUPTMP'.
%%
backup(Tables, File) when is_atom(Tables) ->
	backup([Tables], File);
backup(Tables, File) when is_list(Tables), is_list(File) ->
	case mnesia:activate_checkpoint([{max, Tables}]) of
		{ok, Name, _Nodes} ->
			case mnesia:backup_checkpoint(Name, File) of
				ok ->
					mnesia:deactivate_checkpoint(Name),
					ok;
				{error,Reason} ->
					{error, Reason}
			end;
		{error,Reason} ->
			{error, Reason}
	end.

-spec restore(Tables, File) -> Result
	when
		Tables :: Table | [Table],
		Table :: atom(),
		File :: string(),
		Result :: {ok,  RestoredTabs} | {error, Reason},
		RestoredTabs :: [atom()],
		Reason :: term().
%% @doc Restore the named global title table(s) from the backup in `File.BUPTMP'.
%%
restore(Tables, File) when is_atom(Tables) ->
	restore([Tables], File);
restore(Tables, File) when is_list(Tables), is_list(File) ->
	case mnesia:restore(File, [{clear_tables, Tables}]) of
		{atomic, RestoredTabs} ->
			{ok, RestoredTabs};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec list() -> Tables
	when
		Tables :: [Table],
		Table :: atom().
%% @doc List all global title tables.
%%
list() ->
	list_tables(mnesia:system_info(tables), []).
%% @hidden
list_tables([H | T], Acc) ->
	case mnesia:table_info(H, record_name) of
		gtt_title ->
			list_tables(T, [H | Acc]);
		_ ->
			list_tables(T, Acc)
	end;
list_tables([], Acc) ->
	lists:reverse(Acc).

-spec list(Cont, Table) -> Result
	when
		Cont :: start,
		Table :: atom(),
		Result :: {Cont1, [#gtt_title{}]} | {error, Reason},
		Cont1 :: eof | any(),
		Reason :: term().
%% @doc List all entries of a global title table.
%%
list(start, Table) when is_atom(Table) ->
	MatchSpec = [{#gtt_title{value = '$2', _ = '_'},
			[{'/=', '$2', undefined}], ['$_']}],
	F = fun() ->
			mnesia:select(Table, MatchSpec, ?CHUNKSIZE, read)
	end,
	list(mnesia:async_dirty(F));
list(Cont, _Table) ->
	F = fun() ->
			mnesia:select(Cont)
	end,
	list(mnesia:async_dirty(F)).
%% @hidden
list({[#gtt_title{} | _] = Gtts, Cont}) ->
	{Cont, Gtts};
list('$end_of_table') ->
	{eof, []}.

-spec clear(Table) -> Result
	when
		Table :: atom(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Clear a global title table.
%%
clear(Table) when is_atom(Table) ->
	case mnesia:clear_table(Table) of
		{atomic, ok} ->
			ok;
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec delete(Table) -> Result
	when
		Table :: atom(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Delete a global title table.
%%
delete(Table) when is_atom(Table) ->
	case mnesia:delete_table(Table) of
		{atomic, ok} ->
			ok;
		{aborted, Reason} ->
			{error, Reason}
	end.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

%% @hidden
insert(Table, [H | []], Value, Acc) ->
	Address =  Acc ++ [H],
	Gtt = #gtt_title{gtai = Address, value = Value},
	mnesia:write(Table, Gtt, write);
insert(Table, [H | T], Value, Acc) ->
	Address =  Acc ++ [H],
	case mnesia:read(Table, Address, write) of
		[#gtt_title{}] ->
			insert(Table, T, Value, Address);
		[] ->
			ok = mnesia:write(Table, #gtt_title{gtai = Address}, write),
			insert(Table, T, Value, Address)
	end.

