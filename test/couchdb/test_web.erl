% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
%   http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.

-module(test_web).
-behaviour(gen_server).

-include("couch_eunit.hrl").

-export([start_link/0, stop/0, loop/1, get_port/0, set_assert/1, check_last/0]).
-export([init/1, terminate/2, code_change/3]).
-export([handle_call/3, handle_cast/2, handle_info/2]).

-define(SERVER, test_web_server).
-define(HANDLER, test_web_handler).
-define(DELAY, 500).

start_link() ->
    gen_server:start({local, ?HANDLER}, ?MODULE, [], []),
    mochiweb_http:start([
        {name, ?SERVER},
        {loop, {?MODULE, loop}},
        {port, 0}
    ]).

loop(Req) ->
    %?debugFmt("Handling request: ~p", [Req]),
    case gen_server:call(?HANDLER, {check_request, Req}) of
        {ok, RespInfo} ->
            {ok, mochiweb_request:respond(RespInfo, Req)};
        {raw, {Status, Headers, BodyChunks}} ->
            Resp = mochiweb_request:start_response({Status, Headers}, Req),
            lists:foreach(fun(C) -> mochiweb_response:send(C, Resp) end, BodyChunks),
            erlang:put(mochiweb_request_force_close, true),
            {ok, Resp};
        {chunked, {Status, Headers, BodyChunks}} ->
            Resp = mochiweb_request:respond({Status, Headers, chunked}, Req),
            timer:sleep(?DELAY),
            lists:foreach(fun(C) -> mochiweb_response:write_chunk(C, Resp) end, BodyChunks),
            mochiweb_response:write_chunk([], Resp),
            {ok, Resp};
        {error, Reason} ->
            ?debugFmt("Error: ~p", [Reason]),
            Body = lists:flatten(io_lib:format("Error: ~p", [Reason])),
            {ok, mochiweb_request:respond({200, [], Body}, Req)}
    end.

get_port() ->
    mochiweb_socket_server:get(?SERVER, port).

set_assert(Fun) ->
    ?assertEqual(ok, gen_server:call(?HANDLER, {set_assert, Fun})).

check_last() ->
    gen_server:call(?HANDLER, last_status).

init(_) ->
    {ok, nil}.

terminate(_Reason, _State) ->
    ok.

stop() ->
    gen_server:call(?SERVER, stop).


handle_call({check_request, Req}, _From, State) when is_function(State, 1) ->
    Resp2 = case (catch State(Req)) of
        {ok, Resp} ->
            {reply, {ok, Resp}, was_ok};
        {raw, Resp} ->
            {reply, {raw, Resp}, was_ok};
        {chunked, Resp} ->
            {reply, {chunked, Resp}, was_ok};
        Error ->
            {reply, {error, Error}, not_ok}
    end,
    mochiweb_request:cleanup(Req),
    Resp2;
handle_call({check_request, _Req}, _From, _State) ->
    {reply, {error, no_assert_function}, not_ok};
handle_call(last_status, _From, State) when is_atom(State) ->
    {reply, State, nil};
handle_call(last_status, _From, State) ->
    {reply, {error, not_checked}, State};
handle_call({set_assert, Fun}, _From, nil) ->
    {reply, ok, Fun};
handle_call({set_assert, _}, _From, State) ->
    {reply, {error, assert_function_set}, State};
handle_call(stop, _From, State) ->
    {stop, normal, State};
handle_call(Msg, _From, State) ->
    {reply, {ignored, Msg}, State}.

handle_cast(Msg, State) ->
    ?debugFmt("Ignoring cast message: ~p", [Msg]),
    {noreply, State}.

handle_info(Msg, State) ->
    ?debugFmt("Ignoring info message: ~p", [Msg]),
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
