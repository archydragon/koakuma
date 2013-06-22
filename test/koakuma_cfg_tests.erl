-module (koakuma_cfg_tests).
-include_lib("eunit/include/eunit.hrl").
-define (MOD, koakuma_cfg).

setup() ->
    {ok, Pid} = ?MOD:start_link(),
    Pid.

cleanup(Pid) ->
    gen_server:call(Pid, stop).

read_test_() ->
    {foreach, fun setup/0, fun cleanup/1, [
        ?_test(begin
            ?assertEqual(ok, ?MOD:read("koakuma.cfg")),
            ?assertEqual({error, enoent}, ?MOD:read("nofile.cfg"))
        end)
    ]}.

get_test_() ->
    {foreach, fun setup/0, fun cleanup/1, [
        ?_test(begin
            ?MOD:read("koakuma.cfg"),
            ?assertEqual(6667, ?MOD:get(port)),
            ?assertEqual("EKoakuma_xdcc_list.txt", ?MOD:get(list_export)),
            ?assertEqual([], ?MOD:get(some_unexisting_key))
        end)
    ]}.

set_test_() ->
    {foreach, fun setup/0, fun cleanup/1, [
        ?_test(begin
            ?MOD:read("koakuma.cfg"),
            ?assertEqual(ok, ?MOD:set(port, 6669)),
            ?assertEqual(ok, ?MOD:set(new_key, empty))
        end)
    ]}.
