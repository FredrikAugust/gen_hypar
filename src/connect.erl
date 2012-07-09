%% @doc Module that implements the tcp-connection handling between two
%%      nodes in hyparview. Either listens to a socket for connections
%%      or provided with an existing open socket.

-module(connect).

-behaviour(gen_server).

%% API
-export([start_link/1, start_link/2, send_message/2,
         send_sync_message/2, reply/3, kill/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(TIMEOUT, infinity).

-include("hyparerl.hrl").

-record(conn, {socket :: inet:socket(),
               sync_ref = none :: {reference(), {pid(), reference()}} | none}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Start a tcp-handler that accepts connections from a listen-socket
start_link(ListenSocket) ->
    gen_server:start_link(?MODULE, [listen, ListenSocket], []).

%% @doc Start a tcp-handler with a started tcp-connection
start_link(_ListenSocket, Socket) ->
    gen_server:start_link(?MODULE, [connect, Socket], []).

%% @doc Wrapper function over gen_server:cast
send_message(Pid, Msg) ->
    gen_server:cast(Pid, {async, Msg}).

%% @doc Send a synchrounous message
send_sync_message(Pid, Msg) ->
    gen_server:call(Pid, {sync, Msg}, ?TIMEOUT).

%% @doc Reply to a sync-message
reply(Pid, Ref, Reply) ->
    gen_server:cast(Pid, {reply, Ref, Reply}).

%% @doc Kill a tcp-handler
kill(Pid) ->
    gen_server:cast(Pid, kill).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% Either initiate a connection via a listen socket or existing socket
init([listen, ListenSocket]) ->
    gen_server:cast(self(), accept),
    {ok, #conn{socket=ListenSocket}};
init([connect, Socket]) ->
    {ok, #conn{socket=Socket}}.

%% Handle sync-messages
%% A bit concered of deadlock. Feels like this might be suceptible to that.
%% As far as I can see now that won't happen since I only will use
%% sync-messages for the party who initated the connection.
handle_call({sync, Msg}, From, Conn=#conn{socket=Socket,
                                          sync_ref=none}) ->
    io:format("Sending sync-message: ~p~n", [Msg]),
    Ref = make_ref(),
    send(Socket, {sync, Ref, Msg}),
    {noreply, Conn#conn{sync_ref={Ref, From}}}.

%% Accept an incoming connection
handle_cast(accept, Conn=#conn{socket=ListenSocket}) ->
    {ok, Socket} = gen_tcp:accept(ListenSocket),
    connect_sup:start_listener(),
    {noreply, Conn#conn{socket=Socket}};
%% Kill the connection
handle_cast(kill, Conn=#conn{socket=Socket}) ->
    io:format("Killing connection, pid: ~p~n", [self()]),
    gen_tcp:close(Socket),
    {stop, normal, Conn};
%% Handle a message
handle_cast(Msg, Conn=#conn{socket=Socket}) ->
    io:format("Sending message: ~p~n", [Msg]),
    send(Socket, Msg),
    {noreply, Conn}.

%% Take care of incoming tcp-data
handle_info({tcp, Socket, Data}, Conn) ->
    io:format("Recieved data over connection~n"),  
    Return = case binary_to_term(Data) of
                 {async, Msg} -> 
                     gen_server:cast(hypar_man, {Msg, self()}),
                     {noreply, Conn};
                 {reply, Ref, Reply} ->
                     {Ref, From} = Conn#conn.sync_ref,
                     gen_server:reply(From, Reply),
                     {noreply, Conn#conn{sync_ref=none}};
                 {sync, Ref, Msg} ->
                     Reply = gen_server:call(hypar_man, Msg, ?TIMEOUT),
                     send(Socket, {reply, Ref, Reply}),
                     {noreply, Conn}
             end,
    inet:setopts(Socket, [{active, once}]),
    Return;
%% If the connection is closed, stop the handler
handle_info({tcp_closed, _Socket}, Conn) ->
    io:format("TCP-connection closed, pid: ~p~n", [self()]),
    {stop, normal, Conn};
%% If the connection experience an error, stop the handler
handle_info({tcp_error, _Socket, _Reason}, Conn) ->
    io:format("TCP-connection error, pid: ~p~n", [self()]),
    {stop, normal, Conn}.

terminate(_Reason, _Conn) ->
    ok.

code_change(_OldVsn, Conn, _Extra) ->
    {ok, Conn}.

%%%===================================================================
%%% Internal functions
%%%===================================================================    

%% Wrapper for gen_tcp:send and term_to_binary.
send(Socket, Msg) ->
    gen_tcp:send(Socket, term_to_binary(Msg)).
