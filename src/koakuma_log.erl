-module(koakuma_log).

-export([init/0]).
-export([raw/1, xdcc/1]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

init() ->
    catch file:make_dir("log"),
    ok.

raw(Data) ->
    write("raw", Data).

xdcc(Data) ->
    write("xdcc", Data).

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%% write required data to required file
write(Group, Data) ->
    File = "log/" ++ Group ++ ".log",
    Time = iso_8601_time(),
    Trimmed = trim(Data),
    OutData = <<"[", Time/binary, "] ", Trimmed/binary, "\n">>,
    file:write_file(File, OutData, [append]).

%% formatted current time
iso_8601_time() ->
    {{Year,Month,Day},{Hour,Min,Sec}} = erlang:localtime(),
    iolist_to_binary(io_lib:format("~4.10.0B-~2.10.0B-~2.10.0B ~2.10.0B:~2.10.0B:~2.10.0B",
        [Year, Month, Day, Hour, Min, Sec])).

%% trim string
trim(BinString) ->
    re:replace(BinString, "^\\s+|\\s+$", "", [{return, binary}, global]).
