extern (C) void main()
{
    version (D_BetterC)
    {
        import core.stdc.stdio : println = printf;

        println("D: Hello, world!\n");
    }
    else
    {
        import std.stdio : println = writeln;

        println("D: Hello, world!");
    }
}
