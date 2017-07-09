%%%-------------------------------------------------------------------
%% @doc stepflow source
%% @end
%%%-------------------------------------------------------------------

-module(stepflow_source).

-author('Leonardo Rossi <leonardo.rossi@studenti.unipr.it>').

-export([
  append/3,
  config/1,
  setup_channel/2
]).

-type ctx()   :: map().
-type event() :: stepflow_agent:event().
-type inctx() :: stepflow_interceptor:ctx().

%% API

-spec config({list({atom(), inctx()}), ctx()}) ->
    {ok, ctx()}  | {error, term()}.
config({InterceptorsConfig, Ctx}) ->
  InCtxs = stepflow_interceptor:init_all(InterceptorsConfig),
  Ctx#{inctxs => InCtxs}.

-spec setup_channel(pid(), pid()) -> ok | {error, term()}.
setup_channel(Pid, ChPid) -> gen_server:call(Pid, {setup_channel, ChPid}).

-spec append(list(pid()), event(), list(inctx())) -> list(inctx()).
append(PidChs, Event, InCtxs) ->
  {Event2, InCtxs2} = stepflow_interceptor:transform(Event, InCtxs),
  lists:foreach(fun(PidCh) ->
      stepflow_channel:append(PidCh, Event2)
    end, PidChs),
  InCtxs2.
