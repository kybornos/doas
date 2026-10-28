# OpenBSD doas wrapper in Erlang

Requires user, cmd, args and timeout.

Example:

``` erlang
t1s_doas:run(
    #{
        user => ?ROOT,
        cmd => ?RCCTL,
        args => [<<"enable">>, Service]
    },
    ?TIMEOUT
)
```

After the timeout the entire process group is killed.
