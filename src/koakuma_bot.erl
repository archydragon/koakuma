%%% HERE BE DRAGONS

-module(koakuma_bot).
-behaviour(gen_server).
-define(SERVER, ?MODULE).

-define(VERSION, "0.4a").
-define(CHUNKSIZE, 16384).

-include_lib("kernel/include/file.hrl").

-record(file, {pack, name, size, size_h, modified, gets, md5, crc32}).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0, transfer_init/2, files_update/1]).

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

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Args) ->
    spawn_link(fun() -> connect() end),
    {ok, Args}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({send_raw, Message}, State) ->
    send_raw(Message),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    quit(),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%% Entry point of IRC connection
connect() ->
    cfg_read("koakuma.cfg"),
    spawn_link(?MODULE, files_update, [cfg(data_dir)]),
    {ok, S} = gen_tcp:connect(cfg(server), cfg(port), [{packet, line}]),
    cfg_set(sock, S),
    ok = reply(["NICK ", cfg(nick)]),
    cfg_set(nick_now, cfg(nick)),
    ok = reply(["USER ", cfg(user), " 0 * :", cfg(real_name)]),
    listen(S),
    timer:sleep(cfg(reconnect_interval) * 1000),
    connect(),
    ok.

%% Listener for IRC server replies
listen(Socket) ->
    receive
        {tcp, Socket, Data} ->
            io:format("> [~w] ~s", [Socket, Data]),
            parse(Data),
            listen(Socket);
        quit ->
            quit(),
            gen_tcp:close(Socket)
        end.

%% Parser of IRC server replies
parse(Message) ->
    Actions = [
        ping,
        autojoin,
        nickserv,
        altnick,
        version,
        rejoin,
        xdcc_find,
        xdcc_list,
        xdcc_send,
        xdcc_info
    ],
    [run(A, Message, check(A, Message)) || A <- Actions].

%% Action "controllers"
% Reply to PING from server
run(ping, "PING " ++ From, match) ->
    reply(["PONG ", trim(From)]);
% Auto join required channels after MOTD end
run(autojoin, _Message, match) ->
    [reply(["JOIN ", C]) || C <- cfg(channels)];
% Identify at NickServ on connect
run(nickserv, _Message, match) ->
    identify(cfg(nickserv_password)),
    ok;
% Change nick to alternative when main nick is already taken
run(altnick, _Message, match) ->
    reply(["NICK ", cfg(altnick)]),
    cfg_set(nick_now, cfg(altnick));
% Automatically rejoin after being kicked :)
run(rejoin, Message, match) ->
    {match, [{B, L}]} = re:run(Message, "#.+\s"),
    Chan = [" ", string:substr(Message, B, L), " ", cfg(nick_now)],
    reply(["JOIN", Chan]);
% Reply to CTCP VERSION request
run(version, Message, match) ->
    From = from(Message),
    {_Family, OSName} = os:type(),
    OSVer = string:join(lists:map(fun(X) -> integer_to_list(X) end, tuple_to_list(os:version())), "."),
    OS = [atom_to_list(OSName), " ", OSVer],
    Reply = io_lib:format("PRIVMSG ~s :\001VERSION Koakuma XDCC ~s (~s)\001", [From, ?VERSION, OS]),
    reply(Reply);
% XDCC pack findinf mechanism (not implemented yet)
run(xdcc_find, Message, match) ->
    From = from(Message),
    Query = trim(lists:last(string:tokens(Message, " "))),
    Reply = find_file(Query, cfg(allow_find)),
    notice(From, [Reply]);
% XDCC pack listing to user
run(xdcc_list, Message, match) ->
    From = from(Message),
    Files = sort(pack, db_all()),
    List = reply_list(Files),
    notice(From, List);
% XDCC pack sending to user
run(xdcc_send, Message, match) ->
    From = from(Message),
    Int = re:replace(lists:last(string:tokens(Message, " ")), "[^0-9]", "", [global]),
    [Pack] = [X || X <- Int, is_binary(X)],
    Reply = io_lib:format("I bring you pack \002#~s\002, use it for great good!", [binary_to_list(Pack)]),
    notice(From, [Reply]),
    send_file(From, cfg(data_dir), db_pack(list_to_integer(binary_to_list(Pack))));
% XDCC pack information
run(xdcc_info, Message, match) ->
    From = from(Message),
    Int = re:replace(lists:last(string:tokens(Message, " ")), "[^0-9]", "", [global]),
    [Pack] = [X || X <- Int, is_binary(X)],
    send_info(From, db_pack(list_to_integer(binary_to_list(Pack))));
% Catch-all
run(_Action, _Message, _Nomatch) ->
    ok.

%% Action parsers
check(ping, Message) ->
    seek(Message, "^PING\s");
check(autojoin, Message) ->
    seek(Message, "\s376\s");
check(nickserv, Message) ->
    seek(Message, "\s375\s");
check(altnick, Message) ->
    seek(Message, ":Nickname is already in use");
check(rejoin, Message) ->
    seek(Message, ["KICK\s#.*\s", cfg(nick_now)]);
check(version, Message) ->
    seek(Message, ":\001VERSION\001");
check(xdcc_find, Message) ->
    seek(Message, "\s:[@!]find\s");
check(xdcc_list, Message) ->
    seek(Message, "\sPRIVMSG\s[^#].*:[Xx][Dd][Cc][Cc]\s[Ll][Ii][Ss][Tt]");
check(xdcc_send, Message) ->
    seek(Message, "\sPRIVMSG\s[^#].*:[Xx][Dd][Cc][Cc]\s([Ss][Ee][Nn][Dd])|([Gg][Ee][Tt])\s");
check(xdcc_info, Message) ->
    seek(Message, "\sPRIVMSG\s[^#].*:[Xx][Dd][Cc][Cc]\s[Ii][Nn][Ff][Oo]\s").

seek(Text, Pattern) ->
    case re:run(Text, Pattern) of
        nomatch -> nomatch;
        _       -> match
    end.

reply(Data) ->
    Send = [Data, "\r\n"],
    io:format("< [~w] ~s~n", [cfg(sock), Data]),
    gen_tcp:send(cfg(sock), Send).

notice(Target, [M | Left]) ->
    reply(io_lib:format("NOTICE ~s :~s", [Target, M])),
    timer:sleep(1000),
    notice(Target, Left);
notice(_Target, []) ->
    ok.

quit() ->
    reply("QUIT :Gone.").

%% Identify at NickServ
identify([]) ->
    ok;
identify(Password) ->
    reply(["PRIVMSG NickServ :GHOST ", cfg(nick), " ", Password]),
    reply(["NICK ", cfg(nick)]),
    reply(["PRIVMSG NickServ :IDENTIFY ", Password]).

%% Update XDCC pack list
files_update(Directory) ->
    Files = db_all(),
    files_remove_old(Directory, Files),
    db_insert(files_add_new(Directory, Files)),
    timer:sleep(cfg(db_update_interval) * 1000),
    files_update(Directory).

files_remove_old(_Directory, []) ->
    ok;
files_remove_old(Directory, [[F] | Other]) ->
    Name = F#file.name,
    Mtime = F#file.modified,
    case files_check(file:read_file_info([Directory, $/, Name]), Mtime) of
        ok -> ok;
        _  -> db_delete(F)
    end,
    files_remove_old(Directory, Other).

files_check({error, _}, _Mtime) ->
    lost;
files_check({ok, Info}, Mtime) when Info#file_info.mtime /= Mtime ->
    changed;
files_check({ok, _Info}, _Mtime) ->
    ok.

files_add_new(Directory, []) ->
    {ok, Files} = file:list_dir(Directory),
    fileinfo(Files, 1, [], Directory);
files_add_new(Directory, _Files) ->
    FilesOld = db_all_files(),
    {ok, FilesAll} = file:list_dir(Directory),
    LastPack = list_max(db_all_packs()),
    fileinfo(FilesAll -- FilesOld, LastPack + 1, [], Directory).

%% Generate packs list for reply
reply_list([])    -> ["I have nothing to share with you, sorry."];
reply_list(Files) -> reply_list(lists:reverse(Files), []).

reply_list([], Acc)->
    Acc;
reply_list([[Item] | Left], Acc) ->
    Formatted = io_lib:format("\002~5s\002 ~4s  ~9s  ~s",
        [
            [$#, integer_to_list(Item#file.pack)],
            [$x, integer_to_list(Item#file.gets)],
            [$[, Item#file.size_h, $]],
            Item#file.name
        ]),
    reply_list(Left, [Formatted | Acc]).

%% Get detailed information about files in list
fileinfo([CurrentFile | Others], I, Acc, Dir) ->
    File = [Dir, $/, CurrentFile],
    {ok, Info} = file:read_file_info(File),
    Item = #file{
        pack = I,
        name = CurrentFile,
        size = Info#file_info.size,
        size_h = size_h(Info#file_info.size),
        modified = Info#file_info.mtime,
        gets = 0,
        md5 = checksum:md5(File),
        crc32 = checksum:crc32(File)
    },
    fileinfo(Others, I+1, [Item | Acc], Dir);
fileinfo([], _I, Acc, _Dir) ->
    Acc.

%% Send chosen pack to user
send_file(Target, Dir, [File]) ->
    Ip = int_ip(inet_parse:address(cfg(dcc_ip))),
    {PortMin, PortMax} = cfg(dcc_port_range),
    SendSocket = port(PortMin, PortMax, [{active, false}, {packet, 4}, {reuseaddr, true}]),
    {ok, Port} = inet:port(SendSocket),
    Reply = io_lib:format("PRIVMSG ~s :\001DCC SEND \"~s\" ~B ~B ~B\001",
        [Target, File#file.name, Ip, Port, File#file.size]),
    reply(Reply),
    spawn_link(?MODULE, transfer_init, [SendSocket, [Dir, $/, File#file.name]]),
    GetUp = File#file{gets=File#file.gets + 1},
    db_replace(File, GetUp);
send_file(Target, _Dir, []) ->
    % If user requested wrong pack
    notice(Target, ["Pack not found, sorry."]).

%% Init DCC data transfer
transfer_init(SS, File) ->
    case gen_tcp:accept(SS) of
        {ok, S} ->
            ok = gen_tcp:close(SS),
            inet:setopts(S,[{active, once}, {packet, raw}, binary]),
            {ok, Fd} = file:open(File, [read, raw, binary]),
            {ok, Init} = file:read(Fd, ?CHUNKSIZE),
            ok = gen_tcp:send(S, Init),
            receive
                {tcp, S, Got} ->
                    io:format("~p~n", [Got]),
                    transfer(S, Fd, ?CHUNKSIZE, file:read(Fd, ?CHUNKSIZE));
                _ ->
                    ok
            end;
        _Other ->
            io:format("Socket closed.~n"),
            ok
    end.

%% Continue transfer file chunk-by-chunk
transfer(S, Fd, Offset, {ok, BinData}) ->
    ok = gen_tcp:send(S, BinData),
    transfer(S, Fd, Offset+?CHUNKSIZE, file:read(Fd, ?CHUNKSIZE));
transfer(S, Fd, _Offset, eof) ->
    timer:sleep(5000),
    io:format("~p", [inet:getstat(S)]),
    file:close(Fd),
    gen_tcp:close(S).

%% Send XDCC pack information
send_info(Target, [File]) ->
    {{Y, M, D}, {Hh, Mm, Ss}} = File#file.modified,
    Mtime = io_lib:format("~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B", [Y, M, D, Hh, Mm, Ss]),
    Reply = [
        io_lib:format("Pack info for item \002#~B\002", [File#file.pack]),
        io_lib:format(" File name:      ~s", [File#file.name]),
        io_lib:format(" File size:      ~s", [File#file.size_h]),
        io_lib:format(" Last modified:  ~s", [Mtime]),
        io_lib:format(" Gets:           ~B", [File#file.gets]),
        io_lib:format(" MD5:            ~s", [File#file.md5]),
        io_lib:format(" CRC32:          ~s", [File#file.crc32])
    ],
    notice(Target, Reply);
send_info(Target, []) ->
    % If user requested wrong pack
    notice(Target, ["Pack not found, sorry."]).

%% Find file among the ones we have
find_file(Query, true) ->
    io:format("~p~n", [Query]),
    Names = db_all_files(),
    find_substr(Query, Names);
find_file(_Q, false) ->
    "".

find_substr(_S, []) ->
    "";
find_substr(S, [Current | Tail]) ->
    io:format("~p~n", [Current]),
    case string:str(Current, S) of
        0 -> find_substr(S, Tail);
        _ ->
            [Found] = db_file(Current),
            Pack = Found#file.pack,
            io_lib:format(" :Do you look for \002~s\002? I have it for you. Type \002/msg ~s xdcc send #~B\002 to obtain it",
                [Current, cfg(nick_now), Pack])
    end.

%% -----------------------------------------
%% DETS manipulation functions
%% -----------------------------------------
db_all() ->
    %db_query(dets:match(db, '$1')).
    db_query(match, '$1').

db_all_packs() ->
    db_query(select, [{ #file {pack='$1', _='_'}, [], ['$1']}]).

db_all_files() ->
    db_query(select, [{ #file {name='$1', _='_'}, [], ['$1']}]).

db_pack(Pack) ->
    db_query(select, [{ #file {pack=Pack, _='_'}, [], ['$_']}]).

db_file(Name) ->
    db_query(select, [{ #file {name=Name, _='_'}, [], ['$_']}]).

db_insert(Object) ->
    db_query(insert, Object).

db_delete(Object) ->
    db_query(delete_object, Object).

db_replace(OldObj, NewObj) ->
    db_delete(OldObj),
    db_insert(NewObj).

db_open() ->
    {ok, db} = dets:open_file(db, [{file, cfg(data_db)}, {type, bag}]),
    db.

db_close() ->
    dets:close(db).

db_query(F, Param) ->
    db_open(),
    Result = erlang:apply(dets, F, [db, Param]),
    db_close(),
    Result.

%% -------------------------------
%% "Helper" functions
%% -------------------------------

%% FROM split
from([$: | Text]) ->
    [From | _Tail] = string:tokens(Text, "!"),
    From.

%% Human readable sizes
size_h(Size) when Size < 1024 -> integer_to_list(Size);
size_h(Size)                  -> size_h(Size, ["", "K", "M", "G", "T", "P"]).

size_h(S, [_|[_|_] = L]) when S >= 1024 -> size_h(S/1024, L);
size_h(S, [M|_])                        -> lists:merge(io_lib:format("~.2f~s", [float(S), M])).

%% Convert IP tuple to integer value
int_ip(Ip) when is_tuple(Ip) ->
    {ok, {O1, O2, O3, O4}} = Ip,
    (O1*16777216)+(O2*65536)+(O3*256)+(O4).

%% Bind random free port from configured range
port(Min, Max, TcpOpts) -> port(Min, Max, TcpOpts, {error, fake}).

port(Min, Max, TcpOpts, {error, _}) ->
    TryPort = random:uniform(Max-Min) + Min,
    port(Min, Max, TcpOpts, gen_tcp:listen(TryPort, TcpOpts));
port(_Min, _Max, _TcpOpts, {ok, Socket}) ->
    Socket.

%% Remove line feed characters from message
trim(Message) ->
    re:replace(Message, "(^\\s+)|(\\s+$)", "", [global,{return,list}]).

%% Sort list of recors
sort(pack, Lor) ->
    SF = fun([I1], [I2]) -> I1#file.pack < I2#file.pack end,
    lists:sort(SF, Lor);
sort(name, Lor) ->
    SF = fun([I1], [I2]) -> I1#file.name < I2#file.name end,
    lists:sort(SF, Lor).

%% Get max value in list
list_max([])            -> 0;
list_max([Head | Tail]) -> list_max(Head, Tail).

list_max(X, [])                          -> X;
list_max(X, [Head | Tail]) when X < Head -> list_max(Head, Tail);
list_max(X, [_ | Tail])                  -> list_max(X, Tail).

%% -------------------------------------
%% API implementations
%% -------------------------------------

send_raw(Msg) when is_binary(Msg) ->
    reply(binary_to_list(Msg));
send_raw(Msg) when is_list(Msg) ->
    reply(Msg).

%% -----------------------------------
%% Working with configuration files
%% -----------------------------------

cfg_read(FileName) ->
    {ok, ConfigData} = file:consult(FileName),
    ets:new(config, [set, named_table]),
    ets:insert(config, ConfigData),
    ok.

cfg_set(Key, Value) ->
    ets:insert(config, {Key, Value}),
    ok.

cfg(Key) ->
    {Key, Value} = cfg_try(Key, ets:lookup(config, Key)),
    Value.

cfg_try(Key, []) -> {Key, cfg_default(Key)};
cfg_try(Key, [{Key, Value}]) -> {Key, Value}.

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
