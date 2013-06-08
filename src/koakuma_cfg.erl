-module (koakuma_cfg).
-behaviour (gen_server).
-define(SERVER, ?MODULE).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export ([start_link/0]).
-export ([read/1]).
-export ([set/2]).
-export ([get/1]).

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

read(FileName) ->
    gen_server:call(?MODULE, {cfg_read, FileName}).

set(Key, Value) ->
    gen_server:call(?MODULE, {cfg_set, Key, Value}).

get(Key) ->
    gen_server:call(?MODULE, {cfg_key, Key}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Args) ->
    {ok, Args}.

handle_call({cfg_read, FileName}, _From, State) ->
    {ok, ConfigData} = file:consult(FileName),
    ets:new(config, [set, named_table]),
    ets:insert(config, ConfigData),
    {reply, ok, State};
handle_call({cfg_set, Key, Value}, _From, State) ->
    ets:insert(config, {Key, Value}),
    {reply, ok, State};
handle_call({cfg_key, Key}, _From, State) ->
    {Key, Value} = try_get(Key, ets:lookup(config, Key)),
    {reply, Value, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal function Definitions
%% ------------------------------------------------------------------

try_get(Key, []) -> {Key, cfg_default(Key)};
try_get(Key, [{Key, Value}]) -> {Key, Value}.

%% Default values for some parameters
%% Details about them can be found in README and configuration file
cfg_default(port)               -> 6667;
cfg_default(user)               -> "ekoakuma";
cfg_default(real_name)          -> "Koakuma XDCC";
cfg_default(data_db)            -> "koakuma.db";
cfg_default(db_update_interval) -> 300;
cfg_default(dcc_port_range)     -> {50000, 51000};
cfg_default(allow_find)         -> false;
cfg_default(reconnect_interval) -> 120;
cfg_default(_Key)               -> [].
