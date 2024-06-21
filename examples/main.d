extern (C) void main()
{
    version (D_BetterC)
    {
        alias println = printf;
        println("D: Hello, world!\n");
    }
    else
    {
        import std.stdio : println = writeln;

        println("D: Hello, world!");
    }
}

pragma(printf)
extern (C) int printf(scope const(char)* fmt, scope...) @nogc nothrow;