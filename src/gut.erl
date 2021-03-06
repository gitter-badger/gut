-module(gut).
-export([
         start/0,
         start/2,
         stop/0,
         stop/1,
         main/1
        ]).

%% version number
version() ->
    "0.2".

%%% Exported functions
start() ->
    {ok, _Started} = application:ensure_all_started(gut).

stop() ->
    application:stop(gut).

start(_StartType, _StartArgs) ->
    gut_sup:start_link().

stop(_State) ->
    ok.

main(Args) ->
    gut:start(),
    check_needed_executables(),
    OptSpecList = option_spec_list(),
    case getopt:parse(OptSpecList, Args) of
        {ok, {[], []}} ->
            help();
        {ok, {Options, Commands}} ->
            process_options(Options, Commands);
        {error, {Reason, Data}} ->
            io:format("Error: ~s ~p~n~n", [Reason, Data]),
            help()
    end.

%%% Internal

%% Command line options
-spec process_options([atom()], [string()]) -> ok.
process_options([help | Opts], Cmds) ->
    help(),
    process_options(Opts, Cmds);
process_options([commands | Opts], Cmds) ->
    commands(),
    process_options(Opts, Cmds);
process_options([], Cmds) ->
    process_commands(Cmds).

-spec process_commands([string()]) -> ok.
process_commands(["help" | _]) ->
    commands();
process_commands(["new" | Cmds]) ->
    new(Cmds);
process_commands(["find" | Cmds]) ->
    find(Cmds);
process_commands(["erlang.mk" | _]) ->
    erlang_mk();
process_commands(["escriptize" | Cmds]) ->
    escriptize(Cmds);
process_commands(["update" | _]) ->
    update();
process_commands(["update-gens" | _]) ->
    update_generators();
process_commands(["version" | _]) ->
    io:format("gut version ~s~n", [version()]);
process_commands([_Cmd | _Cmds]) ->
    throw(unrecognized_or_unimplemened_command).

%% Commands

new([_]) ->
    throw(missing_name);
new([ProvidedName, Name | _]) ->
    FullGeneratorName = gut_suffix:full_name(ProvidedName),
    Values = [{<<"{{NAME}}">>, Name}],
    Generator = gut_generators:find_by_name(FullGeneratorName),
    case Generator of
        not_found ->
            io:format("Generator ~s not found ~n", [ProvidedName]);
        #{name := GenName,
          url := GenUrl} ->
            gut_generators:clone(GenName, GenUrl),
            gut_generators:copy(GenName, Name),
            os:cmd("rm -rf " ++ Name ++ "/.git"),

            gut_compile:compile(Name, Values),
            io:format("Generated ~p on ~p~n", [FullGeneratorName, Name])
    end.

find([]) ->
    io:format("Find generators...~n"),
    Generators = gut_generators:find_all(),
    lists:foreach(fun print_generator/1, Generators);
find([Name | _]) ->
    Generators = gut_generators:find_all_by_name(Name),
    lists:foreach(fun print_generator/1, Generators).

print_generator(#{name := GenName, description := Desc}) ->
    ShortName = gut_suffix:short_name(GenName),
    io:format("~s ~s~n", [color:green(ShortName), Desc]).

erlang_mk() ->
    Url = "https://raw.githubusercontent.com/"
          "ninenines/erlang.mk/master/erlang.mk",
    {ok, "200", _, Content} = ibrowse:send_req(Url, [], get),
    file:write_file("erlang.mk", Content).

escriptize([]) ->
    gut_escriptize:run();
escriptize([Name | _]) ->
    gut_escriptize:run(Name).

update() ->
    Url = "https://raw.githubusercontent.com/"
          "unbalancedparentheses/gut/master/bin/gut",
    case os:find_executable("gut") of
        false ->
            io:format("Could not find gut in your system");
        Path ->
            {ok, "200", _, Content} = ibrowse:send_req(Url, [], get),
            file:write_file(Path, Content)
    end.

update_generators() ->
    gut_generators:update().

%% Options

help() ->
    OptSpecList = option_spec_list(),
    getopt:usage(OptSpecList, atom_to_list(?MODULE), standard_io),
    commands().

-spec commands() -> ok.
commands() ->
    Commands = <<
"  new GENERATOR NAME [variable=value]
                 Create a new project using a generator, or a new file
                 using a template. GENERATOR is the generator's or
                 template's name. NAME should be the name of the new project.
                 Subsequent VALUE specifications should be paired with its
                 VARIABLE name.

  find [QUERY]
                 Find available generators and templates. If QUERY is not
                 provided then all will be listed.

  erlang.mk
                 Download erlang.mk.

  escriptize [APPLICATION]
                 Turn your erlang application into an escript.
                 If you do not provide an application name the current
                 directory name will be used to determine the application's
                 name.

  update
                 Get the latest version of the `gut` executable.

  update-gens
                 Update all generators in the local `.gut` folder.

  version
                 Show current version information.
">>,
    io:put_chars(Commands).

option_spec_list() ->
    [
     {help, $h, "help", undefined, "Show this help information."}
    ].

%% Executables checks

needed_executables() ->
    [
     "git"
    ].

check_needed_executables() ->
    lists:foreach(
      fun (X) ->
              executable_present(X)
      end,
      needed_executables()).

executable_present(Name) ->
    case os:find_executable(Name) of
        false ->
            throw(Name ++ " is not present on the system");
        _ ->
            ok
    end.
