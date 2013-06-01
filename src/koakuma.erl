-module (koakuma).

-export ([start/0, stop/0]).
-export ([send_raw/1]).

start() ->
    ok = application:start(koakuma).

stop() ->
    ok = application:stop(koakuma).

send_raw(Msg) ->
    gen_server:cast(koakuma_bot, {send_raw, Msg}).
