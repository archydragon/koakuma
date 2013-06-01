-module (checksum).

-export ([md5/1, crc32/1]).

-define (BLOCKSIZE, 32768).

md5(File)   -> init(md5, File).
crc32(File) -> init(crc, File).

init(Type, File) ->
    case file:open(File, [binary,raw,read]) of
        {ok, P} -> loop(Type, P);
        Error -> Error
    end.

loop(md5, P) -> loop(md5, P, erlang:md5_init());
loop(crc, P) -> loop(crc, P, erlang:crc32("")).

loop(Type, P, C) ->
    case file:read(P, ?BLOCKSIZE) of
        {ok, Bin} ->
            loop(Type, P, update(Type, C, Bin));
        eof ->
            file:close(P),
            final(Type, C)
    end.

update(md5, C, Bin) -> erlang:md5_update(C, Bin);
update(crc, C, Bin) -> erlang:crc32(C, Bin).

final(md5, C) -> hex(erlang:md5_final(C));
final(crc, C) -> binary_to_list(integer_to_binary(C, 16)).

hex(<<X:128/big-unsigned-integer>>) ->
    lists:flatten(io_lib:format("~32.16.0b", [X])).
