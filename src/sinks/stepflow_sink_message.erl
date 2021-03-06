%%%-------------------------------------------------------------------
%% @doc stepflow sink message: send the event as a message to another agent.
%% @end
%%%-------------------------------------------------------------------

-module(stepflow_sink_message).

-author('Leonardo Rossi <leonardo.rossi@studenti.unipr.it>').

-behaviour(stepflow_sink).

-export([
  handle_init/1,
  handle_process/2
]).

-type event() :: stepflow_event:event().
-type ctx()   :: stepflow_sink:ctx().

-spec handle_init(ctx()) -> {ok, ctx()} | {error, term()}.
handle_init(#{source := _Pid}=Ctx) -> {ok, Ctx}.

-spec handle_process(list(event()), ctx()) -> {ok, ctx()}.
handle_process(Events, #{source := Pid}=Ctx) ->
  case stepflow_source_message:sync_append(Pid, Events) of
    ok ->
      io:format("Events send to ~p: ~p~n", [Pid, Events]),
      {ok, Ctx};
    _ -> {error, source_unreachable}
  end.
