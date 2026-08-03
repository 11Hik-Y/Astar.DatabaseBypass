using System.Runtime.CompilerServices;
using Astar.DatabaseBypass.Patches;

namespace Astar.DatabaseBypass;

internal static class ModuleBootstrap
{
    [ModuleInitializer]
    internal static void Initialize()
    {
        try
        {
            DatabaseVerificationBypassPatch.EnableOnce();
            Console.WriteLine("[Astar.DatabaseBypass] Early database-verification patch installed.");
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine("[Astar.DatabaseBypass] Failed to install the early patch.");
            Console.Error.WriteLine(exception);
            throw;
        }
    }
}
