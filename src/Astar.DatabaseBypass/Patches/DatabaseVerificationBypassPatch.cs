using System.Reflection;
using System.Threading;
using Astar.DatabaseBypass.Diagnostics;
using SPTarkov.Reflection.Patching;
using SPTarkov.Server.Helpers;

namespace Astar.DatabaseBypass.Patches;

internal sealed class DatabaseVerificationBypassPatch : AbstractPatch
{
    private static int _enableRequested;

    private DatabaseVerificationBypassPatch()
        : base("com.astar.spt.databasebypass.database-import")
    {
    }

    internal static void EnableOnce()
    {
        if (Interlocked.Exchange(ref _enableRequested, 1) != 0)
        {
            return;
        }

        new DatabaseVerificationBypassPatch().Enable();
    }

    protected override MethodBase? GetTargetMethod()
    {
        return typeof(DatabaseImporter).GetMethod(
            nameof(DatabaseImporter.LoadDatabaseAsync),
            BindingFlags.Instance | BindingFlags.Public,
            binder: null,
            types: new[] { typeof(bool), typeof(CancellationToken) },
            modifiers: null
        );
    }

    [PatchPrefix]
    private static void Prefix(ref bool shouldVerifyDatabase)
    {
        if (shouldVerifyDatabase)
        {
            RiskNotice.WriteOnce();
        }

        shouldVerifyDatabase = false;
    }
}
