%%% HERE BE DRAGONS

-module(koakuma_bot).
-behaviour(gen_server).
-define(SERVER, ?MODULE).

-define(VERSION, "0.5a").
-define(CHUNKSIZE, 16384).

-include_lib("kernel/include/file.hrl").
-include_lib("koakuma.hrl").

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
    koakuma_cfg:read("koakuma.cfg"),
    spawn_link(?MODULE, files_update, [koakuma_cfg:get(data_dir)]),
    {ok, S} = gen_tcp:connect(koakuma_cfg:get(server), koakuma_cfg:get(port), [{packet, line}]),
    koakuma_cfg:set(sock, S),
    koakuma_cfg:set(traffic, 0),
    ok = reply(["NICK ", koakuma_cfg:get(nick)]),
    koakuma_cfg:set(nick_now, koakuma_cfg:get(nick)),
    ok = reply(["USER ", koakuma_cfg:get(user), " 0 * :", koakuma_cfg:get(real_name)]),
    listen(S),
    timer:sleep(koakuma_cfg:get(reconnect_interval) * 1000),
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
    [reply(["JOIN ", C]) || C <- koakuma_cfg:get(channels)];
% Identify at NickServ on connect
run(nickserv, _Message, match) ->
    identify(koakuma_cfg:get(nickserv_password)),
    ok;
% Change nick to alternative when main nick is already taken
run(altnick, _Message, match) ->
    reply(["NICK ", koakuma_cfg:get(altnick)]),
    koakuma_cfg:set(nick_now, koakuma_cfg:get(altnick));
% Automatically rejoin after being kicked :)
run(rejoin, Message, match) ->
    {match, [{B, L}]} = re:run(Message, "#.+\s"),
    Chan = [" ", string:substr(Message, B, L), " ", koakuma_cfg:get(nick_now)],
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
    Reply = find_file(Query, koakuma_cfg:get(allow_find)),
    notice(From, [Reply]);
% XDCC pack listing to user
run(xdcc_list, Message, match) ->
    From = from(Message),
    Files = sort(pack, koakuma_dets:all()),
    List = reply_list(Files),
    notice(From, List);
% XDCC pack sending to user
run(xdcc_send, Message, match) ->
    From = from(Message),
    Int = re:replace(lists:last(string:tokens(Message, " ")), "[^0-9]", "", [global]),
    [Pack] = [X || X <- Int, is_binary(X)],
    Reply = io_lib:format("I bring you pack \002#~s\002, use it for great good!", [binary_to_list(Pack)]),
    notice(From, [Reply]),
    send_file(From, koakuma_cfg:get(data_dir), koakuma_dets:pack(list_to_integer(binary_to_list(Pack))));
% XDCC pack information
run(xdcc_info, Message, match) ->
    From = from(Message),
    Int = re:replace(lists:last(string:tokens(Message, " ")), "[^0-9]", "", [global]),
    [Pack] = [X || X <- Int, is_binary(X)],
    send_info(From, koakuma_dets:pack(list_to_integer(binary_to_list(Pack))));
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
    seek(Message, ["KICK\s#.*\s", koakuma_cfg:get(nick_now)]);
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
    io:format("< [~w] ~s~n", [koakuma_cfg:get(sock), Data]),
    gen_tcp:send(koakuma_cfg:get(sock), Send).

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
    reply(["PRIVMSG NickServ :GHOST ", koakuma_cfg:get(nick), " ", Password]),
    reply(["NICK ", koakuma_cfg:get(nick)]),
    reply(["PRIVMSG NickServ :IDENTIFY ", Password]).

%% Update XDCC pack list
files_update(Directory) ->
    Files = koakuma_dets:all(),
    files_remove_old(Directory, Files),
    koakuma_dets:insert(files_add_new(Directory, Files)),
    timer:sleep(koakuma_cfg:get(db_update_interval) * 1000),
    files_update(Directory).

files_remove_old(_Directory, []) ->
    ok;
files_remove_old(Directory, [[F] | Other]) ->
    Name = F#file.name,
    Mtime = F#file.modified,
    case files_check(file:read_file_info([Directory, $/, Name]), Mtime) of
        ok -> ok;
        _  -> koakuma_dets:delete(F)
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
    FilesOld = koakuma_dets:files(),
    {ok, FilesAll} = file:list_dir(Directory),
    LastPack = list_max(koakuma_dets:packs()),
    fileinfo(FilesAll -- FilesOld, LastPack + 1, [], Directory).

%% Generate packs list for reply
reply_list([])    -> ["I have nothing to share with you, sorry."];
reply_list(Files) -> reply_list(lists:reverse(Files), []).

reply_list([], Acc)->
    % Acc;
    TotalSize = size_h(lists:foldl(fun(X, Sum) -> X + Sum end, 0, koakuma_dets:sizes())),
    Transferred = size_h(koakuma_cfg:get(traffic)),
    Acc ++ [io_lib:format("Total offered: ~s  Total transferred: ~s", [TotalSize, Transferred])];
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
    Ip = int_ip(inet_parse:address(koakuma_cfg:get(dcc_ip))),
    {PortMin, PortMax} = koakuma_cfg:get(dcc_port_range),
    SendSocket = port(PortMin, PortMax, [{active, false}, {packet, 4}, {reuseaddr, true}]),
    {ok, Port} = inet:port(SendSocket),
    Reply = io_lib:format("PRIVMSG ~s :\001DCC SEND \"~s\" ~B ~B ~B\001",
        [Target, File#file.name, Ip, Port, File#file.size]),
    reply(Reply),
    spawn_link(?MODULE, transfer_init, [SendSocket, [Dir, $/, File#file.name]]),
    GetUp = File#file{gets=File#file.gets + 1},
    koakuma_dets:replace(File, GetUp);
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
                {tcp, S, _Got} ->
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
    {ok, [{send_oct, Bytes}]} = inet:getstat(S, [send_oct]),
    koakuma_cfg:set(traffic, koakuma_cfg:get(traffic) + Bytes),
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
    Names = koakuma_dets:files(),
    find_substr(Query, Names);
find_file(_Q, false) ->
    "".

find_substr(_S, []) ->
    "";
find_substr(S, [Current | Tail]) ->
    case string:str(Current, S) of
        0 -> find_substr(S, Tail);
        _ ->
            [Found] = koakuma_dets:file(Current),
            Pack = Found#file.pack,
            io_lib:format("Do you look for \002~s\002? I have it for you. Type \002/msg ~s xdcc send #~B\002 to obtain it",
                [Current, koakuma_cfg:get(nick_now), Pack])
    end.

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
