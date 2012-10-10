%% -------------------------------------------------------------------
%% @author Emil Falk <emil.falk.1988@gmail.com>
%% @copyright (C) 2012, Emil Falk
%% @private
%% @title Utility module, functions that does not fit anywhere else
%% @doc Utility functions
-module(gen_hypar_util).

-include("gen_hypar.hrl").

%% Registration
-export([wait_for/1, register/2, register_self/1]).
%% Encode/decode
-export([encode_id/1, decode_id/1, encode_idlist/1, decode_idlist/1]).
%% Random
-export([drop_return/2, drop_nth/2, random_elem/1, take_n_random/2,
         drop_random_element/1, drop_n_random/2]).

%%%===================================================================
%%% Registration
%%%===================================================================

-spec wait_for(Name :: any()) -> {ok, pid()}.
%% @doc Wait for a process to register via gproc
wait_for(Name) ->
    {Pid, _} = gproc:await({n, l, Name}),
    {ok, Pid}.

-spec register(Name :: any(), Pid :: pid()) -> yes | no.
%% @doc Register a process with pid in gproc
register(Name, Pid) ->
    gproc:register_name(Name, Pid).

-spec register_self(Name :: any()) -> yes | no.
%% @doc Register this process in gproc
register_self(Name) ->
    gproc:add_local_name(Name).

%%%===================================================================
%%% Serialization
%%%===================================================================

-spec encode_id(id()) -> binary().
%% @doc Encode an identifier as a 6-byte binary
encode_id({{A,B,C,D},Port}) ->
    <<A/integer, B/integer, C/integer, D/integer, Port:16/integer>>.

-spec decode_id(binary()) -> id().
%% @doc Parse a 6-byte identifier from a binary
decode_id(<<A/integer, B/integer, C/integer, D/integer, Port:16/integer>>) ->
    {{A, B, C, D}, Port}.

-spec decode_idlist(Bin :: binary()) -> list(id()).
%% @doc Parse a list of ids
decode_idlist(<<>>) ->
    [];
decode_idlist(<<Id:?IDSIZE/binary, Rest/binary>>) ->
    [decode_id(Id)|decode_idlist(Rest)].

-spec encode_idlist(List :: list(id())) -> binary().
%% @doc Encode a list of ids
encode_idlist([]) ->
    <<>>;
encode_idlist([H|List]) ->    
    BId = encode_id(H),
    Bin = encode_idlist(List),
    <<BId:?IDSIZE/binary, Bin/binary>>.

%%%===================================================================
%%% Randomization
%%%===================================================================

-spec drop_return(N :: pos_integer(), List :: list(T)) -> {T,list(T)}.
%% @pure
%% @doc Drops the <em>N'th</em> element of <em>List</em> returning both
%%      the dropped element and the resulting list.
drop_return(N, List) ->
    drop_return(N, List, []).

-spec drop_nth(N :: pos_integer(), List :: list(T)) -> list(T).
%% @pure
%% @doc Drop the <em>N'th</em> element of <em>List</em>.
drop_nth(N, List0) ->
    {_, List} = drop_return(N, List0),
    List.

-spec random_elem(List :: list(T)) -> T.
%% @doc Get a random element of <em>List</em>.
random_elem(List) ->
    I = random:uniform(length(List)),
    lists:nth(I, List).

-spec take_n_random(N :: non_neg_integer(), List :: list(T)) -> list(T).
%% @doc Take <em>N</em> random elements from <em>List</em>.
take_n_random(_, []) -> [];
take_n_random(N, List) -> 
    take_n_random(N, List, length(List)).

-spec drop_random_element(List :: list(T)) -> {T, list(T)}.
%% @doc Removes a random element from <em>List, returning
%%      the new list and the dropped element.
drop_random_element(List) ->
    N = random:uniform(length(List)),
    drop_return(N, List).

-spec drop_n_random(N :: pos_integer(), List :: list(T)) -> list(T).
%% @doc Removes n random elements from the list
drop_n_random(N, List) when N >= 0 -> drop_n_random(List, N, length(List));
drop_n_random(_, List) -> List.

%%%===================================================================
%%% Internal functions
%%%===================================================================

-spec take_n_random(N :: non_neg_integer(), L :: list(T),
                    Len :: non_neg_integer()) -> list(T).
%% @doc Helper function for take_n_random/2.
take_n_random(0, _, _) -> [];
take_n_random(_, _, 0) -> [];
take_n_random(N, L, Len) ->
    I = random:uniform(Len),
    {E, L1} = drop_return(I, L),
    [E|take_n_random(N-1, L1, Len-1)].

-spec drop_return(N :: pos_integer(), L :: list(T), S :: list(T))
                 -> {T, list(T)}.
%% @pure
%% @doc Helper function for drop_return/2
drop_return(1, [H|T], S) -> {H, lists:reverse(S) ++ T};
drop_return(N, [H|T], S) -> drop_return(N-1, T, [H|S]).

-spec drop_n_random(L :: list(T), N :: non_neg_integer(),
                    Len :: non_neg_integer()) -> list(T).
%% @doc Helper-function for drop_n_random/2
drop_n_random(L, 0, _) -> L;
drop_n_random(_, _, 0) -> [];
drop_n_random(L0, N, Len) ->
    I = random:uniform(Len),
    {_, L} = drop_return(I, L0),
    drop_n_random(L, N-1, Len-1).