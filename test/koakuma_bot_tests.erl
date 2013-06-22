-module (koakuma_bot_tests).
-include_lib ("eunit/include/eunit.hrl").
-include_lib ("eunit_my.hrl").
-define (MOD, koakuma_bot).

from_test_() ->
    ?_test(begin
        ?assertEqual("Nick", ?MOD:from(":Nick!username@host.com PRIVMSG :xdcc list"))
    end).

int_ip_test_() ->
    ?multiEqual(fun ?MOD:int_ip/1, [
        {"IP 127.0.0.1",      2130706433, {ok, {127,0,0,1}}},
        {"IP 19.110.203.167", 326028199,  {ok, {19,110,203,167}}}
    ]).

list_max_test_() ->
    ?multiEqual(fun ?MOD:list_max/1, [
        {"empty list", 0, []},
        {"single element", 10, [10]},
        {"different ones", 5, [1, 2, 5, 4, 3, 2]},
        {"multiple max", 5, [2, 5, 3, 5]}
    ]).

ranges_test_() ->
    ?multiEqual(fun ?MOD:ranges/1, [
        {"Range '1'",                 [1],                 "1"},
        {"Range '1-2'",               [1, 2],              "1-2"},
        {"Range '1,3,6'",             [1, 3, 6],           "1,3,6"},
        {"Range '1-3,5-6'",           [1, 2, 3, 5, 6],     "1-3,5-6"},
        {"Range '#1-2,#4,#6,#8,#10'", [1, 2, 4, 6, 8, 10], "#1-2,#4,#6,#8,#10"}
    ]).

size_h_test_() ->
    ?multiEqual(fun ?MOD:size_h/1, [
        {"0 bytes",    "0",         0},
        {"1023 bytes", "1023",      1023},
        {"1 Kbyte",    "1.00K",     1024},
        {"~20 Mbytes", "19.53M",    20480000},
        {"too much",   "10965.17P", 12345678909876543210}
    ]).

trim_test_() ->
    ?multiEqual(fun ?MOD:trim/1, [
        {"both", "clean", " clean "},
        {"none", "nothing to do there", "nothing to do there"},
        {"trailing", "line", "line     "},
        {"heading", "what?", "   what?"}
    ]).

unbold_test_() ->
    ?multiEqual(fun ?MOD:unbold/1, [
        {"bold", "clean", "\002clean\002"},
        {"not bold", "nothing", "nothing"}
    ]).
