%%%-------------------------------------------------------------------
%% @doc stepflow channel mnesia
%% @end
%%%-------------------------------------------------------------------

-module(stepflow_channel_mnesia).

-author('Leonardo Rossi <leonardo.rossi@studenti.unipr.it>').

-behaviour(stepflow_channel).
-behaviour(gen_server).

-include_lib("stdlib/include/qlc.hrl").

-export([
  start_link/1,
  init/1,
  code_change/3,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2
]).

-export([
  ack/1,
  config/1,
  nack/1
]).

-type ctx()   :: map().
-type event() :: stepflow_event:event().
-type skctx() :: stepflow_channel:skctx().

-record(stepflow_channel_mnesia_events, {timestamp, event}).

%% Callbacks channel

-spec config(ctx()) -> {ok, ctx()}  | {error, term()}.
config(#{}=Config) ->
  FlushPeriod = maps:get(flush_period, Config, 3000),
  Capacity = maps:get(capacity, Config, 5),
  Table = maps:get(table, Config, stepflow_channel_mnesia_events),
  {ok, Config#{flush_period => FlushPeriod, capacity => Capacity,
               table => Table}}.

-spec ack(ctx()) -> {ok, ctx()}.
ack(#{records := Bulk, table := Table}=Ctx) ->
  [mnesia:delete({Table, R#stepflow_channel_mnesia_events.timestamp}) || R <- Bulk],
  {ok, maps:remove(records, Ctx)}.

-spec nack(ctx()) -> {ok, ctx()}.
nack(Ctx)-> {ok, maps:remove(records, Ctx)}.

%% Callbacks gen_server

-spec start_link(ctx()) -> {ok, pid()} | ignore | {error, term()}.
start_link(Config) ->
  gen_server:start_link(?MODULE, [Config], []).

-spec init(list(ctx())) -> {ok, ctx()}.
init([#{flush_period := FlushPeriod, table := Table}=Config]) ->
  create_schema(),
  create_table(Table),
  erlang:start_timer(FlushPeriod, self(), flush),
  {ok, Config}.

-spec handle_call(setup | {connect_sink, skctx()}, {pid(), term()}, ctx()) ->
    {reply, ok, ctx()}.
handle_call(setup, _From, Ctx) ->
  {reply, ok, Ctx};
handle_call({connect_sink, SinkCtx}, _From, Ctx) ->
  Ctx2 = Ctx#{skctx => SinkCtx},
  {reply, ok, Ctx2};
handle_call(Input, _From, Ctx) ->
  {reply, Input, Ctx}.

-spec handle_cast({append, event()} | pop, ctx()) -> {noreply, ctx()}.
handle_cast({append, Event}, #{table := Table}=Ctx) ->
  write(Table, Event),
  maybe_pop(Ctx),
  % stepflow_channel:pop(self()),
  {noreply, Ctx};
handle_cast(pop, Ctx) ->
  {ok, Ctx2} = flush(Ctx),
  {noreply, Ctx2};
handle_cast(_, Ctx) ->
  {noreply, Ctx}.

handle_info({timeout, _, flush}, Ctx) ->
  io:format("Flush mnesia memory.. ~n"),
  {ok, Ctx2} = flush(Ctx),
  erlang:start_timer(5000, self(), flush),
  {noreply, Ctx2};
handle_info(_Info, Ctx) ->
  {noreply, Ctx}.

terminate(_Reason, _Ctx) ->
  io:format("Terminate!!~n"),
  ok.

code_change(_OldVsn, Ctx, _Extra) ->
  io:format("code changed !"),
  {ok, Ctx}.

%% Private functions

create_schema() ->
  mnesia:create_schema([node()]),
  application:start(mnesia).

create_table(Table) ->
  ok = case mnesia:create_table(Table, [
        {type, ordered_set},
        {attributes, record_info(fields, stepflow_channel_mnesia_events)},
        {record_name, stepflow_channel_mnesia_events},
        {disc_copies, [node()]}
      ]) of
    {atomic, ok} -> ok;
    {aborted,{already_exists, _}} -> ok;
    Error -> Error
  end,
  % ok = mnesia:add_table_copy(
  %        stepflow_channel_mnesia_events, node(), disc_copy),
  ok = mnesia:wait_for_tables([Table], 5000).

write(Table, Event) ->
  mnesia:activity(transaction, fun() ->
      mnesia:write(Table, #stepflow_channel_mnesia_events{
                      timestamp=os:timestamp(), event=Event
        }, write)
    end).

-spec flush(ctx()) -> {ok, ctx()} | {error, term()}.
flush(#{capacity := Capacity, table := Table}=Ctx) ->
  % CatchAll = [{'_',[],['$_']}],
  {ok, _} = mnesia:activity(transaction, fun() ->
      Bulk = qlc:eval(catch_all(Table), [{max_list_size, Capacity}]),
      % TODO check if bulk is empty!
      % process a bulk of events
      {ok, _} = stepflow_channel:route(
            ?MODULE, [R#stepflow_channel_mnesia_events.event || R <- Bulk],
            Ctx#{records => Bulk})
    end).

maybe_pop(#{capacity := Capacity, table := Table}=Ctx) ->
  case mnesia:table_info(Table, size) > Capacity of
    true -> flush(Ctx);
    false -> ok
  end.

% TODO limit max size of events
catch_all(Table) ->
  qlc:q([R || R <- mnesia:table(Table)]).