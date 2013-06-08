-module (koakuma_dets).

-export ([all/0]).
-export ([packs/0, files/0, sizes/0]).
-export ([pack/1, file/1]).
-export ([insert/1, delete/1, replace/2]).

-include_lib("koakuma.hrl").

%% API

all() ->
    query(match, '$1').

packs() ->
    query(select, [{ #file {pack='$1', _='_'}, [], ['$1']}]).

files() ->
    query(select, [{ #file {name='$1', _='_'}, [], ['$1']}]).

sizes() ->
    query(select, [{ #file {size='$1', _='_'}, [], ['$1']}]).

pack(Pack) ->
    query(select, [{ #file {pack=Pack, _='_'}, [], ['$_']}]).

file(Name) ->
    query(select, [{ #file {name=Name, _='_'}, [], ['$_']}]).

insert(Object) ->
    query(insert, Object).

delete(Object) ->
    query(delete_object, Object).

replace(OldObj, NewObj) ->
    delete(OldObj),
    insert(NewObj).

%% Internal functions

open() ->
    {ok, db} = dets:open_file(db, [{file, koakuma_cfg:get(data_db)}, {type, bag}]),
    db.

close() ->
    dets:close(db).

query(F, Param) ->
    open(),
    Result = erlang:apply(dets, F, [db, Param]),
    close(),
    Result.
