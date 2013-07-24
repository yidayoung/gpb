%%% Copyright (C) 2013  Tomas Abrahamsson
%%%
%%% Author: Tomas Abrahamsson <tab@lysator.liu.se>
%%%
%%% This library is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU Library General Public
%%% License as published by the Free Software Foundation; either
%%% version 2 of the License, or (at your option) any later version.
%%%
%%% This library is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% Library General Public License for more details.
%%%
%%% You should have received a copy of the GNU Library General Public
%%% License along with this library; if not, write to the Free
%%% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

-module(gpb_codegen_tests).

-include("../src/gpb_codegen.hrl").
-include_lib("eunit/include/eunit.hrl").

%-compile(export_all).

-define(dummy_mod, list_to_atom(lists:concat([?MODULE, "-test"]))).
-define(debug,true).

-define(current_function,
        begin
            {current_function,{_M___,_F___,_Arity___}} =
                erlang:process_info(self(), current_function),
            _F___
        end).

plain_parse_transform_test() ->
    M = ?dummy_mod,
    FnName = mk_test_fn_name(),
    {module,M} = l(M, gpb_codegen:mk_fn(FnName, fun(a) -> {ok, 1} end)),
    {ok, 1} = M:FnName(a),
    ?assertError(_, M:FnName(b)).

term_replacements_test() ->
    M = ?dummy_mod,
    FnName = mk_test_fn_name(),
    {module,M} = l(M, gpb_codegen:mk_fn(FnName,
                                        fun(a) -> {ok, b} end,
                                        [{replace_term,a,1},
                                         {replace_term,b,2}])),
    ?assertError(_, M:FnName(a)),
    {ok, 2} = M:FnName(1).

tree_replacements_1_test() ->
    M = ?dummy_mod,
    FnName = mk_test_fn_name(),
    Var = gpb_codegen:expr(V),
    {module,M} = l(M, gpb_codegen:mk_fn(FnName,
                                        fun(a) -> {ok, b} end,
                                        [{replace_tree,a,Var},
                                         {replace_tree,b,Var}])),
    {ok, x} = M:FnName(x),
    {ok, z} = M:FnName(z).

tree_replacements_2_test() ->
    M = ?dummy_mod,
    FnName = mk_test_fn_name(?current_function),
    Add = gpb_codegen:expr(V + V),
    {module,M} = l(M, gpb_codegen:mk_fn(FnName,
                                        fun(V, V) -> ret end,
                                        [{replace_tree,ret,Add}])),
    8 = M:FnName(4, 4).

tree_splicing_1_test() ->
    M = ?dummy_mod,
    FnName = mk_test_fn_name(?current_function),
    Vars = gpb_codegen:exprs(V, V),
    Ret  = gpb_codegen:exprs(V, V),
    {module,M} = l(M, gpb_codegen:mk_fn(FnName,
                                        fun(p) -> {ret} end,
                                        [{splice_trees,p,Vars},
                                         {splice_trees,ret,Ret}])),
    {x,x} = M:FnName(x, x),
    {z,z} = M:FnName(z, z),
    ?assertError(_, M:FnName(x, z)).

tree_splicing_2_test() ->
    M = ?dummy_mod,
    FnName = mk_test_fn_name(?current_function),
    Vars = gpb_codegen:exprs(V, V),
    {module,M} = l(M, gpb_codegen:mk_fn(FnName,
                                        fun(p) -> V + V end,
                                        [{splice_trees,p,Vars}])),
    4 = M:FnName(2, 2).

%% -- helpers ---------------------------

mk_test_fn_name() ->
    %% Make different names (for testability),
    %% but don't exhaust the atom table.
    list_to_atom(lists:concat([test_, small_random_number()])).

mk_test_fn_name(FnName) ->
    %% Make different names (for testability),
    %% but don't exhaust the atom table.
    list_to_atom(lists:concat([test_, FnName, "_", small_random_number()])).

small_random_number() ->
    integer_to_list(erlang:phash2(make_ref()) rem 17).

l(Mod, Form) ->
    File = atom_to_list(Mod)++".erl",
    Program = [mk_attr(file,{File,1}),
               mk_attr(module,Mod),
               mk_attr(compile,export_all),
               Form],
    try compile:forms(Program) of
        {ok, Mod, Bin} ->
            unload_code(Mod),
            code:load_binary(Mod, File, Bin);
        Error ->
            ?debugFmt("~nCompilation Error:~n~s~n  ~p~n",
                      [format_form_debug(Form), Error]),
            Error
    catch error:Error ->
            ST = erlang:get_stacktrace(),
            ?debugFmt("~nCompilation crashed (malformed parse-tree?):~n"
                      ++ "~s~n"
                      ++ "  ~p~n",
                      [format_form_debug(Form), {Error,ST}]),
            {error, {compiler_crash,Error}}
    end.

mk_attr(AttrName, AttrValue) ->
    erl_syntax:revert(
      erl_syntax:attribute(erl_syntax:atom(AttrName),
                           [erl_syntax:abstract(AttrValue)])).

unload_code(Mod) ->
    code:purge(Mod),
    code:delete(Mod),
    code:purge(Mod),
    code:delete(Mod),
    ok.

format_form_debug(Form) ->
    PrettyForm = try erl_prettypr:format(Form)
                 catch error:_ -> "(Failed to pretty-print form)"
                 end,
    io_lib:format("~nForm=~p~n"
                  ++ "-->~n"
                  ++ "~s~n"
                  ++ "^^^^",
                  [Form, PrettyForm]).
