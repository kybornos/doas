-module(doas).

-export([run/2]).

-define(DOAS, "/usr/bin/doas").
-define(KILL, ?DOAS ++ " /usr/bin/pkill -g ~B").
-define(KILL9, ?DOAS ++ " /usr/bin/pkill -9 -g ~B").

-spec exec(binary(), [binary()], timeout()) ->
    {ok, map()} | {error, term()}.

exec(Cmd, Args, Timeout) when
    is_binary(Cmd), is_list(Args)
->
    Port = open_port(
        {spawn_executable, binary_to_list(Cmd)},
        [
            exit_status,
            stderr_to_stdout,
            binary,
            use_stdio,
            {args, [binary_to_list(A) || A <- Args]}
        ]
    ),
    {os_pid, Pgrp} = erlang:port_info(Port, os_pid),
    collect(Port, <<>>, Timeout, Pgrp).

-type run_opts() ::
    #{
        user := binary(),
        cmd := binary(),
        args := [binary()]
    }.

-spec run(run_opts(), timeout()) ->
    {ok, map()} | {error, term()}.

run(#{user := User, cmd := Cmd, args := Args}, Timeout) when
    is_binary(User), is_binary(Cmd), is_list(Args)
->
    exec(?DOAS, [<<"-nu">>, User, Cmd | Args], Timeout).

-spec pid_exists(integer()) -> boolean().

pid_exists(Pid) when is_integer(Pid), Pid > 0 ->
    Port = open_port(
        {spawn_executable, binary_to_list(?DOAS)},
        [
            exit_status,
            binary,
            stderr_to_stdout,
            {args, ["-nu", "root", "/bin/kill", "-0", integer_to_list(Pid)]}
        ]
    ),
    receive
        {Port, {exit_status, 0}} ->
            true;
        {Port, {exit_status, _}} ->
            false
    end;
pid_exists(_) ->
    false.

collect(Port, Acc, Timeout, Pgrp) ->
    receive
        {Port, {data, Data}} ->
            collect(Port, <<Acc/binary, Data/binary>>, Timeout, Pgrp);
        {Port, {exit_status, 0}} ->
            {ok, #{exit_code => 0, output => Acc}};
        {Port, {exit_status, Code}} ->
            {error, #{exit_code => Code, output => Acc}}
    after Timeout ->
        port_close(Port),
        os:cmd(io_lib:format(?KILL, [Pgrp])),
        timer:sleep(1000),
        %% check if process is still around after sigterm and a bit of sleep
        %% if yes, try and kill it
        case pid_exists(Pgrp) of
            true ->
                os:cmd(io_lib:format(?KILL9, [Pgrp]));
            false ->
                ok
        end,
        logger:error(
            "doas cmd exec timeout ~p reached killing pgroup ~P",
            [Timeout, Pgrp, 20]
        ),

        {error, timeout, Pgrp}
    end.
