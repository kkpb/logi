%% @copyright 2014-2016 Takeru Ohta <phjgt308@gmail.com>
%% @end
-module(logi_channel_tests).

-include_lib("eunit/include/eunit.hrl").

%%----------------------------------------------------------------------------------------------------------------------
%% Unit Tests
%%----------------------------------------------------------------------------------------------------------------------
channel_test_() ->
    Channel = test_channel,
    {setup,
     fun () -> ok = application:start(logi) end,
     fun (_) -> ok = application:stop(logi) end,
     [
      {"The predefined channel",
       fun () ->
               ?assertEqual([logi_channel:default_channel()], logi_channel:which_channels())
       end},
      {"Creates a channel",
       fun () ->
               ?assertEqual(ok,        logi_channel:create(Channel)),
               ?assertEqual([Channel], lists:delete(logi_channel:default_channel(), logi_channel:which_channels())),
               ?assertEqual(ok,        logi_channel:delete(Channel)),
               ?assertEqual([],        lists:delete(logi_channel:default_channel(), logi_channel:which_channels()))
       end},
      {"CREATE: If the channel already exists, nothing happens",
       fun () ->
               ok = logi_channel:create(Channel),
               ?assertEqual([Channel], lists:delete(logi_channel:default_channel(), logi_channel:which_channels())),
               ?assertEqual(ok,        logi_channel:create(Channel)),
               ?assertEqual([Channel], lists:delete(logi_channel:default_channel(), logi_channel:which_channels())),
               ok = logi_channel:delete(Channel)
       end},
      {"DELETE: If the channel does exists, it will be silently ignored",
       fun () ->
               ?assertEqual([], lists:delete(logi_channel:default_channel(), logi_channel:which_channels())),
               ?assertEqual(ok, logi_channel:delete(Channel)),
               ?assertEqual([], lists:delete(logi_channel:default_channel(), logi_channel:which_channels()))
       end},
      {"ERROR(badarg): non atom id",
       fun () ->
               ?assertError(badarg, logi_channel:create("hoge")),
               ?assertError(badarg, logi_channel:delete(<<"fuga">>))
       end},
      {"ERROR(badarg): id conflict",
       fun () ->
               true = register(existing_process_name, spawn(timer, sleep, [infinity])),
               ?assertError(badarg, logi_channel:create(existing_process_name)),

               _ = ets:new(existing_table_name, [named_table]),
               ?assertError(badarg, logi_channel:create(existing_table_name))
       end}
     ]}.

sink_test_() ->
    NullSink = logi_builtin_sink_fun:new(null, fun (_, _, _) -> [] end),
    {setup,
     fun () -> ok = application:start(logi) end,
     fun (_) -> ok = application:stop(logi) end,
     [
      {"Initially no sinks are installed",
       fun () ->
               ?assertEqual([], logi_channel:which_sinks())
       end},
      {foreach,
       fun () -> ok = logi_channel:create(logi_channel:default_channel()) end,
       fun (_) -> ok = logi_channel:delete(logi_channel:default_channel()) end,
       [
        {"Installs a sink",
         fun () ->
                 ?assertEqual({ok, undefined}, logi_channel:install_sink(NullSink, debug)),
                 ?assertEqual([null], logi_channel:which_sinks())
         end},
        {"Finds a sink",
         fun () ->
                 ?assertEqual(error, logi_channel:find_sink(null)),
                 {ok, undefined} = logi_channel:install_sink(NullSink, debug),
                 ?assertMatch({ok, #{sink := NullSink}}, logi_channel:find_sink(null))
         end},
        {"Finds a sink: Uses the default channel",
         fun () ->
                 ?assertEqual(error, logi_channel:find_sink(null)),
                 {ok, undefined} = logi_channel:install_sink(NullSink, debug),
                 ?assertMatch({ok, #{sink := NullSink}}, logi_channel:find_sink(null)),
                 {ok, _} = logi_channel:uninstall_sink(null)
         end},
        {"Uninstalls a sink",
         fun () ->
                 {ok, undefined} = logi_channel:install_sink(NullSink, debug),
                 ?assertMatch({ok, #{sink := NullSink}}, logi_channel:uninstall_sink(null)),
                 ?assertEqual(error, logi_channel:uninstall_sink(null)),
                 ?assertEqual(error, logi_channel:find_sink(null)),
                 ?assertEqual([], logi_channel:select_writer(logi_channel:default_channel(), info, hoge, fuga))
         end},
        {"Uninstalls a sink: Uses the default channel",
         fun () ->
                 {ok, undefined} = logi_channel:install_sink(NullSink, debug),
                 ?assertMatch({ok, #{sink := NullSink}}, logi_channel:uninstall_sink(null)),
                 ?assertEqual(error, logi_channel:uninstall_sink(null)),
                 ?assertEqual(error, logi_channel:find_sink(null)),
                 ?assertEqual([], logi_channel:select_writer(logi_channel:default_channel(), info, hoge, fuga))
         end},
        {"INSTALL: `if_exists` option",
         fun () ->
                 {ok, undefined} = logi_channel:install_sink(NullSink, debug),

                 %% if_exists == error
                 ?assertMatch({error, {already_installed, #{sink := NullSink}}},
                              logi_channel:install_sink_opt(NullSink, debug, [{if_exists, error}])),

                 %% if_exists == ignore
                 ?assertMatch({ok, #{condition := debug, sink := NullSink}},
                              logi_channel:install_sink_opt(NullSink, info, [{if_exists, ignore}])),

                 %% if_exists == supersede
                 AnotherSink = logi_builtin_sink_fun:new(null, fun (_, _, _) -> <<"">> end),
                 ?assertMatch({ok, #{condition := debug, sink := NullSink}},
                              logi_channel:install_sink_opt(AnotherSink, info, [{if_exists, supersede}])),
                 ?assertNotEqual(NullSink, AnotherSink),
                 ?assertMatch({ok, #{condition := info, sink := AnotherSink}},
                              logi_channel:find_sink(null)),

                 %% invalid value
                 ?assertError(badarg, logi_channel:install_sink_opt(NullSink, debug, [{if_exists, undefined}]))
         end},
        {"set_sink_condition/2",
         fun () ->
                 Set = fun (Condition) -> logi_channel:set_sink_condition(null, Condition) end,
                 ?assertEqual(error, Set([])),

                 Condition0 = debug,
                 Condition1 = info,
                 Condition2 = alert,
                 Sink = logi_builtin_sink_fun:new(null, fun (_, _, _) -> [] end),

                 {ok, undefined} = logi_channel:install_sink(Sink, Condition0),
                 ?assertMatch({ok, Condition0}, Set(Condition1)),
                 ?assertMatch({ok, Condition1}, Set(Condition2))
         end}
       ]}
     ]}.

select_test_() ->
    Channel = test_channel,
    Install =
        fun (Id, Condition) ->
                Sink = logi_builtin_sink_fun:new(Id, fun (_, _, _) -> atom_to_list(Id) end),
                {ok, _} = logi_channel:install_sink(Channel, Sink, Condition),
                ok
        end,
    SetCond =
        fun (Id, Condition) ->
                {ok, _} = logi_channel:set_sink_condition(Channel, Id, Condition),
                ok
        end,
    Select =
        fun (Severity, Application, Module) ->
                lists:sort([list_to_atom(F([],[],[])) ||
                               {_, F} <- logi_channel:select_writer(Channel, Severity, Application, Module)])
        end,
    {setup,
     fun () -> ok = application:start(logi) end,
     fun (_) -> ok = application:stop(logi) end,
     [
      {foreach,
       fun () -> ok = logi_channel:create(Channel) end,
       fun (_) -> ok = logi_channel:delete(Channel) end,
       [
        {"simple (level)",
         fun () ->
                 ok = Install(aaa, notice),
                 ok = Install(bbb, debug),

                 ?assertEqual([bbb],      Select(debug,  stdlib, lists)),
                 ?assertEqual([bbb],      Select(info,   stdlib, lists)),
                 ?assertEqual([aaa, bbb], Select(notice, stdlib, lists)),
                 ?assertEqual([aaa, bbb], Select(alert,  stdlib, lists))
         end},
        {"range",
         fun () ->
                 ok = Install(aaa, {debug, notice}),
                 ok = Install(bbb, {info, critical}),

                 ?assertEqual([aaa],      Select(debug,   stdlib, lists)),
                 ?assertEqual([aaa, bbb], Select(info,    stdlib, lists)),
                 ?assertEqual([aaa, bbb], Select(notice,  stdlib, lists)),
                 ?assertEqual([bbb],      Select(warning, stdlib, lists)),
                 ?assertEqual([],         Select(alert,   stdlib, lists))
         end},
        {"list",
         fun () ->
                 ok = Install(aaa, [debug, info, notice]),
                 ok = Install(bbb, [notice, critical]),
                 ok = Install(ccc, [info]),

                 ?assertEqual([aaa],      Select(debug,    stdlib, lists)),
                 ?assertEqual([aaa, ccc], Select(info,     stdlib, lists)),
                 ?assertEqual([aaa, bbb], Select(notice,   stdlib, lists)),
                 ?assertEqual([],         Select(alert,    stdlib, lists)),
                 ?assertEqual([bbb],      Select(critical, stdlib, lists))
         end},
        {"severity + application",
         fun () ->
                 ok = Install(aaa, #{severity => debug,             application => stdlib}),
                 ok = Install(bbb, #{severity => [notice, warning], application => [stdlib, kernel]}),
                 ok = Install(ccc, #{severity => info,              application => kernel}),

                 ?assertEqual([aaa],      Select(debug,   stdlib, lists)),
                 ?assertEqual([aaa],      Select(info,    stdlib, lists)),
                 ?assertEqual([aaa, bbb], Select(notice,  stdlib, lists)),
                 ?assertEqual([aaa, bbb], Select(warning, stdlib, lists)),
                 ?assertEqual([aaa],      Select(alert,   stdlib, lists))
         end},
        {"severity + application + module",
         fun () ->
                 ok = Install(aaa, #{severity => debug,             application => kernel, module => [lists, dict]}),
                 ok = Install(bbb, #{severity => [notice, warning], application => stdlib, module => net_kernel}),
                 ok = Install(ccc, #{severity => info,              application => kernel, module => net_kernel}),

                 ?assertEqual([aaa],      Select(debug,   stdlib, lists)),
                 ?assertEqual([aaa],      Select(info,    stdlib, lists)),
                 ?assertEqual([aaa, bbb], Select(notice,  stdlib, lists)),
                 ?assertEqual([aaa, bbb], Select(warning, stdlib, lists)),
                 ?assertEqual([aaa],      Select(alert,   stdlib, lists))
         end},
        {"change condition",
         fun () ->
                 ok = Install(aaa, debug),
                 ok = Install(bbb, info),
                 ok = Install(ccc, alert),
                 ok = Install(ddd, emergency),

                 Applications = applications(),
                 Modules = modules(),
                 lists:foreach(
                   fun (_) ->
                           ok = SetCond(aaa, random_condition(Applications, Modules)),
                           ok = SetCond(bbb, random_condition(Applications, Modules)),
                           ok = SetCond(ccc, random_condition(Applications, Modules)),
                           ok = SetCond(ddd, random_condition(Applications, Modules))
                   end,
                   lists:seq(1, 100)),

                 ok = SetCond(aaa, #{severity => debug,             module => [lists, dict]}),
                 ok = SetCond(bbb, #{severity => [notice, warning], application => stdlib, module => net_kernel}),
                 ok = SetCond(ccc, #{severity => info,              application => kernel, module => net_kernel}),
                 ok = SetCond(ddd, emergency),

                 ?assertEqual([aaa],      Select(debug,   stdlib, lists)),
                 ?assertEqual([aaa],      Select(info,    stdlib, lists)),
                 ?assertEqual([aaa, bbb], Select(notice,  stdlib, lists)),
                 ?assertEqual([aaa, bbb], Select(warning, stdlib, lists)),
                 ?assertEqual([aaa],      Select(alert,   stdlib, lists))
         end}
       ]}
     ]}.

whereis_sink_proc_test_() ->
    {setup,
     fun () -> ok = application:start(logi) end,
     fun (_) -> ok = application:stop(logi) end,
     [
      {"Lookups sink process with specified path",
       fun () ->
               Child1_a = logi_builtin_sink_io_device:new(bar_a),
               Child1_b = logi_builtin_sink_io_device:new(bar_b),
               Child2_a = logi_builtin_sink_io_device:new(baz_a),
               Child2_b = logi_builtin_sink_io_device:new(baz_b),
               Sink = logi_builtin_sink_composite:new(
                        foo,
                        [
                         logi_builtin_sink_composite:new(bar, [Child1_a, Child1_b]),
                         logi_builtin_sink_composite:new(baz, [Child2_a, Child2_b])
                        ]),
               {ok, _} = logi_channel:install_sink(Sink, info),

               %% Existing pathes
               lists:foreach(
                 fun (Path) ->
                         ?assert(is_pid(logi_channel:whereis_sink_proc(Path)))
                 end,
                 [
                  [foo],
                  [foo, bar], [foo, bar, bar_a], [foo, bar, bar_b],
                  [foo, baz], [foo, baz, baz_a], [foo, baz, baz_b]
                 ]),

               %% Unexisting pathes
               ?assertEqual(undefined, logi_channel:whereis_sink_proc([bar])),
               ?assertEqual(undefined, logi_channel:whereis_sink_proc([foo, bar_a]))
       end},
      {"Empty path is forbidden",
       fun () ->
               ?assertError(badarg, logi_channel:whereis_sink_proc([]))
       end}
     ]}.

down_test_() ->
    {setup,
     fun () -> ok = application:start(logi) end,
     fun (_) -> ok = application:stop(logi) end,
     [
      {"If a sink process exited, the associated sink is uninstalled from the channel",
       fun () ->
               Sink = logi_builtin_sink_io_device:new(foo),
               {ok, _} = logi_channel:install_sink(Sink, info),
               ?assertEqual([foo], logi_channel:which_sinks()),

               (fun Loop () ->
                        case logi_channel:whereis_sink_proc([foo]) of
                            undefined -> ok;
                            SinkPid   ->
                                exit(SinkPid, kill),
                                timer:sleep(10),
                                Loop()
                        end
                end)(),
               ?assertEqual([], logi_channel:which_sinks())
       end}
     ]}.

%%----------------------------------------------------------------------------------------------------------------------
%% Internal Functions
%%----------------------------------------------------------------------------------------------------------------------
-spec random_condition([atom()], [module()]) -> logi_sink:condition().
random_condition(Applications, Modules) ->
    Severities = logi:severities(),
    case rand:uniform(3) of
        1 -> subshuffle(Severities);
        2 -> #{severity => subshuffle(Severities), application => subshuffle(Applications)};
        3 -> #{severity => subshuffle(Severities), application => subshuffle(Applications), module => subshuffle(Modules)}
    end.

-spec subshuffle(list()) -> list().
subshuffle(List) ->
    lists:sublist([X || {_, X} <- lists:sort([{rand:uniform(), X} || X <- List])],
                  rand:uniform(max(20, length(List))) -1).

-spec applications() -> [atom()].
applications() ->
    [A || {A, _, _} <- application:which_applications()].

-spec modules() -> [module()].
modules() ->
    [M || {M, _} <- code:all_loaded(), application:get_application(M) =/= undefined].
