%% @copyright 2014-2015 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc A parse_transform module for logi
%%
%% This module is used to provide following information automatically to log messages (e.g. the messages produced by {@link logi:info/2}): <br />
%% - Application Name
%% - Module Name
%% - Function Name
%% - Line Number
%%
%% The above functionality will be enabled, if the option `{parse_transform, logi_transform}' is passed to the compiler.
%%
%% Reference documentations for parse_transform: <br />
%% - http://www.erlang.org/doc/man/erl_id_trans.html
%% - http://www.erlang.org/doc/apps/erts/absform.html
-module(logi_transform).

%%----------------------------------------------------------------------------------------------------------------------
%% Exported API
%%----------------------------------------------------------------------------------------------------------------------
-export([parse_transform/2]).
-export_type([form/0, line/0, expr/0, expr_call_remote/0, expr_var/0]).

%%----------------------------------------------------------------------------------------------------------------------
%% Types & Records
%%----------------------------------------------------------------------------------------------------------------------
-type form() :: {attribute, line(), atom(), term()}
              | {function, line(), atom(), non_neg_integer(), [clause()]}
              | erl_parse:abstract_form().

-type clause() :: {clause, line(), [term()], [term()], [expr()]}
                | erl_parse:abstract_clause().

-type expr() :: expr_call_remote()
              | expr_var()
              | erl_parse:abstract_expr().

-type expr_call_remote() :: {call, line(), {remote, line(), expr(), expr()}, [expr()]}.
-type expr_var() :: {var, line(), atom()}.

-type line() :: non_neg_integer().

-record(location,
        {
          application :: atom(),
          module      :: module(),
          function    :: atom(),
          line        :: line()
        }).

%%----------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%----------------------------------------------------------------------------------------------------------------------
%% @doc Performs transformations for logi
-spec parse_transform([form()], [compile:option()]) -> [form()].
parse_transform(AbstractForms, Options) ->
    Loc = #location{
             application = logi_transform_utils:guess_application(AbstractForms, Options),
             module      = logi_transform_utils:get_module(AbstractForms)
            },
    walk_forms(AbstractForms, Loc).

%%----------------------------------------------------------------------------------------------------------------------
%% Internal Functions
%%----------------------------------------------------------------------------------------------------------------------
-spec walk_forms([form()], #location{}) -> [form()].
walk_forms(Forms, Loc) ->
    [case Form of
         {function, _, Name, _, Clauses} -> setelement(5, Form, walk_clauses(Clauses, Loc#location{function = Name}));
         _                               -> Form
     end || Form <- Forms].

-spec walk_clauses([clause()], #location{}) -> [clause()].
walk_clauses(Clauses, Loc) ->
    [case Clause of
         {clause, Line, Args, Guards, Body} -> {clause, Line, Args, Guards, [walk_expr(E, Loc) || E <- Body]};
         _                                  -> Clause
     end || Clause <- Clauses].

-spec walk_expr(expr(), #location{}) -> expr().
walk_expr({call, Line, {remote, _, {atom, _, logi}, _}, _} = C, Loc) -> transform_logi_call(C, Loc#location{line = Line});
walk_expr(Expr, Loc) when is_tuple(Expr)                             -> list_to_tuple(walk_expr(tuple_to_list(Expr), Loc));
walk_expr(Expr, Loc) when is_list(Expr)                              -> [walk_expr(E, Loc) || E <- Expr];
walk_expr(Expr, _Loc)                                                -> Expr.

-spec transform_logi_call(expr_call_remote(), #location{}) -> expr_call_remote().
transform_logi_call({call, _, {remote, _, _, {atom, _, location}}, []}, Loc) ->
    logi_location_expr(Loc);
transform_logi_call({call, _, {remote, _, _, {atom, _, Severity0}}, Args} = Call, Loc = #location{line = Line}) ->
    DefaultLogger = {atom, Line, logi:default_logger()},
    case {expand_severity(Severity0), Args} of
        {{ok, Severity, false}, [Fmt]}                        -> logi_call_expr(DefaultLogger, Severity, Fmt, {nil, Line}, {nil, Line}, Loc);
        {{ok, Severity, false}, [Fmt, FmtArgs]}               -> logi_call_expr(DefaultLogger, Severity, Fmt, FmtArgs,     {nil, Line}, Loc);
        {{ok, Severity, false}, [Logger, Fmt, FmtArgs]}       -> logi_call_expr(Logger,        Severity, Fmt, FmtArgs,     {nil, Line}, Loc);
        {{ok, Severity, true},  [Fmt, Opts]}                  -> logi_call_expr(DefaultLogger, Severity, Fmt, {nil, Line}, Opts,        Loc);
        {{ok, Severity, true},  [Fmt, FmtArgs, Opts]}         -> logi_call_expr(DefaultLogger, Severity, Fmt, FmtArgs,     Opts,        Loc);
        {{ok, Severity, true},  [Logger, Fmt, FmtArgs, Opts]} -> logi_call_expr(Logger,        Severity, Fmt, FmtArgs,     Opts,        Loc);
        _                                                     -> Call
    end;
transform_logi_call(Call, _Loc) ->
    Call.

-spec logi_location_expr(#location{}) -> expr().
logi_location_expr(Loc = #location{line = Line}) ->
    logi_transform_utils:make_call_remote(
      Line, logi_location, make,
      [
       {call, Line, {atom, Line, node}, []},
       {call, Line, {atom, Line, self}, []},
       {atom, Line, Loc#location.application},
       {atom, Line, Loc#location.module},
       {atom, Line, Loc#location.function},
       {integer, Line, Line}
      ]).

-spec logi_call_expr(expr(), logi:severity(), expr(), expr(), expr(), #location{}) -> expr().
logi_call_expr(ContextExpr, Severity, FormatExpr, FormatArgsExpr, OptionsExpr, Loc = #location{line = Line}) ->
    LocationExpr = logi_location_expr(Loc),
    BackendsVar = logi_transform_utils:make_var(Line, "__Backends"),
    ContextVar = logi_transform_utils:make_var(Line, "__Context"),
    MsgInfoVar = logi_transform_utils:make_var(Line, "__MsgInfo"),
    {'case', Line, logi_transform_utils:make_call_remote(Line, logi_client, ready, [ContextExpr, {atom, Line, Severity}, LocationExpr, OptionsExpr]),
     [
      %% {skip, Context} -> Context
      {clause, Line, [{tuple, Line, [{atom, Line, skip}, ContextVar]}], [],
       [ContextVar]},

      %% {ok, Backends, MsgInfo, Context} -> logi_client:write(Context, Backends, MsgInfo, Format, Args)
      {clause, Line, [{tuple, Line, [{atom, Line, ok}, BackendsVar, MsgInfoVar, ContextVar]}], [],
       [logi_transform_utils:make_call_remote(Line, logi_client, write, [ContextVar, BackendsVar, MsgInfoVar, FormatExpr, FormatArgsExpr])]}
     ]}.

-spec expand_severity(atom()) -> {ok, logi:severity(), HasOptions::boolean()} | error.
expand_severity(Severity) ->
    case lists:member(Severity, logi:log_levels()) of
        true  -> {ok, Severity, false};
        false ->
            Bin = atom_to_binary(Severity, utf8),
            PrefixSize = max(0, byte_size(Bin) - byte_size(<<"_opt">>)),
            case Bin of
                <<Prefix:PrefixSize/binary, "_opt">> ->
                    Severity2 = binary_to_atom(Prefix, utf8),
                    case lists:member(Severity2, logi:log_levels()) of
                        true  -> {ok, Severity2, true};
                        false -> error
                    end;
                _ ->
                    error
            end
    end.
