%%%-------------------------------------------------------------------
%% @doc stepflow public API
%% @end
%%%-------------------------------------------------------------------

-module(stepflow_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    stepflow_sup:start_link().

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================