-module (koakuma_queue_tests).
-include_lib("eunit/include/eunit.hrl").
-define (MOD, koakuma_queue).

setup() ->
    {ok, Pid} = ?MOD:start_link(),
    Pid.

cleanup(Pid) ->
    gen_server:call(Pid, stop).

queue_test_() ->
    {foreach, fun setup/0, fun cleanup/1, [
        ?_test(begin
            ?assertEqual({state, {5, []}}, ?MOD:state()),
            ?assertEqual(start, ?MOD:push(self())),
            ?assertEqual(start, ?MOD:push(self())),
            ?assertEqual(start, ?MOD:push(self())),
            ?assertEqual(start, ?MOD:push(self())),
            ?assertEqual(start, ?MOD:push(self())),
            ?assertEqual(queued, ?MOD:push(self())),
            ?assertEqual(ok, ?MOD:done(self()))
        end)
    ]}.
