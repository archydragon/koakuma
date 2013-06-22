-module (koakuma_queue).
-behaviour (gen_server).
-define (SERVER, ?MODULE).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export ([start_link/0, push/1, done/1, state/0, set_limit/1]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% Push new process to the queue
push(Process) ->
    gen_server:call(?MODULE, {push, Process}).

%% Process exited
done(Process) ->
    gen_server:call(?MODULE, {done, Process}).

%% Get current queue state
state() ->
    gen_server:call(?MODULE, state).

%% Set concurrent processes limit
set_limit(Limit) ->
    gen_server:cast(?MODULE, {limit, Limit}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) ->
    {ok, {5, []}}.

handle_call({push, Process}, _From, {L, Queue}) ->
    Reply = case L =< length(Queue)  of
        true  -> queued;
        false -> start
    end,
    {reply, Reply, {L, Queue ++ [Process]}};
handle_call({done, Process}, _From, {L, Queue}) ->
    NewQueue = lists:delete(Process, Queue),
    case length(NewQueue) >= L of
        true  -> lists:nth(L, NewQueue) ! start;
        false -> ok
    end,
    {reply, ok, {L, NewQueue}};
handle_call(state, _From, State) ->
    {reply, {state, State}, State};
handle_call(stop, _From, State) ->
    {stop, normal, shutdown_ok, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({limit, Limit}, {_OldLimit, Queue}) ->
    {noreply, {Limit, Queue}};
handle_cast({watched, NewState}, _OldState) ->
    {noreply, NewState};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
