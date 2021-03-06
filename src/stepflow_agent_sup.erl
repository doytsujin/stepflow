%%%-------------------------------------------------------------------
%% @doc steflow top level agent supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(stepflow_agent_sup).

-author('Leonardo Rossi <leonardo.rossi@studenti.unipr.it>').

-behaviour(supervisor).

%% API
-export([new/2]).

%% Supervisor callbacks
-export([init/1, start_link/0]).

-define(SERVER, ?MODULE).

-type skctx()   :: stepflow_sink:ctx().
-type srctx()   :: stepflow_source:ctx().
-type chctx()   :: stepflow_channel:ctx().
-type input()   :: {atom(), srctx()}.
-type output()  :: {atom(), chctx(), skctx()}.
-type outputs() :: list(output()).
-type ctx()     :: {pid(), pid(), list(pid())}.

%%====================================================================
%% API functions
%%====================================================================

-spec new(input(), outputs()) -> ctx().
new(Input, Outputs) ->
  {ok, PidAgentSup} = supervisor:start_child(whereis(stepflow_sup), []),
  PidCs = init_outputs(PidAgentSup, Outputs),
  PidS = init_source(PidAgentSup, Input, PidCs),
  {PidAgentSup, PidS, PidCs}.

%%====================================================================
%% Supervisor callbacks
%%====================================================================

-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
  supervisor:start_link(?MODULE, []).

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
-spec init([]) -> {ok, {supervisor:sup_flags(), []}}.
init([]) ->
    {ok, { {one_for_one, 10, 10}, []} }.

%%====================================================================
%% Internal functions
%%====================================================================

-spec init_source(pid(), input(), list(pid())) -> pid().
init_source(_PidAgentSup, none, _PidCs) -> none;
init_source(PidAgentSup, {Source, {InCtxs, Ctx}}, PidCs) ->
  {ok, PidS} = supervisor:start_child(
          PidAgentSup, child("source",
                             stepflow_source, {{Source, Ctx}, InCtxs, PidCs})),
  PidS.

-spec init_outputs(pid(), outputs()) -> list(pid()).
init_outputs(PidAgentSup, Outputs) ->
  Indices = lists:seq(1, length(Outputs)),
  lists:map(fun({Index, {ChConfig, SkConfig}}) ->
      PidC = init_channel(PidAgentSup, Index, ChConfig, SkConfig),
      PidC
    end, lists:zip(Indices, Outputs)).

% -spec init_channel(pid(), integer(), output()) -> pid().
init_channel(PidAgentSup, Index, ChannelCtx, SkCtx) ->
  {ok, PidC} = supervisor:start_child(
          PidAgentSup, child(name(channel, Index),
                             stepflow_channel, {SkCtx, ChannelCtx})),
  PidC.

-spec child(string(), atom(), skctx() | srctx() | chctx()) ->
    {string(),
     {atom(), atom(), list(skctx() | srctx() | chctx())},
     atom(), integer(), atom(), list(atom())}.
child(Type, Module, Ctx) ->
  {Type,
   {Module, start_link, [Ctx]},
   transient, 1000, worker, [Module]
  }.

-spec name(atom(), integer()) -> string().
name(Type, Index) ->
  Stype = atom_to_list(Type),
  SIndex = integer_to_list(Index),
  Stype ++ "_" ++ SIndex.
