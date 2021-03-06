/// The default core provided by JCLI, the 'heart' of your command line tool.
module jaster.cli.core;

private
{
    import std.typecons : Flag;
    import std.traits   : isSomeChar;
    import jaster.cli.parser, jaster.cli.udas, jaster.cli.binder, jaster.cli.helptext, jaster.cli.resolver;
    import jaster.ioc;
}

public
{
    import std.typecons : Nullable;
}

/// 
alias IgnoreFirstArg = Flag!"ignoreFirst";

/++
 + Attach this to any struct/class that represents a command.
 +
 + See_Also:
 +  `jaster.cli.core.CommandLineInterface` for more details.
 + +/
struct Command
{
    /// The pattern to match against.
    string pattern;

    /// The description of this command.
    string description;
}

/++
 + Attach this to any member field to mark it as a named argument.
 +
 + See_Also:
 +  `jaster.cli.core.CommandLineInterface` for more details.
 + +/
struct CommandNamedArg
{
    /// The pattern/"name" to match against.
    string pattern;

    /// The description of this argument.
    string description;
}

/++
 + Attach this to any member field to mark it as a positional argument.
 +
 + See_Also:
 +  `jaster.cli.core.CommandLineInterface` for more details.
 + +/
struct CommandPositionalArg
{
    /// The position this argument appears at.
    size_t position;

    /// The name of this argument. This is only used for the generated help text, and can be left null.
    string name;

    /// The description of this argument.
    string description;
}

/++
 + Attach this onto a `string[]` member field to mark it as the "raw arg list".
 +
 + TLDR; Given the command `"tool.exe command value1 value2 --- value3 value4 value5"`, the member field this UDA is attached to
 + will be populated as `["value3", "value4", "value5"]`
 + ++/
struct CommandRawArg
{}

/++
 + A service that allows commands to access the `CommandLineInterface.parseAndExecute` function of the command's `CommandLineInterface`.
 +
 + Notes:
 +  You **must** use `addCommandLineInterfaceService` to add the default implementation of this service into your `ServiceProvider`, you can of course
 +  create your own implementation, but note that `CommandLineInterface` has special support for the default implementation.
 +
 +  Alternatively, don't pass a `ServiceProvider` into your `CommandLineInterface`, and it'll create this service by itself.
 + ++/
interface ICommandLineInterface
{
    /// See: `CommandLineInterface.parseAndExecute`
    int parseAndExecute(string[] args, IgnoreFirstArg ignoreFirst = IgnoreFirstArg.yes);
}

private final class ICommandLineInterfaceImpl : ICommandLineInterface
{
    alias ParseAndExecuteT = int delegate(string[], IgnoreFirstArg);

    private ParseAndExecuteT _func;

    override int parseAndExecute(string[] args, IgnoreFirstArg ignoreFirst = IgnoreFirstArg.yes)
    {
        return this._func(args, ignoreFirst);
    }
}

/++
 + Returns:
 +  A Singleton `ServiceInfo` providing the default implementation for `ICommandLineInterface`.
 + ++/
ServiceInfo addCommandLineInterfaceService()
{
    return ServiceInfo.asSingleton!(ICommandLineInterface, ICommandLineInterfaceImpl);
}

/// ditto.
ServiceInfo[] addCommandLineInterfaceService(ref ServiceInfo[] services)
{
    services ~= addCommandLineInterfaceService();
    return services;
}

/++
 + Provides the functionality of parsing command line arguments, and then calling a command.
 +
 + Description:
 +  The `Modules` template parameter is used directly with `jaster.cli.binder.ArgBinder` to provide the arg binding functionality.
 +  Please refer to `ArgBinder`'s documentation if you are wanting to use custom made binder funcs.
 +
 +  Commands are detected by looking over every module in `Modules`, and within each module looking for types marked with `@Command` and matching their patterns
 +  to the given input.
 +
 + Patterns:
 +  Patterns are pretty simple.
 +
 +  Example #1: The pattern "run" will match if the given command line args starts with "run".
 +
 +  Example #2: The pattern "run all" will match if the given command line args starts with "run all" (["run all"] won't work right now, only ["run", "all"] will)
 +
 +  Example #3: The pattern "r|run" will match if the given command line args starts with "r", or "run".
 +
 +  Longer patterns take higher priority than shorter ones.
 +
 +  Patterns with spaces are only allowed inside of `@Command` pattern UDAs. The `@CommandNamedArg` UDA is a bit more special.
 +
 +  For `@CommandNamedArg`, spaces are not allowed, since named arguments can't be split into spaces.
 +
 +  For `@CommandNamedArg`, patterns or subpatterns (When "|" is used to have multiple patterns) will be treated differently depending on their length.
 +  For patterns with only 1 character, they will be matched using short-hand argument form (See `ArgPullParser`'s documentation).
 +  For pattern with more than 1 character, they will be matched using long-hand argument form.
 +
 +  Example #4: The pattern (for `@CommandNamedArg`) "v|verbose" will match when either "-v" or "--verbose" is used.
 +
 +  Internally, `CommandResolver` is used to perform command resolution, and a solution custom to `CommandLineInterface` is used for everything else
 +  regarding patterns.
 +
 + Commands:
 +  A command is a struct or class that is marked with `@Command`.
 +
 +  Commands have only one requirement - They have a function called `onExecute`.
 +
 +  The `onExecute` function is called whenever the command's pattern is matched with the command line arguments.
 +
 +  The `onExecute` function must be compatible with one of these signatures:
 +      `void onExecute();`
 +      `int onExecute();`
 +
 +  The signature that returns an `int` is used to return a custom status code.
 +
 +  If a command has its pattern matched, then its arguments will be parsed before `onExecute` is called.
 +
 +  Arguments are either positional (`@CommandPositionalArg`) or named (`@CommandNamedArg`).
 +
 + Dependency_Injection:
 +  Whenever a command object is created, it is created using dependency injection (via the `jioc` library).
 +
 +  Each command is given its own service scope, even when a command calls another command.
 +
 + Positional_Arguments:
 +  A positional arg is an argument that appears in a certain 'position'. For example, imagine we had a command that we wanted to
 +  execute by using `"myTool create SomeFile.txt \"This is some content\""`.
 +
 +  The shell will pass `["create", "SomeFile.txt", "This is some content"]` to our program. We will assume we already have a command that will match with "create".
 +  We are then left with the other two strings.
 +
 +  `"SomeFile.txt"` is in the 0th position, so its value will be binded to the field marked with `@CommandPositionalArg(0)`.
 +
 +  `"This is some content"` is in the 1st position, so its value will be binded to the field marked with `@CommandPositionalArg(1)`.
 +
 + Named_Arguments:
 +  A named arg is an argument that follows a name. Names are either in long-hand form ("--file") or short-hand form ("-f").
 +
 +  For example, imagine we execute a custom tool with `"myTool create -f=SomeFile.txt --content \"This is some content\""`.
 +
 +  The shell will pass `["create", "-f=SomeFile.txt", "--content", "This is some content"]`. Notice how the '-f' uses an '=' sign, but '--content' doesn't.
 +  This is because the `ArgPullParser` supports various different forms of named arguments (e.g. ones that use '=', and ones that don't).
 +  Please refer to its documentation for more information.
 +
 +  Imagine we already have a command made that matches with "create". We are then left with the rest of the arguments.
 +
 +  "-f=SomeFile.txt" is parsed as an argument called "f" with the value "SomeFile.txt". Using the logic specified in the "Binding Arguments" section (below), 
 +  we perform the binding of "SomeFile.txt" to whichever field marked with `@CommandNamedArg` matches with the name "f".
 +
 +  `["--content", "This is some content"]` is parsed as an argument called "content" with the value "This is some content". We apply the same logic as above.
 +
 + Binding_Arguments:
 +  Once we have matched a field marked with either `@CommandPositionalArg` or `@CommandNamedArg` with a position or name (respectively), then we
 +  need to bind the value to the field.
 +
 +  This is where the `ArgBinder` is used. First of all, please refer to its documentation as it's kind of important.
 +  Second of all, we esentially generate a call similar to: `ArgBinderInstance.bind(myCommandInstance.myMatchedField, valueToBind)`
 +
 +  So imagine we have this field inside a command - `@CommandPositionalArg(0) int myIntField;`
 +
 +  Now imagine we have the value "200" in the 0th position. This means it'll be matchd with `myIntField`.
 +
 +  This will esentially generate this call: `ArgBinderInstance.bind(myCommandInstance.myIntField, "200")`
 +
 +  From there, ArgBinder will do its thing of binding/converting the string "200" into the integer 200.
 +
 +  `ArgBinder` has support for user-defined binders (in fact, all of the built-in binders use this mechanism!). Please
 +  refer to its documentation for more information, or see example-04.
 +
 +  You can also specify validation for arguments, by attaching structs (that match the definition specified in `ArgBinder`'s documentation) as
 +  UDAs onto your fields.
 +
 +  $(B Beware) you need to attach your validation struct as `@Struct()` (or with args) and not `@Struct`, notice the first one has parenthesis.
 +
 + Boolean_Binding:
 +  Bool arguments have special logic in place.
 +
 +  By only passing the name of a boolean argument (e.g. "--verbose"), this is treated as setting "verbose" to "true" using the `ArgBinder`.
 +
 +  By passing a value alongside a boolean argument that is either "true" or "false" (e.g. "--verbose true", "--verbose=false"), then the resulting
 +  value is passed to the `ArgBinder` as usual. In other words, "--verbose" is equivalent to "--verbose true".
 +
 +  By passing a value alongside a boolean argument that $(B isn't) one of the preapproved words then: The value will be treated as a positional argument;
 +  the boolean argument will be set to true.
 +
 +  For example, "--verbose" sets "verbose" to "true". Passing "--verbose=false/true" will set "verbose" to "false" or "true" respectively. Passing
 +  "--verbose push" would leave "push" as a positional argument, and then set "verbose" to "true".
 +
 +  These special rules are made so that boolean arguments can be given an explicit value, without them 'randomly' treating positional arguments as their value.
 +
 + Optional_And_Required_Arguments:
 +  By default, all arguments are required.
 +
 +  To make an optional argument, you must make it `Nullable`. For example, to have an optional `int` argument you'd use `Nullable!int` as the type.
 +
 +  Note that `Nullable` is publicly imported by this module, for ease of use.
 +
 +  Before a nullable argument is binded, it is first lowered down into its base type before being passed to the `ArgBinder`.
 +  In other words, a `Nullable!int` argument will be treated as a normal `int` by the ArgBinder.
 +
 +  If **any** required argument is not provided by the user, then an exception is thrown (which in turn ends up showing an error message).
 +  This does not occur with missing optional arguments.
 +
 + Raw_Arguments:
 +  For some applications, they may allow the ability for the user to provide a set of unparsed arguments. For example, dub allows the user
 +  to provide a set of arguments to the resulting output, when using the likes of `dub run`, e.g. `dub run -- value1 value2 etc.`
 +
 +  `CommandLineInterface` also provides this ability. While in the dub example, a double dash ("--") is used, `CommandLineInterface` requires a triple dash ("---").
 +
 +  After that, as long as your command contains a `string[]` field marked with `@CommandRawArg`, then any args after the triple dash are treated as "raw args" - they
 +  won't be parsed, passed to the ArgBinder, etc. they'll just be passed into the variable as-is.
 +
 +  For example, you have the following member in a command `@CommandRawArg string[] rawList;`, and you are given the following command - 
 +  `["command", "value1", "---", "rawValue1", "rawValue2"]`, which will result in `rawList`'s value becoming `["rawValue1", "rawValue2"]`
 +
 + Params:
 +  Modules = The modules that contain the commands and/or binder funcs to use.
 + +/
final class CommandLineInterface(Modules...)
{
    alias CommandExecuteFunc    = int function(ArgPullParser, ref string errorMessageIfThereWasOne, scope ref ServiceScope, HelpTextBuilderSimple);
    alias CommandCompleteFunc   = void function(string[] before, string current, string[] after, ref char[] buffer);
    alias ArgValueSetterFunc(T) = void function(ArgToken, ref T);
    alias ArgBinderInstance     = ArgBinder!Modules;
    alias AllowPartialMatch     = Flag!"partialMatch";
    immutable BASH_COMPLETION   = import("bash_completion.sh");

    private struct CommandInfo
    {
        Command               pattern; // Patterns (and their helper functions) are still being kept around, so previous code can work unimpeded from the migration to CommandResolver.
        HelpTextBuilderSimple helpText;
        CommandExecuteFunc    doExecute;
        CommandCompleteFunc   doComplete;
    }

    private enum Mode
    {
        execute,
        complete,
        bashCompletion
    }

    private enum ParseResultType
    {
        commandFound,
        commandNotFound,
        showHelpText
    }

    private struct ParseResult
    {
        ParseResultType type;
        CommandInfo     command;
        string          helpText;
        ArgPullParser   argParserAfterAttempt;
        ArgPullParser   argParserBeforeAttempt;
        ServiceScope    services;
    }

    struct ArgInfo(UDA, T)
    {
        UDA uda;
        ArgValueSetterFunc!T setter;
        bool wasFound; // For nullables, this is ignore. Otherwise, anytime this is false we need to throw.
        bool isNullable;
        bool isBool;
    }
    alias NamedArgInfo(T) = ArgInfo!(CommandNamedArg, T);
    alias PositionalArgInfo(T) = ArgInfo!(CommandPositionalArg, T);

    /+ VARIABLES +/
    private
    {
        CommandResolver!CommandInfo _resolver;
        ServiceProvider             _services;
        CommandInfo                 _defaultCommand;
    }

    /+ PUBLIC INTERFACE +/
    public final
    {
        /++
         + Params:
         +  services = The `ServiceProvider` to use for dependency injection.
         +             If this value is `null`, then a new `ServiceProvider` will be created containing an `ICommandLineInterface` service.
         + ++/
        this(ServiceProvider services = null)
        {
            import std.algorithm : sort;

            if(services is null)
                services = new ServiceProvider([addCommandLineInterfaceService()]);
            this._services = services;
            this._resolver = new CommandResolver!CommandInfo();

            static foreach(mod; Modules)
                this.addCommandsFromModule!mod();
        }
        
        /++
         + Parses the given `args`, and then executes the appropriate command (if one was found).
         +
         + Notes:
         +  If an exception is thrown, the error message is displayed on screen (as well as the stack trace, for non-release builds)
         +  and then -1 is returned.
         +
         + See_Also:
         +  The documentation for `ArgPullParser` to understand the format for `args`.
         +
         + Params:
         +  args        = The args to parse.
         +  ignoreFirst = Whether to ignore the first value of `args` or not.
         +                If `args` is passed as-is from the main function, then the first value will
         +                be the path to the executable, and should be ignored.
         +
         + Returns:
         +  The status code returned by the command, or -1 if an exception is thrown.
         + +/
        int parseAndExecute(string[] args, IgnoreFirstArg ignoreFirst = IgnoreFirstArg.yes)
        {
            if(ignoreFirst)
            {
                if(args.length <= 1)
                    args.length = 0;
                else
                    args = args[1..$];
            }

            return this.parseAndExecute(ArgPullParser(args));
        } 

        /// ditto
        int parseAndExecute(ArgPullParser args)
        {
            import std.algorithm : filter, any;
            import std.exception : enforce;
            import std.stdio     : writefln;
            import std.format    : format;

            if(args.empty && this._defaultCommand == CommandInfo.init)
            {
                writefln("ERROR: No command was given.");
                writefln(this.createAvailableCommandsHelpText(args, "Available commands").toString());
                return -1;
            }

            Mode mode = Mode.execute;

            if(args.front.type == ArgTokenType.Text && args.front.value == "__jcli:complete")
                mode = Mode.complete;
            else if(args.front.type == ArgTokenType.Text && args.front.value == "__jcli:bash_complete_script")
                mode = Mode.bashCompletion;

            ParseResult parseResult;

            parseResult.argParserBeforeAttempt = args; // If we can't find the exact command, sometimes we can get a partial match when showing help text.
            parseResult.type                   = ParseResultType.commandFound; // Default to command found.
            auto result                        = this._resolver.resolveAndAdvance(args);

            if(!result.success || result.value.type == CommandNodeType.partialWord)
            {
                if(this.containsHelpArgument(args))
                {
                    parseResult.type = ParseResultType.showHelpText;
                    if(this._defaultCommand != CommandInfo.init)
                        parseResult.helpText ~= this._defaultCommand.helpText.toString();
                    
                    //if(this._commands.length > 0)
                        parseResult.helpText ~= this.createAvailableCommandsHelpText(parseResult.argParserBeforeAttempt, "Available commands").toString();
                }
                else if(this._defaultCommand == CommandInfo.init)
                {
                    parseResult.type      = ParseResultType.commandNotFound;
                    parseResult.helpText ~= format("ERROR: Unknown command '%s'.\n\n", parseResult.argParserBeforeAttempt.front.value);
                    parseResult.helpText ~= this.createAvailableCommandsHelpText(parseResult.argParserBeforeAttempt).toString();
                }
                else
                    parseResult.command = this._defaultCommand;
            }
            else
                parseResult.command = result.value.userData;

            parseResult.argParserAfterAttempt = args;
            parseResult.services              = this._services.createScope(); // Reminder: ServiceScope uses RAII.

            // Special support: For our default implementation of `ICommandLineInterface`, set its value.
            auto proxy = cast(ICommandLineInterfaceImpl)parseResult.services.getServiceOrNull!ICommandLineInterface();
            if(proxy !is null)
                proxy._func = &this.parseAndExecute;

            final switch(mode) with(Mode)
            {
                case execute:        return this.onExecute(parseResult);
                case complete:       return this.onComplete(parseResult);
                case bashCompletion: return this.onBashCompletionScript();
            }
        }
    }

    /+ MODE EXECUTORS +/
    private final
    {
        int onExecute(ref ParseResult result)
        {
            import std.stdio : writeln, writefln;

            final switch(result.type) with(ParseResultType)
            {
                case showHelpText:
                    writeln(result.helpText);
                    return 0;

                case commandNotFound:
                    writeln(result.helpText);
                    return -1;

                case commandFound: break;
            }

            string errorMessage;
            auto statusCode = result.command.doExecute(result.argParserAfterAttempt, /*ref*/ errorMessage, result.services, result.command.helpText);

            if(errorMessage !is null)
                writefln("ERROR: %s", errorMessage);

            return statusCode;
        }

        int onComplete(ref ParseResult result)
        {
            // Parsing here shouldn't be affected by user-defined ArgBinders, so stuff being done here is done manually.
            // This way we gain reliability.
            //
            // Since this is also an internal function, error checking is much more lax.
            import std.array     : array;
            import std.algorithm : map, filter, splitter, equal, startsWith;
            import std.conv      : to;
            import std.stdio     : writeln;

            // Expected args:
            //  [0]    = COMP_CWORD
            //  [1..$] = COMP_WORDS
            result.argParserAfterAttempt.popFront(); // Skip __jcli:complete
            auto cword = result.argParserAfterAttempt.front.value.to!uint;
            result.argParserAfterAttempt.popFront();
            auto  words = result.argParserAfterAttempt.map!(t => t.value).array;

            cword -= 1;
            words = words[1..$]; // [0] is the exe name, which we don't care about.
            auto before  = words[0..cword];
            auto current = (cword < words.length)     ? words[cword]      : [];
            auto after   = (cword + 1 < words.length) ? words[cword+1..$] : [];

            auto beforeParser = ArgPullParser(before);
            auto commandInfo  = this._resolver.resolveAndAdvance(beforeParser);

            // Can't find command, so we're in "display command name" mode.
            if(!commandInfo.success || commandInfo.value.type == CommandNodeType.partialWord)
            {
                char[] output;
                output.reserve(1024); // Gonna be doing a good bit of concat.

                // Special case: When we have no text to look for, just display the first word of every command path.
                if(before.length == 0 && current is null)
                    commandInfo.value = this._resolver.root;

                // Otherwise try to match using the existing text.

                // Display the word of all children of the current command word.
                //
                // If the current argument word isn't null, then use that as a further filter.
                //
                // e.g.
                // Before  = ["name"]
                // Pattern = "name get"
                // Output  = "get"
                foreach(child; commandInfo.value.children)
                {
                    if(current.length > 0 && !child.word.startsWith(current))
                        continue;

                    output ~= child.word;
                    output ~= " ";
                }

                writeln(output);
                return 0;
            }

            // Found command, so we're in "display possible args" mode.
            char[] output;
            output.reserve(1024);

            commandInfo.value.userData.doComplete(before, current, after, /*ref*/ output); // We need black magic, so this is generated in addCommand.
            writeln(output);

            return 0;
        }

        int onBashCompletionScript()
        {
            import std.stdio : writefln;
            import std.file  : thisExePath;
            import std.path  : baseName;

            const fullPath = thisExePath;
            const exeName  = fullPath.baseName;

            writefln(BASH_COMPLETION,
                exeName,
                fullPath,
                exeName,
                exeName
            );
            return 0;
        }
    }

    /+ COMMAND INFO CREATOR FUNCTIONS +/
    private final
    {
        HelpTextBuilderSimple createHelpText(alias T)()
        {
            import std.algorithm : splitter;
            import std.array     : array;

            // Get arg info.
            NamedArgInfo!T[] namedArgs;
            PositionalArgInfo!T[] positionalArgs;
            /*static member*/ getArgs!T(/*ref*/ namedArgs, /*ref*/ positionalArgs);

            // Get UDA
            enum UDA = getSingleUDA!(T, Command);
            auto builder = new HelpTextBuilderSimple();

            foreach(arg; namedArgs)
            {
                builder.addNamedArg(
                    arg.uda.pattern.splitter('|')
                                   .array,
                    arg.uda.description,
                    cast(ArgIsOptional)arg.isNullable
                );
            }

            foreach(arg; positionalArgs)
            {
                builder.addPositionalArg(
                    arg.uda.position,
                    arg.uda.description,
                    cast(ArgIsOptional)arg.isNullable,
                    arg.uda.name
                );
            }

            builder.commandName = UDA.pattern;
            builder.description = UDA.description;

            return builder;
        }

        CommandExecuteFunc createCommandExecuteFunc(alias T)()
        {
            import std.format    : format;
            import std.algorithm : filter, map;
            import std.exception : enforce, collectException;

            // This is expecting the parser to have already read in the command's name, leaving only the args.
            return (ArgPullParser parser, ref string executionError, scope ref ServiceScope services, HelpTextBuilderSimple helpText)
            {
                if(containsHelpArgument(parser))
                {
                    import std.stdio : writeln;
                    writeln(helpText.toString());
                    return 0;
                }

                T commandInstance = Injector.construct!T(services);
                static if(is(T == class))
                    assert(commandInstance !is null, "Dependency injection failed somehow.");
                
                // Get arg info.
                NamedArgInfo!T[]      namedArgs;
                PositionalArgInfo!T[] positionalArgs;
                /*static member*/ getArgs!T(/*ref*/ namedArgs, /*ref*/ positionalArgs);

                // Parse args.
                size_t   positionalArgIndex = 0;
                bool     processRawList = false;
                string[] rawList;
                for(; !parser.empty && !processRawList; parser.popFront())
                {
                    const  token = parser.front;
                    string debugName; // Used for when there's a validation error
                    try final switch(token.type) with(ArgTokenType)
                    {
                        case Text:
                            if(positionalArgIndex >= positionalArgs.length)
                            {
                                executionError = "Stray positional arg found: '"~token.value~"'";
                                return -1;
                            }

                            debugName = "positional arg %s(%s)".format(positionalArgIndex, positionalArgs[positionalArgIndex].uda.name);
                            positionalArgs[positionalArgIndex].setter(token, /*ref*/ commandInstance);
                            positionalArgs[positionalArgIndex++].wasFound = true;
                            break;

                        case LongHandArgument:
                            if(token.value == "-") // ---
                            {
                                processRawList = true;
                                rawList = parser.unparsedArgs;
                                break;
                            }
                            goto case;
                        case ShortHandArgument:
                            NamedArgInfo!T result;
                            foreach(ref arg; namedArgs)
                            {
                                if(/*static member*/matchSpacelessPattern(arg.uda.pattern, token.value))
                                {
                                    arg.wasFound = true;
                                    result       = arg;
                                    debugName    = "named argument "~arg.uda.pattern;
                                    break;
                                }
                            }

                            if(result == NamedArgInfo!T.init)
                            {
                                executionError = "Unknown named argument: '"~token.value~"'";
                                return -1;
                            }
                            
                            if(result.isBool)
                            {
                                import std.algorithm : canFind;
                                // Bools have special support:
                                //  If they are defined, they are assumed to be true, however:
                                //      If the next token is Text, and its value is one of a predefined list, then it is then sent to the ArgBinder instead of defaulting to true.
                                
                                auto parserCopy = parser;
                                parserCopy.popFront();
                                
                                if(parserCopy.empty 
                                || parserCopy.front.type != ArgTokenType.Text
                                || !["true", "false"].canFind(parserCopy.front.value))
                                {
                                    result.setter(ArgToken("true", ArgTokenType.Text), /*ref*/ commandInstance);
                                    break;
                                }

                                result.setter(parserCopy.front, /*ref*/ commandInstance);
                                parser.popFront(); // Keep the main parser up to date.
                            }
                            else
                            {
                                parser.popFront();

                                if(parser.front.type == ArgTokenType.EOF)
                                {
                                    executionError = "Named arg '"~result.uda.pattern~"' was specified, but wasn't given a value.";
                                    return -1;
                                }

                                result.setter(parser.front, /*ref*/ commandInstance);
                            }
                            break;

                        case None:
                            throw new Exception("An Unknown error occured when parsing the arguments.");

                        case EOF:
                            break;
                    }
                    catch(ArgBinderValidationException ex)
                    {
                        executionError = "For "~debugName~": "~ex.msg;
                        return -1;
                    }
                }

                // Check for missing args.
                auto missingNamedArgs      = namedArgs.filter!(a => !a.isNullable && !a.wasFound);
                auto missingPositionalArgs = positionalArgs.filter!(a => !a.isNullable && !a.wasFound);
                if(!missingNamedArgs.empty)
                {
                    executionError = "The following required named arguments were not provided: %s"
                                     .format(missingNamedArgs.map!(a => a.uda.pattern));
                    return -1;
                }
                if(!missingPositionalArgs.empty)
                {
                    executionError = "The following required positional arguments were not provided: %s"
                                      .format(missingPositionalArgs.map!(a => format("[%s] %s", a.uda.position, a.uda.name)));
                    return -1;
                }

                // Process the raw list if we can
                if(processRawList)
                    insertRawList!T(/*ref*/ commandInstance, rawList);

                // Execute the command.
                static assert(
                    __traits(compiles, commandInstance.onExecute())
                 || __traits(compiles, { int code = commandInstance.onExecute(); }),
                    "Unable to call the `onExecute` function for command `"~__traits(identifier, T)~"` please ensure it's signature matches either:"
                   ~"\n\tvoid onExecute();"
                   ~"\n\tint onExecute();"
                );

                try
                {
                    static if(__traits(compiles, {int i = commandInstance.onExecute();}))
                        return commandInstance.onExecute();
                    else 
                    {
                        commandInstance.onExecute();
                        return 0;
                    }
                }
                catch(Exception ex)
                {
                    executionError = ex.msg;
                    debug executionError ~= "\n\nSTACK TRACE:\n" ~ ex.info.toString(); // trace info
                    return -1;
                }
            };
        }
        
        CommandCompleteFunc createCommandCompleteFunc(alias T)()
        {
            import std.algorithm : filter, map, startsWith, splitter, canFind;
            import std.exception : assumeUnique;

            return (string[] before, string current, string[] after, ref char[] output)
            {
                // Check if there's been a null ("--") or '-' ("---"), and if there has, don't bother with completion.
                // Because anything past that is of course, the raw arg list.
                if(before.canFind(null) || before.canFind("-"))
                    return;

                // Get arg info.
                NamedArgInfo!T[]      namedArgs;
                PositionalArgInfo!T[] positionalArgs;
                getArgs!T(/*ref*/ namedArgs, /*ref*/ positionalArgs);

                // See if the previous value was a non-boolean argument.
                const justBefore               = ArgPullParser(before[$-1..$]).front;
                auto  justBeforeNamedArgResult = namedArgs.filter!(a => matchSpacelessPattern(a.uda.pattern, justBefore.value));
                if((justBefore.type == ArgTokenType.LongHandArgument || justBefore.type == ArgTokenType.ShortHandArgument)
                && (!justBeforeNamedArgResult.empty && !justBeforeNamedArgResult.front.isBool))
                {
                    // TODO: In the future, add support for specifying values to a parameter, either static and/or dynamically.
                    return;
                }

                // Otherwise, we either need to autocomplete an argument's name, or something else that's predefined.
                
                string[] names;
                names.reserve(namedArgs.length * 2);

                foreach(arg; namedArgs)
                {
                    foreach(pattern; arg.uda.pattern.splitter('|'))
                    {
                        // Reminder: Confusingly for this use case, arguments don't have their leading dashes in the before and after arrays.
                        if(before.canFind(pattern) || after.canFind(pattern))
                            continue;

                        names ~= pattern;
                    }
                }

                foreach(name; names.filter!(n => n.startsWith(current)))
                {
                    output ~= (name.length == 1) ? "-" : "--";
                    output ~= name;
                    output ~= ' ';
                }
            };
        }
    }

    /+ COMMAND RUNTIME HELPERS +/
    private final
    {
        static void insertRawList(T)(ref T command, string[] rawList)
        {
            import std.traits : getSymbolsByUDA;

            alias RawListArgs = getSymbolsByUDA!(T, CommandRawArg);
            static assert(RawListArgs.length < 2, "Only a single `@CommandRawArg` can exist for command "~T.stringof);

            static if(RawListArgs.length > 0)
            {
                alias RawListArg = RawListArgs[0];
                static assert(
                    is(typeof(RawListArg) == string[]), 
                    "`@CommandRawArg` can ONLY be used with `string[]`, not `" ~ typeof(RawListArg).stringof ~ "` in command " ~ T.stringof
                );

                const RawListName = __traits(identifier, RawListArg);
                static assert(RawListName != "RawListName", "__traits(identifier) failed.");

                mixin("command."~RawListName~" = rawList;");
            }
        }

        static void getArgs(T)(ref NamedArgInfo!T[] namedArgs, ref PositionalArgInfo!T[] positionalArgs)
        {
            import std.format : format;
            import std.meta   : staticMap, Filter;
            import std.traits : isType, hasUDA, isInstanceOf, ReturnType, Unqual, isBuiltinType;

            alias NameToMember(string Name) = __traits(getMember, T, Name);
            alias MemberNames               = __traits(allMembers, T);

            static foreach(symbolName; MemberNames)
            {{
                static if(__traits(compiles, NameToMember!symbolName))
                {
                    // The postfix is necessary so the below `if` works, without forcing the user to not use the name 'symbol' in their code.
                    alias symbol_SOME_RANDOM_CRAP = NameToMember!symbolName; 
                    
                    // Skip over aliases, nested types, and enums.
                    static if(!isType!symbol_SOME_RANDOM_CRAP
                        && !is(symbol_SOME_RANDOM_CRAP == enum)
                        && __traits(identifier, symbol_SOME_RANDOM_CRAP) != "symbol_SOME_RANDOM_CRAP"
                    )
                    {
                        // I wish there were a convinent way to 'continue' a static foreach...

                        alias Symbol     = symbol_SOME_RANDOM_CRAP;
                        alias SymbolType = typeof(Symbol);
                        const SymbolName = __traits(identifier, Symbol);

                        enum IsField = (
                            isBuiltinType!SymbolType
                         || is(SymbolType == struct)
                         || is(SymbolType == class)
                        );

                        static if(
                                IsField
                            && (hasUDA!(Symbol, CommandNamedArg) || hasUDA!(Symbol, CommandPositionalArg))
                        ) 
                        {
                            alias SymbolUDAs = __traits(getAttributes, Symbol);

                            static if(hasUDA!(Symbol, CommandNamedArg))
                            {
                                NamedArgInfo!T arg;
                                arg.uda = getSingleUDA!(Symbol, CommandNamedArg);
                            }
                            else static if(hasUDA!(Symbol, CommandPositionalArg))
                            {
                                PositionalArgInfo!T arg;
                                arg.uda = getSingleUDA!(Symbol, CommandPositionalArg);
                            }
                            else static assert(false, "Bug with parent if statement.");

                            arg.setter = (ArgToken tok, ref T commandInstance)
                            {
                                import std.exception : enforce;
                                import std.conv : to;
                                assert(tok.type == ArgTokenType.Text, tok.to!string);

                                static if(isInstanceOf!(Nullable, SymbolType))
                                {
                                    // The Unqual removes the `inout` that `get` uses.
                                    alias SymbolUnderlyingType = Unqual!(ReturnType!(SymbolType.get));

                                    SymbolUnderlyingType proxy;
                                    ArgBinderInstance.bind!(SymbolUnderlyingType, SymbolUDAs)(tok.value, /*ref*/ proxy);

                                    mixin("commandInstance.%s = proxy;".format(SymbolName));
                                }
                                else
                                    ArgBinderInstance.bind!(SymbolType, SymbolUDAs)(tok.value, /*ref*/ mixin("commandInstance.%s".format(SymbolName)));
                            };
                            arg.isNullable = isInstanceOf!(Nullable, SymbolType);
                            arg.isBool     = is(SymbolType == bool) || is(SymbolType == Nullable!bool);

                            static if(hasUDA!(Symbol, CommandNamedArg)) namedArgs ~= arg;
                            else                                        positionalArgs ~= arg;
                        }
                    }
                }
            }}
        }
    }

    /+ PARSING HELPERS +/
    private final
    {
        static bool containsHelpArgument(ArgPullParser args)
        {
            import std.algorithm : any;

            return args.any!(t => t.type == ArgTokenType.ShortHandArgument && t.value == "h"
                               || t.type == ArgTokenType.LongHandArgument && t.value == "help");
        }

        static bool matchSpacelessPattern(string pattern, string toTestAgainst)
        {
            import std.algorithm : splitter, any;

            return pattern.splitter("|").any!(str => str == toTestAgainst);
        }
        ///
        unittest
        {
            assert(matchSpacelessPattern("v|verbose", "v"));
            assert(matchSpacelessPattern("v|verbose", "verbose"));
            assert(!matchSpacelessPattern("v|verbose", "lalafell"));
        }

        static bool matchSpacefullPattern(string pattern, ref ArgPullParser parser, AllowPartialMatch allowPartial = AllowPartialMatch.no)
        {
            import std.algorithm : splitter;

            foreach(subpattern; pattern.splitter("|"))
            {
                auto savedParser = parser.save();
                bool isAMatch = true;
                bool isAPartialMatch = false;
                foreach(split; subpattern.splitter(" "))
                {
                    // import std.stdio;
                    // writeln(subpattern, " > ", split, " > ", savedParser.front, " > ", savedParser.empty, " > ", (savedParser.front.type == ArgTokenType.Text && savedParser.front.value == split));

                    if(savedParser.empty
                    || !(savedParser.front.type == ArgTokenType.Text && savedParser.front.value == split))
                    {
                        isAMatch = false;
                        break;
                    }

                    isAPartialMatch = true;
                    savedParser.popFront();
                }

                if(isAMatch
                || (isAPartialMatch && allowPartial))
                {
                    parser = savedParser;
                    return true;
                }
            }

            return false;
        }
        ///
        unittest
        {
            // Test empty parsers.
            auto parser = ArgPullParser([]);
            assert(!matchSpacefullPattern("v", parser));

            // Test that the parser's position is moved forward correctly.
            parser = ArgPullParser(["v", "verbose"]);
            assert(matchSpacefullPattern("v", parser));
            assert(matchSpacefullPattern("verbose", parser));
            assert(parser.empty);

            // Test that a parser that fails to match isn't moved forward at all.
            parser = ArgPullParser(["v", "verbose"]);
            assert(!matchSpacefullPattern("lel", parser));
            assert(parser.front.value == "v");

            // Test that a pattern with spaces works.
            parser = ArgPullParser(["give", "me", "chocolate"]);
            assert(matchSpacefullPattern("give me", parser));
            assert(parser.front.value == "chocolate");

            // Test that multiple patterns work.
            parser = ArgPullParser(["v", "verbose"]);
            assert(matchSpacefullPattern("lel|v|verbose", parser));
            assert(matchSpacefullPattern("lel|v|verbose", parser));
            assert(parser.empty);
        }
    }

    /+ UNCATEGORISED HELPERS +/
    private final
    {
        HelpTextBuilderTechnical createAvailableCommandsHelpText(ArgPullParser args, string sectionName = "Did you mean")
        {
            import std.array     : array;
            import std.algorithm : filter, sort, map, splitter;

            auto command = this._resolver.root;
            auto result  = this._resolver.resolveAndAdvance(args);
            if(result.success)
                command = result.value;

            auto builder = new HelpTextBuilderTechnical();
            builder.addSection(sectionName)
                   .addContent(
                       new HelpSectionArgInfoContent(
                           command.finalWords
                                  .map!(c => c.userData)
                                  .map!(c => HelpSectionArgInfoContent.ArgInfo(
                                       [c.pattern.pattern],
                                       c.pattern.description,
                                       ArgIsOptional.no
                                  ))
                                  .array
                                  .sort!"a.names[0] < b.names[0]"
                                  .array, // eww...
                            AutoAddArgDashes.no
                       )
            );

            return builder;
        }

        void addCommandsFromModule(alias Module)()
        {
            import std.traits : getSymbolsByUDA;

            static foreach(symbol; getSymbolsByUDA!(Module, Command))
            {
                static assert(is(symbol == struct) || is(symbol == class), 
                    "Only structs and classes can be marked with @Command. Issue Symbol = " ~ __traits(identifier, symbol)
                );

                pragma(msg, "Found command: ", __traits(identifier, symbol));
                this.addCommand!symbol();
            }
        }

        void addCommand(alias T)()
        if(is(T == struct) || is(T == class))
        {
            import std.algorithm : splitter;
            import std.format    : format;
            import std.exception : enforce;

            CommandInfo info;
            info.helpText   = this.createHelpText!T();
            info.pattern    = getSingleUDA!(T, Command);
            info.doExecute  = this.createCommandExecuteFunc!T();
            info.doComplete = this.createCommandCompleteFunc!T();

            if(info.pattern.pattern is null)
            {
                enforce(
                    this._defaultCommand == CommandInfo.init, 
                    "Multiple default commands defined: Second default command is %s"
                    .format(T.stringof)
                );
                info.helpText.setCommandName("DEFAULT");
                this._defaultCommand = info;
            }
            else
            {
                foreach(pattern; info.pattern.pattern.splitter('|'))
                    this._resolver.define(pattern, info);
            }
        }
    }
}

version(unittest)
{
    private alias InstansiationTest = CommandLineInterface!(jaster.cli.core);

    // NOTE: The only reason it can see and use private @Commands is because they're in the same module.
    @Command("execute t|execute test|et|e test", "This is a test command")
    private struct CommandTest
    {
        // These are added to test that they are safely ignored.
        alias al = int;
        enum e = 2;
        struct S
        {
        }
        void f () {}

        @CommandNamedArg("a|avar", "A variable")
        int a;

        @CommandPositionalArg(0, "b")
        Nullable!string b;

        @CommandNamedArg("c")
        Nullable!bool c;

        int onExecute()
        {
            import std.conv : to;
            
            return (b.isNull || !c.isNull) ? 0
                                           : (b.get() == a.to!string) ? 1
                                                                      : -1;
        }
    }

    // Should always return 1 via `CommandTest`
    @Command("test injection")
    private struct CallCommandTest
    {
        private ICommandLineInterface _cli;
        this(ICommandLineInterface cli)
        {
            this._cli = cli;
            assert(cli !is null);
        }

        int onExecute()
        {
            return this._cli.parseAndExecute(["et", "20", "-a 20"], IgnoreFirstArg.no);
        }
    }

    @Command(null, "This is the default command.")
    private struct DefaultCommandTest
    {
        @CommandNamedArg("var", "A variable")
        int a;

        int onExecute()
        {
            return a % 2 == 0
            ? a
            : 0;
        }
    }

    @("General test")
    unittest
    {
        auto cli = new CommandLineInterface!(jaster.cli.core);
        assert(cli.parseAndExecute(["execute", "t", "-a 20"],              IgnoreFirstArg.no) == 0); // b is null
        assert(cli.parseAndExecute(["execute", "test", "20", "--avar 21"], IgnoreFirstArg.no) == -1); // a and b don't match
        assert(cli.parseAndExecute(["et", "20", "-a 20"],                  IgnoreFirstArg.no) == 1); // a and b match
        assert(cli.parseAndExecute(["e", "test", "20", "-a 20", "-c"],     IgnoreFirstArg.no) == 0); // -c is used
    }

    @("Test ICommandLineInterface injection")
    unittest
    {
        auto provider = new ServiceProvider([
            addCommandLineInterfaceService()
        ]);

        auto cli = new CommandLineInterface!(jaster.cli.core)(provider);
        assert(cli.parseAndExecute(["test", "injection"], IgnoreFirstArg.no) == 1);
    }

    @("Default command test")
    unittest
    {
        auto cli = new CommandLineInterface!(jaster.cli.core);
        assert(cli.parseAndExecute(["--var 1"], IgnoreFirstArg.no) == 0);
        assert(cli.parseAndExecute(["--var 2"], IgnoreFirstArg.no) == 2);
    }

    @Command("booltest", "Bool test")
    private struct BoolTestCommand
    {
        @CommandNamedArg("a")
        bool definedNoValue;

        @CommandNamedArg("b")
        bool definedFalseValue;

        @CommandNamedArg("c")
        bool definedTrueValue;

        @CommandNamedArg("d")
        bool definedNoValueWithArg;

        @CommandPositionalArg(0)
        string comesAfterD;

        void onExecute()
        {
            assert(this.definedNoValue,            "-a doesn't equal true.");
            assert(!this.definedFalseValue,        "-b=false doesn't equal false");
            assert(this.definedTrueValue,          "-c true doesn't equal true");
            assert(this.definedNoValueWithArg,     "-d Lalafell doesn't equal true");
            assert(this.comesAfterD == "Lalafell", "Lalafell was eaten incorrectly.");
        }
    }
    @("Test that booleans are handled properly")
    unittest
    {
        auto cli = new CommandLineInterface!(jaster.cli.core);
        assert(
            cli.parseAndExecute(
                ["booltest", "-a", "-b=false", "-c", "true", "-d", "Lalafell"],
                // Unforunately due to ArgParser discarding some info, "-d=Lalafell" won't become an error as its treated the same as "-d Lalafell".
                IgnoreFirstArg.no
            ) == 0
        );
    }

    @Command("rawListTest", "Test raw lists")
    private struct RawListTestCommand
    {
        @CommandNamedArg("a")
        bool dummyThicc;

        @CommandRawArg
        string[] rawList;

        void onExecute()
        {
            assert(rawList.length == 2);
        }
    }
    @("Test that raw lists work")
    unittest
    {
        auto cli = new CommandLineInterface!(jaster.cli.core);
        assert(
            cli.parseAndExecute(
                ["rawListTest", "-a", "---", "raw1", "raw2"],
                IgnoreFirstArg.no
            ) == 0
        );
    }

    private struct Expect(T)
    {
        T value;

        bool onValidate(T boundValue, ref string error)
        {
            import std.format : format;
            error = "Expected value to equal '%s', not '%s'.".format(this.value, boundValue);

            return this.value == boundValue;
        }
    }

    @Command("validationTest", "Test validation")
    private struct ValidationTestCommand
    {
        @CommandPositionalArg(0)
        @Expect!string("lol")
        string value;
        
        void onExecute(){}
    }
    @("Test ArgBinder validation integration")
    unittest
    {
        auto cli = new CommandLineInterface!(jaster.cli.core);
        assert(
            cli.parseAndExecute(
                ["validationTest", "lol"],
                IgnoreFirstArg.no
            ) == 0
        );

        assert(
            cli.parseAndExecute(
                ["validationTest", "non"],
                IgnoreFirstArg.no
            ) == -1
        );
    }
}