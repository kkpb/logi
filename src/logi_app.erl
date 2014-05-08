%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc application module
%% @private
-module(logi_app).

-include("logi.hrl").
-behaviour(application).

%%------------------------------------------------------------------------------------------------------------------------
%% 'application' Callback API
%%------------------------------------------------------------------------------------------------------------------------
-export([start/2, stop/1]).

%%------------------------------------------------------------------------------------------------------------------------
%% 'application' Callback Functions
%%------------------------------------------------------------------------------------------------------------------------
%% @hidden
start(_StartType, _StartArgs) ->
    SupResult = logi_sup:start_link(),
    case SupResult of
        {ok, _} ->
            case logi:start_event_manager({local, ?LOGI_DEFAULT_EVENT_MANAGER}) of
                {ok, _}         -> SupResult;
                {error, Reason} -> {error, {cannot_start_default_event_manager, Reason}}
            end;
        Other -> Other
    end.

%% @hidden
stop(_State) ->
    ok.
