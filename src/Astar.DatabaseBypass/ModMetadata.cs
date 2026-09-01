using SPTarkov.Server.Core.Models.Spt.Mod;
using SemVersion = SemanticVersioning.Version;
using SemVersionRange = SemanticVersioning.Range;

namespace Astar.DatabaseBypass;

internal static class SptBuildTarget
{
    private static readonly System.Version CoreAssemblyVersion =
        typeof(IModMetadata).Assembly.GetName().Version ?? new System.Version(4, 1, 0);

    internal static string ExactVersion { get; } = CoreAssemblyVersion.ToString(3);
}

public sealed record ModMetadata : IModMetadata
{
    public string ModGuid { get; init; } = "com.astar.spt.databasebypass";
    public string Name { get; init; } = "Astar Database Bypass";
    public string Author { get; init; } = "Astar";
    public List<string>? Contributors { get; init; }
    public SemVersion Version { get; init; } = new("0.1.0");
    public SemVersionRange SptVersion { get; init; } = new(SptBuildTarget.ExactVersion);
    public bool HasPrepatcher { get; init; }
    public List<string>? Incompatibilities { get; init; }
    public Dictionary<string, SemVersionRange>? ModDependencies { get; init; }
    public string? Url { get; init; }
    public string License { get; init; } = "CC-BY-NC-SA-4.0";
}
