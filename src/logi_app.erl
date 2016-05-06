%% @copyright 2014-2016 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc application module
%% @private
%% @end
-module(logi_app).

-behaviour(application).

%%----------------------------------------------------------------------------------------------------------------------
%% 'application' Callback API
%%----------------------------------------------------------------------------------------------------------------------
-export([start/2, stop/1]).

%%----------------------------------------------------------------------------------------------------------------------
%% 'application' Callback Functions
%%----------------------------------------------------------------------------------------------------------------------
%% @private
start(_StartType, _StartArgs) ->
    logi_sup:start_link().

%% @private
stop(_State) ->
    ok.
