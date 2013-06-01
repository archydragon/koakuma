#!/bin/sh

function showhelp {
  echo "Usage: $0 start|kill"
}

erl=`which erl`
koakuma="$erl -detached -pa ebin -s koakuma"

action=$1

case "$action" in
  'start')
    $koakuma start
    ;;
  'kill')
    ps ax | grep koakuma | awk '{print $1}' | xargs -I{} kill -9 {}
    ;;
  *)
    echo "Unknown option."
    showhelp
    ;;
esac
