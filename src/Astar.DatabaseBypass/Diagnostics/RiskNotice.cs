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
            Console.WriteLine("Invalid database edits can prevent startup, cause runtime");
            Console.WriteLine("errors, or damage profiles. The author is not responsible");
            Console.WriteLine("for failures caused by user or third-party modifications.");
            Console.WriteLine("JSON parsing and normal server errors remain enabled.");
            Console.WriteLine("============================================================");
        }
        finally
        {
            Console.ForegroundColor = previousColor;
        }
    }
}
