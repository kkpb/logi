%% @copyright 2014-2016 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc The root supervisor module
%% @private
%% @end
-module(logi_sup).

-behaviour(supervisor).

%%----------------------------------------------------------------------------------------------------------------------
%% Exported API
%%----------------------------------------------------------------------------------------------------------------------
-export([start_link/0]).

%%----------------------------------------------------------------------------------------------------------------------
%% 'supervisor' Callback API
%%----------------------------------------------------------------------------------------------------------------------
-export([init/1]).

%%----------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%----------------------------------------------------------------------------------------------------------------------
%% @doc Starts the root supervisor
-spec start_link() -> {ok, pid()} | {error, Reason::term()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%----------------------------------------------------------------------------------------------------------------------
%% 'supervisor' Callback Functions
%%----------------------------------------------------------------------------------------------------------------------
%% @private
init([]) ->
    Children =
        [
         #{id => name_server, start => {logi_name_server, start_link, []}},
         #{id => channel_set_sup, start => {logi_channel_set_sup, start_link, []}, type => supervisor}
        ],
    {ok, {#{strategy => rest_for_one}, Children}}.
