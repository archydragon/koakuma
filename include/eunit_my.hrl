%% Multiple assertEqual generator
-define (multiEqual (Fun, Data),
    {foreach, fun() -> ok end, [
        {Message, fun() -> ?assertEqual(Expected, Fun(Source)) end} || {Message, Expected, Source} <- Data
    ]}).