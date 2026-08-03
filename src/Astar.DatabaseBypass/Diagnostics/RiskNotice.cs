using System.Threading;

namespace Astar.DatabaseBypass.Diagnostics;

internal static class RiskNotice
{
    private static int _written;

    internal static void WriteOnce()
    {
        if (Interlocked.Exchange(ref _written, 1) != 0)
        {
            return;
        }

        var previousColor = Console.ForegroundColor;

        try
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine("============================================================");
            Console.WriteLine("[Astar.DatabaseBypass] WARNING");
            Console.WriteLine("SPT database hash verification has been disabled.");
            Console.WriteLine("This mod does not write, modify, or delete database");
            Console.WriteLine("or player profile files.");
            Console.WriteLine("JSON parsing and normal server errors remain enabled.");
            Console.WriteLine("Custom and third-party edits are used at your own risk.");
            Console.WriteLine("============================================================");
        }
        finally
        {
            Console.ForegroundColor = previousColor;
        }
    }
}
